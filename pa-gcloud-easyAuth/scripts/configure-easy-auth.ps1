# Configure Easy Auth for Azure Function App
# This enables platform-level authentication using Microsoft Identity Provider

$ErrorActionPreference = "Stop"

# Load configuration
if (-not (Test-Path "config\deployment-config.env")) {
    Write-Error "deployment-config.env not found. Please run deploy.ps1 first."
    exit 1
}

# Parse environment file
$config = @{}
$configPath = "config\deployment-config.env"
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
$APP_REGISTRATION_NAME = $config.APP_REGISTRATION_NAME
$TENANT_ID = $config.TENANT_ID
$WEB_APP_NAME = $config.WEB_APP_NAME

function Write-Info { param([string]$msg) Write-Host "[INFO] $msg" -ForegroundColor Blue }
function Write-Success { param([string]$msg) Write-Host "[SUCCESS] $msg" -ForegroundColor Green }
function Write-Warning { param([string]$msg) Write-Host "[WARNING] $msg" -ForegroundColor Yellow }
function Write-Error { param([string]$msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }

Write-Info "Configuring Easy Auth for Function App: $FUNCTION_APP_NAME"

# Get App Registration details
Write-Info "Getting App Registration details..."
$ErrorActionPreference = 'SilentlyContinue'
$appListJson = az ad app list --display-name $APP_REGISTRATION_NAME --query "[].{appId:appId,displayName:displayName}" -o json 2>&1
$ErrorActionPreference = 'Stop'

if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($appListJson)) {
    Write-Error "App Registration '$APP_REGISTRATION_NAME' not found"
    Write-Info "Please create the App Registration first or update deployment-config.env"
    exit 1
}

$appList = $appListJson | ConvertFrom-Json
if ($appList.Count -eq 0) {
    Write-Error "App Registration '$APP_REGISTRATION_NAME' not found"
    exit 1
}

$CLIENT_ID = $appList[0].appId
Write-Success "Found App Registration: $CLIENT_ID"

# Get client secret from Key Vault or create one
Write-Info "Getting client secret..."
$KEY_VAULT_NAME = $config.KEY_VAULT_NAME
$CLIENT_SECRET = $null

if ($KEY_VAULT_NAME) {
    try {
        $secretName = "AzureAdClientSecret"
        $CLIENT_SECRET = az keyvault secret show --vault-name $KEY_VAULT_NAME --name $secretName --query "value" -o tsv 2>&1
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($CLIENT_SECRET)) {
            Write-Success "Retrieved client secret from Key Vault"
        } else {
            Write-Warning "Client secret not found in Key Vault, will create new one"
            $CLIENT_SECRET = $null
        }
    } catch {
        Write-Warning "Could not retrieve client secret from Key Vault: $_"
        $CLIENT_SECRET = $null
    }
}

# Create client secret if needed
if (-not $CLIENT_SECRET) {
    Write-Info "Creating new client secret..."
    $secretName = "EasyAuth-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    
    # Use tsv output to get just the password value (more reliable than JSON)
    $ErrorActionPreference = 'SilentlyContinue'
    $CLIENT_SECRET = az ad app credential reset --id $CLIENT_ID --display-name $secretName --query "password" -o tsv 2>$null
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    
    if ($exitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($CLIENT_SECRET)) {
        Write-Success "Created new client secret"
        
        # Store in Key Vault if available
        if ($KEY_VAULT_NAME) {
            Write-Info "Storing client secret in Key Vault..."
            az keyvault secret set --vault-name $KEY_VAULT_NAME --name "AzureAdClientSecret" --value $CLIENT_SECRET 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Success "Stored client secret in Key Vault"
            } else {
                Write-Warning "Failed to store client secret in Key Vault, but secret was created successfully"
            }
        }
    } else {
        Write-Error "Failed to create client secret. Exit code: $exitCode"
        if ([string]::IsNullOrWhiteSpace($CLIENT_SECRET)) {
            Write-Error "Client secret is empty"
        }
        exit 1
    }
}

# Get Function App URL for redirect URI
$FUNCTION_APP_URL = "https://$FUNCTION_APP_NAME.azurewebsites.net"
$REDIRECT_URI = "$FUNCTION_APP_URL/.auth/login/aad/callback"

# Get Web App URL for allowed external redirects
$WEB_APP_URL = if ($WEB_APP_NAME) { "https://$WEB_APP_NAME.azurewebsites.net" } else { "" }

Write-Info "Function App URL: $FUNCTION_APP_URL"
Write-Info "Web App URL: $WEB_APP_URL"
Write-Info "Redirect URI: $REDIRECT_URI"

