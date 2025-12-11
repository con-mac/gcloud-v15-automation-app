# Quick Fix: Enable Dependency Installation
# Sets SCM_DO_BUILD_DURING_DEPLOYMENT=true to enable automatic pip install from requirements.txt

$ErrorActionPreference = "Stop"

function Write-Info { param([string]$msg) Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Success { param([string]$msg) Write-Host "[SUCCESS] $msg" -ForegroundColor Green }
function Write-Warning { param([string]$msg) Write-Host "[WARNING] $msg" -ForegroundColor Yellow }
function Write-Error { param([string]$msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }

# Load configuration
$configPath = "config\deployment-config.env"
if (-not (Test-Path $configPath)) {
    $configPath = "..\config\deployment-config.env"
    if (-not (Test-Path $configPath)) {
        Write-Error "deployment-config.env not found. Please run deploy.ps1 first."
        exit 1
    }
}

# Parse environment file
$config = @{}
$fileLines = Get-Content $configPath -Encoding UTF8
foreach ($line in $fileLines) {
    $line = $line.Trim()
    if ($line -and -not $line.StartsWith('#')) {
        $equalsIndex = $line.IndexOf('=')
        if ($equalsIndex -gt 0) {
            $key = $line.Substring(0, $equalsIndex).Trim()
            $value = $line.Substring($equalsIndex + 1).Trim()
            if ($key -and $value) {
                $config[$key] = $value
            }
        }
    }
}

$FUNCTION_APP_NAME = $config.FUNCTION_APP_NAME
$RESOURCE_GROUP = $config.RESOURCE_GROUP

if ([string]::IsNullOrWhiteSpace($FUNCTION_APP_NAME)) {
    Write-Error "Missing FUNCTION_APP_NAME in config"
    exit 1
}

Write-Info "Enabling automatic dependency installation for: $FUNCTION_APP_NAME"
Write-Info ""
Write-Info "This setting tells Azure Functions to install packages from requirements.txt during deployment"
Write-Info ""

# Set the critical app setting
Write-Info "Setting SCM_DO_BUILD_DURING_DEPLOYMENT=true..."
az functionapp config appsettings set `
    --name $FUNCTION_APP_NAME `
    --resource-group $RESOURCE_GROUP `
    --settings "SCM_DO_BUILD_DURING_DEPLOYMENT=true" `
    --output none

if ($LASTEXITCODE -eq 0) {
    Write-Success "✓ App setting configured successfully!"
    Write-Info ""
    Write-Info "Next steps:"
    Write-Info "1. Restart the Function App to trigger dependency installation"
    Write-Info "2. Wait 5-10 minutes for dependencies to install"
    Write-Info "3. Test the API again"
    Write-Info ""
    Write-Info "Restarting Function App now..."
    az functionapp restart --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP --output none
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Function App restarted"
        Write-Info ""
        Write-Info "Dependencies should now install automatically."
        Write-Info "Check logs in Azure Portal to see pip install progress."
        Write-Info ""
        Write-Warning "Note: If requirements.txt wasn't in the zip root, you still need to redeploy."
        Write-Info "Run: .\pa-deployment\scripts\deploy-functions.ps1"
    } else {
        Write-Warning "Failed to restart Function App. Please restart manually in Azure Portal."
    }
} else {
    Write-Error "Failed to set app setting"
    exit 1
}

