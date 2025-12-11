# Simple script to grant SharePoint permissions using site URL
# This finds the site by URL and grants permissions directly

$ErrorActionPreference = "Stop"

function Write-Info { param([string]$msg) Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Success { param([string]$msg) Write-Host "[SUCCESS] $msg" -ForegroundColor Green }
function Write-Error { param([string]$msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }

# Load configuration
$configPath = "config\deployment-config.env"
if (-not (Test-Path $configPath)) {
    Write-Error "deployment-config.env not found."
    exit 1
}

$config = @{}
Get-Content $configPath -Encoding UTF8 | ForEach-Object {
    if ($_ -match '^([^=]+)=(.*)$') {
        $config[$matches[1].Trim()] = $matches[2].Trim()
    }
}

$APP_REGISTRATION_NAME = $config.APP_REGISTRATION_NAME
$SHAREPOINT_SITE_URL = $config.SHAREPOINT_SITE_URL

Write-Info "Granting SharePoint permissions"
Write-Info ""

# Get App Registration Object ID
$appReg = az ad app list --display-name "$APP_REGISTRATION_NAME" --query "[0].id" -o tsv
if (-not $appReg) {
    Write-Error "App Registration not found"
    exit 1
}

Write-Info "App Registration Object ID: $appReg"
Write-Info "Site URL: $SHAREPOINT_SITE_URL"
Write-Info ""

# Get token
$token = az account get-access-token --resource https://graph.microsoft.com --query accessToken -o tsv

# Get site by URL
Write-Info "Finding site by URL..."
$siteUrlEncoded = [System.Web.HttpUtility]::UrlEncode($SHAREPOINT_SITE_URL)
$site = az rest --method GET `
    --uri "https://graph.microsoft.com/v1.0/sites/$siteUrlEncoded" `
    --headers "Authorization=Bearer $token" `
    -o json | ConvertFrom-Json

if (-not $site.id) {
    Write-Error "Could not find site"
    exit 1
}

Write-Success "Site found: $($site.displayName)"
Write-Info "Site ID: $($site.id)"
Write-Info ""

# Get groups
Write-Info "Getting site groups..."
$groups = az rest --method GET `
    --uri "https://graph.microsoft.com/v1.0/sites/$($site.id)/siteGroups" `
    --headers "Authorization=Bearer $token" `
    -o json | ConvertFrom-Json

if ($groups.value) {
    Write-Success "Found groups:"
    $groups.value | ForEach-Object { Write-Info "  - $($_.displayName)" }
    Write-Info ""
    
    $membersGroup = $groups.value | Where-Object { $_.displayName -like "*Members*" } | Select-Object -First 1
    
    if ($membersGroup) {
        Write-Info "Adding to group: $($membersGroup.displayName)"
        
        $body = @{
            "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$appReg"
        } | ConvertTo-Json
        
        $result = az rest --method POST `
            --uri "https://graph.microsoft.com/v1.0/groups/$($membersGroup.id)/members/`$ref" `
            --headers "Authorization=Bearer $token" "Content-Type=application/json" `
            --body $body 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Success "✓ Added to group!"
        } else {
            if ($result -like "*already exists*" -or $result -like "*204*") {
                Write-Success "✓ Already in group!"
            } else {
                Write-Error "Failed: $result"
            }
        }
    }
} else {
    Write-Error "No groups found"
}

Write-Info ""
Write-Info "Test: curl https://pa-gcloud15-api.azurewebsites.net/api/v1/sharepoint/test"

