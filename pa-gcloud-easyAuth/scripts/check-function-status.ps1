# Quick Function Status Check
# Checks if function is registered and shows recent errors

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

Write-Info "Checking function registration status..."
Write-Info ""

# Check if function is registered
$ErrorActionPreference = 'SilentlyContinue'
$functions = az functionapp function list `
    --name $FUNCTION_APP_NAME `
    --resource-group $RESOURCE_GROUP `
    --query "[].name" -o tsv 2>&1
$ErrorActionPreference = 'Stop'

if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($functions)) {
    Write-Info "Registered functions:"
    $functions | ForEach-Object { Write-Info "  - $_" }
    
    if ($functions -contains "function_app") {
        Write-Success "✓ function_app IS REGISTERED!"
        Write-Info ""
        Write-Warning "But API endpoints return 404. This suggests:"
        Write-Info "1. Import errors in __init__.py"
        Write-Info "2. FastAPI app not loading correctly"
        Write-Info "3. Check Application Insights logs for Python errors"
    } else {
        Write-Error "✗ function_app is NOT in registered functions list"
        Write-Info ""
        Write-Info "Possible causes:"
        Write-Info "1. Function discovery hasn't completed (wait 2-3 minutes)"
        Write-Info "2. function.json has syntax errors"
        Write-Info "3. __init__.py has import errors preventing registration"
    }
} else {
    Write-Error "✗ No functions registered OR error listing functions"
    Write-Info ""
    Write-Info "This means Azure Functions hasn't discovered any functions."
    Write-Info "Check:"
    Write-Info "1. function_app folder exists in deployment"
    Write-Info "2. function.json is valid JSON"
    Write-Info "3. __init__.py doesn't have syntax errors"
}

Write-Info ""
Write-Info "To check logs in Azure Portal:"
Write-Info "  Function App -> Monitor -> Logs"
Write-Info "  Function App -> Log stream"
Write-Info ""
Write-Info "Look for:"
Write-Info "  - 'No functions found'"
Write-Info "  - 'ImportError' or 'ModuleNotFoundError'"
Write-Info "  - 'SyntaxError' in __init__.py"

