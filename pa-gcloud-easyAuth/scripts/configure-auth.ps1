# Configure Authentication Script (PowerShell)
# Sets up Microsoft 365 SSO integration

# Suppress any automatic error handling that might try to parse JSON
# Also bypass PowerShell profile error handlers
$ErrorActionPreference = "Stop"
$PSDefaultParameterValues = @{}

# Disable any error handlers that might intercept JSON parse errors
# Clear errors at script start to prevent profile interference
$global:Error.Clear() | Out-Null

# Wrap the entire script execution in a try-catch to prevent profile error handlers
# from intercepting and re-throwing errors with custom messages
$script:OriginalErrorActionPreference = $ErrorActionPreference

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

$APP_REGISTRATION_NAME = $config.APP_REGISTRATION_NAME
$KEY_VAULT_NAME = $config.KEY_VAULT_NAME
$RESOURCE_GROUP = $config.RESOURCE_GROUP
$FUNCTION_APP_NAME = $config.FUNCTION_APP_NAME
$WEB_APP_NAME = $config.WEB_APP_NAME
$SHAREPOINT_SITE_URL = $config.SHAREPOINT_SITE_URL
$SHAREPOINT_SITE_ID = $config.SHAREPOINT_SITE_ID

function Write-Info { param([string]$msg) Write-Host "[INFO] $msg" -ForegroundColor Blue }
function Write-Success { param([string]$msg) Write-Host "[SUCCESS] $msg" -ForegroundColor Green }
function Write-Warning { param([string]$msg) Write-Host "[WARNING] $msg" -ForegroundColor Yellow }

Write-Info "Configuring Microsoft 365 SSO authentication..."

# Check if App Registration exists
Write-Info "Checking for App Registration: $APP_REGISTRATION_NAME"
$ErrorActionPreference = 'SilentlyContinue'
$appListJson = az ad app list --display-name $APP_REGISTRATION_NAME --query "[].{AppId:appId, DisplayName:displayName}" -o json 2>&1
$ErrorActionPreference = 'Stop'

$APP_ID = ""
if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($appListJson)) {
    try {
        $appList = $appListJson | ConvertFrom-Json
        if ($appList -and $appList.Count -gt 0) {
            $APP_ID = $appList[0].AppId
        }
    } catch {
        Write-Warning "Could not parse App Registration response: $_"
    }
}

# Get Web App URL (needed for redirect URIs and app settings)
$WEB_APP_URL = "https://${WEB_APP_NAME}.azurewebsites.net"