# Configure Easy Auth using Azure CLI
Write-Info "Enabling Easy Auth..."
Write-Info "This configures Microsoft Identity Provider with 'From this tenant only'"

# Enable Easy Auth and configure Microsoft provider
$easyAuthConfig = @{
    enabled = $true
    unauthenticatedAction = "RedirectToLoginPage"
    defaultProvider = "AzureActiveDirectory"
    tokenStoreEnabled = $true
    allowedExternalRedirectUrls = @($FUNCTION_APP_URL)
    httpSettings = @{
        requireHttps = $true
    }
    identityProviders = @{
        azureActiveDirectory = @{
            enabled = $true
            registration = @{
                openIdIssuer = "https://login.microsoftonline.com/$TENANT_ID/v2.0"
                clientId = $CLIENT_ID
                clientSecretSettingName = "MICROSOFT_PROVIDER_AUTHENTICATION_SECRET"
            }
            validation = @{
                jwtClaimChecks = @{}
                allowedAudiences = @("api://$CLIENT_ID", $CLIENT_ID)
            }
            isAutoProvisioned = $false
        }
    }
}

# Convert to JSON
$easyAuthJson = $easyAuthConfig | ConvertTo-Json -Depth 10 -Compress

# Use Azure CLI to configure Easy Auth
Write-Info "Applying Easy Auth configuration..."
$authUpdateParams = @(
    "webapp", "auth", "update",
    "--name", $FUNCTION_APP_NAME,
    "--resource-group", $RESOURCE_GROUP,
    "--enabled", "true",
    "--action", "LoginWithAzureActiveDirectory",
    "--aad-client-id", $CLIENT_ID,
    "--aad-client-secret-setting-name", "MICROSOFT_PROVIDER_AUTHENTICATION_SECRET",
    "--aad-allowed-token-audiences", "api://$CLIENT_ID", $CLIENT_ID,
    "--token-store", "true"
)

# Add Web App URL to allowed external redirect URLs if available
if ($WEB_APP_URL) {
    $authUpdateParams += "--allowed-external-redirect-urls", $WEB_APP_URL
    Write-Info "Adding Web App URL to allowed external redirect URLs: $WEB_APP_URL"
}

az $authUpdateParams 2>&1 | Out-Null

if ($LASTEXITCODE -ne 0) {
    Write-Warning "Azure CLI auth update may have failed, trying alternative method..."
    # Alternative: Set app settings and use REST API
}

# Set client secret as app setting
Write-Info "Setting client secret as app setting..."
az functionapp config appsettings set `
    --name $FUNCTION_APP_NAME `
    --resource-group $RESOURCE_GROUP `
    --settings "MICROSOFT_PROVIDER_AUTHENTICATION_SECRET=$CLIENT_SECRET" `
    2>&1 | Out-Null

if ($LASTEXITCODE -eq 0) {
    Write-Success "Client secret configured"
} else {
    Write-Warning "Failed to set client secret app setting"
}

# Update App Registration redirect URIs
Write-Info "Updating App Registration redirect URIs..."
$ErrorActionPreference = 'SilentlyContinue'
$currentApp = az ad app show --id $CLIENT_ID -o json | ConvertFrom-Json
$ErrorActionPreference = 'Stop'

$redirectUris = @()
if ($currentApp.web.redirectUris) {
    $redirectUris = [System.Collections.ArrayList]@($currentApp.web.redirectUris)
}

# Add redirect URI if not present
if ($redirectUris -notcontains $REDIRECT_URI) {
    $redirectUris.Add($REDIRECT_URI) | Out-Null
    Write-Info "Adding redirect URI: $REDIRECT_URI"
    
    $redirectUrisJson = $redirectUris | ConvertTo-Json -Compress
    az ad app update --id $CLIENT_ID --web-redirect-uris $redirectUrisJson 2>&1 | Out-Null
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Updated App Registration redirect URIs"
    } else {
        Write-Warning "Failed to update App Registration redirect URIs"
        Write-Info "Please manually add: $REDIRECT_URI"
    }
} else {
    Write-Success "Redirect URI already configured"
}

# Restart Function App
Write-Info "Restarting Function App to apply changes..."
az functionapp restart --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP 2>&1 | Out-Null

Write-Success "Easy Auth configuration complete!"
Write-Info ""
Write-Info "Easy Auth is now enabled with:"
Write-Info "  - Provider: Microsoft (Azure Active Directory)"
Write-Info "  - Tenant restriction: This tenant only"
Write-Info "  - Redirect URI: $REDIRECT_URI"
Write-Info ""
Write-Info "Users can now authenticate via: $FUNCTION_APP_URL/.auth/login/aad"

