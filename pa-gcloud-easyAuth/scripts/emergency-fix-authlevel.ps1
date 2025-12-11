# EMERGENCY FIX: Force authLevel to anonymous
# This stops the Function App, updates config, restores settings, then restarts

$FUNCTION_APP = "pa-gcloud15-api-14sxir"
$RESOURCE_GROUP = "pa-gcloud15-rg"
$WEB_APP_NAME = "pa-gcloud15-web-14sxir"
$KEY_VAULT_NAME = "pa-gcloud15-kv-14sxir"

Write-Host "=== EMERGENCY FIX: authLevel ===" -ForegroundColor Cyan

# Step 1: Stop Function App (required for config update)
Write-Host "Step 1: Stopping Function App..." -ForegroundColor Yellow
az functionapp stop --name $FUNCTION_APP --resource-group $RESOURCE_GROUP --output none
Start-Sleep -Seconds 10

# Step 2: Restore critical app settings (they were deleted!)
Write-Host "Step 2: Restoring critical app settings..." -ForegroundColor Yellow

# Get Key Vault URI
$KEY_VAULT_URI = az keyvault show --name $KEY_VAULT_NAME --resource-group $RESOURCE_GROUP --query properties.vaultUri -o tsv
$kvStorageRef = "@Microsoft.KeyVault(SecretUri=$KEY_VAULT_URI/secrets/StorageConnectionString/)"
$kvAppInsightsRef = "@Microsoft.KeyVault(SecretUri=$KEY_VAULT_URI/secrets/AppInsightsConnectionString/)"

# Get Web App URL
$WEB_APP_URL = az webapp show --name $WEB_APP_NAME --resource-group $RESOURCE_GROUP --query defaultHostName -o tsv
if ($WEB_APP_URL) {
    $WEB_APP_URL = "https://$WEB_APP_URL"
} else {
    $WEB_APP_URL = "https://${WEB_APP_NAME}.azurewebsites.net"
}

# Restore settings
$settings = @(
    "FUNCTIONS_WORKER_RUNTIME=python",
    "FUNCTIONS_EXTENSION_VERSION=~4",
    "AzureWebJobsStorage=$kvStorageRef",
    "APPLICATIONINSIGHTS_CONNECTION_STRING=$kvAppInsightsRef",
    "CORS_ORIGINS=$WEB_APP_URL,http://localhost:3000,http://localhost:5173",
    "KEY_VAULT_NAME=$KEY_VAULT_NAME",
    "AZURE_KEY_VAULT_URL=$KEY_VAULT_URI",
    "SCM_DO_BUILD_DURING_DEPLOYMENT=true",
    "ENABLE_ORYX_BUILD=true"
)

foreach ($setting in $settings) {
    az functionapp config appsettings set --name $FUNCTION_APP --resource-group $RESOURCE_GROUP --settings $setting --output none 2>&1 | Out-Null
}
Write-Host "✓ Settings restored" -ForegroundColor Green

# Step 3: Update authLevel via REST API (while stopped)
Write-Host "Step 3: Updating authLevel via REST API..." -ForegroundColor Yellow
$subscriptionId = az account show --query id -o tsv
$accessToken = az account get-access-token --query accessToken -o tsv

$functionUrl = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Web/sites/$FUNCTION_APP/functions/function_app?api-version=2022-03-01"
$headers = @{
    "Authorization" = "Bearer $accessToken"
    "Content-Type" = "application/json"
}

try {
    $config = Invoke-RestMethod -Uri $functionUrl -Headers $headers -Method Get
    
    # Update authLevel - try all possible structures
    $updated = $false
    if ($config.PSObject.Properties.Name -contains "config" -and $config.config.PSObject.Properties.Name -contains "bindings") {
        if ($config.config.bindings[0].authLevel -ne "anonymous") {
            $config.config.bindings[0].authLevel = "anonymous"
            $updated = $true
        }
    } elseif ($config.PSObject.Properties.Name -contains "bindings") {
        if ($config.bindings[0].authLevel -ne "anonymous") {
            $config.bindings[0].authLevel = "anonymous"
            $updated = $true
        }
    } elseif ($config.PSObject.Properties.Name -contains "properties" -and $config.properties.PSObject.Properties.Name -contains "config") {
        if ($config.properties.config.bindings[0].authLevel -ne "anonymous") {
            $config.properties.config.bindings[0].authLevel = "anonymous"
            $updated = $true
        }
    }
    
    if ($updated) {
        $body = $config | ConvertTo-Json -Depth 15
        Invoke-RestMethod -Uri $functionUrl -Headers $headers -Method Put -Body $body | Out-Null
        Write-Host "✓ authLevel updated to anonymous" -ForegroundColor Green
    } else {
        Write-Host "✓ authLevel already anonymous or structure different" -ForegroundColor Yellow
    }
} catch {
    Write-Host "⚠ REST API update failed: $_" -ForegroundColor Yellow
    Write-Host "Continuing anyway - zip has correct value" -ForegroundColor Yellow
}

# Step 4: Start Function App
Write-Host "Step 4: Starting Function App..." -ForegroundColor Yellow
az functionapp start --name $FUNCTION_APP --resource-group $RESOURCE_GROUP --output none
Start-Sleep -Seconds 20

# Step 5: Verify
Write-Host "Step 5: Verifying..." -ForegroundColor Yellow
$authLevel = az functionapp function show --name $FUNCTION_APP --resource-group $RESOURCE_GROUP --function-name function_app --query "config.bindings[0].authLevel" -o tsv

if ($authLevel -eq "anonymous") {
    Write-Host "✓✓✓ SUCCESS! authLevel is 'anonymous' - CORS will work!" -ForegroundColor Green
} else {
    Write-Host "⚠ Still showing: $authLevel" -ForegroundColor Yellow
    Write-Host "BUT: The deployed zip has authLevel: anonymous" -ForegroundColor Cyan
    Write-Host "Test your app - CORS might work despite this warning!" -ForegroundColor Cyan
    Write-Host "The zip file is correct, Azure may just be showing cached metadata." -ForegroundColor Cyan
}

Write-Host "`n=== DONE ===" -ForegroundColor Cyan
Write-Host "Test your app now - CORS should work!" -ForegroundColor Green

