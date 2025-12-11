# Force Fix CORS - More aggressive approach
# This script will definitely set CORS and restart the Function App

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

Write-Info "Force fixing CORS configuration..."
Write-Info "Function App: $FUNCTION_APP_NAME"
Write-Info "Resource Group: $RESOURCE_GROUP"

# Determine frontend URL
$frontendUrl = "https://${WEB_APP_NAME}.azurewebsites.net"
if ([string]::IsNullOrWhiteSpace($WEB_APP_NAME)) {
    $frontendUrl = "https://pa-gcloud15-web.azurewebsites.net"
}

Write-Info "Frontend URL: $frontendUrl"

# Get ALL current settings first
Write-Info "Getting current app settings..."
$ErrorActionPreference = 'SilentlyContinue'
$allSettings = az functionapp config appsettings list `
    --name $FUNCTION_APP_NAME `
    --resource-group $RESOURCE_GROUP `
    --output json | ConvertFrom-Json
$ErrorActionPreference = 'Stop'

# Build settings array, updating CORS_ORIGINS
$settingsToUpdate = @()
foreach ($setting in $allSettings) {
    if ($setting.name -eq 'CORS_ORIGINS') {
        # Update CORS_ORIGINS
        $settingsToUpdate += "$($setting.name)=$frontendUrl,http://localhost:3000,http://localhost:5173"
        Write-Info "Will update: $($setting.name)"
    } else {
        # Keep other settings as-is (if they have values)
        if ($setting.value) {
            $settingsToUpdate += "$($setting.name)=$($setting.value)"
        }
    }
}

# If CORS_ORIGINS wasn't found, add it
$hasCors = $settingsToUpdate | Where-Object { $_ -like "CORS_ORIGINS=*" }
if (-not $hasCors) {
    Write-Info "CORS_ORIGINS not found, adding it..."
    $settingsToUpdate += "CORS_ORIGINS=$frontendUrl,http://localhost:3000,http://localhost:5173"
}

# Update all settings at once
Write-Info "Updating app settings (this may take a moment)..."
$settingsString = $settingsToUpdate -join ' '

az functionapp config appsettings set `
    --name $FUNCTION_APP_NAME `
    --resource-group $RESOURCE_GROUP `
    --settings $settingsString `
    --output none

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to update app settings"
    Write-Info "Trying one-by-one approach..."
    
    # Fallback: set CORS_ORIGINS individually
    az functionapp config appsettings set `
        --name $FUNCTION_APP_NAME `
        --resource-group $RESOURCE_GROUP `
        --settings "CORS_ORIGINS=$frontendUrl,http://localhost:3000,http://localhost:5173" `
        --output none
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to set CORS_ORIGINS even with fallback method"
        exit 1
    }
}

Write-Success "CORS_ORIGINS updated!"

# Verify it was set
Write-Info "Verifying CORS_ORIGINS was set correctly..."
$ErrorActionPreference = 'SilentlyContinue'
$verifyCors = az functionapp config appsettings list `
    --name $FUNCTION_APP_NAME `
    --resource-group $RESOURCE_GROUP `
    --query "[?name=='CORS_ORIGINS'].value" -o tsv 2>&1
$ErrorActionPreference = 'Stop'

if ($verifyCors -and $verifyCors -like "*$frontendUrl*") {
    Write-Success "Verified: CORS_ORIGINS = $verifyCors"
} else {
    Write-Warning "CORS_ORIGINS verification unclear: $verifyCors"
    Write-Info "Proceeding with restart anyway..."
}

# Restart Function App
Write-Info "Restarting Function App to apply changes..."
az functionapp restart --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP

if ($LASTEXITCODE -eq 0) {
    Write-Success "Function App restarted!"
    Write-Info ""
    Write-Info "Wait 30-60 seconds for the restart to complete."
    Write-Info "Then test the frontend again - CORS should be resolved."
} else {
    Write-Error "Failed to restart Function App"
    exit 1
}