# Get Tenant ID for frontend configuration
$ErrorActionPreference = 'SilentlyContinue'
$TENANT_ID = az account show --query tenantId -o tsv 2>&1
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($APP_ID)) {
    Write-Warning "App Registration not found. Creating..."
    
    # Create App Registration with redirect URIs
    # For SPA redirect flow, use base URL (not /auth/callback)
    # MSAL handles redirect responses automatically on the base URL
    $appJson = az ad app create `
        --display-name $APP_REGISTRATION_NAME `
        --web-redirect-uris "${WEB_APP_URL}" "http://localhost:3000" "http://localhost:5173" | ConvertFrom-Json
    
    $APP_ID = $appJson.appId
    
    # Add SPA platform configuration (required for redirect flow to work properly)
    # Use Graph API to ensure SPA platform is created correctly (more reliable than Azure CLI)
    Write-Info "Configuring as Single-Page Application (SPA) platform..."
    
    # Get tenant ID and access token for Graph API
    $tenantId = az account show --query tenantId -o tsv
    $token = az account get-access-token --resource "https://graph.microsoft.com" --query accessToken -o tsv
    
    if ($tenantId -and $token) {
        # Use Graph API to set SPA platform (more reliable than Azure CLI)
        $appUri = "https://graph.microsoft.com/v1.0/applications(appId='$APP_ID')"
        $headers = @{
            "Authorization" = "Bearer $token"
            "Content-Type" = "application/json"
        }
        
        $body = @{
            spa = @{
                redirectUris = @($WEB_APP_URL, "http://localhost:3000", "http://localhost:5173")
            }
        } | ConvertTo-Json -Depth 10
        
        try {
            Invoke-RestMethod -Uri $appUri -Method Patch -Headers $headers -Body $body | Out-Null
            Write-Success "App Registration configured as SPA platform via Graph API"
        } catch {
            Write-Warning "Could not configure SPA platform via Graph API: $_"
            Write-Warning "Falling back to Azure CLI method..."
            # Fallback to Azure CLI
            az ad app update --id $APP_ID --set "spa.redirectUris=['${WEB_APP_URL}','http://localhost:3000','http://localhost:5173']" --output none 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Success "App Registration configured as SPA platform (fallback method)"
            } else {
                Write-Warning "Could not configure SPA platform automatically. Please configure manually:"
                Write-Warning "  App Registrations -> $APP_REGISTRATION_NAME -> Authentication"
                Write-Warning "  Platform: Single-page application"
                Write-Warning "  Add redirect URI: $WEB_APP_URL"
            }
        }
    } else {
        # Fallback to Azure CLI if Graph API not available
        Write-Warning "Could not get Graph API token, using Azure CLI fallback..."
        az ad app update --id $APP_ID --set "spa.redirectUris=['${WEB_APP_URL}','http://localhost:3000','http://localhost:5173']" --output none 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Success "App Registration configured as SPA platform (Azure CLI method)"
        } else {
            Write-Warning "Could not configure SPA platform automatically. Please configure manually:"
            Write-Warning "  App Registrations -> $APP_REGISTRATION_NAME -> Authentication"
            Write-Warning "  Platform: Single-page application"
            Write-Warning "  Add redirect URI: $WEB_APP_URL"
        }
    }
    
    Write-Success "App Registration created: $APP_ID"
    
    # Create service principal
    az ad sp create --id $APP_ID --output none | Out-Null
    
    # Add API permissions for SharePoint/Graph
    Write-Info "Adding API permissions for SharePoint/Graph API..."
    
    # Microsoft Graph API ID
    $GRAPH_API_ID = "00000003-0000-0000-c000-000000000000"
    
    # Add User.Read permission
    Write-Info "Adding User.Read permission..."
    az ad app permission add `
        --id $APP_ID `
        --api $GRAPH_API_ID `
        --api-permissions "e1fe6dd8-ba31-4d61-89e7-88639da4683d=Scope" `
        --output none 2>&1 | Out-Null
    
    # Add SharePoint permissions - using Application permissions for server-to-server access
    # Reference: https://learn.microsoft.com/en-us/dynamics365/customerengagement/on-premises/admin/on-prem-server-configure-azure-app-with-sharepoint-access
    # For Azure App Service (server-to-server), we need Application permissions, not delegated
    
    # Sites.FullControl.All - Application permission (for full SharePoint site access)
    Write-Info "Adding Sites.FullControl.All permission (Application permission for SharePoint)..."
    az ad app permission add `
        --id $APP_ID `
        --api $GRAPH_API_ID `
        --api-permissions "678536fe-1083-478a-9c59-b99265e6b0d3=Role" `
        --output none 2>&1 | Out-Null
    
    # Sites.ReadWrite.All - Application permission (alternative, more restrictive)
    Write-Info "Adding Sites.ReadWrite.All permission (Application permission)..."
    az ad app permission add `
        --id $APP_ID `
        --api $GRAPH_API_ID `
        --api-permissions "0c0bf378-bf22-4481-978f-6afc4c88705c=Role" `
        --output none 2>&1 | Out-Null
    
    # Files.ReadWrite.All - Application permission (for file operations)
    Write-Info "Adding Files.ReadWrite.All permission (Application permission)..."
    az ad app permission add `
        --id $APP_ID `
        --api $GRAPH_API_ID `
        --api-permissions "75359482-378d-4052-8f01-80520e7db3cd=Role" `
        --output none 2>&1 | Out-Null
    
    # Add offline_access permission
    Write-Info "Adding offline_access permission..."
    az ad app permission add `
        --id $APP_ID `
        --api $GRAPH_API_ID `
        --api-permissions "7427e0e9-2fba-42fe-b0c0-848c9e6a8182=Scope" `
        --output none 2>&1 | Out-Null
    
    # Grant admin consent
    Write-Info "Granting admin consent for API permissions..."
    Write-Info "Note: Application permissions (Role) require admin consent - this is required for SharePoint access"
    $grantConsent = Read-Host "Grant admin consent now? (y/n) [y]"
    if ([string]::IsNullOrWhiteSpace($grantConsent) -or $grantConsent -eq "y") {
        az ad app permission admin-consent --id $APP_ID --output none | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Admin consent granted for all API permissions"
        } else {
            Write-Warning "Could not grant admin consent automatically. This is REQUIRED for SharePoint access."
            Write-Warning "Please grant manually in Azure Portal:"
            Write-Warning "  1. Go to Azure Portal -> App Registrations -> $APP_REGISTRATION_NAME"
            Write-Warning "  2. API permissions -> Grant admin consent for '<tenant name>'"
            Write-Warning "  3. This is required for Sites.FullControl.All and other Application permissions"
        }
    } else {
        Write-Warning "Admin consent not granted. This is REQUIRED for SharePoint Application permissions."
        Write-Warning "Please grant manually in Azure Portal:"
        Write-Warning "  App Registration -> API permissions -> Grant admin consent"
    }
} else {
    Write-Success "App Registration found: $APP_ID"
    
    # Ensure redirect URIs are correct for SPA redirect flow (base URL, not /auth/callback)
    Write-Info "Verifying redirect URIs for SPA redirect flow..."
    $ErrorActionPreference = 'SilentlyContinue'
    $currentUris = az ad app show --id $APP_ID --query "web.redirectUris" -o json 2>&1
    $ErrorActionPreference = 'Stop'
    
    # Check if base URL is already in redirect URIs
    $needsUpdate = $true
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($currentUris)) {
        try {
            $uris = $currentUris | ConvertFrom-Json
            if ($uris -contains $WEB_APP_URL) {
                $needsUpdate = $false
                Write-Info "Redirect URI already configured: $WEB_APP_URL"
            }
        } catch {
            # Continue to update
        }
    }
    
    if ($needsUpdate) {
        Write-Info "Updating redirect URIs to use base URL for SPA redirect flow..."
        Write-Info "Adding: $WEB_APP_URL (and localhost for development)"
        # Update web redirect URIs
        az ad app update --id $APP_ID --web-redirect-uris "${WEB_APP_URL}" "http://localhost:3000" "http://localhost:5173" --output none 2>&1 | Out-Null
        
        # Use Graph API to set SPA redirect URIs (more reliable - creates platform if needed)
        $tenantId = az account show --query tenantId -o tsv
        $token = az account get-access-token --resource "https://graph.microsoft.com" --query accessToken -o tsv
        
        if ($tenantId -and $token) {
            $appUri = "https://graph.microsoft.com/v1.0/applications(appId='$APP_ID')"
            $headers = @{
                "Authorization" = "Bearer $token"
                "Content-Type" = "application/json"
            }
            
            $body = @{
                spa = @{
                    redirectUris = @($WEB_APP_URL, "http://localhost:3000", "http://localhost:5173")
                }
            } | ConvertTo-Json -Depth 10
            
            try {
                Invoke-RestMethod -Uri $appUri -Method Patch -Headers $headers -Body $body | Out-Null
                Write-Success "Redirect URIs updated for SPA redirect flow via Graph API"
            } catch {
                Write-Warning "Could not update SPA redirect URIs via Graph API: $_"
                Write-Warning "Please update manually in Azure Portal:"
                Write-Warning "  App Registrations -> $APP_REGISTRATION_NAME -> Authentication"
                Write-Warning "  Add platform: Single-page application"
                Write-Warning "  Add redirect URI: $WEB_APP_URL"
            }
        } else {
            Write-Warning "Could not get Graph API token. Please update manually in Azure Portal"
        }
    } else {
        # Ensure SPA platform is configured even if redirect URI already exists
        Write-Info "Ensuring SPA platform configuration..."
        # Use Graph API for more reliable SPA platform configuration
        $tenantId = az account show --query tenantId -o tsv
        $token = az account get-access-token --resource "https://graph.microsoft.com" --query accessToken -o tsv
        
        if ($tenantId -and $token) {
            $appUri = "https://graph.microsoft.com/v1.0/applications(appId='$APP_ID')"
            $headers = @{
                "Authorization" = "Bearer $token"
                "Content-Type" = "application/json"
            }
            
            $body = @{
                spa = @{
                    redirectUris = @($WEB_APP_URL, "http://localhost:3000", "http://localhost:5173")
                }
            } | ConvertTo-Json -Depth 10
            
            try {
                Invoke-RestMethod -Uri $appUri -Method Patch -Headers $headers -Body $body | Out-Null
                Write-Success "SPA platform redirect URIs configured via Graph API"
            } catch {
                Write-Warning "Could not configure SPA redirect URIs via Graph API: $_"
                Write-Warning "Please configure manually in Azure Portal"
            }
        } else {
            # Fallback to Azure CLI
            az ad app update --id $APP_ID --set "spa.redirectUris=['${WEB_APP_URL}','http://localhost:3000','http://localhost:5173']" --output none 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Success "SPA platform redirect URIs configured"
            } else {
                Write-Warning "Could not configure SPA redirect URIs. Please configure manually in Azure Portal"
            }
        }
    }
}

