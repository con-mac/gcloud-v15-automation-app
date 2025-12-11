# Check Python Environment in Azure Functions
# Provides commands to check what Python/pip is available

$ErrorActionPreference = "Stop"

function Write-Info { param([string]$msg) Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Success { param([string]$msg) Write-Host "[SUCCESS] $msg" -ForegroundColor Green }

# Load configuration
$configPath = "config\deployment-config.env"
if (-not (Test-Path $configPath)) {
    $configPath = "..\config\deployment-config.env"
}

if (-not (Test-Path $configPath)) {
    Write-Host "deployment-config.env not found. Using default Function App name."
    $FUNCTION_APP_NAME = "pa-gcloud15-api"
} else {
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
    if ([string]::IsNullOrWhiteSpace($FUNCTION_APP_NAME)) {
        $FUNCTION_APP_NAME = "pa-gcloud15-api"
    }
}

Write-Info "Azure Functions Python Environment Check"
Write-Info "=========================================="
Write-Info ""
Write-Info "SSH Console URL: https://$FUNCTION_APP_NAME.scm.azurewebsites.net"
Write-Info ""
Write-Info "Run these commands in the SSH console to check Python environment:"
Write-Info ""
Write-Host "which python3" -ForegroundColor Yellow
Write-Host "which python" -ForegroundColor Yellow
Write-Host "python3 --version" -ForegroundColor Yellow
Write-Host "ls -la /usr/local/bin/python*" -ForegroundColor Yellow
Write-Host "ls -la /azure-functions-host/workers/python/*/LINUX/X64/" -ForegroundColor Yellow
Write-Info ""
Write-Info "Try these pip alternatives:"
Write-Info ""
Write-Host "/usr/local/bin/python3 -m pip --version" -ForegroundColor Yellow
Write-Host "/azure-functions-host/workers/python/3.11/LINUX/X64/python -m pip --version" -ForegroundColor Yellow
Write-Info ""
Write-Info "If pip is not available, we need to ensure dependencies are installed during deployment."
Write-Info "The deployment script should handle this automatically."

