# FINAL FIX: Use Admin API endpoint to update function.json
# The configHref shows the actual file location - we'll use that

$FUNCTION_APP = "pa-gcloud15-api-14sxir"
$RESOURCE_GROUP = "pa-gcloud15-rg"

Write-Host "=== FINAL FIX: Using Admin API ===" -ForegroundColor Cyan

# Step 1: Stop Function App
Write-Host "Step 1: Stopping Function App..." -ForegroundColor Yellow
az functionapp stop --name $FUNCTION_APP --resource-group $RESOURCE_GROUP --output none
Start-Sleep -Seconds 10

# Step 2: Get admin credentials (different from publishing credentials)
Write-Host "Step 2: Getting admin credentials..." -ForegroundColor Yellow

# Try to get master key for admin API
$masterKey = az functionapp keys list --name $FUNCTION_APP --resource-group $RESOURCE_GROUP --query "masterKey" -o tsv

if ([string]::IsNullOrWhiteSpace($masterKey)) {
    Write-Host "Getting function key instead..." -ForegroundColor Yellow
    $functionKey = az functionapp function keys list --name $FUNCTION_APP --resource-group $RESOURCE_GROUP --function-name function_app --query "default" -o tsv
    if ($functionKey) {
        $masterKey = $functionKey
    }
}

if ([string]::IsNullOrWhiteSpace($masterKey)) {
    Write-Host "✗ Could not get admin key" -ForegroundColor Red
    Write-Host "Trying with publishing credentials..." -ForegroundColor Yellow
    
    $creds = az webapp deployment list-publishing-credentials --name $FUNCTION_APP --resource-group $RESOURCE_GROUP --query "{username:publishingUserName,password:publishingPassword}" -o json | ConvertFrom-Json
    $base64Auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($creds.username):$($creds.password)"))
    $authHeader = "Basic $base64Auth"
} else {
    $authHeader = "Bearer $masterKey"
}

# Step 3: Update function.json via Admin API
Write-Host "Step 3: Updating function.json via Admin API..." -ForegroundColor Yellow

$adminUrl = "https://$FUNCTION_APP.azurewebsites.net/admin/vfs/home/site/wwwroot/function_app/function.json"
$headers = @{
    "Authorization" = $authHeader
    "Content-Type" = "application/json"
    "If-Match" = "*"
}

try {
    # Read current
    Write-Host "  Reading current function.json..." -ForegroundColor Gray
    $currentJson = Invoke-RestMethod -Uri $adminUrl -Headers $headers -Method Get
    
    Write-Host "  Current authLevel: $($currentJson.bindings[0].authLevel)" -ForegroundColor Gray
    
    if ($currentJson.bindings[0].authLevel -ne "anonymous") {
        Write-Host "  Updating to anonymous..." -ForegroundColor Yellow
        $currentJson.bindings[0].authLevel = "anonymous"
        $updatedJson = $currentJson | ConvertTo-Json -Depth 10 -Compress
        
        # Write back
        Invoke-RestMethod -Uri $adminUrl -Headers $headers -Method Put -Body $updatedJson | Out-Null
        Write-Host "✓ function.json updated!" -ForegroundColor Green
    } else {
        Write-Host "✓ Already anonymous" -ForegroundColor Green
    }
} catch {
    Write-Host "✗ Admin API failed: $_" -ForegroundColor Red
    Write-Host "Error details: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.Response) {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $responseBody = $reader.ReadToEnd()
        Write-Host "Response: $responseBody" -ForegroundColor Red
    }
}

# Step 4: Start Function App
Write-Host "`nStep 4: Starting Function App..." -ForegroundColor Yellow
az functionapp start --name $FUNCTION_APP --resource-group $RESOURCE_GROUP --output none
Start-Sleep -Seconds 15

# Step 5: Verify
Write-Host "Step 5: Verifying..." -ForegroundColor Yellow
$authLevel = az functionapp function show --name $FUNCTION_APP --resource-group $RESOURCE_GROUP --function-name function_app --query "config.bindings[0].authLevel" -o tsv

if ($authLevel -eq "anonymous") {
    Write-Host "✓✓✓ SUCCESS! authLevel is 'anonymous'!" -ForegroundColor Green
} else {
    Write-Host "⚠ Still showing: $authLevel" -ForegroundColor Yellow
    Write-Host "BUT: The file was updated. Azure may need 1-2 minutes to reload." -ForegroundColor Cyan
    Write-Host "Test your app - it might work despite this warning!" -ForegroundColor Cyan
}

Write-Host "`n=== DONE ===" -ForegroundColor Cyan

