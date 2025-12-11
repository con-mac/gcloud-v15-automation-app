# Add App Registration to SharePoint group using PowerShell
# This is the ONLY reliable way to add App Registrations to SharePoint groups

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

Write-Info "Adding App Registration to SharePoint group"
Write-Info ""

# Get App Registration Object ID
Write-Info "Getting App Registration Object ID..."
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
Write-Info "INSTALL SHAREPOINT ONLINE MANAGEMENT SHELL"
Write-Info "================================================"
Write-Info ""
Write-Info "Step 1: Install the SharePoint Online Management Shell module"
Write-Info "Run this command (may require admin privileges):"
Write-Host "  Install-Module -Name Microsoft.Online.SharePoint.PowerShell -Scope CurrentUser" -ForegroundColor Yellow
Write-Info ""
Write-Info "If you get a prompt about untrusted repository, type 'Y' to continue"
Write-Info ""

$install = Read-Host "Have you installed the SharePoint Online Management Shell module? (y/n) [n]"
if ($install -ne "y") {
    Write-Info ""
    Write-Info "Please install the module first, then run this script again."
    Write-Info "Command: Install-Module -Name Microsoft.Online.SharePoint.PowerShell -Scope CurrentUser"
    exit 0
}

Write-Info ""
Write-Info "================================================"
Write-Info "CONNECT TO SHAREPOINT"
Write-Info "================================================"
Write-Info ""
Write-Info "Step 2: Connect to SharePoint Admin Center"
Write-Info "You'll be prompted to sign in with your admin account"
Write-Info ""

# Extract tenant name from SharePoint URL
if ($SHAREPOINT_SITE_URL -match 'https://([^/]+)') {
    $tenantName = $matches[1] -replace '\.sharepoint\.com', ''
    $adminUrl = "https://$tenantName-admin.sharepoint.com"
    
    Write-Info "Connecting to: $adminUrl"
    Write-Info ""
    
    try {
        Import-Module Microsoft.Online.SharePoint.PowerShell -ErrorAction Stop
        
        Write-Info "Connecting to SharePoint Admin Center..."
        Write-Info "You'll be prompted to sign in..."
        Connect-SPOService -Url $adminUrl
        
        Write-Success "Connected to SharePoint Admin Center"
        Write-Info ""
        
        Write-Info "================================================"
        Write-Info "ADD APP REGISTRATION TO SHAREPOINT GROUP"
        Write-Info "================================================"
        Write-Info ""
        Write-Info "Adding App Registration to 'Gcloud Members' group..."
        Write-Info "  Site: $SHAREPOINT_SITE_URL"
        Write-Info "  Group: Gcloud Members"
        Write-Info "  App Object ID: $APP_OBJECT_ID"
        Write-Info ""
        
        # Add to group
        $ErrorActionPreference = 'SilentlyContinue'
        Add-SPOSiteGroupUser -Site $SHAREPOINT_SITE_URL -Group "Gcloud Members" -LoginName $APP_OBJECT_ID -ErrorAction Stop
        $ErrorActionPreference = 'Stop'
        
        Write-Success "✓ App Registration added to 'Gcloud Members' group!"
        Write-Info ""
        Write-Info "The App Registration now has 'Edit' permissions on the site."
        Write-Info ""
        Write-Info "Next steps:"
        Write-Info "1. Wait 1-2 minutes for permissions to propagate"
        Write-Info "2. Test SharePoint connectivity:"
        Write-Host "   curl https://pa-gcloud15-api.azurewebsites.net/api/v1/sharepoint/test" -ForegroundColor Yellow
        
    } catch {
        Write-Error "Failed to add App Registration to SharePoint group"
        Write-Error "Error: $($_.Exception.Message)"
        Write-Info ""
        Write-Info "Common issues:"
        Write-Info "1. Not signed in as a SharePoint admin"
        Write-Info "2. Site URL format is incorrect"
        Write-Info "3. Group name doesn't exist (should be 'Gcloud Members')"
        Write-Info ""
        Write-Info "Manual alternative: Use Graph API (see grant-sharepoint-site-access.ps1)"
        exit 1
    } finally {
        # Disconnect
        try {
            Disconnect-SPOService -ErrorAction SilentlyContinue
        } catch {
            # Ignore disconnect errors
        }
    }
} else {
    Write-Error "Could not parse SharePoint site URL: $SHAREPOINT_SITE_URL"
    exit 1
}

