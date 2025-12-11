# Simple Dependency Installation
# Uses Azure CLI to run pip install directly on the Function App

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

Write-Info "Installing Python dependencies for: $FUNCTION_APP_NAME"
Write-Info ""
Write-Info "This will use Azure Portal SSH console to install dependencies."
Write-Info ""

# Find requirements.txt locally
$localRequirements = $null
$possiblePaths = @(
    "backend\requirements.txt",
    "..\backend\requirements.txt",
    "..\..\backend\requirements.txt",
    "pa-deployment\backend\requirements.txt"
)

foreach ($path in $possiblePaths) {
    if (Test-Path $path) {
        $localRequirements = (Resolve-Path $path).Path
        Write-Success "Found requirements.txt at: $localRequirements"
        break
    }
}

if ($null -eq $localRequirements) {
    Write-Error "Could not find requirements.txt locally!"
    Write-Info "Please ensure requirements.txt exists in backend directory."
    exit 1
}

# Read requirements.txt to get package list
Write-Info "Reading requirements.txt..."
$requirements = Get-Content $localRequirements | Where-Object { $_ -notmatch '^\s*#' -and $_.Trim() -ne '' }

Write-Info ""
Write-Info "=========================================="
Write-Info "MANUAL INSTALLATION INSTRUCTIONS"
Write-Info "=========================================="
Write-Info ""
Write-Info "1. Open Azure Portal:"
Write-Info "   https://portal.azure.com"
Write-Info ""
Write-Info "2. Navigate to your Function App:"
Write-Info "   $FUNCTION_APP_NAME"
Write-Info ""
Write-Info "3. Go to: Development Tools > SSH (or Advanced Tools > Go > SSH)"
Write-Info ""
Write-Info "4. In the SSH console, run these commands:"
Write-Info ""
Write-Info "   cd /home/site/wwwroot"
Write-Info "   python3 -m pip install -r requirements.txt --target .python_packages/lib/site-packages"
Write-Info ""
Write-Info "5. Wait for installation to complete (5-10 minutes)"
Write-Info ""
Write-Info "6. Restart the Function App:"
Write-Info "   az functionapp restart --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP"
Write-Info ""
Write-Info "=========================================="
Write-Info ""

# Offer to open the portal
$openPortal = Read-Host "Would you like me to open the Azure Portal SSH console? (y/n)"
if ($openPortal -eq 'y' -or $openPortal -eq 'Y') {
    $sshUrl = "https://$FUNCTION_APP_NAME.scm.azurewebsites.net/webssh/host"
    Write-Info "Opening SSH console in browser..."
    Start-Process $sshUrl
    Write-Info ""
    Write-Info "Once the SSH console opens, run:"
    Write-Info "  cd /home/site/wwwroot"
    Write-Info "  python3 -m pip install -r requirements.txt --target .python_packages/lib/site-packages"
}

Write-Info ""
Write-Info "Alternatively, you can copy this command and run it in the SSH console:"
Write-Info ""
Write-Host "python3 -m pip install -r requirements.txt --target .python_packages/lib/site-packages" -ForegroundColor Yellow
Write-Info ""

