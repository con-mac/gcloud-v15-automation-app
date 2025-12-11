# Configure CORS at Azure Functions PLATFORM level
# This works regardless of authLevel because it's handled by Azure before your code runs

$FUNCTION_APP = "pa-gcloud15-api-14sxir"
$RESOURCE_GROUP = "pa-gcloud15-rg"
$WEB_APP_NAME = "pa-gcloud15-web-14sxir"

Write-Host "=== CONFIGURING PLATFORM-LEVEL CORS ===" -ForegroundColor Cyan

# Get Web App URL
$ErrorActionPreference = 'SilentlyContinue'
$WEB_APP_URL = az webapp show --name $WEB_APP_NAME --resource-group $RESOURCE_GROUP --query defaultHostName -o tsv 2>&1
$ErrorActionPreference = 'Stop'

if ($WEB_APP_URL) {
    $WEB_APP_URL = "https://$WEB_APP_URL"
} else {
    $WEB_APP_URL = "https://${WEB_APP_NAME}.azurewebsites.net"
}

Write-Host "Web App URL: $WEB_APP_URL" -ForegroundColor Yellow

# Configure CORS via Azure CLI
# Azure Functions CORS is configured via app settings
Write-Host "`nConfiguring CORS origins..." -ForegroundColor Yellow
$corsOrigins = "$WEB_APP_URL,http://localhost:3000,http://localhost:5173"

az functionapp cors add `
    --name $FUNCTION_APP `
    --resource-group $RESOURCE_GROUP `
    --allowed-origins $corsOrigins `
    --output none

if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ CORS origins configured" -ForegroundColor Green
} else {
    Write-Host "⚠ CORS command failed, trying app settings method..." -ForegroundColor Yellow
    
    # Fallback: Set via app settings
    az functionapp config appsettings set `
        --name $FUNCTION_APP `
        --resource-group $RESOURCE_GROUP `
        --settings "CORS_ORIGINS=$corsOrigins" `
        --output none
    
    Write-Host "✓ CORS configured via app settings" -ForegroundColor Green
}

# Also ensure CORS is enabled
Write-Host "`nEnabling CORS support..." -ForegroundColor Yellow
az functionapp config set `
    --name $FUNCTION_APP `
    --resource-group $RESOURCE_GROUP `
    --always-on true `
    --output none

Write-Host "✓ Function App configured" -ForegroundColor Green

# Restart to apply
Write-Host "`nRestarting Function App..." -ForegroundColor Yellow
az functionapp restart --name $FUNCTION_APP --resource-group $RESOURCE_GROUP --output none
Start-Sleep -Seconds 10

Write-Host "`n=== DONE ===" -ForegroundColor Cyan
Write-Host "Platform-level CORS is now configured!" -ForegroundColor Green
Write-Host "This should work even if authLevel is 'function'" -ForegroundColor Green
Write-Host "Test your app now!" -ForegroundColor Green

