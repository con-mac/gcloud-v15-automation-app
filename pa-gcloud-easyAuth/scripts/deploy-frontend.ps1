# Deploy Frontend Script (PowerShell)
# Deploys React frontend to Azure App Service using Docker container from ACR

$ErrorActionPreference = "Stop"

# Load configuration
if (-not (Test-Path "config\deployment-config.env")) {
    Write-Error "deployment-config.env not found. Please run deploy.ps1 first."
    exit 1
}

# Parse environment file
$config = @{}
$configPath = "config\deployment-config.env"

if (-not (Test-Path $configPath)) {
    Write-Error "Config file not found: $configPath"
    exit 1
}

# Read file line by line (more reliable than Raw)
$fileLines = Get-Content $configPath -Encoding UTF8
foreach ($line in $fileLines) {
    $line = $line.Trim()
    if ($line -and -not $line.StartsWith('#')) {
        # Find first = sign and split on it
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

$WEB_APP_NAME = $config.WEB_APP_NAME
$RESOURCE_GROUP = $config.RESOURCE_GROUP
$FUNCTION_APP_NAME = $config.FUNCTION_APP_NAME
$ACR_NAME = $config.ACR_NAME
$IMAGE_TAG = $config.IMAGE_TAG

function Write-Info { param([string]$msg) Write-Host "[INFO] $msg" -ForegroundColor Blue }
function Write-Success { param([string]$msg) Write-Host "[SUCCESS] $msg" -ForegroundColor Green }
function Write-Warning { param([string]$msg) Write-Host "[WARNING] $msg" -ForegroundColor Yellow }
function Write-Error { param([string]$msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }

Write-Info "Deploying frontend to Web App using Docker container from ACR..."

# Validate configuration
if ([string]::IsNullOrWhiteSpace($FUNCTION_APP_NAME)) {
    Write-Error "FUNCTION_APP_NAME is missing or empty in config file!"
    Write-Info "Please check config\deployment-config.env"
    exit 1
}

if ([string]::IsNullOrWhiteSpace($WEB_APP_NAME)) {
    Write-Error "WEB_APP_NAME is missing or empty in config file!"
    exit 1
}

# Auto-detect Web App name if the configured one doesn't exist
$ErrorActionPreference = 'SilentlyContinue'
$webAppCheck = az webapp show --name "$WEB_APP_NAME" --resource-group "$RESOURCE_GROUP" --query name -o tsv 2>&1
$ErrorActionPreference = 'Stop'
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($webAppCheck)) {
    Write-Warning "Web App '$WEB_APP_NAME' not found. Auto-detecting from resource group..."
    $ErrorActionPreference = 'SilentlyContinue'
    $allWebApps = az webapp list --resource-group "$RESOURCE_GROUP" --query "[].{name:name, kind:kind}" -o json 2>&1
    $ErrorActionPreference = 'Stop'
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($allWebApps)) {
        $webApps = $allWebApps | ConvertFrom-Json
        # Filter for Web Apps (exclude Function Apps which have kind='functionapp')
        $detectedWebApp = $webApps | Where-Object { 
            $_.kind -ne 'functionapp' -or [string]::IsNullOrWhiteSpace($_.kind)
        } | Select-Object -First 1 -ExpandProperty name
        
        if (-not [string]::IsNullOrWhiteSpace($detectedWebApp)) {
            $WEB_APP_NAME = $detectedWebApp
            Write-Success "✓ Auto-detected Web App: $WEB_APP_NAME"
        } else {
            # Fallback: try to find by name pattern
            $detectedWebApp = $webApps | Where-Object { $_.name -like '*web*' } | Select-Object -First 1 -ExpandProperty name
            if (-not [string]::IsNullOrWhiteSpace($detectedWebApp)) {
                $WEB_APP_NAME = $detectedWebApp
                Write-Success "✓ Auto-detected Web App (by pattern): $WEB_APP_NAME"
            } else {
                Write-Error "Could not find Web App in resource group '$RESOURCE_GROUP'"
                Write-Error "Please ensure Web App exists or update WEB_APP_NAME in deployment-config.env"
                exit 1
            }
        }
    } else {
        Write-Error "Could not list web apps in resource group '$RESOURCE_GROUP'"
        Write-Error "Please ensure Web App exists or update WEB_APP_NAME in deployment-config.env"
        exit 1
    }
}

if ([string]::IsNullOrWhiteSpace($RESOURCE_GROUP)) {
    Write-Error "RESOURCE_GROUP is missing or empty in config file!"
    exit 1
}

# Auto-detect ACR name if missing or incorrect
if ([string]::IsNullOrWhiteSpace($ACR_NAME)) {
    Write-Warning "ACR_NAME not set in config. Auto-detecting from resource group..."
    $ErrorActionPreference = 'SilentlyContinue'
    $detectedAcr = az acr list --resource-group "$RESOURCE_GROUP" --query "[0].name" -o tsv 2>&1
    $ErrorActionPreference = 'Stop'
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($detectedAcr)) {
        $ACR_NAME = $detectedAcr
        Write-Success "✓ Auto-detected ACR: $ACR_NAME"
    } else {
        Write-Error "ACR_NAME is missing and could not auto-detect from resource group '$RESOURCE_GROUP'"
        Write-Info "Please run deploy.ps1 and configure Container Registry, or update ACR_NAME in deployment-config.env"
        exit 1
    }
} else {
    # Verify configured ACR exists, auto-detect if not
    $ErrorActionPreference = 'SilentlyContinue'
    $acrCheck = az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" --query name -o tsv 2>&1
    $ErrorActionPreference = 'Stop'
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($acrCheck)) {
        Write-Warning "ACR '$ACR_NAME' not found. Auto-detecting from resource group..."
        $ErrorActionPreference = 'SilentlyContinue'
        $detectedAcr = az acr list --resource-group "$RESOURCE_GROUP" --query "[0].name" -o tsv 2>&1
        $ErrorActionPreference = 'Stop'
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($detectedAcr)) {
            $ACR_NAME = $detectedAcr
            Write-Success "✓ Auto-detected ACR: $ACR_NAME"
        } else {
            Write-Error "ACR '$ACR_NAME' not found and could not auto-detect from resource group '$RESOURCE_GROUP'"
            Write-Info "Please ensure ACR exists or update ACR_NAME in deployment-config.env"
            exit 1
        }
    }
}

