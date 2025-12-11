# Fix config file and CORS immediately

$ErrorActionPreference = "Stop"

function Write-Info { param([string]$msg) Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Success { param([string]$msg) Write-Host "[SUCCESS] $msg" -ForegroundColor Green }
function Write-Error { param([string]$msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }

# Load and fix config file
$configPath = "config\deployment-config.env"
if (-not (Test-Path $configPath)) {
    $configPath = "..\config\deployment-config.env"
    if (-not (Test-Path $configPath)) {
        Write-Error "deployment-config.env not found"
        exit 1
    }
}

Write-Info "Reading config file: $configPath"
$configContent = Get-Content $configPath -Raw

# Get actual Function App name from Azure
Write-Info "Getting actual Function App name from Azure..."
$actualFunctionApp = az functionapp list --resource-group pa-gcloud15-rg --query "[0].name" -o tsv

if ([string]::IsNullOrWhiteSpace($actualFunctionApp)) {
    Write-Error "Could not find Function App in resource group"
    exit 1
}

Write-Success "Found Function App: $actualFunctionApp"

# Fix FUNCTION_APP_NAME in config
$configContent = $configContent -replace "FUNCTION_APP_NAME=.*", "FUNCTION_APP_NAME=$actualFunctionApp"

# Save fixed config
$configContent | Set-Content $configPath -Encoding UTF8
Write-Success "Config file updated with correct Function App name: $actualFunctionApp"

# Get Web App name
$webAppMatch = [regex]::Match($configContent, "WEB_APP_NAME=(.+)")
$webAppName = if ($webAppMatch.Success) { $webAppMatch.Groups[1].Value.Trim() } else { "pa-gcloud15-web-14sxir" }

Write-Info "Web App: $webAppName"
Write-Info "Function App: $actualFunctionApp"

# Configure CORS on the ACTUAL Function App
$frontendUrl = "https://${webAppName}.azurewebsites.net"
Write-Info ""
Write-Info "Configuring CORS on Function App: $actualFunctionApp"
Write-Info "Allowing origin: $frontendUrl"

# Use Azure CLI to set CORS
az functionapp cors add `
    --name $actualFunctionApp `
    --resource-group pa-gcloud15-rg `
    --allowed-origins $frontendUrl `
    --output none

if ($LASTEXITCODE -eq 0) {
    Write-Success "CORS configured successfully!"
    Write-Info ""
    Write-Info "Next steps:"
    Write-Info "  1. Restart Function App: az functionapp restart --name $actualFunctionApp --resource-group pa-gcloud15-rg"
    Write-Info "  2. Wait 30 seconds"
    Write-Info "  3. Refresh your browser"
} else {
    Write-Error "Failed to configure CORS via CLI"
    Write-Info ""
    Write-Info "Please configure CORS manually in Azure Portal:"
    Write-Info "  1. Go to: https://portal.azure.com"
    Write-Info "  2. Function App → $actualFunctionApp"
    Write-Info "  3. Settings → CORS"
    Write-Info "  4. Add: $frontendUrl"
    Write-Info "  5. Enable 'Access-Control-Allow-Credentials'"
    Write-Info "  6. Save and restart"
}

