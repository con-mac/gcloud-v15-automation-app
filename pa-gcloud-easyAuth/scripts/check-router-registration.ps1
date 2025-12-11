# Check Router Registration
# Diagnoses why proposals endpoint returns 404

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

Write-Info "Checking router registration for: $FUNCTION_APP_NAME"
Write-Info ""

# Check Application Insights logs for router import messages
Write-Info "Checking Application Insights logs for router import status..."
Write-Info "Look for these messages in the logs:"
Write-Info "  - 'Proposals router imported successfully'"
Write-Info "  - 'Proposals router included'"
Write-Info "  - 'Failed to import proposals router'"
Write-Info "  - 'Proposals router NOT included'"
Write-Info ""

# Get Application Insights component
$ErrorActionPreference = 'SilentlyContinue'
$appInsightsName = $config.APP_INSIGHTS_NAME
if ([string]::IsNullOrWhiteSpace($appInsightsName)) {
    $appInsightsName = "$FUNCTION_APP_NAME-insights"
}
$ErrorActionPreference = 'Stop'

Write-Info "Application Insights: $appInsightsName"
Write-Info ""

# Check if we can query logs
Write-Info "To check logs manually:"
Write-Info "1. Go to: https://portal.azure.com"
Write-Info "2. Navigate to: Application Insights > $appInsightsName > Logs"
Write-Info "3. Run this query:"
Write-Info ""
Write-Host @"
traces
| where timestamp > ago(1h)
| where message contains "proposals" or message contains "router"
| project timestamp, message, severityLevel
| order by timestamp desc
| take 20
"@ -ForegroundColor Yellow
Write-Info ""

# Also check for import errors
Write-Info "Or check for import errors:"
Write-Host @"
exceptions
| where timestamp > ago(1h)
| where outerMessage contains "proposals" or outerMessage contains "sharepoint"
| project timestamp, type, outerMessage, innermostMessage
| order by timestamp desc
| take 10
"@ -ForegroundColor Yellow
Write-Info ""

# Check API docs endpoint to see registered routes
Write-Info "Checking OpenAPI schema for registered routes..."
try {
    $openApiUrl = "https://$FUNCTION_APP_NAME.azurewebsites.net/openapi.json"
    $openApi = Invoke-RestMethod -Uri $openApiUrl -Method GET -ErrorAction Stop
    
    Write-Success "✓ OpenAPI schema retrieved"
    Write-Info ""
    Write-Info "Registered paths:"
    $paths = $openApi.PSObject.Properties.Name | Where-Object { $_ -like "/api/v1/*" }
    foreach ($path in $paths) {
        Write-Info "  - $path"
    }
    
    if ($paths -notcontains "/api/v1/proposals/" -and $paths -notcontains "/api/v1/proposals") {
        Write-Warning "✗ /api/v1/proposals route NOT found in OpenAPI schema!"
        Write-Info "This confirms the proposals router is not registered."
    } else {
        Write-Success "✓ /api/v1/proposals route found in OpenAPI schema"
    }
} catch {
    Write-Warning "Could not retrieve OpenAPI schema: $($_.Exception.Message)"
    Write-Info "This might indicate the FastAPI app isn't loading correctly."
}

Write-Info ""
Write-Info "=========================================="
Write-Info "Next Steps:"
Write-Info "1. Check Application Insights logs (queries above)"
Write-Info "2. Look for 'Failed to import proposals router' or SharePoint import errors"
Write-Info "3. If SharePoint service is missing, ensure it's deployed with the backend code"

