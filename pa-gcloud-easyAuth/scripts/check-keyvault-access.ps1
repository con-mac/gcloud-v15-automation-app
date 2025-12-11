# Check if Function App can access Key Vault

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
$SUBSCRIPTION_ID = $config.SUBSCRIPTION_ID

Write-Info "Checking Key Vault access for Function App: $FUNCTION_APP_NAME"
Write-Info ""

# Check managed identity
Write-Info "1. Checking managed identity..."
$ErrorActionPreference = 'SilentlyContinue'
$identity = az functionapp identity show `
    --name "$FUNCTION_APP_NAME" `
    --resource-group "$RESOURCE_GROUP" `
    --query "principalId" -o tsv 2>&1
$ErrorActionPreference = 'Stop'

if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($identity)) {
    Write-Success "  ✓ Managed identity enabled: $identity"
} else {
    Write-Error "  ✗ Managed identity not enabled"
    Write-Info "    Run: az functionapp identity assign --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP"
    exit 1
}

# Check Key Vault access
Write-Info ""
Write-Info "2. Checking Key Vault access..."
$kvScope = "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$KEY_VAULT_NAME"

$ErrorActionPreference = 'SilentlyContinue'
$roleAssignment = az role assignment list `
    --assignee "$identity" `
    --scope "$kvScope" `
    --role "Key Vault Secrets User" `
    --query "[].{Role:roleDefinitionName, Scope:scope}" -o json 2>&1 | ConvertFrom-Json
$ErrorActionPreference = 'Stop'

if ($LASTEXITCODE -eq 0 -and $roleAssignment) {
    Write-Success "  ✓ Key Vault Secrets User role assigned"
    foreach ($assignment in $roleAssignment) {
        Write-Info "    Role: $($assignment.Role), Scope: $($assignment.Scope)"
    }
} else {
    Write-Error "  ✗ Key Vault Secrets User role NOT assigned"
    Write-Info "    Run: az role assignment create --role 'Key Vault Secrets User' --assignee $identity --scope $kvScope"
}

# Check if secrets exist
Write-Info ""
Write-Info "3. Checking secrets in Key Vault..."
$secrets = @("AzureADTenantId", "AzureADClientId", "AzureADClientSecret")
foreach ($secretName in $secrets) {
    $ErrorActionPreference = 'SilentlyContinue'
    $secret = az keyvault secret show `
        --vault-name "$KEY_VAULT_NAME" `
        --name "$secretName" `
        --query "name" -o tsv 2>&1
    $ErrorActionPreference = 'Stop'
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "  ✓ Secret exists: $secretName"
    } else {
        Write-Error "  ✗ Secret missing: $secretName"
    }
}

Write-Info ""
Write-Info "4. Checking Function App logs for Key Vault errors..."
Write-Info "   Run this to see recent logs:"
Write-Info "   az functionapp log tail --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP"
Write-Info ""
Write-Info "   Or check in Portal:"
Write-Info "   https://portal.azure.com -> $FUNCTION_APP_NAME -> Log stream"

