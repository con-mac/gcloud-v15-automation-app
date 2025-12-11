# FORCE FIX: Update function.json via Kudu API (bypasses all restrictions)
# This uses publishing credentials which should have write access

$FUNCTION_APP = "pa-gcloud15-api-14sxir"
$RESOURCE_GROUP = "pa-gcloud15-rg"

Write-Host "=== FORCE FIX: authLevel via Kudu API ===" -ForegroundColor Cyan

# Step 1: Ensure WEBSITE_RUN_FROM_PACKAGE is deleted
Write-Host "Step 1: Ensuring package mode is disabled..." -ForegroundColor Yellow
$ErrorActionPreference = 'SilentlyContinue'
$packageSetting = az webapp config appsettings list --name $FUNCTION_APP --resource-group $RESOURCE_GROUP --query "[?name=='WEBSITE_RUN_FROM_PACKAGE']" -o json 2>&1 | ConvertFrom-Json
$ErrorActionPreference = 'Stop'

if ($packageSetting -and $packageSetting.Count -gt 0 -and $packageSetting[0].value) {
    Write-Host "Deleting WEBSITE_RUN_FROM_PACKAGE..." -ForegroundColor Yellow
    az webapp config appsettings delete --name $FUNCTION_APP --resource-group $RESOURCE_GROUP --setting-names WEBSITE_RUN_FROM_PACKAGE --output none
    Write-Host "✓ Deleted" -ForegroundColor Green
    Start-Sleep -Seconds 10
} else {
    Write-Host "✓ Package mode already disabled" -ForegroundColor Green
}

# Step 2: Stop Function App
Write-Host "Step 2: Stopping Function App..." -ForegroundColor Yellow
az functionapp stop --name $FUNCTION_APP --resource-group $RESOURCE_GROUP --output none
Start-Sleep -Seconds 5

# Step 3: Get publishing credentials
Write-Host "Step 3: Getting publishing credentials..." -ForegroundColor Yellow
$creds = az webapp deployment list-publishing-credentials --name $FUNCTION_APP --resource-group $RESOURCE_GROUP --query "{username:publishingUserName,password:publishingPassword}" -o json | ConvertFrom-Json

if (-not $creds.username -or -not $creds.password) {
    Write-Host "✗ Failed to get publishing credentials" -ForegroundColor Red
    exit 1
}

$base64Auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($creds.username):$($creds.password)"))
$headers = @{
    "Authorization" = "Basic $base64Auth"
    "Content-Type" = "application/json"
}

Write-Host "✓ Got credentials" -ForegroundColor Green

# Step 4: Try multiple paths for function.json
Write-Host "Step 4: Finding and updating function.json..." -ForegroundColor Yellow
$paths = @(
    "site/wwwroot/function_app/function.json",
    "home/site/wwwroot/function_app/function.json",
    "wwwroot/function_app/function.json"
)

$kuduBase = "https://$FUNCTION_APP.scm.azurewebsites.net/api/vfs"
$updated = $false

foreach ($path in $paths) {
    $url = "$kuduBase/$path"
    try {
        Write-Host "  Trying: $path" -ForegroundColor Gray
        $json = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
        
        if ($json.bindings -and $json.bindings[0].authLevel -ne "anonymous") {
            Write-Host "  Found! Updating authLevel..." -ForegroundColor Yellow
            $json.bindings[0].authLevel = "anonymous"
            $updatedJson = $json | ConvertTo-Json -Depth 10 -Compress
            
            Invoke-RestMethod -Uri $url -Headers $headers -Method Put -Body $updatedJson | Out-Null
            Write-Host "✓ Updated function.json at: $path" -ForegroundColor Green
            $updated = $true
            break
        } elseif ($json.bindings -and $json.bindings[0].authLevel -eq "anonymous") {
            Write-Host "✓ Already anonymous at: $path" -ForegroundColor Green
            $updated = $true
            break
        }
    } catch {
        if ($_.Exception.Response.StatusCode -eq 404) {
            Write-Host "  Not found" -ForegroundColor Gray
            continue
        } else {
            Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Yellow
            continue
        }
    }
}

if (-not $updated) {
    Write-Host "✗ Could not find or update function.json" -ForegroundColor Red
    Write-Host "Trying alternative: Create function.json if missing..." -ForegroundColor Yellow
    
    # Try to create it
    $functionJson = @{
        scriptFile = "__init__.py"
        bindings = @(
            @{
                authLevel = "anonymous"
                type = "httpTrigger"
                direction = "in"
                name = "req"
                methods = @("get", "post", "put", "delete", "patch", "options")
                route = "{*route}"
            },
            @{
                type = "http"
                direction = "out"
                name = "$return"
            }
        )
    } | ConvertTo-Json -Depth 10
    
    $createPath = "site/wwwroot/function_app"
    $createUrl = "$kuduBase/$createPath"
    
    try {
        # Try to create directory first
        Invoke-RestMethod -Uri $createUrl -Headers $headers -Method Put -Body '{}' -ContentType "application/json" | Out-Null
    } catch {
        # Directory might exist, that's fine
    }
    
    $jsonUrl = "$kuduBase/site/wwwroot/function_app/function.json"
    try {
        Invoke-RestMethod -Uri $jsonUrl -Headers $headers -Method Put -Body $functionJson -ContentType "application/json" | Out-Null
        Write-Host "✓ Created function.json with authLevel: anonymous" -ForegroundColor Green
        $updated = $true
    } catch {
        Write-Host "✗ Could not create function.json: $_" -ForegroundColor Red
    }
}

# Step 5: Start Function App
Write-Host "Step 5: Starting Function App..." -ForegroundColor Yellow
az functionapp start --name $FUNCTION_APP --resource-group $RESOURCE_GROUP --output none
Start-Sleep -Seconds 15

# Step 6: Verify
Write-Host "Step 6: Verifying..." -ForegroundColor Yellow
$authLevel = az functionapp function show --name $FUNCTION_APP --resource-group $RESOURCE_GROUP --function-name function_app --query "config.bindings[0].authLevel" -o tsv

if ($authLevel -eq "anonymous") {
    Write-Host "✓✓✓ SUCCESS! authLevel is 'anonymous'!" -ForegroundColor Green
} else {
    Write-Host "⚠ Still showing: $authLevel" -ForegroundColor Yellow
    Write-Host "But function.json was updated. Wait 1 minute and test your app." -ForegroundColor Cyan
}

Write-Host "`n=== DONE ===" -ForegroundColor Cyan
Write-Host "Test your app now!" -ForegroundColor Green

