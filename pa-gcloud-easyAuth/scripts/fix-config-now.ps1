# Quick fix for config file - detects actual Function App and updates config

$ErrorActionPreference = "Stop"

function Write-Info { param([string]$msg) Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Success { param([string]$msg) Write-Host "[SUCCESS] $msg" -ForegroundColor Green }
function Write-Error { param([string]$msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }

# Find config file
$configPath = "config\deployment-config.env"
if (-not (Test-Path $configPath)) {
    $configPath = "pa-deployment\config\deployment-config.env"
    if (-not (Test-Path $configPath)) {
        Write-Error "deployment-config.env not found. Please run from project root or pa-deployment directory."
        exit 1
    }
}

Write-Info "Reading config file: $configPath"

# Get actual Function App name from Azure
Write-Info "Getting actual Function App name from Azure..."
$resourceGroup = "pa-gcloud15-rg"
$actualFunctionApp = az functionapp list --resource-group $resourceGroup --query "[0].name" -o tsv

if ([string]::IsNullOrWhiteSpace($actualFunctionApp)) {
    Write-Error "Could not find Function App in resource group: $resourceGroup"
    Write-Info "Available resource groups:"
    az group list --query "[].name" -o table
    exit 1
}

Write-Success "Found Function App: $actualFunctionApp"

# Read and update config file
$configLines = Get-Content $configPath -Encoding UTF8
$updated = $false
$newLines = @()

foreach ($line in $configLines) {
    if ($line -match "^FUNCTION_APP_NAME=") {
        $newLines += "FUNCTION_APP_NAME=$actualFunctionApp"
        $updated = $true
        Write-Info "Updated: FUNCTION_APP_NAME=$actualFunctionApp"
    } else {
        $newLines += $line
    }
}

if ($updated) {
    $newLines | Set-Content $configPath -Encoding UTF8
    Write-Success "Config file updated successfully!"
    Write-Info ""
    Write-Info "Next steps:"
    Write-Info "  1. Rebuild Docker image: .\pa-deployment\scripts\build-and-push-images.ps1"
    Write-Info "  2. Redeploy frontend: .\pa-deployment\scripts\deploy-frontend.ps1"
    Write-Info "  3. Restart Web App: az webapp restart --name pa-gcloud15-web-14sxir --resource-group pa-gcloud15-rg"
} else {
    Write-Info "FUNCTION_APP_NAME already correct or not found in config"
}

