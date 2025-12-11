# Test SharePoint Connectivity
# Tests the /api/v1/sharepoint/test endpoint

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
            $config[$key] = $value
        }
    }
}

$functionAppName = $config["FUNCTION_APP_NAME"]
$resourceGroup = $config["RESOURCE_GROUP"]

if (-not $functionAppName -or -not $resourceGroup) {
    Write-Error "FUNCTION_APP_NAME or RESOURCE_GROUP not found in config"
    exit 1
}

$apiUrl = "https://${functionAppName}.azurewebsites.net/api/v1/sharepoint/test"

Write-Info "Testing SharePoint connectivity..."
Write-Info "Endpoint: $apiUrl"
Write-Info ""

try {
    $response = Invoke-RestMethod -Uri $apiUrl -Method Get -ContentType "application/json" -ErrorAction Stop
    
    Write-Info "Response received:"
    Write-Info "  Connected: $($response.connected)"
    Write-Info "  Site ID: $($response.site_id)"
    Write-Info "  Site URL: $($response.site_url)"
    Write-Info "  Message: $($response.message)"
    
    if ($response.error) {
        Write-Warning "  Error: $($response.error)"
    }
    
    Write-Info ""
    
    if ($response.connected) {
        Write-Success "✓ SharePoint connectivity test PASSED!"
    } else {
        Write-Warning "✗ SharePoint connectivity test FAILED"
        Write-Warning "This may be a test tenant limitation (conmacdev.onmicrosoft.com)"
        Write-Warning "Production deployment (paconsulting.com) should work correctly"
    }
    
} catch {
    Write-Error "Failed to test SharePoint connectivity: $_"
    Write-Info ""
    Write-Info "Try checking:"
    Write-Info "1. Function App is running: az functionapp show --name $functionAppName --resource-group $resourceGroup"
    Write-Info "2. Endpoint is accessible: curl $apiUrl"
    exit 1
}

