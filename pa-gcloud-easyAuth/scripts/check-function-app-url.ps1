# Quick script to check Function App name and URL

$ErrorActionPreference = "Stop"

function Write-Info { param([string]$msg) Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Success { param([string]$msg) Write-Host "[SUCCESS] $msg" -ForegroundColor Green }

# Load configuration
$configPath = "config\deployment-config.env"
if (-not (Test-Path $configPath)) {
    $configPath = "..\config\deployment-config.env"
    if (-not (Test-Path $configPath)) {
        Write-Error "deployment-config.env not found"
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

$FUNCTION_APP_NAME = $config.FUNCTION_APP_NAME
$RESOURCE_GROUP = $config.RESOURCE_GROUP
$WEB_APP_NAME = $config.WEB_APP_NAME

Write-Info "From deployment-config.env:"
Write-Info "  Function App Name: $FUNCTION_APP_NAME"
Write-Info "  Web App Name: $WEB_APP_NAME"
Write-Info "  Resource Group: $RESOURCE_GROUP"
Write-Info ""

# Get actual Function App URL
Write-Info "Checking actual Function App URL..."
$ErrorActionPreference = 'SilentlyContinue'
$functionAppUrl = az functionapp show --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP" --query defaultHostName -o tsv 2>&1
$ErrorActionPreference = 'Stop'

if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($functionAppUrl)) {
    Write-Success "Actual Function App URL: https://$functionAppUrl"
    Write-Info ""
    Write-Info "CORS should allow:"
    Write-Info "  https://${WEB_APP_NAME}.azurewebsites.net"
    Write-Info ""
    Write-Info "Function App CORS should be configured at:"
    Write-Info "  Azure Portal → Function App → $FUNCTION_APP_NAME → Settings → CORS"
} else {
    Write-Error "Could not get Function App URL. Check if Function App exists."
    Write-Info "Try: az functionapp list --resource-group $RESOURCE_GROUP"
}

