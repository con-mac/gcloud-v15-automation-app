# Verify Key Vault references are set correctly

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

Write-Info "Verifying Key Vault references for: $FUNCTION_APP_NAME"
Write-Info ""

# Get all app settings
$ErrorActionPreference = 'SilentlyContinue'
$allSettings = az functionapp config appsettings list `
    --name "$FUNCTION_APP_NAME" `
    --resource-group "$RESOURCE_GROUP" `
    -o json 2>&1 | ConvertFrom-Json
$ErrorActionPreference = 'Stop'

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to retrieve app settings"
    exit 1
}

$tenantId = $allSettings | Where-Object { $_.name -eq "AZURE_AD_TENANT_ID" }
$clientId = $allSettings | Where-Object { $_.name -eq "AZURE_AD_CLIENT_ID" }
$clientSecret = $allSettings | Where-Object { $_.name -eq "AZURE_AD_CLIENT_SECRET" }

Write-Info "Current settings:"
Write-Info ""

if ($tenantId) {
    $value = $tenantId.value
    if ([string]::IsNullOrWhiteSpace($value)) {
        Write-Error "AZURE_AD_TENANT_ID: NOT SET (value is null or empty)"
    } elseif ($value -like "*@Microsoft.KeyVault*") {
        Write-Success "AZURE_AD_TENANT_ID: Key Vault Reference"
        Write-Info "  Value: $value"
    } else {
        Write-Warning "AZURE_AD_TENANT_ID: Direct value (not Key Vault reference)"
        Write-Info "  Value: $($value.Substring(0, [Math]::Min(20, $value.Length)))..."
    }
} else {
    Write-Error "AZURE_AD_TENANT_ID: NOT FOUND"
}

if ($clientId) {
    $value = $clientId.value
    if ([string]::IsNullOrWhiteSpace($value)) {
        Write-Error "AZURE_AD_CLIENT_ID: NOT SET (value is null or empty)"
    } elseif ($value -like "*@Microsoft.KeyVault*") {
        Write-Success "AZURE_AD_CLIENT_ID: Key Vault Reference"
        Write-Info "  Value: $value"
    } else {
        Write-Warning "AZURE_AD_CLIENT_ID: Direct value (not Key Vault reference)"
        Write-Info "  Value: $($value.Substring(0, [Math]::Min(20, $value.Length)))..."
    }
} else {
    Write-Error "AZURE_AD_CLIENT_ID: NOT FOUND"
}

if ($clientSecret) {
    $value = $clientSecret.value
    if ([string]::IsNullOrWhiteSpace($value)) {
        Write-Error "AZURE_AD_CLIENT_SECRET: NOT SET (value is null or empty)"
    } elseif ($value -like "*@Microsoft.KeyVault*") {
        Write-Success "AZURE_AD_CLIENT_SECRET: Key Vault Reference"
        Write-Info "  Value: $value"
    } else {
        Write-Warning "AZURE_AD_CLIENT_SECRET: Direct value (not Key Vault reference)"
        Write-Info "  Value: [HIDDEN]"
    }
} else {
    Write-Error "AZURE_AD_CLIENT_SECRET: NOT FOUND"
}

Write-Info ""
Write-Info "Expected Key Vault reference format:"
Write-Info "  @Microsoft.KeyVault(SecretUri=https://$KEY_VAULT_NAME.vault.azure.net/secrets/AzureADTenantId/)"
Write-Info ""
Write-Info "If values are null, the Key Vault references were not set correctly."
Write-Info "Try using the Azure Portal method instead (see below)."

