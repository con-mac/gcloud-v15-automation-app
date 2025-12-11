# Instructions for setting Key Vault references via Azure Portal
# This is more reliable than PowerShell when there are parsing issues

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

$kvUri = "https://${KEY_VAULT_NAME}.vault.azure.net"

Write-Info "================================================"
Write-Info "Set Key Vault References via Azure Portal"
Write-Info "================================================"
Write-Info ""
Write-Info "This method is more reliable when PowerShell has parsing issues."
Write-Info ""
Write-Info "Step 1: Open Azure Portal"
Write-Info "  URL: https://portal.azure.com"
Write-Info ""
Write-Info "Step 2: Navigate to Function App"
Write-Info "  1. Search for: $FUNCTION_APP_NAME"
Write-Info "  2. Click on the Function App"
Write-Info "  3. In left menu, click: Configuration"
Write-Info ""
Write-Info "Step 3: Add/Edit Application Settings"
Write-Info "  For each setting below, click '+ New application setting' or edit existing:"
Write-Info ""
Write-Info "Setting 1: AZURE_AD_TENANT_ID"
Write-Info "  Name: AZURE_AD_TENANT_ID"
Write-Info "  Value: @Microsoft.KeyVault(SecretUri=${kvUri}/secrets/AzureADTenantId/)"
Write-Info ""
Write-Info "Setting 2: AZURE_AD_CLIENT_ID"
Write-Info "  Name: AZURE_AD_CLIENT_ID"
Write-Info "  Value: @Microsoft.KeyVault(SecretUri=${kvUri}/secrets/AzureADClientId/)"
Write-Info ""
Write-Info "Setting 3: AZURE_AD_CLIENT_SECRET"
Write-Info "  Name: AZURE_AD_CLIENT_SECRET"
Write-Info "  Value: @Microsoft.KeyVault(SecretUri=${kvUri}/secrets/AzureADClientSecret/)"
Write-Info ""
Write-Info "Step 4: Save"
Write-Info "  Click 'Save' at the top"
Write-Info "  Confirm when prompted"
Write-Info ""
Write-Info "Step 5: Verify"
Write-Info "  After saving, verify each setting shows the Key Vault reference"
Write-Info "  The value should start with: @Microsoft.KeyVault"
Write-Info ""
Write-Info "Alternative: Use 'Key Vault Reference' Button"
Write-Info "  1. Click '+ New application setting'"
Write-Info "  2. Enter the name (e.g., AZURE_AD_TENANT_ID)"
Write-Info "  3. Click the 'Key Vault Reference' toggle"
Write-Info "  4. Select Key Vault: $KEY_VAULT_NAME"
Write-Info "  5. Select Secret: AzureADTenantId"
Write-Info "  6. Click 'OK'"
Write-Info "  7. Repeat for other secrets"
Write-Info ""
Write-Info "This method is easier and avoids typing the full reference!"
Write-Info ""
Write-Info "After setting, restart the Function App:"
Write-Info "  az functionapp restart --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP"
Write-Info ""

