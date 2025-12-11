# Check if Azure AD credentials are set in Function App

$ErrorActionPreference = "Stop"

function Write-Info { param([string]$msg) Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Success { param([string]$msg) Write-Host "[SUCCESS] $msg" -ForegroundColor Green }
function Write-Warning { param([string]$msg) Write-Host "[WARNING] $msg" -ForegroundColor Yellow }
function Write-Error { param([string]$msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }

# Load configuration
$configPath = "config\deployment-config.env"
if (-not (Test-Path $configPath)) {
    Write-Error "deployment-config.env not found. Please run deploy.ps1 first."
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
$KEY_VAULT_NAME = $config.KEY_VAULT_NAME

Write-Info "Checking Azure AD credential settings for: $FUNCTION_APP_NAME"
Write-Info ""

# Get all app settings
$allSettings = az functionapp config appsettings list `
    --name "$FUNCTION_APP_NAME" `
    --resource-group "$RESOURCE_GROUP" `
    -o json | ConvertFrom-Json

Write-Info "Azure AD and Key Vault Settings:"
Write-Info ""

$tenantId = $allSettings | Where-Object { $_.name -eq "AZURE_AD_TENANT_ID" }
$clientId = $allSettings | Where-Object { $_.name -eq "AZURE_AD_CLIENT_ID" }
$clientSecret = $allSettings | Where-Object { $_.name -eq "AZURE_AD_CLIENT_SECRET" }
$kvUrl = $allSettings | Where-Object { $_.name -eq "AZURE_KEY_VAULT_URL" }
$kvName = $allSettings | Where-Object { $_.name -eq "KEY_VAULT_NAME" }

if ($tenantId) {
    $value = $tenantId.value
    if ($value -like "*@Microsoft.KeyVault*") {
        Write-Warning "AZURE_AD_TENANT_ID: Key Vault Reference (should auto-resolve)"
        Write-Info "  Value: $value"
    } elseif ([string]::IsNullOrWhiteSpace($value)) {
        Write-Error "AZURE_AD_TENANT_ID: EMPTY"
    } else {
        Write-Success "AZURE_AD_TENANT_ID: Set (direct value)"
    }
} else {
    Write-Error "AZURE_AD_TENANT_ID: NOT SET"
}

if ($clientId) {
    $value = $clientId.value
    if ($value -like "*@Microsoft.KeyVault*") {
        Write-Warning "AZURE_AD_CLIENT_ID: Key Vault Reference (should auto-resolve)"
        Write-Info "  Value: $value"
    } elseif ([string]::IsNullOrWhiteSpace($value)) {
        Write-Error "AZURE_AD_CLIENT_ID: EMPTY"
    } else {
        Write-Success "AZURE_AD_CLIENT_ID: Set (direct value)"
    }
} else {
    Write-Error "AZURE_AD_CLIENT_ID: NOT SET"
}

if ($clientSecret) {
    $value = $clientSecret.value
    if ($value -like "*@Microsoft.KeyVault*") {
        Write-Warning "AZURE_AD_CLIENT_SECRET: Key Vault Reference (should auto-resolve)"
        Write-Info "  Value: $value"
    } elseif ([string]::IsNullOrWhiteSpace($value)) {
        Write-Error "AZURE_AD_CLIENT_SECRET: EMPTY"
    } else {
        Write-Success "AZURE_AD_CLIENT_SECRET: Set (direct value - hidden)"
    }
} else {
    Write-Error "AZURE_AD_CLIENT_SECRET: NOT SET"
}

if ($kvUrl) {
    Write-Success "AZURE_KEY_VAULT_URL: $($kvUrl.value)"
} else {
    Write-Error "AZURE_KEY_VAULT_URL: NOT SET"
}

if ($kvName) {
    Write-Success "KEY_VAULT_NAME: $($kvName.value)"
} else {
    Write-Warning "KEY_VAULT_NAME: NOT SET (will try to construct from AZURE_KEY_VAULT_URL)"
}

Write-Info ""
Write-Info "If credentials are Key Vault references but not resolving:"
Write-Info "1. Verify managed identity is enabled: az functionapp identity show --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP"
Write-Info "2. Verify Key Vault access: Check 'Key Vault Secrets User' role is granted"
Write-Info "3. The code will now try to read directly from Key Vault if env vars are missing"

