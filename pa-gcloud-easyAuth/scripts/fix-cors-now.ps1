# Quick CORS fix - sets CORS_ORIGINS in Function App to allow frontend

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

$FUNCTION_APP_NAME = $config.FUNCTION_APP_NAME
$RESOURCE_GROUP = $config.RESOURCE_GROUP
$WEB_APP_NAME = $config.WEB_APP_NAME

if ([string]::IsNullOrWhiteSpace($FUNCTION_APP_NAME) -or [string]::IsNullOrWhiteSpace($WEB_APP_NAME)) {
    Write-Error "Missing FUNCTION_APP_NAME or WEB_APP_NAME in config"
    exit 1
}

# Build frontend URL
$frontendUrl = "https://${WEB_APP_NAME}.azurewebsites.net"
$corsOrigins = "$frontendUrl,http://localhost:3000,http://localhost:5173"

Write-Info "Setting CORS_ORIGINS in Function App: $FUNCTION_APP_NAME"
Write-Info "Frontend URL: $frontendUrl"
Write-Info "CORS Origins: $corsOrigins"
Write-Info ""

# Set CORS_ORIGINS
az functionapp config appsettings set `
    --name "$FUNCTION_APP_NAME" `
    --resource-group "$RESOURCE_GROUP" `
    --settings "CORS_ORIGINS=$corsOrigins" `
    --output none

if ($LASTEXITCODE -eq 0) {
    Write-Success "CORS_ORIGINS updated successfully!"
    Write-Info ""
    Write-Info "Next steps:"
    Write-Info "  1. Restart Function App: az functionapp restart --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP"
    Write-Info "  2. Wait 30 seconds"
    Write-Info "  3. Refresh your browser and try the API call again"
} else {
    Write-Error "Failed to update CORS_ORIGINS"
    exit 1
}

