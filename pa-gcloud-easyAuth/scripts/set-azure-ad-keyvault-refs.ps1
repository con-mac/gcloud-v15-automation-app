# Set Azure AD credentials as Key Vault references in Function App

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

if ([string]::IsNullOrWhiteSpace($FUNCTION_APP_NAME) -or 
    [string]::IsNullOrWhiteSpace($RESOURCE_GROUP) -or 
    [string]::IsNullOrWhiteSpace($KEY_VAULT_NAME)) {
    Write-Error "Missing required configuration. Please check deployment-config.env"
    exit 1
}

Write-Info "Setting Azure AD Key Vault references for: $FUNCTION_APP_NAME"
Write-Info "Key Vault: $KEY_VAULT_NAME"
Write-Info ""

# Verify secrets exist in Key Vault
Write-Info "Verifying secrets exist in Key Vault..."
$secrets = @("AzureADTenantId", "AzureADClientId", "AzureADClientSecret")
foreach ($secretName in $secrets) {
    $ErrorActionPreference = 'SilentlyContinue'
    $secret = az keyvault secret show --vault-name $KEY_VAULT_NAME --name $secretName --query "name" -o tsv 2>&1
    $ErrorActionPreference = 'Stop'
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "  ✓ Secret exists: $secretName"
    } else {
        Write-Error "  ✗ Secret missing: $secretName"
        Write-Error "    Please run configure-auth.ps1 first to create secrets"
        exit 1
    }
}

Write-Info ""
Write-Info "Setting Key Vault references in Function App..."

# Build Key Vault references
# Use single quotes in the string to prevent PowerShell variable expansion issues
$kvUri = "https://${KEY_VAULT_NAME}.vault.azure.net"
$kvTenantRef = '@Microsoft.KeyVault(SecretUri=' + $kvUri + '/secrets/AzureADTenantId/)'
$kvClientIdRef = '@Microsoft.KeyVault(SecretUri=' + $kvUri + '/secrets/AzureADClientId/)'
$kvClientSecretRef = '@Microsoft.KeyVault(SecretUri=' + $kvUri + '/secrets/AzureADClientSecret/)'

# Set each setting individually
# Use --set parameter instead of --settings to avoid PowerShell parsing issues
Write-Info "Setting AZURE_AD_TENANT_ID..."
$ErrorActionPreference = 'SilentlyContinue'
# Use --set which handles special characters better than --settings
$result = az functionapp config appsettings set `
    --name "$FUNCTION_APP_NAME" `
    --resource-group "$RESOURCE_GROUP" `
    --set "AZURE_AD_TENANT_ID=$kvTenantRef" `
    2>&1
$ErrorActionPreference = 'Stop'

if ($LASTEXITCODE -eq 0) {
    Write-Success "  ✓ AZURE_AD_TENANT_ID set"
} else {
    Write-Error "  ✗ Failed to set AZURE_AD_TENANT_ID"
    Write-Error "  Error: $result"
    Write-Info "  Attempting with --settings parameter..."
    
    # Try with --settings using proper escaping
    $ErrorActionPreference = 'SilentlyContinue'
    $result2 = az functionapp config appsettings set `
        --name "$FUNCTION_APP_NAME" `
        --resource-group "$RESOURCE_GROUP" `
        --settings "AZURE_AD_TENANT_ID=`"$kvTenantRef`"" `
        2>&1
    $ErrorActionPreference = 'Stop'
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "  ✓ AZURE_AD_TENANT_ID set (with --settings)"
    } else {
        Write-Error "  ✗ Both methods failed"
        Write-Error "  Last error: $result2"
        Write-Info ""
        Write-Warning "  Manual step required - use Azure Portal:"
        Write-Warning "  1. Go to: https://portal.azure.com"
        Write-Warning "  2. Function App → $FUNCTION_APP_NAME → Configuration"
        Write-Warning "  3. Add new application setting:"
        Write-Warning "     Name: AZURE_AD_TENANT_ID"
        Write-Warning "     Value: $kvTenantRef"
        Write-Warning "  4. Click 'OK' and 'Save'"
        Write-Info ""
        Write-Info "  See: pa-deployment/scripts/set-keyvault-refs-portal.md for detailed steps"
        exit 1
    }
}

Write-Info "Setting AZURE_AD_CLIENT_ID..."
$ErrorActionPreference = 'SilentlyContinue'
$result = az functionapp config appsettings set `
    --name "$FUNCTION_APP_NAME" `
    --resource-group "$RESOURCE_GROUP" `
    --set "AZURE_AD_CLIENT_ID=$kvClientIdRef" `
    2>&1
$ErrorActionPreference = 'Stop'

if ($LASTEXITCODE -eq 0) {
    Write-Success "  ✓ AZURE_AD_CLIENT_ID set"
} else {
    Write-Error "  ✗ Failed to set AZURE_AD_CLIENT_ID"
    Write-Error "  Error: $result"
    Write-Warning "  Please set manually in Azure Portal (see instructions above)"
    exit 1
}

Write-Info "Setting AZURE_AD_CLIENT_SECRET..."
$ErrorActionPreference = 'SilentlyContinue'
$result = az functionapp config appsettings set `
    --name "$FUNCTION_APP_NAME" `
    --resource-group "$RESOURCE_GROUP" `
    --set "AZURE_AD_CLIENT_SECRET=$kvClientSecretRef" `
    2>&1
$ErrorActionPreference = 'Stop'

if ($LASTEXITCODE -eq 0) {
    Write-Success "  ✓ AZURE_AD_CLIENT_SECRET set"
} else {
    Write-Error "  ✗ Failed to set AZURE_AD_CLIENT_SECRET"
    Write-Error "  Error: $result"
    Write-Warning "  Please set manually in Azure Portal (see instructions above)"
    exit 1
}

Write-Info ""
Write-Success "All Key Vault references set successfully!"
Write-Info ""
Write-Info "Verifying settings..."
Start-Sleep -Seconds 2

# Verify they were set
$ErrorActionPreference = 'SilentlyContinue'
$tenantId = az functionapp config appsettings list `
    --name "$FUNCTION_APP_NAME" `
    --resource-group "$RESOURCE_GROUP" `
    --query "[?name=='AZURE_AD_TENANT_ID'].value" -o tsv 2>&1
$ErrorActionPreference = 'Stop'

if ($tenantId -like "*@Microsoft.KeyVault*") {
    Write-Success "  ✓ AZURE_AD_TENANT_ID verified: Key Vault reference"
} else {
    Write-Warning "  ⚠ AZURE_AD_TENANT_ID may not be set correctly: $tenantId"
}

Write-Info ""
Write-Info "Next steps:"
Write-Info "1. Restart Function App: az functionapp restart --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP"
Write-Info "2. Wait 2-3 minutes for restart"
Write-Info "3. Test SharePoint: curl https://$FUNCTION_APP_NAME.azurewebsites.net/api/v1/sharepoint/test"
Write-Info ""
Write-Info "Note: If Key Vault references don't auto-resolve, the code will read directly from Key Vault"