if ([string]::IsNullOrWhiteSpace($IMAGE_TAG)) {
    $IMAGE_TAG = "latest"
    Write-Warning "IMAGE_TAG not specified, using 'latest'"
}

# Debug output
Write-Info "Configuration loaded:"
Write-Info "  Function App: '$FUNCTION_APP_NAME'"
Write-Info "  Web App: '$WEB_APP_NAME'"
Write-Info "  Resource Group: '$RESOURCE_GROUP'"
Write-Info "  ACR: '$ACR_NAME'"
Write-Info "  Image Tag: '$IMAGE_TAG'"

# Get Function App URL for API configuration
# Use standard Azure pattern - Function Apps always follow {name}.azurewebsites.net
# This avoids hanging on Azure CLI queries
Write-Info "Getting Function App URL for: $FUNCTION_APP_NAME..."
$FUNCTION_APP_URL = "${FUNCTION_APP_NAME}.azurewebsites.net"
Write-Info "Using Function App URL: https://$FUNCTION_APP_URL"

Write-Success "Function App URL: https://$FUNCTION_APP_URL"

# Verify ACR exists (should already be verified/auto-detected above, but double-check)
Write-Info "Verifying Azure Container Registry: $ACR_NAME..."
$ErrorActionPreference = 'SilentlyContinue'
$acrExists = az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" --query "name" -o tsv 2>&1
$ErrorActionPreference = 'Stop'

if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($acrExists)) {
    Write-Error "Azure Container Registry '$ACR_NAME' not found in resource group '$RESOURCE_GROUP'"
    Write-Info "Please ensure:"
    Write-Info "  1. ACR exists: az acr list --resource-group $RESOURCE_GROUP"
    Write-Info "  2. Images are built and pushed: .\scripts\build-and-push-images.ps1"
    exit 1
}

Write-Success "✓ ACR verified: $ACR_NAME"

# Check if frontend image exists in ACR
Write-Info "Checking if frontend image exists in ACR..."
$ErrorActionPreference = 'SilentlyContinue'
# Check if frontend repository and image tag exist
Write-Info "Checking if frontend image exists in ACR..."
$ErrorActionPreference = 'SilentlyContinue'

# Try to list tags - this will fail if repository doesn't exist, or succeed if it does
$allTags = az acr repository show-tags --name "$ACR_NAME" --repository "frontend" --output tsv 2>&1
$tagsCheckExitCode = $LASTEXITCODE

