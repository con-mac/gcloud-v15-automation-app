# Check Deployed Files Script
# Uses Azure CLI to check what files are actually deployed

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

Write-Info "Checking deployed files in Function App: $FUNCTION_APP_NAME"
Write-Info ""

# Method 1: Check if function is registered
Write-Info "Method 1: Checking if function 'function_app' is registered..."
$ErrorActionPreference = 'SilentlyContinue'
$functionCheck = az functionapp function show `
    --name $FUNCTION_APP_NAME `
    --resource-group $RESOURCE_GROUP `
    --function-name "function_app" `
    --query "name" -o tsv 2>&1
$ErrorActionPreference = 'Stop'

if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($functionCheck)) {
    Write-Success "✓ Function 'function_app' IS REGISTERED!"
    Write-Info ""
    Write-Warning "But API endpoints return 404. This suggests:"
    Write-Info "1. Function is registered but routes aren't working"
    Write-Info "2. Check Function App logs for import errors"
    Write-Info "3. Verify __init__.py imports are working"
} else {
    Write-Error "✗ Function 'function_app' is NOT registered"
    Write-Info ""
}

# Method 2: Check deployment package location
Write-Info ""
Write-Info "Method 2: Checking deployment package location..."
$ErrorActionPreference = 'SilentlyContinue'
$runFromPackage = az functionapp config appsettings list `
    --name $FUNCTION_APP_NAME `
    --resource-group $RESOURCE_GROUP `
    --query "[?name=='WEBSITE_RUN_FROM_PACKAGE'].value" -o tsv 2>&1
$ErrorActionPreference = 'Stop'

if (-not [string]::IsNullOrWhiteSpace($runFromPackage)) {
    Write-Info "Function App is running from package:"
    Write-Info "  $runFromPackage"
    Write-Info ""
    Write-Warning "Since it's running from a zip package, we can't directly list files."
    Write-Info "The function_app folder should be in that zip."
}

# Method 3: Check Function App logs for errors
Write-Info ""
Write-Info "Method 3: Checking recent Function App logs for errors..."
Write-Info "Fetching last 50 log lines..."
$ErrorActionPreference = 'SilentlyContinue'
$logs = az functionapp log tail `
    --name $FUNCTION_APP_NAME `
    --resource-group $RESOURCE_GROUP `
    --output tsv 2>&1 | Select-Object -First 50
$ErrorActionPreference = 'Stop'

if ($logs) {
    Write-Info "Recent logs:"
    $logs | ForEach-Object { Write-Info "  $_" }
    
    # Look for specific errors
    $importErrors = $logs | Where-Object { $_ -match "ImportError|ModuleNotFoundError|No module named" }
    $functionErrors = $logs | Where-Object { $_ -match "function_app|function discovery|No functions found" }
    
    if ($importErrors) {
        Write-Warning ""
        Write-Warning "Found import errors in logs:"
        $importErrors | ForEach-Object { Write-Warning "  $_" }
    }
    
    if ($functionErrors) {
        Write-Warning ""
        Write-Warning "Found function-related errors in logs:"
        $functionErrors | ForEach-Object { Write-Warning "  $_" }
    }
} else {
    Write-Info "No recent logs found (or log streaming not available)"
}

# Method 4: List all registered functions
Write-Info ""
Write-Info "Method 4: Listing all registered functions..."
$ErrorActionPreference = 'SilentlyContinue'
$functions = az functionapp function list `
    --name $FUNCTION_APP_NAME `
    --resource-group $RESOURCE_GROUP `
    --query "[].name" -o tsv 2>&1
$ErrorActionPreference = 'Stop'

if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($functions)) {
    Write-Info "Registered functions:"
    $functions | ForEach-Object { Write-Info "  - $_" }
    
    if ($functions -notcontains "function_app") {
        Write-Error ""
        Write-Error "function_app is NOT in the list of registered functions!"
        Write-Info ""
        Write-Info "This means:"
        Write-Info "1. The function_app folder may not be in the deployment zip"
        Write-Info "2. Or function.json has syntax errors"
        Write-Info "3. Or Azure Functions hasn't discovered it yet"
    }
} else {
    Write-Warning "Could not list functions (may be empty or error)"
}

Write-Info ""
Write-Info "=" * 60
Write-Info "SUMMARY"
Write-Info "=" * 60
Write-Info ""
Write-Info "If function_app is not registered, the deployment zip likely"
Write-Info "didn't include the function_app folder properly."
Write-Info ""
Write-Info "NEXT STEPS:"
Write-Info "1. If function_app is missing: Redeploy with fixed script"
Write-Info "2. If function_app exists but not registered: Check logs for errors"
Write-Info "3. Check Azure Portal -> Function App -> Functions (should list function_app)"
Write-Info ""
Write-Info "To view logs in Azure Portal:"
Write-Info "  Function App -> Log stream"
Write-Info "  Function App -> Monitor -> Logs"

