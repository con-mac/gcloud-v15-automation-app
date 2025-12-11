# Deploy Function App with Dependencies
# Uses Azure Functions Core Tools which properly installs dependencies

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

Write-Info "Deploying Function App with dependencies: $FUNCTION_APP_NAME"
Write-Info ""

# Check if Azure Functions Core Tools is installed
$funcCheck = Get-Command func -ErrorAction SilentlyContinue
if (-not $funcCheck) {
    Write-Error "Azure Functions Core Tools (func) is not installed!"
    Write-Info ""
    Write-Info "Install it with:"
    Write-Info "  npm install -g azure-functions-core-tools@4"
    Write-Info ""
    Write-Info "Or use Chocolatey:"
    Write-Info "  choco install azure-functions-core-tools-4"
    Write-Info ""
    Write-Info "Azure Functions Core Tools is REQUIRED to properly install Python dependencies."
    Write-Info "Zip deployment does not reliably install dependencies."
    exit 1
}

Write-Success "✓ Azure Functions Core Tools found"
Write-Info ""

# Navigate to backend directory
$backendPath = "backend"
if (-not (Test-Path $backendPath)) {
    $backendPath = "..\backend"
    if (-not (Test-Path $backendPath)) {
        Write-Error "Backend directory not found!"
        exit 1
    }
}

Write-Info "Using backend directory: $backendPath"
Push-Location $backendPath

try {
    # Ensure requirements.txt exists
    if (-not (Test-Path "requirements.txt")) {
        Write-Warning "requirements.txt not found in backend directory"
        $mainRepoRequirements = "..\..\backend\requirements.txt"
        if (Test-Path $mainRepoRequirements) {
            Write-Info "Copying requirements.txt from main repo..."
            Copy-Item -Path $mainRepoRequirements -Destination "requirements.txt" -Force
            Write-Success "✓ requirements.txt copied"
        } else {
            Write-Error "requirements.txt not found! Cannot deploy."
            exit 1
        }
    }
    
    # Ensure host.json exists
    if (-not (Test-Path "host.json")) {
        Write-Warning "host.json not found. Copying from main repo..."
        if (Test-Path "..\..\backend\host.json") {
            Copy-Item -Path "..\..\backend\host.json" -Destination "host.json" -Force
            Write-Success "✓ host.json copied"
        } else {
            Write-Error "host.json not found! Cannot deploy."
            exit 1
        }
    }
    
    # Ensure function_app folder exists
    if (-not (Test-Path "function_app")) {
        Write-Warning "function_app folder not found. Copying from main repo..."
        if (Test-Path "..\..\backend\function_app") {
            Copy-Item -Path "..\..\backend\function_app" -Destination "function_app" -Recurse -Force
            Write-Success "✓ function_app folder copied"
        } else {
            Write-Error "function_app folder not found! Cannot deploy."
            exit 1
        }
    }
    
    # CRITICAL: Ensure app folder exists (contains FastAPI routes)
    if (-not (Test-Path "app")) {
        Write-Warning "app folder not found. Copying from main repo..."
        if (Test-Path "..\..\backend\app") {
            Copy-Item -Path "..\..\backend\app" -Destination "app" -Recurse -Force -Exclude "*.pyc","__pycache__"
            Write-Success "✓ app folder copied"
        } else {
            Write-Error "app folder not found! Cannot deploy."
            exit 1
        }
    }
    
    # CRITICAL: Ensure sharepoint_service folder exists (required for proposals router)
    if (-not (Test-Path "sharepoint_service")) {
        Write-Warning "sharepoint_service folder not found. Copying from main repo..."
        if (Test-Path "..\..\backend\sharepoint_service") {
            Copy-Item -Path "..\..\backend\sharepoint_service" -Destination "sharepoint_service" -Recurse -Force -Exclude "*.pyc","__pycache__"
            Write-Success "✓ sharepoint_service folder copied"
        } else {
            Write-Warning "sharepoint_service folder not found in main repo. Proposals router may fail."
        }
    }
    
    Write-Info ""
    Write-Info "Deploying with Azure Functions Core Tools..."
    Write-Info "This will automatically install dependencies from requirements.txt"
    Write-Info "This may take 5-10 minutes..."
    Write-Info ""
    
    # Deploy using Functions Core Tools
    # This properly handles dependency installation
    func azure functionapp publish $FUNCTION_APP_NAME --python --build remote
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "✓ Deployment successful!"
        Write-Info ""
        Write-Info "Dependencies should be installed automatically."
        Write-Info "Wait 2-3 minutes for the Function App to restart, then test your API."
    } else {
        Write-Error "Deployment failed!"
        Write-Info "Check the output above for errors."
        exit 1
    }
} finally {
    Pop-Location
}

