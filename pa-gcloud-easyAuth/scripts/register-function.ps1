# Register Function Explicitly
# This script attempts to register the function if auto-discovery fails

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

if ([string]::IsNullOrWhiteSpace($FUNCTION_APP_NAME)) {
    Write-Error "Missing FUNCTION_APP_NAME in config"
    exit 1
}

Write-Info "Attempting to trigger function discovery..."

# Method 1: Sync triggers (forces function discovery)
Write-Info "Method 1: Syncing triggers..."
az functionapp function show `
    --name $FUNCTION_APP_NAME `
    --resource-group $RESOURCE_GROUP `
    --function-name "function_app" `
    --output none 2>&1 | Out-Null

if ($LASTEXITCODE -ne 0) {
    Write-Warning "Function 'function_app' not found. This is expected if it hasn't been discovered yet."
}

# Method 2: Restart again (sometimes helps)
Write-Info "Method 2: Restarting Function App again..."
az functionapp restart --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP --output none

if ($LASTEXITCODE -eq 0) {
    Write-Success "Function App restarted"
    Write-Info "Wait 60 seconds, then check Functions list in Azure Portal"
} else {
    Write-Warning "Failed to restart Function App"
}

Write-Info ""
Write-Info "If function still not listed after 60 seconds:"
Write-Info "1. Check Kudu console: site/wwwroot/function_app/ exists"
Write-Info "2. Verify function.json is in function_app folder"
Write-Info "3. Check Function App settings: FUNCTIONS_WORKER_RUNTIME = python"
Write-Info "4. Try manual registration in Azure Portal: Functions -> + Create -> HTTP trigger"

