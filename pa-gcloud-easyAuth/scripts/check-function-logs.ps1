# Check Function App Logs Script
# Retrieves recent Application Insights logs to see Python errors

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

Write-Info "Checking Function App logs for errors..."
Write-Info "Function App: $FUNCTION_APP_NAME"
Write-Info ""

Write-Info "To view logs in Azure Portal:"
Write-Info "1. Go to: https://portal.azure.com"
Write-Info "2. Navigate to: Function App -> $FUNCTION_APP_NAME -> Monitor -> Log stream"
Write-Info "3. Or: Function App -> $FUNCTION_APP_NAME -> Functions -> function_app -> Monitor"
Write-Info ""
Write-Info "Alternatively, check Application Insights:"
Write-Info "1. Go to: Function App -> $FUNCTION_APP_NAME -> Application Insights"
Write-Info "2. Click 'Logs'"
Write-Info "3. Run query:"
Write-Info ""
Write-Info "   traces"
Write-Info "   | where timestamp > ago(1h)"
Write-Info "   | where severityLevel >= 3"
Write-Info "   | project timestamp, message, severityLevel"
Write-Info "   | order by timestamp desc"
Write-Info ""
Write-Info "Or for Python errors specifically:"
Write-Info ""
Write-Info "   exceptions"
Write-Info "   | where timestamp > ago(1h)"
Write-Info "   | project timestamp, outerMessage, details"
Write-Info "   | order by timestamp desc"
Write-Info ""

# Try to get recent logs via Azure CLI
Write-Info "Attempting to retrieve recent logs via Azure CLI..."
$ErrorActionPreference = 'SilentlyContinue'
$recentLogs = az functionapp log tail `
    --name $FUNCTION_APP_NAME `
    --resource-group $RESOURCE_GROUP `
    --output tsv 2>&1 | Select-Object -First 100
$ErrorActionPreference = 'Stop'

if ($recentLogs -and $recentLogs.Count -gt 0) {
    Write-Info ""
    Write-Info "Recent logs (last 100 lines):"
    Write-Info "=" * 60
    $recentLogs | ForEach-Object {
        # Look for errors
        if ($_ -match "ERROR|Exception|Traceback|ImportError|ModuleNotFoundError|Failed") {
            Write-Error "  $_"
        } elseif ($_ -match "WARNING|Warning") {
            Write-Warning "  $_"
        } else {
            Write-Info "  $_"
        }
    }
} else {
    Write-Warning "Could not retrieve logs via Azure CLI"
    Write-Info "Please check logs in Azure Portal (see instructions above)"
}

Write-Info ""
Write-Info "=" * 60
Write-Info "Look for:"
Write-Info "  - ImportError or ModuleNotFoundError (missing dependencies)"
Write-Info "  - SyntaxError (Python syntax issues)"
Write-Info "  - Traceback (full error stack)"
Write-Info "  - Failed to import (module import issues)"

