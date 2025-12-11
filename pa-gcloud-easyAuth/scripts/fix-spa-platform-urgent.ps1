# URGENT FIX: Configure App Registration as SPA Platform
# Fixes "Cross-origin token redemption is permitted only for the 'Single-Page Application' client-type" error

$ErrorActionPreference = "Stop"

function Write-Info { param([string]$msg) Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Success { param([string]$msg) Write-Host "[SUCCESS] $msg" -ForegroundColor Green }
function Write-Warning { param([string]$msg) Write-Host "[WARNING] $msg" -ForegroundColor Yellow }
function Write-Error { param([string]$msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }

Write-Info "URGENT FIX: Configuring App Registration as SPA Platform"
Write-Info ""

# Load configuration
$configPath = "config\deployment-config.env"
if (-not (Test-Path $configPath)) {
    $configPath = "..\config\deployment-config.env"
    if (-not (Test-Path $configPath)) {
        Write-Error "deployment-config.env not found. Please run deploy.ps1 first."
        exit 1
    }
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
            $config[$key] = $value
        }
    }
}

$APP_REGISTRATION_NAME = $config["APP_REGISTRATION_NAME"]
$WEB_APP_NAME = $config["WEB_APP_NAME"]
$RESOURCE_GROUP = $config["RESOURCE_GROUP"]

if (-not $APP_REGISTRATION_NAME) {
    Write-Error "APP_REGISTRATION_NAME not found in config"
    exit 1
}

# Get Web App URL
$WEB_APP_URL = "https://${WEB_APP_NAME}.azurewebsites.net"
if ($WEB_APP_NAME) {
    Write-Info "Web App URL: $WEB_APP_URL"
}

# Get App Registration ID
Write-Info "Finding App Registration: $APP_REGISTRATION_NAME"
$appListJson = az ad app list --display-name $APP_REGISTRATION_NAME --query "[].{appId:appId,displayName:displayName}" -o json 2>&1
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($appListJson)) {
    Write-Error "Could not find App Registration: $APP_REGISTRATION_NAME"
    exit 1
}

$appList = $appListJson | ConvertFrom-Json
if ($appList.Count -eq 0) {
    Write-Error "App Registration not found: $APP_REGISTRATION_NAME"
    exit 1
}

$APP_ID = $appList[0].appId
Write-Info "App Registration ID: $APP_ID"
Write-Info ""

# Get tenant ID
$tenantId = az account show --query tenantId -o tsv
if (-not $tenantId) {
    Write-Error "Could not get tenant ID"
    exit 1
}

# Get access token for Graph API
Write-Info "Getting access token for Graph API..."
$token = az account get-access-token --resource "https://graph.microsoft.com" --query accessToken -o tsv
if (-not $token) {
    Write-Error "Could not get access token"
    exit 1
}

# Get current app registration details
Write-Info "Fetching current App Registration configuration..."
$appUri = "https://graph.microsoft.com/v1.0/applications(appId='$APP_ID')"
$headers = @{
    "Authorization" = "Bearer $token"
    "Content-Type" = "application/json"
}

try {
    $currentApp = Invoke-RestMethod -Uri $appUri -Method Get -Headers $headers
    Write-Info "Current SPA redirect URIs: $($currentApp.spa.redirectUris -join ', ')"
} catch {
    Write-Error "Could not fetch current app registration: $_"
    exit 1
}

# Prepare redirect URIs
$redirectUris = @()
if ($WEB_APP_URL) {
    $redirectUris += $WEB_APP_URL
}
$redirectUris += "http://localhost:3000"
$redirectUris += "http://localhost:5173"

Write-Info ""
Write-Info "Configuring SPA platform with redirect URIs:"
foreach ($uri in $redirectUris) {
    Write-Info "  - $uri"
}
Write-Info ""

# Update SPA redirect URIs using Graph API
$body = @{
    spa = @{
        redirectUris = $redirectUris
    }
} | ConvertTo-Json -Depth 10

try {
    Write-Info "Updating App Registration via Graph API..."
    Invoke-RestMethod -Uri $appUri -Method Patch -Headers $headers -Body $body | Out-Null
    Write-Success "✓ SPA platform configured successfully!"
    Write-Info ""
} catch {
    Write-Error "Failed to update SPA platform: $_"
    Write-Info ""
    Write-Warning "MANUAL FIX REQUIRED:"
    Write-Warning "1. Go to: https://portal.azure.com -> Azure Active Directory -> App registrations"
    Write-Warning "2. Find: $APP_REGISTRATION_NAME"
    Write-Warning "3. Go to 'Authentication'"
    Write-Warning "4. Under 'Platform configurations', click 'Add a platform' -> 'Single-page application'"
    Write-Warning "5. Add redirect URI: $WEB_APP_URL"
    Write-Warning "6. Click 'Configure'"
    exit 1
}

# Verify the update
Write-Info "Verifying configuration..."
Start-Sleep -Seconds 2
try {
    $updatedApp = Invoke-RestMethod -Uri $appUri -Method Get -Headers $headers
    Write-Info "Updated SPA redirect URIs: $($updatedApp.spa.redirectUris -join ', ')"
    
    if ($updatedApp.spa.redirectUris -contains $WEB_APP_URL) {
        Write-Success "✓ Verification successful!"
    } else {
        Write-Warning "⚠ Redirect URI may not be updated yet. Wait 1-2 minutes and try again."
    }
} catch {
    Write-Warning "Could not verify update: $_"
}

Write-Info ""
Write-Success "Fix complete! Please wait 1-2 minutes for changes to propagate, then try logging in again."
Write-Info ""
Write-Info "If login still fails, clear your browser cache and cookies for the site."

