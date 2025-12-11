# Quick fix script to set Node.js runtime and restart the app
# Run this if the app is showing PHP instead of Node.js

$ErrorActionPreference = "Stop"

# Load configuration
if (-not (Test-Path "config\deployment-config.env")) {
    Write-Error "deployment-config.env not found. Please run deploy.ps1 first."
    exit 1
}

# Parse config
$config = @{}
$fileLines = Get-Content "config\deployment-config.env" -Encoding UTF8
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

$WEB_APP_NAME = $config.WEB_APP_NAME
$RESOURCE_GROUP = $config.RESOURCE_GROUP

if ([string]::IsNullOrWhiteSpace($WEB_APP_NAME) -or [string]::IsNullOrWhiteSpace($RESOURCE_GROUP)) {
    Write-Error "WEB_APP_NAME or RESOURCE_GROUP missing from config"
    exit 1
}

function Write-Info { param([string]$msg) Write-Host "[INFO] $msg" -ForegroundColor Blue }
function Write-Success { param([string]$msg) Write-Host "[SUCCESS] $msg" -ForegroundColor Green }
function Write-Warning { param([string]$msg) Write-Host "[WARNING] $msg" -ForegroundColor Yellow }
function Write-Error { param([string]$msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }

Write-Info "Fixing Node.js runtime for: $WEB_APP_NAME"

# Step 1: Set Node.js runtime
Write-Info "Setting Node.js 20 runtime..."
az webapp config set `
    --name $WEB_APP_NAME `
    --resource-group $RESOURCE_GROUP `
    --linux-fx-version "NODE:20-lts" `
    --output none

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to set Node.js runtime"
    exit 1
}

Write-Success "Node.js runtime set"

# Step 2: Set Node.js version in app settings
Write-Info "Setting WEBSITE_NODE_DEFAULT_VERSION..."
az webapp config appsettings set `
    --name $WEB_APP_NAME `
    --resource-group $RESOURCE_GROUP `
    --settings "WEBSITE_NODE_DEFAULT_VERSION=~20" `
    --output none

# Step 3: Restart the app
Write-Info "Restarting app..."
az webapp restart `
    --name $WEB_APP_NAME `
    --resource-group $RESOURCE_GROUP `
    --output none

Write-Success "App restarted"
Write-Info ""
Write-Info "Next steps:"
Write-Info "1. Wait 30 seconds for the app to restart"
Write-Info "2. Check the app: https://$WEB_APP_NAME.azurewebsites.net"
Write-Info "3. Check logs: az webapp log tail --name $WEB_APP_NAME --resource-group $RESOURCE_GROUP"
Write-Info ""
Write-Info "To check what's in wwwroot, SSH in:"
Write-Info "  az webapp ssh --name $WEB_APP_NAME --resource-group $RESOURCE_GROUP"
Write-Info "  Then run: ls -la /home/site/wwwroot"