if ($tagsCheckExitCode -ne 0) {
    # Repository might not exist, or there might be a permission issue
    Write-Error "Frontend repository not found in ACR '$ACR_NAME' or access denied"
    Write-Info ""
    Write-Info "The frontend Docker image has not been built and pushed yet."
    Write-Info ""
    Write-Info "Next steps:"
    Write-Info "  1. Build and push the frontend image:"
    Write-Info "     .\scripts\build-and-push-images.ps1"
    Write-Info ""
    Write-Info "  2. Then run deployment again:"
    Write-Info "     .\deploy.ps1"
    Write-Info "     OR"
    Write-Info "     .\scripts\deploy-frontend.ps1"
    Write-Info ""
    exit 1
}

# Repository exists, check for specific tag
$ErrorActionPreference = 'SilentlyContinue'
# Get all tags as simple text list (most reliable)
$allTagsList = az acr repository show-tags --name "$ACR_NAME" --repository "frontend" --output tsv 2>&1
$ErrorActionPreference = 'Stop'

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to retrieve tags from ACR"
    exit 1
}

# Check if our tag exists in the list
$tagFound = $false
if (-not [string]::IsNullOrWhiteSpace($allTagsList)) {
    # Split by newlines and check each tag
    $tags = $allTagsList -split "`n" | Where-Object { $_ -and $_.Trim() -ne "" }
    foreach ($tag in $tags) {
        $tag = $tag.Trim()
        if ($tag -eq $IMAGE_TAG) {
            $tagFound = $true
            break
        }
    }
}

if (-not $tagFound) {
    Write-Warning "Frontend image 'frontend:$IMAGE_TAG' not found in ACR '$ACR_NAME'"
    Write-Info ""
    Write-Info "Available tags in 'frontend' repository:"
    $ErrorActionPreference = 'SilentlyContinue'
    az acr repository show-tags --name "$ACR_NAME" --repository "frontend" --output table 2>&1
    $ErrorActionPreference = 'Stop'
    Write-Info ""
    Write-Info "Please build and push the image with tag '$IMAGE_TAG':"
    Write-Info "  .\scripts\build-and-push-images.ps1"
    Write-Info ""
    Write-Info "Or use an existing tag from the list above"
    exit 1
}

Write-Success "Frontend image found: frontend:$IMAGE_TAG"

# Get ACR credentials
Write-Info "Getting ACR credentials..."
$ErrorActionPreference = 'SilentlyContinue'
$acrUsername = az acr credential show --name "$ACR_NAME" --query "username" -o tsv 2>&1
$acrPassword = az acr credential show --name "$ACR_NAME" --query "passwords[0].value" -o tsv 2>&1
$ErrorActionPreference = 'Stop'

if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($acrUsername) -or [string]::IsNullOrWhiteSpace($acrPassword)) {
    Write-Error "Failed to get ACR credentials"
    Write-Info "Please ensure ACR admin user is enabled:"
    Write-Info "  az acr update --name $ACR_NAME --admin-enabled true"
    exit 1
}

Write-Success "ACR credentials retrieved"

# Configure Web App to use Docker container
Write-Info "Configuring Web App to use Docker container..."
$acrLoginServer = "$ACR_NAME.azurecr.io"
$dockerImage = "$acrLoginServer/frontend:$IMAGE_TAG"

Write-Info "Setting container configuration..."
Write-Info "  Image: $dockerImage"
Write-Info "  Registry: $acrLoginServer"

