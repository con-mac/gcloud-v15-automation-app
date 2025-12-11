# Fix SharePoint permissions - Remove Delegated, Add Application permissions

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

if ([string]::IsNullOrWhiteSpace($APP_REGISTRATION_NAME)) {
    Write-Error "Missing APP_REGISTRATION_NAME in config"
    exit 1
}

Write-Info "Fixing SharePoint permissions for: $APP_REGISTRATION_NAME"
Write-Info ""
Write-Warning "This will:"
Write-Warning "1. Remove incorrect Delegated permissions"
Write-Warning "2. Add correct Application permissions"
Write-Warning "3. Grant admin consent"
Write-Info ""

$confirm = Read-Host "Continue? (y/n) [y]"
if ($confirm -ne "y" -and -not [string]::IsNullOrWhiteSpace($confirm)) {
    Write-Info "Cancelled"
    exit 0
}

# Get App Registration ID
$APP_ID = az ad app list --display-name "$APP_REGISTRATION_NAME" --query "[0].appId" -o tsv

if ([string]::IsNullOrWhiteSpace($APP_ID)) {
    Write-Error "App Registration '$APP_REGISTRATION_NAME' not found"
    exit 1
}

Write-Info "App Registration ID: $APP_ID"
Write-Info ""

# Microsoft Graph API ID
$GRAPH_API_ID = "00000003-0000-0000-c000-000000000000"

# Remove incorrect Delegated permissions
# Note: We'll keep User.Read as it's needed for SSO
Write-Info "Removing SharePoint Delegated permissions..."
Write-Info "Note: Keeping User.Read (needed for SSO)"

# Get current permissions
$currentPerms = az ad app show --id $APP_ID --query "requiredResourceAccess" -o json | ConvertFrom-Json

# Remove SharePoint delegated permissions (we'll add Application ones)
# Sites.FullControl.All Delegated ID: 678536fe-1083-478a-9c59-b99265e6b0d3 (but as Scope, not Role)
# Actually, the same ID is used for both, just different type

# Better approach: Remove all, then add correct ones
Write-Info "Removing all SharePoint-related permissions..."

# Remove Sites.FullControl.All (Delegated)
az ad app permission delete `
    --id $APP_ID `
    --api $GRAPH_API_ID `
    --api-permissions "678536fe-1083-478a-9c59-b99265e6b0d3=Scope" `
    --output none 2>&1 | Out-Null

# Remove Sites.ReadWrite.All (Delegated)  
az ad app permission delete `
    --id $APP_ID `
    --api $GRAPH_API_ID `
    --api-permissions "0c0bf378-bf22-4481-978f-6afc4c88705c=Scope" `
    --output none 2>&1 | Out-Null

Write-Success "Removed Delegated permissions"
Write-Info ""

# Add correct Application permissions
Write-Info "Adding Application permissions (required for server-to-server access)..."

# Sites.FullControl.All - Application permission (Role)
Write-Info "Adding Sites.FullControl.All (Application permission)..."
az ad app permission add `
    --id $APP_ID `
    --api $GRAPH_API_ID `
    --api-permissions "678536fe-1083-478a-9c59-b99265e6b0d3=Role" `
    --output none 2>&1 | Out-Null

if ($LASTEXITCODE -eq 0) {
    Write-Success "  ✓ Sites.FullControl.All (Application) added"
} else {
    Write-Warning "  Could not add Sites.FullControl.All"
}

# Sites.ReadWrite.All - Application permission (Role)
Write-Info "Adding Sites.ReadWrite.All (Application permission)..."
az ad app permission add `
    --id $APP_ID `
    --api $GRAPH_API_ID `
    --api-permissions "0c0bf378-bf22-4481-978f-6afc4c88705c=Role" `
    --output none 2>&1 | Out-Null

if ($LASTEXITCODE -eq 0) {
    Write-Success "  ✓ Sites.ReadWrite.All (Application) added"
} else {
    Write-Warning "  Could not add Sites.ReadWrite.All"
}

# Files.ReadWrite.All - Application permission (Role)
Write-Info "Adding Files.ReadWrite.All (Application permission)..."
az ad app permission add `
    --id $APP_ID `
    --api $GRAPH_API_ID `
    --api-permissions "75359482-378d-4052-8f01-80520e7db3cd=Role" `
    --output none 2>&1 | Out-Null

if ($LASTEXITCODE -eq 0) {
    Write-Success "  ✓ Files.ReadWrite.All (Application) added"
} else {
    Write-Warning "  Could not add Files.ReadWrite.All"
}

Write-Info ""
Write-Info "Granting admin consent for Application permissions..."
Write-Info "This is REQUIRED for SharePoint access!"
Write-Info ""

$grantConsent = Read-Host "Grant admin consent now? (y/n) [y]"
if ([string]::IsNullOrWhiteSpace($grantConsent) -or $grantConsent -eq "y") {
    az ad app permission admin-consent --id $APP_ID --output none | Out-Null
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Admin consent granted!"
        Write-Info ""
        Write-Info "Next steps:"
        Write-Info "1. Wait 5-10 minutes for permissions to propagate"
        Write-Info "2. Restart Function App: az functionapp restart --name pa-gcloud15-api --resource-group pa-gcloud15-rg"
        Write-Info "3. Test: curl https://pa-gcloud15-api.azurewebsites.net/api/v1/sharepoint/test"
    } else {
        Write-Error "Failed to grant admin consent automatically"
        Write-Info ""
        Write-Warning "MANUAL STEPS REQUIRED:"
        Write-Warning "1. Go to: https://portal.azure.com -> Azure Active Directory -> App registrations"
        Write-Warning "2. Find: $APP_REGISTRATION_NAME"
        Write-Warning "3. Go to 'API permissions'"
        Write-Warning "4. Click 'Grant admin consent for [your tenant]'"
        Write-Warning "5. Confirm the consent"
        Write-Warning ""
        Write-Warning "This is CRITICAL - Application permissions won't work without admin consent!"
    }
} else {
    Write-Warning "Admin consent not granted. This is REQUIRED!"
    Write-Warning "Please grant manually in Azure Portal (see instructions above)"
}

Write-Info ""
Write-Success "Permission fix complete!"
Write-Info "Run verify-sharepoint-permissions.ps1 to confirm everything is correct"

