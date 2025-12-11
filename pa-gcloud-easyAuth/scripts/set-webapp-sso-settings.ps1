# Quick script to set SSO environment variables in Web App
# Use this if configure-auth.ps1 fails or SSO shows as "not configured"

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
            $config[$key] = $value
        }
    }
}

$WEB_APP_NAME = $config.WEB_APP_NAME
$RESOURCE_GROUP = $config.RESOURCE_GROUP
$APP_REGISTRATION_NAME = $config.APP_REGISTRATION_NAME
$ADMIN_GROUP_ID = $config.ADMIN_GROUP_ID

if ([string]::IsNullOrWhiteSpace($WEB_APP_NAME) -or [string]::IsNullOrWhiteSpace($RESOURCE_GROUP)) {
    Write-Error "Missing WEB_APP_NAME or RESOURCE_GROUP in config"
    exit 1
}

Write-Info "Setting SSO environment variables for Web App: $WEB_APP_NAME"
Write-Info ""

# Get tenant ID
$TENANT_ID = az account show --query tenantId -o tsv
if ([string]::IsNullOrWhiteSpace($TENANT_ID)) {
    Write-Error "Failed to get tenant ID"
    exit 1
}

# Get App Registration Client ID
$APP_ID = ""
if (-not [string]::IsNullOrWhiteSpace($APP_REGISTRATION_NAME)) {
    $APP_ID = az ad app list --display-name "$APP_REGISTRATION_NAME" --query "[0].appId" -o tsv
    if ([string]::IsNullOrWhiteSpace($APP_ID)) {
        Write-Error "App Registration '$APP_REGISTRATION_NAME' not found"
        exit 1
    }
} else {
    Write-Error "APP_REGISTRATION_NAME not found in config"
    exit 1
}

# Build Web App URL
$WEB_APP_URL = "https://${WEB_APP_NAME}.azurewebsites.net"

Write-Info "SSO Configuration:"
Write-Info "  Tenant ID: $($TENANT_ID.Substring(0,8))..."
Write-Info "  Client ID: $($APP_ID.Substring(0,8))..."
Write-Info "  Redirect URI: $WEB_APP_URL"
if ($ADMIN_GROUP_ID) {
    Write-Info "  Admin Group ID: $($ADMIN_GROUP_ID.Substring(0,8))..."
}
Write-Info ""

# Build app settings array
$webAuthSettings = @(
    "VITE_AZURE_AD_TENANT_ID=$TENANT_ID",
    "VITE_AZURE_AD_CLIENT_ID=$APP_ID",
    "VITE_AZURE_AD_REDIRECT_URI=$WEB_APP_URL"
)

# Add admin group ID if configured
if (-not [string]::IsNullOrWhiteSpace($ADMIN_GROUP_ID)) {
    $webAuthSettings += "VITE_AZURE_AD_ADMIN_GROUP_ID=$ADMIN_GROUP_ID"
}

Write-Info "Setting app settings on Web App..."
$ErrorActionPreference = 'SilentlyContinue'
az webapp config appsettings set `
    --name "$WEB_APP_NAME" `
    --resource-group "$RESOURCE_GROUP" `
    --settings $webAuthSettings `
    --output none 2>&1 | Out-Null
$ErrorActionPreference = 'Stop'

if ($LASTEXITCODE -eq 0) {
    Write-Success "Web App SSO settings updated!"
    Write-Info ""
    Write-Info "Next steps:"
    Write-Info "  1. Restart the Web App: az webapp restart --name $WEB_APP_NAME --resource-group $RESOURCE_GROUP"
    Write-Info "  2. Wait 30 seconds for the container to restart"
    Write-Info "  3. Refresh the browser: $WEB_APP_URL"
    Write-Info ""
    Write-Info "The SSO 'not configured' message should disappear after restart."
} else {
    Write-Error "Failed to update Web App settings"
    Write-Info "Please check:"
    Write-Info "  1. Web App exists: az webapp show --name $WEB_APP_NAME --resource-group $RESOURCE_GROUP"
    Write-Info "  2. You have permissions to update app settings"
    exit 1
}

