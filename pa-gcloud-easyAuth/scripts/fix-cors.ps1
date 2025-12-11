# Fix CORS Configuration Script
# Checks and updates CORS_ORIGINS setting in Function App

$ErrorActionPreference = "Stop"

function Write-Info { param([string]$msg) Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Success { param([string]$msg) Write-Host "[SUCCESS] $msg" -ForegroundColor Green }
function Write-Warning { param([string]$msg) Write-Host "[WARNING] $msg" -ForegroundColor Yellow }
function Write-Error { param([string]$msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }

# Load configuration
if (-not (Test-Path "config\deployment-config.env")) {
    Write-Error "deployment-config.env not found. Please run deploy.ps1 first."
    exit 1
}

# Parse environment file
$config = @{}
$configPath = "config\deployment-config.env"
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
$WEB_APP_NAME = $config.WEB_APP_NAME

if ([string]::IsNullOrWhiteSpace($FUNCTION_APP_NAME) -or [string]::IsNullOrWhiteSpace($RESOURCE_GROUP)) {
    Write-Error "Missing required configuration: FUNCTION_APP_NAME or RESOURCE_GROUP"
    exit 1
}

Write-Info "Checking current CORS_ORIGINS setting..."
Write-Info "Function App: $FUNCTION_APP_NAME"
Write-Info "Resource Group: $RESOURCE_GROUP"

# Get current CORS setting
$ErrorActionPreference = 'SilentlyContinue'
$currentCors = az functionapp config appsettings list `
    --name $FUNCTION_APP_NAME `
    --resource-group $RESOURCE_GROUP `
    --query "[?name=='CORS_ORIGINS'].value" -o tsv 2>&1
$ErrorActionPreference = 'Stop'

Write-Info "Current CORS_ORIGINS: $currentCors"

# Determine frontend URL
$frontendUrl = "https://${WEB_APP_NAME}.azurewebsites.net"
if ([string]::IsNullOrWhiteSpace($WEB_APP_NAME)) {
    $frontendUrl = "https://pa-gcloud15-web.azurewebsites.net"
}

# Check if CORS_ORIGINS needs updating
$needsUpdate = $false
if ([string]::IsNullOrWhiteSpace($currentCors)) {
    Write-Warning "CORS_ORIGINS is not set!"
    $needsUpdate = $true
} elseif ($currentCors -notlike "*$frontendUrl*") {
    Write-Warning "CORS_ORIGINS doesn't include frontend URL: $frontendUrl"
    $needsUpdate = $true
}

if ($needsUpdate) {
    Write-Info "Updating CORS_ORIGINS to include frontend URL..."
    $newCorsValue = "$frontendUrl,http://localhost:3000,http://localhost:5173"
    
    az functionapp config appsettings set `
        --name $FUNCTION_APP_NAME `
        --resource-group $RESOURCE_GROUP `
        --settings "CORS_ORIGINS=$newCorsValue" `
        --output none
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "CORS_ORIGINS updated successfully!"
    } else {
        Write-Error "Failed to update CORS_ORIGINS"
        exit 1
    }
    
    Write-Info "Restarting Function App to apply changes..."
    az functionapp restart --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Function App restarted!"
        Write-Info ""
        Write-Info "Wait 30-60 seconds for the restart to complete, then test the frontend again."
        Write-Info "The CORS error should be resolved."
    } else {
        Write-Error "Failed to restart Function App"
        exit 1
    }
} else {
    Write-Success "CORS_ORIGINS is correctly configured!"
    Write-Info ""
    Write-Warning "If you're still getting CORS errors, try:"
    Write-Info "1. Restart the Function App:"
    Write-Info "   az functionapp restart --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP"
    Write-Info ""
    Write-Info "2. Or redeploy the backend to ensure latest code is running:"
    Write-Info "   .\scripts\deploy-functions.ps1"
}