# Create client secret
Write-Info "Creating client secret..."
Write-Info "Note: This command may take 10-30 seconds..."

# Check if there's an existing secret we can use (optional - we'll create new one anyway)
# But this helps us understand if the command is hanging
Write-Info "Calling Azure AD API (this may take a moment)..."
# Capture raw output - we'll use regex to extract password, NEVER JSON parsing
# Use PowerShell's native command execution but suppress all errors to prevent JSON parsing

$secretOutput = ""
$secretExitCode = 0

# Find az command (works even without profile)
$azPath = $null
$ErrorActionPreference = 'SilentlyContinue'
try {
    # Try to find az in PATH
    $azPath = (Get-Command az -ErrorAction SilentlyContinue).Source
    if (-not $azPath) {
        # Try common installation paths
        $commonPaths = @(
            "$env:ProgramFiles\Microsoft SDKs\Azure\CLI2\wbin\az.cmd",
            "$env:ProgramFiles(x86)\Microsoft SDKs\Azure\CLI2\wbin\az.cmd",
            "$env:LOCALAPPDATA\Programs\Python\Python*\Scripts\az.cmd"
        )
        foreach ($path in $commonPaths) {
            if (Test-Path $path) {
                $azPath = $path
                break
            }
        }
        # If still not found, try expanding wildcards
        if (-not $azPath) {
            $pythonPaths = Get-ChildItem "$env:LOCALAPPDATA\Programs\Python" -ErrorAction SilentlyContinue | 
                Where-Object { $_.PSIsContainer } | 
                ForEach-Object { Join-Path $_.FullName "Scripts\az.cmd" } |
                Where-Object { Test-Path $_ }
            if ($pythonPaths) {
                $azPath = $pythonPaths | Select-Object -First 1
            }
        }
    }
} catch {
    # Ignore errors
}

