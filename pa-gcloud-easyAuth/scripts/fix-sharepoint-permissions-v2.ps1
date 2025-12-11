# Fix SharePoint permissions - Remove ALL instances, Add only Application permissions

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

# Permission IDs
$SITES_FULL_CONTROL_ID = "678536fe-1083-478a-9c59-b99265e6b0d3"
$SITES_READWRITE_ID = "0c0bf378-bf22-4481-978f-6afc4c88705c"
$FILES_READWRITE_ID = "75359482-378d-4052-8f01-80520e7db3cd"

Write-Info "Step 1: Removing ALL instances of SharePoint permissions (both Delegated and Application)..."
Write-Info ""

# Remove Delegated (Scope) versions
Write-Info "Removing Delegated (Scope) permissions..."
az ad app permission delete --id $APP_ID --api $GRAPH_API_ID --api-permissions "${SITES_FULL_CONTROL_ID}=Scope" --output none 2>&1 | Out-Null
az ad app permission delete --id $APP_ID --api $GRAPH_API_ID --api-permissions "${SITES_READWRITE_ID}=Scope" --output none 2>&1 | Out-Null
az ad app permission delete --id $APP_ID --api $GRAPH_API_ID --api-permissions "${FILES_READWRITE_ID}=Scope" --output none 2>&1 | Out-Null

# Remove Application (Role) versions (in case they exist)
Write-Info "Removing any existing Application (Role) permissions..."
az ad app permission delete --id $APP_ID --api $GRAPH_API_ID --api-permissions "${SITES_FULL_CONTROL_ID}=Role" --output none 2>&1 | Out-Null
az ad app permission delete --id $APP_ID --api $GRAPH_API_ID --api-permissions "${SITES_READWRITE_ID}=Role" --output none 2>&1 | Out-Null
az ad app permission delete --id $APP_ID --api $GRAPH_API_ID --api-permissions "${FILES_READWRITE_ID}=Role" --output none 2>&1 | Out-Null

Write-Success "Removed all SharePoint permissions"
Write-Info ""
Start-Sleep -Seconds 2

Write-Info "Step 2: Adding Application permissions (Role type)..."
Write-Info ""

# Add Application permissions
Write-Info "Adding Sites.FullControl.All (Application permission)..."
az ad app permission add --id $APP_ID --api $GRAPH_API_ID --api-permissions "${SITES_FULL_CONTROL_ID}=Role" --output none
if ($LASTEXITCODE -eq 0) {
    Write-Success "  ✓ Sites.FullControl.All (Application) added"
} else {
    Write-Error "  ✗ Failed to add Sites.FullControl.All"
}

Write-Info "Adding Sites.ReadWrite.All (Application permission)..."
az ad app permission add --id $APP_ID --api $GRAPH_API_ID --api-permissions "${SITES_READWRITE_ID}=Role" --output none
if ($LASTEXITCODE -eq 0) {
    Write-Success "  ✓ Sites.ReadWrite.All (Application) added"
} else {
    Write-Error "  ✗ Failed to add Sites.ReadWrite.All"
}

Write-Info "Adding Files.ReadWrite.All (Application permission)..."
az ad app permission add --id $APP_ID --api $GRAPH_API_ID --api-permissions "${FILES_READWRITE_ID}=Role" --output none
if ($LASTEXITCODE -eq 0) {
    Write-Success "  ✓ Files.ReadWrite.All (Application) added"
} else {
    Write-Error "  ✗ Failed to add Files.ReadWrite.All"
}

Write-Info ""
Write-Warning "IMPORTANT: You must grant admin consent in Azure Portal"
Write-Warning ""
Write-Warning "1. Go to: https://portal.azure.com -> Azure Active Directory -> App registrations"
Write-Warning "2. Find: $APP_REGISTRATION_NAME"
Write-Warning "3. Go to 'API permissions'"
Write-Warning "4. Verify permissions show as 'Application' type (not Delegated)"
Write-Warning "5. Click 'Grant admin consent for [your tenant]'"
Write-Warning "6. Confirm the consent"
Write-Info ""
Write-Info "After granting consent, run: .\pa-deployment\scripts\verify-sharepoint-permissions.ps1"

