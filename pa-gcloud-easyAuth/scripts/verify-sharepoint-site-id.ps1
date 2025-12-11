# Verify SharePoint Site ID matches the actual site

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

$SHAREPOINT_SITE_URL = $config.SHAREPOINT_SITE_URL
$SHAREPOINT_SITE_ID = $config.SHAREPOINT_SITE_ID
$APP_REGISTRATION_NAME = $config.APP_REGISTRATION_NAME

Write-Info "Verifying SharePoint Site Configuration"
Write-Info ""

Write-Info "Current Configuration:"
Write-Info "  Site URL: $SHAREPOINT_SITE_URL"
Write-Info "  Site ID: $SHAREPOINT_SITE_ID"
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

# Extract site hostname and path
if ($SHAREPOINT_SITE_URL -match 'https://([^/]+)(/sites/([^/]+))?') {
    $hostname = $matches[1]
    $sitePath = $matches[3]
    
    Write-Info "Extracted:"
    Write-Info "  Hostname: $hostname"
    Write-Info "  Site Path: $sitePath"
    Write-Info ""
    
    # Try to get site info using Graph API
    Write-Info "Querying Microsoft Graph API for site information..."
    
    # Method 1: Try with site ID directly
    $ErrorActionPreference = 'SilentlyContinue'
    $siteInfo = az rest --method GET `
        --uri "https://graph.microsoft.com/v1.0/sites/$SHAREPOINT_SITE_ID" `
        --headers "Authorization=Bearer $token" `
        -o json 2>&1 | ConvertFrom-Json
    $ErrorActionPreference = 'Stop'
    
    if ($LASTEXITCODE -eq 0 -and $siteInfo) {
        Write-Success "✓ Site ID is valid!"
        Write-Info "  Site Name: $($siteInfo.displayName)"
        Write-Info "  Site URL: $($siteInfo.webUrl)"
        Write-Info "  Site ID: $($siteInfo.id)"
        Write-Info ""
        
        if ($siteInfo.id -ne $SHAREPOINT_SITE_ID) {
            Write-Warning "⚠ Site ID in config doesn't match Graph API response"
            Write-Info "  Config has: $SHAREPOINT_SITE_ID"
            Write-Info "  Graph API returned: $($siteInfo.id)"
            Write-Info ""
            Write-Info "Consider updating config with: $($siteInfo.id)"
        }
    } else {
        Write-Warning "Could not verify site ID via Graph API"
        Write-Info "This might be a permissions issue with the Graph API token"
    }
    
    # Method 2: Try to get site by hostname and path
    Write-Info ""
    Write-Info "Attempting to find site by hostname and path..."
    $sitePathEncoded = [System.Web.HttpUtility]::UrlEncode("$hostname`:/sites/$sitePath")
    
    $ErrorActionPreference = 'SilentlyContinue'
    $siteByPath = az rest --method GET `
        --uri "https://graph.microsoft.com/v1.0/sites/$hostname`:/sites/$sitePath" `
        --headers "Authorization=Bearer $token" `
        -o json 2>&1 | ConvertFrom-Json
    $ErrorActionPreference = 'Stop'
    
    if ($LASTEXITCODE -eq 0 -and $siteByPath) {
        Write-Success "✓ Site found by path!"
        Write-Info "  Site Name: $($siteByPath.displayName)"
        Write-Info "  Site URL: $($siteByPath.webUrl)"
        Write-Info "  Site ID: $($siteByPath.id)"
        Write-Info ""
        
        if ($siteByPath.id -ne $SHAREPOINT_SITE_ID) {
            Write-Warning "⚠ Site ID mismatch!"
            Write-Info "  Config has: $SHAREPOINT_SITE_ID"
            Write-Info "  Actual Site ID: $($siteByPath.id)"
            Write-Info ""
            Write-Warning "Update your config with the correct Site ID:"
            Write-Host "  SHAREPOINT_SITE_ID=$($siteByPath.id)" -ForegroundColor Yellow
        } else {
            Write-Success "✓ Site ID matches!"
        }
    } else {
        Write-Warning "Could not find site by path"
        Write-Info "Error: $siteByPath"
    }
} else {
    Write-Error "Could not parse SharePoint site URL: $SHAREPOINT_SITE_URL"
    Write-Info "Expected format: https://<tenant>.sharepoint.com/sites/<sitename>"
}

Write-Info ""
Write-Info "Next Steps:"
Write-Info "1. If Site ID is wrong, update config and redeploy"
Write-Info "2. Grant site-level permissions: Go to $SHAREPOINT_SITE_URL -> Settings -> Site permissions"
Write-Info "3. Add App Registration: $APP_REGISTRATION_NAME (or App ID from config)"
Write-Info "4. Grant 'Edit' or 'Full Control' permissions"

