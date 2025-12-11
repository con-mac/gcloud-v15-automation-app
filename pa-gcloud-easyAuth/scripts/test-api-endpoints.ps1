# Test API Endpoints Script
# Verifies that API routes are accessible

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

$apiBaseUrl = "https://${FUNCTION_APP_NAME}.azurewebsites.net"

Write-Info "Testing API endpoints for: $apiBaseUrl"
Write-Info ""

# Test endpoints
$endpoints = @(
    @{ Path = "/"; Name = "Root" },
    @{ Path = "/health"; Name = "Health Check" },
    @{ Path = "/api/v1/"; Name = "API Root" },
    @{ Path = "/api/v1/proposals/"; Name = "Proposals List" },
    @{ Path = "/docs"; Name = "API Docs" }
)

foreach ($endpoint in $endpoints) {
    $url = "$apiBaseUrl$($endpoint.Path)"
    Write-Info "Testing: $($endpoint.Name) - $url"
    
    try {
        $response = Invoke-WebRequest -Uri $url -Method GET -UseBasicParsing -ErrorAction Stop -TimeoutSec 10
        
        if ($response.StatusCode -eq 200) {
            Write-Success "  ✓ $($endpoint.Name) - Status: $($response.StatusCode)"
        } else {
            Write-Warning "  ⚠ $($endpoint.Name) - Status: $($response.StatusCode)"
        }
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -eq 404) {
            Write-Error "  ✗ $($endpoint.Name) - 404 Not Found"
        } elseif ($statusCode -eq 500) {
            Write-Error "  ✗ $($endpoint.Name) - 500 Internal Server Error"
        } else {
            Write-Error "  ✗ $($endpoint.Name) - Error: $($_.Exception.Message)"
        }
    }
    
    Write-Info ""
}

Write-Info "Test complete!"
Write-Info ""
Write-Info "If /api/v1/proposals/ returns 404, the proposals router may not be loading."
Write-Info "Check Function App logs in Azure Portal for import errors."