if (-not $azPath) {
    # Fallback: use 'az' and hope it's in PATH
    $azPath = "az"
}

$ErrorActionPreference = 'Stop'

# Use PowerShell's native command execution with error suppression
# This works even without profile and handles PATH correctly
try {
    $ErrorActionPreference = 'SilentlyContinue'
    $null = $Error.Clear()
    
    # Run command and capture ALL output (stdout + stderr) - warnings may be in stderr
    # Use 2>&1 to merge stderr into stdout, then filter out warnings
    $rawOutput = & $azPath ad app credential reset --id $APP_ID --output json 2>&1
    $secretExitCode = $LASTEXITCODE
    
    # Convert to string and filter out warning lines (lines starting with "WARNING:")
    $secretOutput = ($rawOutput | Out-String)
    
    # Remove warning lines that might interfere
    $lines = $secretOutput -split "`r?`n"
    $jsonLines = @()
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        # Skip warning lines and empty lines
        if ($trimmed -and -not $trimmed.StartsWith("WARNING:") -and -not $trimmed.StartsWith("Note:")) {
            $jsonLines += $line
        } elseif ($trimmed.StartsWith("WARNING:") -or $trimmed.StartsWith("Note:")) {
            # Log warnings but don't include in JSON
            Write-Info "Azure CLI warning (ignored): $trimmed"
        }
    }
    $secretOutput = $jsonLines -join "`n"
    
    # Trim the output
    if (-not [string]::IsNullOrWhiteSpace($secretOutput)) {
        $secretOutput = $secretOutput.Trim()
    }
} catch {
    # Suppress all errors - we'll check output below
    $null = $Error.Clear()
    Write-Warning "Error during command execution (this may be expected): $_"
} finally {
    $ErrorActionPreference = 'Stop'
    $null = $Error.Clear()
}

