# Quick fix: Enable managed identity and grant Key Vault access to Function App
# This allows the Function App to read secrets from Key Vault

$ErrorActionPreference = "Stop"

function Write-Info { param([string]$msg) Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Success { param([string]$msg) Write-Host "[SUCCESS] $msg" -ForegroundColor Green }
function Write-Warning { param([string]$msg) Write-Host "[WARNING] $msg" -ForegroundColor Yellow }
function Write-Error { param([string]$msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }

# Load configuration
# Resolve path relative to script location
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$configPath = Join-Path $scriptDir "..\config\deployment-config.env"
$configPath = [System.IO.Path]::GetFullPath($configPath)

if (-not (Test-Path $configPath)) {
    # Try alternative location (project root)
    $configPath = Join-Path $scriptDir "..\..\config\deployment-config.env"
    $configPath = [System.IO.Path]::GetFullPath($configPath)
    if (-not (Test-Path $configPath)) {
        Write-Error "deployment-config.env not found at: $configPath"
        Write-Info "Please run deploy.ps1 first to create the config file."
        exit 1
    }
}

Write-Info "Loading configuration from: $configPath"

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

if ([string]::IsNullOrWhiteSpace($FUNCTION_APP_NAME)) {
    Write-Error "Missing FUNCTION_APP_NAME in config"
    exit 1
}
if ([string]::IsNullOrWhiteSpace($RESOURCE_GROUP)) {
    Write-Error "Missing RESOURCE_GROUP in config"
    exit 1
}
if ([string]::IsNullOrWhiteSpace($KEY_VAULT_NAME)) {
    Write-Error "Missing KEY_VAULT_NAME in config"
    exit 1
}
if ([string]::IsNullOrWhiteSpace($SUBSCRIPTION_ID)) {
    Write-Error "Missing SUBSCRIPTION_ID in config"
    exit 1
}

Write-Info "Enabling managed identity for Function App: $FUNCTION_APP_NAME"
Write-Info ""

# Enable system-assigned managed identity
$ErrorActionPreference = 'SilentlyContinue'
$identityResult = az functionapp identity assign `
    --name "$FUNCTION_APP_NAME" `
    --resource-group "$RESOURCE_GROUP" `
    --query "principalId" -o tsv 2>&1
$ErrorActionPreference = 'Stop'

if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($identityResult)) {
    Write-Success "Managed identity enabled for Function App"
    $FUNCTION_APP_PRINCIPAL_ID = $identityResult
    Write-Info "Principal ID: $FUNCTION_APP_PRINCIPAL_ID"
    Write-Info ""
    
    # Grant Key Vault access to Function App managed identity
    Write-Info "Granting Key Vault access to Function App managed identity..."
    $kvScope = "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$KEY_VAULT_NAME"
    
    $ErrorActionPreference = 'SilentlyContinue'
    $existingRole = az role assignment list `
        --assignee "$FUNCTION_APP_PRINCIPAL_ID" `
        --scope "$kvScope" `
        --role "Key Vault Secrets User" `
        --query "[].id" -o tsv 2>&1
    $ErrorActionPreference = 'Stop'
    
    if ([string]::IsNullOrWhiteSpace($existingRole)) {
        Write-Info "Creating role assignment..."
        az role assignment create `
            --role "Key Vault Secrets User" `
            --assignee "$FUNCTION_APP_PRINCIPAL_ID" `
            --scope "$kvScope" `
            --output none
        
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Key Vault access granted to Function App managed identity"
            Write-Info "Waiting 10 seconds for permissions to propagate..."
            Start-Sleep -Seconds 10
        } else {
            Write-Error "Failed to grant Key Vault access. You may need to grant 'Key Vault Secrets User' role manually."
            Write-Info "Run this command manually:"
            Write-Host "az role assignment create --role 'Key Vault Secrets User' --assignee '$FUNCTION_APP_PRINCIPAL_ID' --scope '$kvScope'" -ForegroundColor Yellow
            exit 1
        }
    } else {
        Write-Success "Key Vault access already granted to Function App managed identity"
    }
    
    Write-Info ""
    Write-Success "Setup complete! The Function App can now read secrets from Key Vault."
    Write-Info ""
    Write-Info "Next steps:"
    Write-Info "1. Wait 1-2 minutes for changes to propagate"
    Write-Info "2. Restart the Function App: az functionapp restart --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP"
    Write-Info "3. Test SharePoint connectivity: curl https://$FUNCTION_APP_NAME.azurewebsites.net/api/v1/sharepoint/test"
    
} else {
    Write-Error "Could not enable managed identity for Function App"
    Write-Info "Error: $identityResult"
    Write-Info ""
    Write-Info "You may need to enable it manually:"
    Write-Host "az functionapp identity assign --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP" -ForegroundColor Yellow
    exit 1
}

