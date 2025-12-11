# Verify CORS is working in the backend
# This script checks if the backend is reading CORS_ORIGINS correctly

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
    Write-Error "Missing required configuration"
    exit 1
}

Write-Info "Verifying CORS configuration in Function App..."
Write-Info "Function App: $FUNCTION_APP_NAME"

# Check CORS_ORIGINS setting
Write-Info "Checking CORS_ORIGINS app setting..."
$ErrorActionPreference = 'SilentlyContinue'
$corsSetting = az functionapp config appsettings list `
    --name $FUNCTION_APP_NAME `
    --resource-group $RESOURCE_GROUP `
    --query "[?name=='CORS_ORIGINS'].value" -o tsv 2>&1
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($corsSetting)) {
    Write-Error "CORS_ORIGINS is not set!"
    exit 1
}

Write-Success "CORS_ORIGINS is set: $corsSetting"

# Check if frontend URL is in the list
$frontendUrl = "https://${WEB_APP_NAME}.azurewebsites.net"
if ($corsSetting -like "*$frontendUrl*") {
    Write-Success "Frontend URL found in CORS_ORIGINS: $frontendUrl"
} else {
    Write-Warning "Frontend URL NOT found in CORS_ORIGINS!"
    Write-Warning "Expected: $frontendUrl"
    Write-Warning "Current: $corsSetting"
}

# Test the API endpoint directly
Write-Info "`nTesting API endpoint with CORS preflight..."
$apiUrl = "https://${FUNCTION_APP_NAME}.azurewebsites.net/api/v1/health"

Write-Info "Making OPTIONS request (CORS preflight) to: $apiUrl"
Write-Info "Origin header: $frontendUrl"

try {
    # Use Invoke-WebRequest to test CORS preflight
    $headers = @{
        'Origin' = $frontendUrl
        'Access-Control-Request-Method' = 'GET'
        'Access-Control-Request-Headers' = 'Content-Type'
    }
    
    $response = Invoke-WebRequest -Uri $apiUrl -Method OPTIONS -Headers $headers -UseBasicParsing -ErrorAction Stop
    
    Write-Success "CORS preflight successful!"
    Write-Info "Response headers:"
    $response.Headers | ForEach-Object {
        if ($_ -like "*Access-Control*") {
            Write-Host "  $_" -ForegroundColor Green
        }
    }
} catch {
    Write-Warning "CORS preflight test failed or returned non-200 status"
    Write-Info "Error: $($_.Exception.Message)"
    Write-Info "`nThis might be normal - the backend might need to be redeployed."
    Write-Info "Try redeploying the backend:"
    Write-Info "  .\scripts\deploy-functions.ps1"
}

Write-Info "`nNext steps:"
Write-Info "1. If CORS still fails, redeploy the backend:"
Write-Info "   .\scripts\deploy-functions.ps1"
Write-Info ""
Write-Info "2. Check Function App logs in Azure Portal:"
Write-Info "   https://portal.azure.com -> Function App -> Log stream"
Write-Info ""
Write-Info "3. Verify the backend is reading CORS_ORIGINS correctly"