if ($secretExitCode -ne 0) {
    Write-Error "Failed to create client secret (exit code: $secretExitCode)"
    Write-Info "Output: $secretOutput"
    Write-Info ""
    Write-Info "Possible issues:"
    Write-Info "  1. Insufficient Azure AD permissions"
    Write-Info "  2. App Registration not found"
    Write-Info "  3. Network connectivity issues"
    Write-Info ""
    Write-Info "You can create a secret manually in Azure Portal:"
    Write-Info "  App Registrations -> $APP_REGISTRATION_NAME -> Certificates & secrets -> New client secret"
    exit 1
}

if ([string]::IsNullOrWhiteSpace($secretOutput)) {
    Write-Error "Client secret command returned empty output"
    Write-Info "This may indicate a timeout or permission issue"
    exit 1
}

# Parse the secret - USE REGEX ONLY, never attempt JSON parsing
# This avoids all JSON parsing errors when warnings are present
$SECRET = $null

# Debug: Show first 200 chars of output (for troubleshooting) - safely
if ($secretOutput -and $secretOutput.Length -gt 0) {
    $previewLength = [Math]::Min(200, $secretOutput.Length)
    Write-Info "Output preview: $($secretOutput.Substring(0, $previewLength))"
} else {
    Write-Info "Output is empty or null"
}

# Method 1: Regex extraction from entire output (most reliable)
if ($secretOutput -match '"password"\s*:\s*"([^"]+)"') {
    $SECRET = $matches[1]
    Write-Success "Client secret extracted using regex: $($SECRET.Substring(0, 4))..."
}

# Method 2: Line-by-line regex extraction (fallback if Method 1 failed)
if ([string]::IsNullOrWhiteSpace($SECRET)) {
    Write-Info "Trying line-by-line regex extraction..."
    $lines = $secretOutput -split "`r?`n"
    foreach ($line in $lines) {
        if ($line -match '"password"\s*:\s*"([^"]+)"') {
            $SECRET = $matches[1]
            Write-Success "Client secret extracted from line using regex"
            break
        }
    }
}

# DO NOT attempt JSON parsing - it will fail if warnings are present
# Regex extraction should always work, even with warnings

# Final validation
if ([string]::IsNullOrWhiteSpace($SECRET)) {
    Write-Error "Could not extract client secret from output"
    Write-Info "Raw output: $secretOutput"
    Write-Info ""
    Write-Info "The secret may have been created. You can:"
    Write-Info "1. Check Azure Portal: App Registrations -> $APP_REGISTRATION_NAME -> Certificates & secrets"
    Write-Info "2. Or manually extract the password from the output above"
    Write-Info "3. Then run this script again or set it manually in Key Vault"
    Write-Info ""
    Write-Info "To set manually:"
    Write-Info "  az keyvault secret set --vault-name $KEY_VAULT_NAME --name 'AzureADClientSecret' --value 'YOUR_SECRET'"
    exit 1
}

# Get or create admin security group
# First check if ADMIN_GROUP_ID is in config (from deploy.ps1)
$ADMIN_GROUP_ID = $config.ADMIN_GROUP_ID
$ADMIN_GROUP_NAME = ""

