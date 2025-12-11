# Simple one-command fix for config file

$configPath = "pa-deployment\config\deployment-config.env"
if (-not (Test-Path $configPath)) {
    $configPath = "config\deployment-config.env"
}

Write-Host "Fixing config file: $configPath" -ForegroundColor Cyan

# Get actual Function App name
$actualFunctionApp = az functionapp list --resource-group pa-gcloud15-rg --query "[0].name" -o tsv

if ([string]::IsNullOrWhiteSpace($actualFunctionApp)) {
    Write-Host "ERROR: Could not find Function App" -ForegroundColor Red
    exit 1
}

Write-Host "Found Function App: $actualFunctionApp" -ForegroundColor Green

# Fix the file
$content = Get-Content $configPath -Raw
$content = $content -replace "FUNCTION_APP_NAME=.*", "FUNCTION_APP_NAME=$actualFunctionApp"
$content | Set-Content $configPath -Encoding UTF8

Write-Host "Config file fixed!" -ForegroundColor Green
Write-Host "FUNCTION_APP_NAME is now: $actualFunctionApp" -ForegroundColor Green

