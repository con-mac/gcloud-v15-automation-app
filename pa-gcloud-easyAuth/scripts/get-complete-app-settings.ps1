# Get complete app settings JSON with Key Vault references fixed

$ErrorActionPreference = "Stop"

function Write-Info { param([string]$msg) Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Success { param([string]$msg) Write-Host "[SUCCESS] $msg" -ForegroundColor Green }

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

Write-Info "Generating complete app settings JSON for: $FUNCTION_APP_NAME"
Write-Info ""

# Get current settings first to preserve existing values
Write-Info "Retrieving current app settings..."
$ErrorActionPreference = 'SilentlyContinue'
$currentSettings = az functionapp config appsettings list `
    --name "$FUNCTION_APP_NAME" `
    --resource-group "$RESOURCE_GROUP" `
    -o json 2>&1 | ConvertFrom-Json
$ErrorActionPreference = 'Stop'

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to retrieve current settings"
    exit 1
}

# Build settings hashtable from current settings
$settings = @{}
foreach ($setting in $currentSettings) {
    $settings[$setting.name] = $setting.value
}

# Fix Key Vault references (add missing closing parentheses and missing secret)
$settings["AZURE_AD_TENANT_ID"] = "@Microsoft.KeyVault(SecretUri=${kvUri}/secrets/AzureADTenantId/)"
$settings["AZURE_AD_CLIENT_ID"] = "@Microsoft.KeyVault(SecretUri=${kvUri}/secrets/AzureADClientId/)"
$settings["AZURE_AD_CLIENT_SECRET"] = "@Microsoft.KeyVault(SecretUri=${kvUri}/secrets/AzureADClientSecret/)"

# Convert to JSON
$json = $settings | ConvertTo-Json -Depth 10

Write-Info "Complete App Settings JSON:"
Write-Info "================================================"
Write-Host $json
Write-Info "================================================"
Write-Info ""

# Save to file
$jsonFile = "app-settings-complete.json"
$json | Out-File -FilePath $jsonFile -Encoding UTF8
Write-Success "JSON saved to: $jsonFile"
Write-Info ""

Write-Info "To apply these settings, run:"
Write-Info "  az functionapp config appsettings set --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP --settings `@$jsonFile"
Write-Info ""
Write-Info "Or copy the JSON above and use it in Azure Portal:"
Write-Info "  Portal -> $FUNCTION_APP_NAME -> Configuration -> Advanced edit -> Paste JSON"

