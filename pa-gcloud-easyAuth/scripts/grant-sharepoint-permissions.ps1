# Grant App Registration permissions to SharePoint site

$ErrorActionPreference = "Stop"

function Write-Info { param([string]$msg) Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Success { param([string]$msg) Write-Host "[SUCCESS] $msg" -ForegroundColor Green }
function Write-Warning { param([string]$msg) Write-Host "[WARNING] $msg" -ForegroundColor Yellow }
function Write-Error { param([string]$msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }

# Load configuration
# Look for config in same location as other scripts (project root/config/)
$configPath = "config\deployment-config.env"
if (-not (Test-Path $configPath)) {
    Write-Error "deployment-config.env not found. Please run deploy.ps1 first."
    Write-Info "Expected location: $((Get-Location).Path)\config\deployment-config.env"
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

if ([string]::IsNullOrWhiteSpace($APP_REGISTRATION_NAME)) {
    Write-Error "Missing APP_REGISTRATION_NAME in config"
    exit 1
}
if ([string]::IsNullOrWhiteSpace($SHAREPOINT_SITE_ID)) {
    Write-Error "Missing SHAREPOINT_SITE_ID in config"
    exit 1
}

# Get App Registration ID
Write-Info "Getting App Registration ID for: $APP_REGISTRATION_NAME"
$APP_ID = az ad app list --display-name "$APP_REGISTRATION_NAME" --query "[0].appId" -o tsv

if ([string]::IsNullOrWhiteSpace($APP_ID)) {
    Write-Error "App Registration '$APP_REGISTRATION_NAME' not found"
    exit 1
}

Write-Info "App Registration ID: $APP_ID"
Write-Info "SharePoint Site ID: $SHAREPOINT_SITE_ID"
Write-Info "SharePoint Site URL: $SHAREPOINT_SITE_URL"
Write-Info ""

Write-Info "Granting App Registration access to SharePoint site..."
Write-Info "This requires:"
Write-Info "1. App Registration has 'Sites.FullControl.All' API permission (Application)"
Write-Info "2. Admin consent granted for the permission"
Write-Info ""

# Get access token for Graph API
Write-Info "Getting access token for Microsoft Graph API..."
$token = az account get-access-token --resource https://graph.microsoft.com --query accessToken -o tsv

if ([string]::IsNullOrWhiteSpace($token)) {
    Write-Error "Failed to get access token"
    exit 1
}

# Try to grant permissions via Graph API
Write-Info "Attempting to grant permissions via Graph API..."
try {
    $body = @{
        roles = @("write")
        grantedToIdentities = @(@{
            application = @{
                id = $APP_ID
                displayName = $APP_REGISTRATION_NAME
            }
        })
    } | ConvertTo-Json -Depth 10
    
    $response = az rest --method POST `
        --uri "https://graph.microsoft.com/v1.0/sites/$SHAREPOINT_SITE_ID/permissions" `
        --headers "Authorization=Bearer $token" "Content-Type=application/json" `
        --body $body 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "SharePoint permissions granted via Graph API!"
    } else {
        Write-Warning "Graph API call failed. You may need to grant permissions manually."
        Write-Info "Response: $response"
        Write-Info ""
        Write-Info "MANUAL STEPS:"
        Write-Info "1. Go to SharePoint site: $SHAREPOINT_SITE_URL"
        Write-Info "2. Click Settings (gear icon) -> Site permissions"
        Write-Info "3. Click 'Grant permissions'"
        Write-Info "4. Add: $APP_REGISTRATION_NAME (or App ID: $APP_ID)"
        Write-Info "5. Grant 'Edit' or 'Full Control' permissions"
        Write-Info "6. Click 'Share'"
    }
} catch {
    Write-Warning "Exception occurred: $_"
    Write-Info ""
    Write-Info "MANUAL STEPS:"
    Write-Info "1. Go to SharePoint site: $SHAREPOINT_SITE_URL"
    Write-Info "2. Click Settings (gear icon) -> Site permissions"
    Write-Info "3. Click 'Grant permissions'"
    Write-Info "4. Add: $APP_REGISTRATION_NAME (or App ID: $APP_ID)"
    Write-Info "5. Grant 'Edit' or 'Full Control' permissions"
    Write-Info "6. Click 'Share'"
}

Write-Info ""
Write-Info "Also verify App Registration has required API permissions:"
Write-Info "1. Go to Azure Portal -> Azure Active Directory -> App registrations"
Write-Info "2. Find: $APP_REGISTRATION_NAME"
Write-Info "3. Go to 'API permissions'"
Write-Info "4. Ensure 'Sites.FullControl.All' (Application permission) is added"
Write-Info "5. Ensure 'Admin consent' is granted (green checkmark)"
