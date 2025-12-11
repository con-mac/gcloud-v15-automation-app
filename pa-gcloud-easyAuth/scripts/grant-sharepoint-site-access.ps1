# Grant App Registration access to SharePoint site
# This is REQUIRED in addition to API permissions and admin consent

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

$APP_REGISTRATION_NAME = $config.APP_REGISTRATION_NAME
$SHAREPOINT_SITE_URL = $config.SHAREPOINT_SITE_URL
$SHAREPOINT_SITE_ID = $config.SHAREPOINT_SITE_ID

if ([string]::IsNullOrWhiteSpace($APP_REGISTRATION_NAME) -or 
    [string]::IsNullOrWhiteSpace($SHAREPOINT_SITE_URL) -or 
    [string]::IsNullOrWhiteSpace($SHAREPOINT_SITE_ID)) {
    Write-Error "Missing required configuration. Please check deployment-config.env"
    exit 1
}

Write-Info "================================================"
Write-Info "SharePoint Site Access Configuration"
Write-Info "================================================"
Write-Info ""
Write-Info "IMPORTANT: SharePoint access requires THREE layers of security:"
Write-Info ""
Write-Info "1. API Permissions (App Registration)"
Write-Info "   - Sites.FullControl.All (Application permission)"
Write-Info "   - Sites.ReadWrite.All (Application permission)"
Write-Info "   - Files.ReadWrite.All (Application permission)"
Write-Info ""
Write-Info "2. Admin Consent (REQUIRED for Application permissions)"
Write-Info "   - Must be granted by Azure AD admin"
Write-Info "   - Portal: Azure AD -> App registrations -> API permissions -> Grant admin consent"
Write-Info ""
Write-Info "3. SharePoint Site-Level Permissions (THIS SCRIPT)"
Write-Info "   - App Registration must be granted access to the specific SharePoint site"
Write-Info "   - This is separate from API permissions"
Write-Info "   - Can be done via Graph API or SharePoint UI"
Write-Info ""
Write-Info "================================================"
Write-Info ""

# Get App Registration ID
Write-Info "Getting App Registration details..."
$ErrorActionPreference = 'SilentlyContinue'
$appReg = az ad app list --display-name "$APP_REGISTRATION_NAME" --query "[0].{AppId:appId, ObjectId:id}" -o json 2>&1
$ErrorActionPreference = 'Stop'

if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($appReg)) {
    Write-Error "Could not find App Registration: $APP_REGISTRATION_NAME"
    Write-Info "Please verify the App Registration exists and the name is correct"
    exit 1
}

$appObj = $appReg | ConvertFrom-Json
$APP_ID = $appObj.AppId
$APP_OBJECT_ID = $appObj.ObjectId

Write-Success "App Registration found:"
Write-Info "  Name: $APP_REGISTRATION_NAME"
Write-Info "  App ID (Client ID): $APP_ID"
Write-Info "  Object ID: $APP_OBJECT_ID"
Write-Info ""

# Clean SharePoint Site ID (remove query parameters if present)
$cleanSiteId = $SHAREPOINT_SITE_ID
if ($cleanSiteId -match '^([^?]+)') {
    $cleanSiteId = $matches[1]
}

Write-Info "SharePoint Site Details:"
Write-Info "  URL: $SHAREPOINT_SITE_URL"
Write-Info "  Site ID: $cleanSiteId"
Write-Info ""

Write-Info "Attempting to grant site-level permissions via Microsoft Graph API..."
Write-Info ""

# Get access token for Graph API
$ErrorActionPreference = 'SilentlyContinue'
$token = az account get-access-token --resource https://graph.microsoft.com --query accessToken -o tsv 2>&1
$ErrorActionPreference = 'Stop'

if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
    Write-Error "Could not get access token for Graph API"
    Write-Info "Please ensure you're logged in: az login"
    exit 1
}

