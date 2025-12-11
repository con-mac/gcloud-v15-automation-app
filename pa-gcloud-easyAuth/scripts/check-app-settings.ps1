# Check Function App settings to verify Key Vault references

$ErrorActionPreference = "Stop"

function Write-Info { param([string]$msg) Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Success { param([string]$msg) Write-Host "[SUCCESS] $msg" -ForegroundColor Green }
function Write-Warning { param([string]$msg) Write-Host "[WARNING] $msg" -ForegroundColor Yellow }
function Write-Error { param([string]$msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }

# Load configuration
# Look for config in same location as other scripts (project root/config/)
$configPath = "config\deployment-config.env"
if (-not (Test-Path $configPath)) {
    Write-Error "deployment-config.env not found. Please run deploy.ps1 first."
    Write-Info "Expected location: $((Get-Location).Path)\config\deployment-config.env"
    exit 1
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

Write-Info "Checking app settings for Function App: $FUNCTION_APP_NAME"
Write-Info ""

# Get app settings
$appSettings = az functionapp config appsettings list `
    --name "$FUNCTION_APP_NAME" `
    --resource-group "$RESOURCE_GROUP" `
    --query "[?name=='AZURE_AD_TENANT_ID' || name=='AZURE_AD_CLIENT_ID' || name=='AZURE_AD_CLIENT_SECRET' || name=='SHAREPOINT_SITE_ID' || name=='SHAREPOINT_SITE_URL' || name=='USE_SHAREPOINT']" `
    -o json | ConvertFrom-Json

Write-Info "Azure AD and SharePoint Settings:"
Write-Info ""

foreach ($setting in $appSettings) {
    $value = $setting.value
    if ($value -like "*@Microsoft.KeyVault*") {
        Write-Warning "$($setting.name): Key Vault Reference (not resolved)"
        Write-Info "  Value: $value"
    } elseif ([string]::IsNullOrWhiteSpace($value)) {
        Write-Error "$($setting.name): EMPTY or NOT SET"
    } else {
        if ($setting.name -like "*SECRET*") {
            Write-Success "$($setting.name): Set (value hidden)"
        } else {
            Write-Success "$($setting.name): $value"
        }
    }
}

Write-Info ""
Write-Info "Note: Key Vault references should be automatically resolved by Azure Functions."
Write-Info "If they're not resolving, check:"
Write-Info "1. Function App has managed identity enabled"
Write-Info "2. Managed identity has 'Key Vault Secrets User' role"
Write-Info "3. Key Vault has 'Allow Azure services to access this key vault' enabled"