if (-not [string]::IsNullOrWhiteSpace($ADMIN_GROUP_ID)) {
    Write-Info "Admin group ID found in config: $($ADMIN_GROUP_ID.Substring(0,8))..."
    # Verify it still exists
    $ErrorActionPreference = 'SilentlyContinue'
    $groupInfo = az ad group show --group "$ADMIN_GROUP_ID" --query "{DisplayName:displayName, Id:id}" -o json 2>&1
    $ErrorActionPreference = 'Stop'
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($groupInfo)) {
        try {
            $groupObj = $groupInfo | ConvertFrom-Json
            $ADMIN_GROUP_NAME = $groupObj.DisplayName
            Write-Success "Using admin group from config: $ADMIN_GROUP_NAME"
        } catch {
            Write-Warning "Could not parse group info, will prompt for new group"
            $ADMIN_GROUP_ID = ""
        }
    } else {
        Write-Warning "Admin group from config not found, will prompt for new group"
        $ADMIN_GROUP_ID = ""
    }
}

if ([string]::IsNullOrWhiteSpace($ADMIN_GROUP_ID)) {
    Write-Info "Configuring admin security group..."
    $ADMIN_GROUP_NAME = Read-Host "Enter admin security group name (e.g., G-Cloud-Admins) [G-Cloud-Admins]"
    if ([string]::IsNullOrWhiteSpace($ADMIN_GROUP_NAME)) {
        $ADMIN_GROUP_NAME = "G-Cloud-Admins"
    }

    $ErrorActionPreference = 'SilentlyContinue'
    $adminGroup = az ad group list --display-name "$ADMIN_GROUP_NAME" --query "[0].{Id:id, DisplayName:displayName}" -o json 2>&1
    $ErrorActionPreference = 'Stop'

    $ADMIN_GROUP_ID = ""
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($adminGroup)) {
        try {
            $groupObj = $adminGroup | ConvertFrom-Json
            if ($groupObj -and $groupObj.Id) {
                $ADMIN_GROUP_ID = $groupObj.Id
                Write-Success "Using existing admin group: $ADMIN_GROUP_NAME ($ADMIN_GROUP_ID)"
            }
        } catch {
            Write-Warning "Could not parse admin group response"
        }
    }

    if ([string]::IsNullOrWhiteSpace($ADMIN_GROUP_ID)) {
        Write-Info "Admin security group '$ADMIN_GROUP_NAME' not found."
        $createGroup = Read-Host "Create admin security group? (y/n) [y]"
        if ([string]::IsNullOrWhiteSpace($createGroup) -or $createGroup -eq "y") {
            Write-Info "Creating admin security group: $ADMIN_GROUP_NAME"
            $ErrorActionPreference = 'SilentlyContinue'
            $newGroup = az ad group create --display-name "$ADMIN_GROUP_NAME" --mail-nickname "$($ADMIN_GROUP_NAME -replace ' ', '')" --query "{Id:id, DisplayName:displayName}" -o json 2>&1
            $ErrorActionPreference = 'Stop'
            
            if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($newGroup)) {
                try {
                    $groupObj = $newGroup | ConvertFrom-Json
                    $ADMIN_GROUP_ID = $groupObj.Id
                    Write-Success "Admin security group created: $ADMIN_GROUP_NAME ($ADMIN_GROUP_ID)"
                } catch {
                    Write-Warning "Could not parse new group response"
                }
            } else {
                Write-Warning "Could not create admin group. You can create it manually in Azure Portal."
            }
        } else {
            Write-Info "Skipping admin group creation. You can create it manually and set VITE_AZURE_AD_ADMIN_GROUP_ID later."
        }
    }
}

# Store in Key Vault
az keyvault secret set `
    --vault-name $KEY_VAULT_NAME `
    --name "AzureADClientId" `
    --value $APP_ID `
    --output none | Out-Null

az keyvault secret set `
    --vault-name $KEY_VAULT_NAME `
    --name "AzureADClientSecret" `
    --value $SECRET `
    --output none | Out-Null

# Get tenant ID
$account = az account show | ConvertFrom-Json
$TENANT_ID = $account.tenantId

