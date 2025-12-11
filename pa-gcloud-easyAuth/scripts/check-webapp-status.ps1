# Check Web App Status and Docker Container Configuration

$ErrorActionPreference = "Stop"

function Write-Info { param([string]$msg) Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Success { param([string]$msg) Write-Host "[SUCCESS] $msg" -ForegroundColor Green }
function Write-Warning { param([string]$msg) Write-Host "[WARNING] $msg" -ForegroundColor Yellow }
function Write-Error { param([string]$msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }

# Load configuration
$configPath = "config\deployment-config.env"
if (-not (Test-Path $configPath)) {
    Write-Error "deployment-config.env not found. Please run deploy.ps1 first."
    exit 1
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

$WEB_APP_NAME = $config.WEB_APP_NAME
$RESOURCE_GROUP = $config.RESOURCE_GROUP
$ACR_NAME = $config.ACR_NAME

if ([string]::IsNullOrWhiteSpace($WEB_APP_NAME)) {
    Write-Error "Missing WEB_APP_NAME in config"
    exit 1
}
if ([string]::IsNullOrWhiteSpace($RESOURCE_GROUP)) {
    Write-Error "Missing RESOURCE_GROUP in config"
    exit 1
}

Write-Info "Checking Web App Status: $WEB_APP_NAME"
Write-Info ""

# Check Web App state
Write-Info "1. Checking Web App state..."
$ErrorActionPreference = 'SilentlyContinue'
$webAppState = az webapp show --name "$WEB_APP_NAME" --resource-group "$RESOURCE_GROUP" --query "state" -o tsv 2>&1
$ErrorActionPreference = 'Stop'

if ($LASTEXITCODE -eq 0) {
    Write-Info "   State: $webAppState"
    if ($webAppState -ne "Running") {
        Write-Warning "   Web App is not running. Attempting to start..."
        az webapp start --name "$WEB_APP_NAME" --resource-group "$RESOURCE_GROUP" 2>&1 | Out-Null
        Start-Sleep -Seconds 10
    }
} else {
    Write-Error "   Could not check Web App state"
}

# Check Docker container configuration
Write-Info ""
Write-Info "2. Checking Docker container configuration..."
$ErrorActionPreference = 'SilentlyContinue'
$containerConfig = az webapp config container show --name "$WEB_APP_NAME" --resource-group "$RESOURCE_GROUP" -o json 2>&1 | ConvertFrom-Json
$ErrorActionPreference = 'Stop'

if ($LASTEXITCODE -eq 0 -and $containerConfig) {
    Write-Info "   Docker Image: $($containerConfig.dockerImageName)"
    Write-Info "   Registry: $($containerConfig.registryServerUrl)"
    Write-Info "   Username: $($containerConfig.registryUserName)"
    
    if ([string]::IsNullOrWhiteSpace($containerConfig.dockerImageName)) {
        Write-Warning "   ⚠ Docker image not configured!"
        Write-Info "   Run: .\pa-deployment\scripts\deploy-frontend.ps1"
    }
} else {
    Write-Warning "   ⚠ Could not get container configuration"
    Write-Info "   Docker container may not be configured"
}

# Check app settings
Write-Info ""
Write-Info "3. Checking critical app settings..."
$ErrorActionPreference = 'SilentlyContinue'
$appSettings = az webapp config appsettings list --name "$WEB_APP_NAME" --resource-group "$RESOURCE_GROUP" -o json 2>&1 | ConvertFrom-Json
$ErrorActionPreference = 'Stop'

if ($LASTEXITCODE -eq 0 -and $appSettings) {
    $dockerSettings = $appSettings | Where-Object { $_.name -like "DOCKER_*" -or $_.name -eq "WEBSITES_ENABLE_APP_SERVICE_STORAGE" }
    foreach ($setting in $dockerSettings) {
        Write-Info "   $($setting.name): $($setting.value)"
    }
    
    $storageSetting = $appSettings | Where-Object { $_.name -eq "WEBSITES_ENABLE_APP_SERVICE_STORAGE" }
    if (-not $storageSetting -or $storageSetting.value -ne "false") {
        Write-Warning "   ⚠ WEBSITES_ENABLE_APP_SERVICE_STORAGE should be 'false' for Docker containers"
    }
}

# Check logs
Write-Info ""
Write-Info "4. Recent logs (last 50 lines)..."
Write-Info "   View full logs: https://$WEB_APP_NAME.scm.azurewebsites.net/api/logs/docker"
Write-Info ""
Write-Info "   Or run: az webapp log tail --name $WEB_APP_NAME --resource-group $RESOURCE_GROUP"
Write-Info ""

# Summary
Write-Info "=== Summary ==="
Write-Info "If Docker image is missing or incorrect:"
Write-Info "  1. Run: .\pa-deployment\scripts\build-and-push-images.ps1"
Write-Info "  2. Run: .\pa-deployment\scripts\deploy-frontend.ps1"
Write-Info ""
Write-Info "If Web App is not running:"
Write-Info "  az webapp start --name $WEB_APP_NAME --resource-group $RESOURCE_GROUP"
Write-Info ""
Write-Info "View logs in portal:"
Write-Info "  https://portal.azure.com -> Web App -> Log stream"