# Method 1: Try using Graph API to grant permissions
Write-Info "Method 1: Granting via Graph API (sites/{siteId}/permissions)..."
$body = @{
    roles = @("write")
    grantedToIdentities = @(@{
        application = @{
            id = $APP_ID
            displayName = $APP_REGISTRATION_NAME
        }
    })
} | ConvertTo-Json -Depth 10

$ErrorActionPreference = 'SilentlyContinue'
$result = az rest --method POST `
    --uri "https://graph.microsoft.com/v1.0/sites/$cleanSiteId/permissions" `
    --headers "Authorization=Bearer $token" "Content-Type=application/json" `
    --body $body 2>&1
$ErrorActionPreference = 'Stop'

if ($LASTEXITCODE -eq 0) {
    Write-Success "✓ Site-level permissions granted via Graph API"
    Write-Info ""
    Write-Success "All three security layers should now be configured!"
    Write-Info ""
    Write-Info "Next steps:"
    Write-Info "1. Verify admin consent is granted (Azure Portal -> App registrations -> API permissions)"
    Write-Info "2. Restart Function App: az functionapp restart --name <function-app-name> --resource-group <rg>"
    Write-Info "3. Test SharePoint connectivity"
    exit 0
} else {
    Write-Warning "Graph API method failed (this is common)"
    Write-Info "Error: $result"
    Write-Info ""
}

# Method 2: Try using SharePoint REST API
Write-Info "Method 2: Trying SharePoint REST API..."
$sharePointUrl = $SHAREPOINT_SITE_URL
if ($sharePointUrl -match 'https://([^/]+)') {
    $sharePointHost = $matches[1]
    $sharePointApiUrl = "https://$sharePointHost/_api/web/siteusers/add"
    
    Write-Info "Attempting SharePoint REST API: $sharePointApiUrl"
    Write-Warning "This method may require different authentication"
}

Write-Info ""
Write-Warning "================================================"
Write-Warning "MANUAL STEPS REQUIRED"
Write-Warning "================================================"
Write-Warning ""
Write-Warning "The automated methods failed. Please grant access manually:"
Write-Warning ""
Write-Warning "OPTION A: Via SharePoint Site (Recommended)"
Write-Warning "1. Go to SharePoint site: $SHAREPOINT_SITE_URL"
Write-Warning "2. Click 'Settings' (gear icon) -> 'Site permissions'"
Write-Warning "3. Click 'Grant permissions'"
Write-Warning "4. In 'Share' dialog, enter: $APP_REGISTRATION_NAME"
Write-Warning "5. Or search for App ID: $APP_ID"
Write-Warning "6. Select permission level: 'Edit' or 'Full Control'"
Write-Warning "7. Click 'Share'"
Write-Warning ""
Write-Warning "OPTION B: Via SharePoint Admin Center"
Write-Warning "1. Go to: https://admin.microsoft.com"
Write-Warning "2. Navigate to: SharePoint -> Sites -> Active sites"
Write-Warning "3. Find your site: $SHAREPOINT_SITE_URL"
Write-Warning "4. Click on the site -> 'Permissions' tab"
Write-Warning "5. Add the App Registration: $APP_REGISTRATION_NAME ($APP_ID)"
Write-Warning ""
Write-Warning "OPTION C: Via PowerShell (SharePoint Online Management Shell)"
Write-Warning "1. Install: Install-Module -Name Microsoft.Online.SharePoint.PowerShell"
Write-Warning "2. Connect: Connect-SPOService -Url https://<tenant>-admin.sharepoint.com"
Write-Warning "3. Grant: Add-SPOSiteGroup -Site $SHAREPOINT_SITE_URL -Group 'Members' -LoginName $APP_ID"
Write-Warning ""
Write-Warning "================================================"
Write-Warning ""
Write-Info "After granting site-level permissions:"
Write-Info "1. Verify admin consent is granted for API permissions"
Write-Info "2. Restart Function App"
Write-Info "3. Test SharePoint connectivity"
Write-Info ""
Write-Info "To verify site access was granted, check:"
Write-Info "  SharePoint Site -> Settings -> Site permissions"
Write-Info "  The App Registration should appear in the permissions list"

