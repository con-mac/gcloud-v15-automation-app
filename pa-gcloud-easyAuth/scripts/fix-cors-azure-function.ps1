# Fix CORS at Azure Function App Level
# This configures CORS at the Function App level (not just app settings)

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

Write-Info "Configuring CORS at Azure Function App level..."
Write-Info "Function App: $FUNCTION_APP_NAME"

# Determine frontend URL
$frontendUrl = "https://${WEB_APP_NAME}.azurewebsites.net"
if ([string]::IsNullOrWhiteSpace($WEB_APP_NAME)) {
    $frontendUrl = "https://pa-gcloud15-web.azurewebsites.net"
}

Write-Info "Frontend URL: $frontendUrl"

# Check current CORS settings
Write-Info "Checking current CORS settings..."
$ErrorActionPreference = 'SilentlyContinue'
$currentCors = az functionapp cors show `
    --name $FUNCTION_APP_NAME `
    --resource-group $RESOURCE_GROUP `
    --output json 2>&1 | ConvertFrom-Json
$ErrorActionPreference = 'Stop'

if ($currentCors) {
    Write-Info "Current allowed origins: $($currentCors.allowedOrigins -join ', ')"
}

# Add CORS origins (this adds to existing, doesn't replace)
Write-Info "Adding CORS allowed origins..."
$origins = @(
    $frontendUrl,
    "http://localhost:3000",
    "http://localhost:5173"
)

foreach ($origin in $origins) {
    Write-Info "Adding origin: $origin"
    $ErrorActionPreference = 'SilentlyContinue'
    az functionapp cors add `
        --name $FUNCTION_APP_NAME `
        --resource-group $RESOURCE_GROUP `
        --allowed-origins $origin `
        --output none 2>&1 | Out-Null
    $ErrorActionPreference = 'Stop'
    
    if ($LASTEXITCODE -eq 0) {
        Write-Info "  ✓ Added: $origin"
    } else {
        Write-Warning "  ⚠ May already exist: $origin"
    }
}

# Verify CORS settings
Write-Info "Verifying CORS configuration..."
$ErrorActionPreference = 'SilentlyContinue'
$verifyCors = az functionapp cors show `
    --name $FUNCTION_APP_NAME `
    --resource-group $RESOURCE_GROUP `
    --output json 2>&1 | ConvertFrom-Json
$ErrorActionPreference = 'Stop'

if ($verifyCors -and $verifyCors.allowedOrigins) {
    Write-Success "CORS configured successfully!"
    Write-Info "Allowed origins:"
    $verifyCors.allowedOrigins | ForEach-Object {
        if ($_ -like "*$frontendUrl*") {
            Write-Host "  ✓ $_" -ForegroundColor Green
        } else {
            Write-Host "  • $_" -ForegroundColor Yellow
        }
    }
} else {
    Write-Warning "Could not verify CORS settings, but they should be applied"
}

# Restart Function App
Write-Info "Restarting Function App to apply CORS changes..."
az functionapp restart --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP

if ($LASTEXITCODE -eq 0) {
    Write-Success "Function App restarted!"
    Write-Info ""
    Write-Info "Wait 30-60 seconds for the restart to complete."
    Write-Info "Then test the frontend - CORS should now work!"
    Write-Info ""
    Write-Info "Note: This configures CORS at the Azure Function App level,"
    Write-Info "which is required for CORS to work properly in Azure Functions."
} else {
    Write-Error "Failed to restart Function App"
    exit 1
}