az webapp config container set `
    --name $WEB_APP_NAME `
    --resource-group $RESOURCE_GROUP `
    --container-image-name $dockerImage `
    --container-registry-url "https://$acrLoginServer" `
    --container-registry-user $acrUsername `
    --container-registry-password $acrPassword `
    --output none

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to configure Web App container"
    exit 1
}

Write-Success "Web App configured to use Docker container"

# Set app settings for API URL and other configuration
Write-Info "Configuring app settings..."

# Get actual SSO values from Azure (same as build script does)
Write-Info "Getting SSO configuration for app settings..."
$tenantId = az account show --query tenantId -o tsv 2>&1
if ([string]::IsNullOrWhiteSpace($tenantId)) {
    Write-Warning "Could not get tenant ID, using placeholder"
    $tenantId = "PLACEHOLDER_TENANT_ID"
}

$clientId = ""
$APP_REGISTRATION_NAME = $config.APP_REGISTRATION_NAME
if (-not [string]::IsNullOrWhiteSpace($APP_REGISTRATION_NAME)) {
    $clientId = az ad app list --display-name "$APP_REGISTRATION_NAME" --query "[0].appId" -o tsv 2>&1
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($clientId)) {
        Write-Warning "Could not get client ID from App Registration '$APP_REGISTRATION_NAME', using placeholder"
        $clientId = "PLACEHOLDER_CLIENT_ID"
    }
} else {
    Write-Warning "APP_REGISTRATION_NAME not in config, using placeholder"
    $clientId = "PLACEHOLDER_CLIENT_ID"
}

$redirectUri = "https://${WEB_APP_NAME}.azurewebsites.net"
$adminGroupId = $config.ADMIN_GROUP_ID

Write-Info "SSO Configuration for app settings:"
Write-Info "  Tenant ID: $($tenantId.Substring(0, [Math]::Min(8, $tenantId.Length)))..."
Write-Info "  Client ID: $($clientId.Substring(0, [Math]::Min(8, $clientId.Length)))..."
Write-Info "  Redirect URI: $redirectUri"

# Get function key (workaround for authLevel: function issue)
Write-Info "Getting function key for API authentication..."
$ErrorActionPreference = 'SilentlyContinue'
$functionKey = az functionapp function keys list --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP" --function-name "function_app" --query "default" -o tsv 2>&1
$ErrorActionPreference = 'Stop'

if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($functionKey) -and $functionKey -notmatch "ERROR") {
    Write-Success "✓ Function key retrieved"
} else {
    Write-Warning "Could not get function key automatically"
    Write-Info "You may need to add it manually in Azure Portal:"
    Write-Info "  Function App -> Functions -> function_app -> Function Keys"
    $functionKey = ""
}

$appSettings = @(
    "VITE_API_BASE_URL=https://${FUNCTION_APP_URL}",
    "VITE_AZURE_AD_TENANT_ID=$tenantId",
    "VITE_AZURE_AD_CLIENT_ID=$clientId",
    "VITE_AZURE_AD_REDIRECT_URI=$redirectUri",
    "WEBSITES_ENABLE_APP_SERVICE_STORAGE=false",
    "PORT=80"
)

# Add function key if available (workaround for authLevel: function)
if (-not [string]::IsNullOrWhiteSpace($functionKey)) {
    $appSettings += "VITE_FUNCTION_KEY=$functionKey"
    Write-Info "  Function Key: $($functionKey.Substring(0, [Math]::Min(8, $functionKey.Length)))..."
}

# Add admin group ID if available
if (-not [string]::IsNullOrWhiteSpace($adminGroupId)) {
    $appSettings += "VITE_AZURE_AD_ADMIN_GROUP_ID=$adminGroupId"
}

# Set app settings in a single batch operation
Write-Info "Setting app settings in batch..."
$ErrorActionPreference = 'SilentlyContinue'
az webapp config appsettings set `
    --name $WEB_APP_NAME `
    --resource-group $RESOURCE_GROUP `
    --settings $appSettings `
    --output none 2>&1 | Out-Null
$ErrorActionPreference = 'Stop'

if ($LASTEXITCODE -ne 0) {
    Write-Warning "Batch app settings update failed, trying one by one..."
    # Fallback to one-by-one if batch fails
    foreach ($setting in $appSettings) {
        Write-Info "Setting: $setting"
        $ErrorActionPreference = 'SilentlyContinue'
        az webapp config appsettings set `
            --name $WEB_APP_NAME `
            --resource-group $RESOURCE_GROUP `
            --settings "$setting" `
            --output none 2>&1 | Out-Null
        $ErrorActionPreference = 'Stop'
        
        if ($LASTEXITCODE -eq 0) {
            Write-Info "✓ Set: $setting"
        } else {
            Write-Warning "Failed to set: $setting"
        }
    }
}

Write-Success "App settings configured"

# Restart the app to apply container changes
Write-Info "Restarting Web App to apply container configuration..."
$ErrorActionPreference = 'SilentlyContinue'
az webapp restart `
    --name $WEB_APP_NAME `
    --resource-group $RESOURCE_GROUP `
    --output none 2>&1 | Out-Null
$ErrorActionPreference = 'Stop'

if ($LASTEXITCODE -ne 0) {
    Write-Warning "Failed to restart Web App, but configuration should still apply"
} else {
    Write-Success "Web App restarted"
}

Write-Success "Frontend deployment complete!"
Write-Info ""
Write-Info "Next steps:"
Write-Info "  1. Wait 30-60 seconds for the container to start"
Write-Info "  2. Check the app: https://$WEB_APP_NAME.azurewebsites.net"
Write-Info "  3. Check logs: az webapp log tail --name $WEB_APP_NAME --resource-group $RESOURCE_GROUP"
Write-Info ""
Write-Info "Note: Azure AD configuration needs to be updated with actual values"
Write-Info "Note: Private endpoint configuration may be required"