az keyvault secret set `
    --vault-name $KEY_VAULT_NAME `
    --name "AzureADTenantId" `
    --value $TENANT_ID `
    --output none | Out-Null

# Enable system-assigned managed identity for Function App (required for Key Vault references)
Write-Info "Enabling system-assigned managed identity for Function App..."
$ErrorActionPreference = 'SilentlyContinue'
$identityResult = az functionapp identity assign `
    --name "$FUNCTION_APP_NAME" `
    --resource-group "$RESOURCE_GROUP" `
    --query "principalId" -o tsv 2>&1
$ErrorActionPreference = 'Stop'

if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($identityResult)) {
    Write-Success "Managed identity enabled for Function App"
    $FUNCTION_APP_PRINCIPAL_ID = $identityResult
    
    # Grant Key Vault access to Function App managed identity
    Write-Info "Granting Key Vault access to Function App managed identity..."
    
    # Get Key Vault resource ID (more reliable than building scope manually)
    $ErrorActionPreference = 'SilentlyContinue'
    $kvResourceId = az keyvault show --name "$KEY_VAULT_NAME" --resource-group "$RESOURCE_GROUP" --query id -o tsv 2>&1
    $ErrorActionPreference = 'Stop'
    
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($kvResourceId)) {
        $kvScope = $kvResourceId
    } else {
        # Fallback: build scope manually
        if ([string]::IsNullOrWhiteSpace($SUBSCRIPTION_ID)) {
            $SUBSCRIPTION_ID = az account show --query id -o tsv
        }
        $kvScope = "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$KEY_VAULT_NAME"
    }
    
    $ErrorActionPreference = 'SilentlyContinue'
    $existingRole = az role assignment list `
        --assignee "$FUNCTION_APP_PRINCIPAL_ID" `
        --scope "$kvScope" `
        --role "Key Vault Secrets User" `
        --query "[].id" -o tsv 2>&1
    $ErrorActionPreference = 'Stop'
    
    if ([string]::IsNullOrWhiteSpace($existingRole)) {
        Write-Info "Creating role assignment for Key Vault access..."
        az role assignment create `
            --role "Key Vault Secrets User" `
            --assignee "$FUNCTION_APP_PRINCIPAL_ID" `
            --scope "$kvScope" `
            --output none 2>&1 | Out-Null
        
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Key Vault access granted to Function App managed identity"
            Start-Sleep -Seconds 5  # Wait for propagation
        } else {
            Write-Warning "Failed to grant Key Vault access. You may need to grant 'Key Vault Secrets User' role manually."
        }
    } else {
        Write-Success "Key Vault access already granted to Function App managed identity"
    }
} else {
    Write-Warning "Could not enable managed identity. Key Vault references may not work."
    Write-Info "You may need to enable it manually: az functionapp identity assign --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP"
}

# Update Function App settings (build array to avoid PowerShell parsing issues)
Write-Info "Updating Function App with authentication settings..."
$kvUri = "https://${KEY_VAULT_NAME}.vault.azure.net"
# Build Key Vault references using string concatenation to avoid PowerShell expansion issues
$kvTenantRef = '@Microsoft.KeyVault(SecretUri=' + $kvUri + '/secrets/AzureADTenantId/)'
$kvClientIdRef = '@Microsoft.KeyVault(SecretUri=' + $kvUri + '/secrets/AzureADClientId/)'
$kvClientSecretRef = '@Microsoft.KeyVault(SecretUri=' + $kvUri + '/secrets/AzureADClientSecret/)'

$funcAuthSettings = @(
    "AZURE_AD_TENANT_ID=$kvTenantRef",
    "AZURE_AD_CLIENT_ID=$kvClientIdRef",
    "AZURE_AD_CLIENT_SECRET=$kvClientSecretRef"
)

# Set app settings one by one to avoid PowerShell parsing issues
Write-Info "Setting Function App auth settings one by one..."
foreach ($setting in $funcAuthSettings) {
    $ErrorActionPreference = 'SilentlyContinue'
    az functionapp config appsettings set `
        --name "$FUNCTION_APP_NAME" `
        --resource-group "$RESOURCE_GROUP" `
        --settings "$setting" `
        --output none 2>&1 | Out-Null
    $ErrorActionPreference = 'Stop'
}

# Update Web App settings (build array to avoid PowerShell parsing issues)
Write-Info "Updating Web App with authentication settings..."
$webAuthSettings = @(
    "VITE_AZURE_AD_TENANT_ID=$TENANT_ID",
    "VITE_AZURE_AD_CLIENT_ID=$APP_ID",
    "VITE_AZURE_AD_REDIRECT_URI=$WEB_APP_URL"
)

# Add admin group ID if configured
if (-not [string]::IsNullOrWhiteSpace($ADMIN_GROUP_ID)) {
    $webAuthSettings += "VITE_AZURE_AD_ADMIN_GROUP_ID=$ADMIN_GROUP_ID"
    Write-Info "Admin group ID configured: $ADMIN_GROUP_ID"
}

$ErrorActionPreference = 'SilentlyContinue'
az webapp config appsettings set `
    --name "$WEB_APP_NAME" `
    --resource-group "$RESOURCE_GROUP" `
    --settings $webAuthSettings `
    --output none 2>&1 | Out-Null
$ErrorActionPreference = 'Stop'

if ($LASTEXITCODE -eq 0) {
    Write-Success "Web App authentication settings updated"
    Write-Info "  Tenant ID: $TENANT_ID"
    Write-Info "  Client ID: $APP_ID"
    Write-Info "  Redirect URI: $WEB_APP_URL"
} else {
    Write-Warning "Failed to update Web App authentication settings"
    Write-Info "Please update manually in Azure Portal or run this script again"
}

# Configure SharePoint site permissions (if SharePoint is configured)
if (-not [string]::IsNullOrWhiteSpace($SHAREPOINT_SITE_URL) -and -not [string]::IsNullOrWhiteSpace($SHAREPOINT_SITE_ID)) {
    Write-Info "Configuring SharePoint site permissions..."
    $grantSharePoint = Read-Host "Grant App Registration access to SharePoint site? (y/n) [y]"
    if ([string]::IsNullOrWhiteSpace($grantSharePoint) -or $grantSharePoint -eq "y") {
        Write-Info "Attempting to grant SharePoint permissions via Graph API..."
        try {
            $token = az account get-access-token --resource https://graph.microsoft.com --query accessToken -o tsv
            $body = @{
                roles = @("write")
                grantedToIdentities = @(@{
                    application = @{
                        id = $APP_ID
                        displayName = $APP_REGISTRATION_NAME
                    }
                })
            } | ConvertTo-Json -Depth 10
            
            az rest --method POST `
                --uri "https://graph.microsoft.com/v1.0/sites/$SHAREPOINT_SITE_ID/permissions" `
                --headers "Authorization=Bearer $token" "Content-Type=application/json" `
                --body $body 2>&1 | Out-Null
            
            if ($LASTEXITCODE -eq 0) {
                Write-Success "SharePoint permissions granted via Graph API"
            } else {
                Write-Warning "Could not grant permissions via API. Please grant manually:"
                Write-Info "1. Go to SharePoint site: $SHAREPOINT_SITE_URL"
                Write-Info "2. Settings -> Site permissions -> Grant permissions"
                Write-Info "3. Add App Registration: $APP_REGISTRATION_NAME"
                Write-Info "4. Grant 'Edit' or 'Full Control' permissions"
            }
        } catch {
            Write-Warning "Could not grant SharePoint permissions automatically. Please grant manually:"
            Write-Info "1. Go to SharePoint site: $SHAREPOINT_SITE_URL"
            Write-Info "2. Settings -> Site permissions -> Grant permissions"
            Write-Info "3. Add App Registration: $APP_REGISTRATION_NAME"
        }
    }
}

Write-Success "Authentication configuration complete!"
if ([string]::IsNullOrWhiteSpace($SHAREPOINT_SITE_URL) -or [string]::IsNullOrWhiteSpace($SHAREPOINT_SITE_ID)) {
    Write-Warning "SharePoint not configured. Configure SharePoint site permissions manually if needed."
}

