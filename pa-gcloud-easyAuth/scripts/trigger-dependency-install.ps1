# Trigger Dependency Installation Script
# Manually triggers Azure Functions to install Python packages from requirements.txt
# This is useful if dependencies weren't installed automatically after deployment

$ErrorActionPreference = "Stop"

function Write-Info { param([string]$msg) Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Success { param([string]$msg) Write-Host "[SUCCESS] $msg" -ForegroundColor Green }
function Write-Warning { param([string]$msg) Write-Host "[WARNING] $msg" -ForegroundColor Yellow }
function Write-Error { param([string]$msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }

# Load configuration
$configPath = "config\deployment-config.env"
if (-not (Test-Path $configPath)) {
    # Try from pa-deployment directory
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

Write-Info "Triggering dependency installation for Function App: $FUNCTION_APP_NAME"
Write-Info ""

# Method 1: Restart Function App (triggers dependency installation if requirements.txt exists)
Write-Info "Method 1: Restarting Function App to trigger dependency installation..."
Write-Info "Azure Functions will automatically install packages from requirements.txt on restart"
Write-Info ""

az functionapp restart --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP --output none
if ($LASTEXITCODE -eq 0) {
    Write-Success "Function App restarted successfully"
    Write-Info ""
    Write-Info "Waiting 60 seconds for dependency installation to complete..."
    Write-Info "Azure Functions installs packages from requirements.txt during startup"
    Start-Sleep -Seconds 60
    
    Write-Info ""
    Write-Info "Dependency installation should be in progress."
    Write-Info "Check Function App logs in Azure Portal to see installation progress."
    Write-Info ""
    Write-Info "To check logs:"
    Write-Info "1. Go to: https://portal.azure.com"
    Write-Info "2. Navigate to Function App: $FUNCTION_APP_NAME"
    Write-Info "3. Go to 'Log stream' or 'Application Insights'"
    Write-Info "4. Look for messages about 'Installing packages' or 'pip install'"
    Write-Info ""
    Write-Warning "Note: Dependency installation can take 5-10 minutes for large requirements.txt files"
    Write-Info ""
    Write-Info "After installation completes, test the API again."
} else {
    Write-Error "Failed to restart Function App"
    Write-Info ""
    Write-Info "Alternative: Manually restart via Azure Portal"
    Write-Info "1. Go to: https://portal.azure.com"
    Write-Info "2. Navigate to Function App: $FUNCTION_APP_NAME"
    Write-Info "3. Click 'Restart' button"
    exit 1
}

# Method 2: Sync triggers (also triggers dependency check)
Write-Info ""
Write-Info "Method 2: Syncing triggers (also checks dependencies)..."
az functionapp sync-triggers --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP --output none
if ($LASTEXITCODE -eq 0) {
    Write-Success "Triggers synced successfully"
} else {
    Write-Warning "Trigger sync failed (non-critical)"
}

Write-Info ""
Write-Success "Dependency installation triggered!"
Write-Info ""
Write-Info "Next steps:"
Write-Info "1. Wait 5-10 minutes for dependencies to install"
Write-Info "2. Check Function App logs for installation progress"
Write-Info "3. Test API endpoint: https://$FUNCTION_APP_NAME.azurewebsites.net/api/v1/health"
Write-Info ""
Write-Info "If ModuleNotFoundError persists after 10 minutes:"
Write-Info "- Verify requirements.txt exists at zip root (use check-requirements-deployment.ps1)"
Write-Info "- Check Application Insights logs for pip install errors"
Write-Info "- Redeploy using deploy-functions.ps1"

