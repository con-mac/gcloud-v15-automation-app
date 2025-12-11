# Fix malformed Key Vault references and add missing ones

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

Write-Info "Fixing Key Vault references for: $FUNCTION_APP_NAME"
Write-Info ""

# Build correct Key Vault references (with closing parenthesis)
$kvTenantRef = "@Microsoft.KeyVault(SecretUri=${kvUri}/secrets/AzureADTenantId/)"
$kvClientIdRef = "@Microsoft.KeyVault(SecretUri=${kvUri}/secrets/AzureADClientId/)"
$kvClientSecretRef = "@Microsoft.KeyVault(SecretUri=${kvUri}/secrets/AzureADClientSecret/)"

Write-Info "Correct Key Vault reference format:"
Write-Info "  $kvTenantRef"
Write-Info ""

# Fix AZURE_AD_TENANT_ID (add missing closing parenthesis)
Write-Info "Fixing AZURE_AD_TENANT_ID (adding missing closing parenthesis)..."
$ErrorActionPreference = 'SilentlyContinue'
$result = az functionapp config appsettings set `
    --name "$FUNCTION_APP_NAME" `
    --resource-group "$RESOURCE_GROUP" `
    --settings "AZURE_AD_TENANT_ID=$kvTenantRef" `
    --output none 2>&1
$ErrorActionPreference = 'Stop'

if ($LASTEXITCODE -eq 0) {
    Write-Success "  ✓ AZURE_AD_TENANT_ID fixed"
} else {
    Write-Warning "  ⚠ Could not fix via CLI. Error: $result"
    Write-Info "    You may need to fix this in Azure Portal"
}

# Fix AZURE_AD_CLIENT_ID (add missing closing parenthesis)
Write-Info "Fixing AZURE_AD_CLIENT_ID (adding missing closing parenthesis)..."
$ErrorActionPreference = 'SilentlyContinue'
$result = az functionapp config appsettings set `
    --name "$FUNCTION_APP_NAME" `
    --resource-group "$RESOURCE_GROUP" `
    --settings "AZURE_AD_CLIENT_ID=$kvClientIdRef" `
    --output none 2>&1
$ErrorActionPreference = 'Stop'

if ($LASTEXITCODE -eq 0) {
    Write-Success "  ✓ AZURE_AD_CLIENT_ID fixed"
} else {
    Write-Warning "  ⚠ Could not fix via CLI. Error: $result"
    Write-Info "    You may need to fix this in Azure Portal"
}

# Add missing AZURE_AD_CLIENT_SECRET
Write-Info "Adding missing AZURE_AD_CLIENT_SECRET..."
$ErrorActionPreference = 'SilentlyContinue'
$result = az functionapp config appsettings set `
    --name "$FUNCTION_APP_NAME" `
    --resource-group "$RESOURCE_GROUP" `
    --settings "AZURE_AD_CLIENT_SECRET=$kvClientSecretRef" `
    --output none 2>&1
$ErrorActionPreference = 'Stop'

if ($LASTEXITCODE -eq 0) {
    Write-Success "  ✓ AZURE_AD_CLIENT_SECRET added"
} else {
    Write-Warning "  ⚠ Could not add via CLI. Error: $result"
    Write-Info "    You may need to add this in Azure Portal"
}

Write-Info ""
Write-Info "Verifying fixes..."
Start-Sleep -Seconds 2

# Verify
$ErrorActionPreference = 'SilentlyContinue'
$allSettings = az functionapp config appsettings list `
    --name "$FUNCTION_APP_NAME" `
    --resource-group "$RESOURCE_GROUP" `
    -o json 2>&1 | ConvertFrom-Json
$ErrorActionPreference = 'Stop'

if ($LASTEXITCODE -eq 0) {
    $tenantId = $allSettings | Where-Object { $_.name -eq "AZURE_AD_TENANT_ID" }
    $clientId = $allSettings | Where-Object { $_.name -eq "AZURE_AD_CLIENT_ID" }
    $clientSecret = $allSettings | Where-Object { $_.name -eq "AZURE_AD_CLIENT_SECRET" }
    
    Write-Info ""
    Write-Info "Verification Results:"
    
    if ($tenantId -and $tenantId.value -like "*@Microsoft.KeyVault*" -and $tenantId.value.EndsWith(")")) {
        Write-Success "  ✓ AZURE_AD_TENANT_ID: Correct format"
    } else {
        Write-Warning "  ⚠ AZURE_AD_TENANT_ID: May still need fixing"
        if ($tenantId) {
            Write-Info "     Current: $($tenantId.value)"
        }
    }
    
    if ($clientId -and $clientId.value -like "*@Microsoft.KeyVault*" -and $clientId.value.EndsWith(")")) {
        Write-Success "  ✓ AZURE_AD_CLIENT_ID: Correct format"
    } else {
        Write-Warning "  ⚠ AZURE_AD_CLIENT_ID: May still need fixing"
        if ($clientId) {
            Write-Info "     Current: $($clientId.value)"
        }
    }
    
    if ($clientSecret -and $clientSecret.value -like "*@Microsoft.KeyVault*") {
        Write-Success "  ✓ AZURE_AD_CLIENT_SECRET: Set"
    } else {
        Write-Error "  ✗ AZURE_AD_CLIENT_SECRET: Still missing or incorrect"
    }
} else {
    Write-Warning "Could not verify settings"
}

Write-Info ""
Write-Info "If any settings still need fixing, use Azure Portal:"
Write-Info "  https://portal.azure.com -> $FUNCTION_APP_NAME -> Configuration"
Write-Info ""
Write-Info "After fixing, restart Function App:"
Write-Info "  az functionapp restart --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP"

