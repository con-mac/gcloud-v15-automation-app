# Test Function App Endpoints
# Helps diagnose 404 errors

$ErrorActionPreference = "Stop"

function Write-Info { param([string]$msg) Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Success { param([string]$msg) Write-Host "[SUCCESS] $msg" -ForegroundColor Green }
function Write-Warning { param([string]$msg) Write-Host "[WARNING] $msg" -ForegroundColor Yellow }
function Write-Error { param([string]$msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }

# Load configuration
$configPath = "config\deployment-config.env"
if (-not (Test-Path $configPath)) {
    $configPath = "..\config\deployment-config.env"
}

if (-not (Test-Path $configPath)) {
    Write-Error "deployment-config.env not found"
    exit 1
}

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

$baseUrl = "https://$FUNCTION_APP_NAME.azurewebsites.net"

Write-Info "Testing Function App endpoints: $baseUrl"
Write-Info ""

# Test endpoints in order
$endpoints = @(
    @{Path="/"; Name="Root"},
    @{Path="/health"; Name="Health Check"},
    @{Path="/api/v1"; Name="API Root"},
    @{Path="/api/v1/proposals"; Name="Proposals List (no trailing slash)"},
    @{Path="/api/v1/proposals/"; Name="Proposals List (with trailing slash)"},
    @{Path="/api/v1/proposals/?owner_email=test@test.com"; Name="Proposals with query param"},
    @{Path="/docs"; Name="API Docs"}
)

foreach ($endpoint in $endpoints) {
    $url = $baseUrl + $endpoint.Path
    Write-Info "Testing: $($endpoint.Name) - $url"
    
    try {
        $response = Invoke-WebRequest -Uri $url -Method GET -TimeoutSec 10 -ErrorAction Stop
        Write-Success "  ✓ Status: $($response.StatusCode)"
        if ($response.Content.Length -lt 500) {
            Write-Info "  Response: $($response.Content)"
        }
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        Write-Warning "  ✗ Status: $statusCode - $($_.Exception.Message)"
    }
    Write-Info ""
}

Write-Info "=========================================="
Write-Info "Check Function App logs for more details:"
Write-Info "https://portal.azure.com -> Function App -> Log stream"
Write-Info "Or: https://$FUNCTION_APP_NAME.scm.azurewebsites.net -> Log stream"

