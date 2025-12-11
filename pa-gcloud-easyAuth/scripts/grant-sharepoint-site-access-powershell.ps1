# Grant App Registration access to SharePoint site using PowerShell
# This method is more reliable than the SharePoint UI

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

Write-Info "Granting App Registration access to SharePoint site"
Write-Info ""

# Get App Registration Object ID
Write-Info "Getting App Registration details..."
$ErrorActionPreference = 'SilentlyContinue'
$appReg = az ad app list --display-name "$APP_REGISTRATION_NAME" --query "[0].{AppId:appId, ObjectId:id}" -o json 2>&1 | ConvertFrom-Json
$ErrorActionPreference = 'Stop'

if (-not $appReg -or -not $appReg.ObjectId) {
    Write-Error "Could not find App Registration: $APP_REGISTRATION_NAME"
    exit 1
}

$APP_OBJECT_ID = $appReg.ObjectId
$APP_ID = $appReg.AppId

Write-Success "App Registration found:"
Write-Info "  Name: $APP_REGISTRATION_NAME"
Write-Info "  App ID: $APP_ID"
Write-Info "  Object ID: $APP_OBJECT_ID"
Write-Info ""

Write-Info "================================================"
Write-Info "MANUAL STEPS REQUIRED"
Write-Info "================================================"
Write-Info ""
Write-Info "SharePoint UI doesn't easily support adding App Registrations."
Write-Info "Use one of these methods:"
Write-Info ""
Write-Info "METHOD 1: Add to SharePoint Group (Easiest)"
Write-Info "1. Go to: $SHAREPOINT_SITE_URL"
Write-Info "2. Click: Settings (gear) -> Site permissions"
Write-Info "3. Click on: 'Gcloud Members' group"
Write-Info "4. Click: 'New' -> 'Add users to this group'"
Write-Info "5. In the 'Enter names or email addresses' field, paste:"
Write-Host "   $APP_OBJECT_ID" -ForegroundColor Yellow
Write-Info "6. Click: 'Share'"
Write-Info ""
Write-Info "METHOD 2: Use SharePoint Online Management Shell"
Write-Info "1. Install: Install-Module -Name Microsoft.Online.SharePoint.PowerShell"
Write-Info "2. Connect: Connect-SPOService -Url https://conmacdev-admin.sharepoint.com"
Write-Info "3. Add to group:"
Write-Host "   Add-SPOSiteGroupUser -Site '$SHAREPOINT_SITE_URL' -Group 'Gcloud Members' -LoginName '$APP_OBJECT_ID'" -ForegroundColor Yellow
Write-Info ""
Write-Info "METHOD 3: Use Graph API (Advanced)"
Write-Info "The Graph API method requires the App Registration to already have"
Write-Info "permissions, which creates a chicken-and-egg problem."
Write-Info ""
Write-Info "RECOMMENDED: Use Method 1 (Add to SharePoint Group)"
Write-Info ""

