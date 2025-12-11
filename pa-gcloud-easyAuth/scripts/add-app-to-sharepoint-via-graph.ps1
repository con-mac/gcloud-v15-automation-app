# Add App Registration to SharePoint group using Microsoft Graph API
# This uses your existing Azure CLI authentication

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

Write-Info "Adding App Registration to SharePoint group via Graph API"
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

# Get access token for Graph API
Write-Info "Getting access token for Microsoft Graph API..."
$ErrorActionPreference = 'SilentlyContinue'
$token = az account get-access-token --resource https://graph.microsoft.com --query accessToken -o tsv 2>&1
$ErrorActionPreference = 'Stop'

if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
    Write-Error "Could not get access token. Please ensure you're logged in: az login"
    exit 1
}

Write-Success "Access token obtained"
Write-Info ""

# Clean Site ID (remove query parameters if present)
$cleanSiteId = $SHAREPOINT_SITE_ID
if ($cleanSiteId -match '^([^?]+)') {
    $cleanSiteId = $matches[1]
}

Write-Info "Getting SharePoint site information..."
Write-Info "Site ID: $cleanSiteId"
Write-Info ""

# First, get the site to verify it exists and get the correct format
$ErrorActionPreference = 'SilentlyContinue'
$siteInfo = az rest --method GET `
    --uri "https://graph.microsoft.com/v1.0/sites/$cleanSiteId" `
    --headers "Authorization=Bearer $token" `
    -o json 2>&1 | ConvertFrom-Json
$ErrorActionPreference = 'Stop'

if ($LASTEXITCODE -ne 0 -or -not $siteInfo.id) {
    Write-Warning "Could not get site by ID, trying by URL..."
    
    # Try getting site by URL
    $siteUrlEncoded = [System.Web.HttpUtility]::UrlEncode($SHAREPOINT_SITE_URL)
    $ErrorActionPreference = 'SilentlyContinue'
    $siteInfo = az rest --method GET `
        --uri "https://graph.microsoft.com/v1.0/sites/$siteUrlEncoded" `
        --headers "Authorization=Bearer $token" `
        -o json 2>&1 | ConvertFrom-Json
    $ErrorActionPreference = 'Stop'
}

if ($LASTEXITCODE -eq 0 -and $siteInfo.id) {
    Write-Success "Site found: $($siteInfo.displayName)"
    Write-Info "Site ID: $($siteInfo.id)"
    Write-Info ""
    
    # Use the site ID from the response
    $actualSiteId = $siteInfo.id
    
    Write-Info "Getting site groups..."
    
    # Get site groups using the correct endpoint
    $ErrorActionPreference = 'SilentlyContinue'
    $groups = az rest --method GET `
        --uri "https://graph.microsoft.com/v1.0/sites/$actualSiteId/siteGroups" `
        --headers "Authorization=Bearer $token" `
        -o json 2>&1 | ConvertFrom-Json
    $ErrorActionPreference = 'Stop'
    
    if ($LASTEXITCODE -ne 0 -or -not $groups.value) {
        Write-Warning "Could not get groups via /siteGroups, trying /sites/root/web/siteGroups..."
        
        # Try alternative endpoint
        $ErrorActionPreference = 'SilentlyContinue'
        $groups = az rest --method GET `
            --uri "https://graph.microsoft.com/v1.0/sites/$actualSiteId/sites/root/web/siteGroups" `
            --headers "Authorization=Bearer $token" `
            -o json 2>&1 | ConvertFrom-Json
        $ErrorActionPreference = 'Stop'
    }
} else {
    Write-Error "Could not find SharePoint site"
    Write-Info "Error: $siteInfo"
    Write-Info ""
    Write-Info "Please verify:"
    Write-Info "1. Site URL is correct: $SHAREPOINT_SITE_URL"
    Write-Info "2. Site ID is correct: $cleanSiteId"
    Write-Info "3. You have permissions to access the site"
    exit 1
}

if ($LASTEXITCODE -eq 0 -and $groups -and $groups.value) {
    Write-Success "Found site groups:"
    foreach ($group in $groups.value) {
        Write-Info "  - $($group.displayName) (ID: $($group.id))"
    }
    Write-Info ""
    
    # Find "Gcloud Members" group
    $membersGroup = $groups.value | Where-Object { $_.displayName -like "*Members*" -or $_.displayName -eq "Gcloud Members" }
    
    if ($membersGroup) {
        $groupId = $membersGroup.id
        Write-Info "Using group: $($membersGroup.displayName) (ID: $groupId)"
        Write-Info ""
        
        Write-Info "Adding App Registration to group..."
        
        # Add service principal to group
        $body = @{
            "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$APP_OBJECT_ID"
        } | ConvertTo-Json
        
        $ErrorActionPreference = 'SilentlyContinue'
        $result = az rest --method POST `
            --uri "https://graph.microsoft.com/v1.0/groups/$groupId/members/`$ref" `
            --headers "Authorization=Bearer $token" "Content-Type=application/json" `
            --body $body 2>&1
        $ErrorActionPreference = 'Stop'
        
        if ($LASTEXITCODE -eq 0 -or $result -like "*204*") {
            Write-Success "✓ App Registration added to '$($membersGroup.displayName)' group!"
            Write-Info ""
            Write-Info "The App Registration now has access to the SharePoint site."
            Write-Info ""
            Write-Info "Next steps:"
            Write-Info "1. Wait 1-2 minutes for permissions to propagate"
            Write-Info "2. Test SharePoint connectivity:"
            Write-Host "   curl https://pa-gcloud15-api.azurewebsites.net/api/v1/sharepoint/test" -ForegroundColor Yellow
        } else {
            Write-Warning "Response: $result"
            Write-Info ""
            Write-Info "The App Registration might already be in the group, or there was an error."
            Write-Info "Let's verify by checking group members..."
            
            # Check if already in group
            $ErrorActionPreference = 'SilentlyContinue'
            $members = az rest --method GET `
                --uri "https://graph.microsoft.com/v1.0/groups/$groupId/members" `
                --headers "Authorization=Bearer $token" `
                -o json 2>&1 | ConvertFrom-Json
            $ErrorActionPreference = 'Stop'
            
            if ($members.value) {
                $appInGroup = $members.value | Where-Object { $_.id -eq $APP_OBJECT_ID }
                if ($appInGroup) {
                    Write-Success "✓ App Registration is already in the group!"
                } else {
                    Write-Warning "App Registration not found in group members"
                    Write-Info "You may need to grant permissions manually or wait for propagation"
                }
            }
        }
    } else {
        Write-Error "Could not find 'Gcloud Members' group"
        Write-Info "Available groups:"
        foreach ($group in $groups.value) {
            Write-Info "  - $($group.displayName)"
        }
        Write-Info ""
        Write-Info "You may need to use a different group name or create the group first"
    }
} else {
    Write-Error "Could not retrieve site groups"
    Write-Info "Error: $groups"
    Write-Info ""
    Write-Info "This might indicate:"
    Write-Info "1. Site ID is incorrect"
    Write-Info "2. You don't have permissions to view site groups"
    Write-Info "3. The site doesn't exist"
    Write-Info ""
    Write-Info "Verify the site exists: $SHAREPOINT_SITE_URL"
    exit 1
}

