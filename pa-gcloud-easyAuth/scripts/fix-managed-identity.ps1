# Fix Managed Identity for Function App to enable Key Vault references

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

Write-Info "Fixing Managed Identity for Function App: $FUNCTION_APP_NAME"
Write-Info ""

# Check current identity status
Write-Info "Checking current managed identity status..."
$ErrorActionPreference = 'SilentlyContinue'
$currentIdentity = az functionapp identity show `
    --name "$FUNCTION_APP_NAME" `
    --resource-group "$RESOURCE_GROUP" `
    --query "principalId" -o tsv 2>&1
$ErrorActionPreference = 'Stop'

if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($currentIdentity)) {
    Write-Success "Managed identity already enabled"
    Write-Info "Principal ID: $currentIdentity"
} else {
    Write-Info "Enabling system-assigned managed identity..."
    $ErrorActionPreference = 'SilentlyContinue'
    $identityResult = az functionapp identity assign `
        --name "$FUNCTION_APP_NAME" `
        --resource-group "$RESOURCE_GROUP" `
        --query "principalId" -o tsv 2>&1
    $ErrorActionPreference = 'Stop'

    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($identityResult)) {
        Write-Success "Managed identity enabled"
        $currentIdentity = $identityResult
        Write-Info "Principal ID: $currentIdentity"
    } else {
        Write-Error "Failed to enable managed identity: $identityResult"
        exit 1
    }
}

Write-Info ""
Write-Info "Waiting 30 seconds for managed identity to propagate..."
Start-Sleep -Seconds 30

# Grant Key Vault access
Write-Info "Granting Key Vault access to managed identity..."
$ErrorActionPreference = 'SilentlyContinue'
$kvResourceId = az keyvault show --name "$KEY_VAULT_NAME" --resource-group "$RESOURCE_GROUP" --query id -o tsv 2>&1
$ErrorActionPreference = 'Stop'

if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($kvResourceId)) {
    $kvScope = $kvResourceId
    
    # Check if role assignment already exists
    $ErrorActionPreference = 'SilentlyContinue'
    $existingRole = az role assignment list `
        --assignee "$currentIdentity" `
        --scope "$kvScope" `
        --role "Key Vault Secrets User" `
        --query "[].id" -o tsv 2>&1
    $ErrorActionPreference = 'Stop'
    
    if ([string]::IsNullOrWhiteSpace($existingRole)) {
        Write-Info "Creating role assignment..."
        $ErrorActionPreference = 'SilentlyContinue'
        az role assignment create `
            --role "Key Vault Secrets User" `
            --assignee "$currentIdentity" `
            --scope "$kvScope" `
            --output none 2>&1 | Out-Null
        $ErrorActionPreference = 'Stop'
        
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Key Vault access granted"
            Write-Info "Waiting 30 seconds for permissions to propagate..."
            Start-Sleep -Seconds 30
        } else {
            Write-Warning "Failed to grant Key Vault access. You may need to grant manually."
        }
    } else {
        Write-Success "Key Vault access already granted"
    }
} else {
    Write-Warning "Could not get Key Vault resource ID. Skipping role assignment."
}

Write-Info ""
Write-Info "Restarting Function App to apply changes..."
$ErrorActionPreference = 'SilentlyContinue'
az functionapp restart --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP" 2>&1 | Out-Null
$ErrorActionPreference = 'Stop'

Write-Success "Function App restarted"
Write-Info ""
Write-Info "Next steps:"
Write-Info "1. Wait 2-3 minutes for changes to fully propagate"
Write-Info "2. Check Key Vault references in Azure Portal:"
Write-Info "   Function App → Configuration → Check the three AZURE_AD_* settings"
Write-Info "3. Test SharePoint connectivity:"
Write-Info "   curl https://$FUNCTION_APP_NAME.azurewebsites.net/api/v1/sharepoint/test"

