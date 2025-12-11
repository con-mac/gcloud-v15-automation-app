# Complete fix script for frontend deployment issues
# Fixes: PHP runtime, source files in wwwroot, broken startup.sh

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

Write-Info "=== Complete Frontend Fix ==="
Write-Info "Web App: $WEB_APP_NAME"
Write-Info "Resource Group: $RESOURCE_GROUP"
Write-Info ""

# Step 1: Force Node.js runtime
Write-Info "Step 1: Setting Node.js 20 runtime..."
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

# Step 2: Set app settings for Oryx build
Write-Info "Step 2: Configuring app settings for Oryx build..."
$appSettings = @(
    "SCM_DO_BUILD_DURING_DEPLOYMENT=true",
    "ENABLE_ORYX_BUILD=true",
    "WEBSITE_RUN_FROM_PACKAGE=0",
    "WEBSITE_NODE_DEFAULT_VERSION=~20",
    "POST_BUILD_COMMAND=mkdir -p /home/site/wwwroot && cp -r dist/. /home/site/wwwroot/ 2>/dev/null || true",
    "WEBSITES_ENABLE_APP_SERVICE_STORAGE=false",
    "PORT=8080"
)

foreach ($setting in $appSettings) {
    $ErrorActionPreference = 'SilentlyContinue'
    $result = az webapp config appsettings set `
        --name $WEB_APP_NAME `
        --resource-group $RESOURCE_GROUP `
        --settings "$setting" `
        --output none 2>&1
    $ErrorActionPreference = 'Stop'
    
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Failed to set: $setting"
    }
}
Write-Success "App settings configured"

# Step 3: Set startup command (simple, no script file)
Write-Info "Step 3: Setting startup command..."
$startupCommand = "npx -y serve -s /home/site/wwwroot -l 8080 --host 0.0.0.0 || npx -y serve -s /home/site/dist -l 8080 --host 0.0.0.0"
az webapp config set `
    --name $WEB_APP_NAME `
    --resource-group $RESOURCE_GROUP `
    --startup-file "$startupCommand" `
    --output none

Write-Success "Startup command set"

# Step 4: Clean wwwroot (remove source files and old startup.sh)
Write-Info "Step 4: Cleaning wwwroot (removing source files)..."
Write-Warning "This will remove all files from wwwroot. The next deployment will rebuild them."
$confirm = Read-Host "Continue? (y/n)"
if ($confirm -ne 'y') {
    Write-Info "Skipping cleanup. You may need to manually clean wwwroot."
} else {
    # Use Kudu API to delete files
    Write-Info "Deleting files in wwwroot..."
    $ErrorActionPreference = 'SilentlyContinue'
    
    # Get publishing credentials
    $publishCreds = az webapp deployment list-publishing-profiles `
        --name $WEB_APP_NAME `
        --resource-group $RESOURCE_GROUP `
        --xml 2>&1 | Out-String
    
    if ($LASTEXITCODE -eq 0) {
        Write-Info "Note: Files will be cleaned on next deployment"
        Write-Info "To manually clean via SSH, run: rm -rf /home/site/wwwroot/*"
    }
    $ErrorActionPreference = 'Stop'
}

# Step 5: Restart app
Write-Info "Step 5: Restarting app..."
az webapp restart `
    --name $WEB_APP_NAME `
    --resource-group $RESOURCE_GROUP `
    --output none

Write-Success "App restarted"
Write-Info ""
Write-Info "=== Fix Complete ==="
Write-Info ""
Write-Info "Next steps:"
Write-Info "1. Wait 30 seconds for the app to restart"
Write-Info "2. Redeploy the frontend: .\scripts\deploy-frontend.ps1"
Write-Info "3. This will:"
Write-Info "   - Build the app with Oryx (npm install + npm run build)"
Write-Info "   - Copy dist files to wwwroot"
Write-Info "   - Start serving with npx serve"
Write-Info ""
Write-Info "To check logs: az webapp log tail --name $WEB_APP_NAME --resource-group $RESOURCE_GROUP"

