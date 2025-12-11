# Verify SharePoint API permissions and admin consent for App Registration

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

Write-Info "Verifying SharePoint permissions for: $APP_REGISTRATION_NAME"
Write-Info ""

# Get App Registration ID
$APP_ID = az ad app list --display-name "$APP_REGISTRATION_NAME" --query "[0].appId" -o tsv

if ([string]::IsNullOrWhiteSpace($APP_ID)) {
    Write-Error "App Registration '$APP_REGISTRATION_NAME' not found"
    exit 1
}

Write-Info "App Registration ID: $APP_ID"
Write-Info ""

# Get API permissions
Write-Info "Checking API permissions..."
$permissions = az ad app show --id $APP_ID --query "requiredResourceAccess" -o json | ConvertFrom-Json

$graphApiId = "00000003-0000-0000-c000-000000000000" # Microsoft Graph API ID
$requiredPermissions = @(
    @{Id="678536fe-1083-478a-9c59-b99265e6b0d3"; Name="Sites.FullControl.All"; Type="Role"},
    @{Id="0c0bf378-bf22-4481-978f-6afc4c88705c"; Name="Sites.ReadWrite.All"; Type="Role"},
    @{Id="75359482-378d-4052-8f01-80520e7db3cd"; Name="Files.ReadWrite.All"; Type="Role"}
)

$graphResource = $permissions | Where-Object { $_.resourceAppId -eq $graphApiId }

if ($graphResource) {
    Write-Success "Microsoft Graph API permissions found"
    Write-Info ""
    
    foreach ($reqPerm in $requiredPermissions) {
        $perm = $graphResource.resourceAccess | Where-Object { $_.id -eq $reqPerm.Id }
        if ($perm) {
            $permType = if ($perm.type -eq "Role") { "Application" } else { "Delegated" }
            Write-Success "  ✓ $($reqPerm.Name) ($permType permission)"
        } else {
            Write-Error "  ✗ $($reqPerm.Name) - NOT FOUND"
        }
    }
} else {
    Write-Error "Microsoft Graph API permissions not found!"
}

Write-Info ""
Write-Info "Checking admin consent status..."
Write-Info ""

# Check service principal and admin consent
$spId = az ad sp list --filter "appId eq '$APP_ID'" --query "[0].id" -o tsv

if (-not [string]::IsNullOrWhiteSpace($spId)) {
    Write-Success "Service Principal found: $spId"
    
    # Get OAuth2 permission grants (admin consent)
    $grants = az rest --method GET --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$spId/oauth2PermissionGrants" -o json | ConvertFrom-Json
    
    # Get app role assignments (for Application permissions)
    $appRoles = az rest --method GET --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$spId/appRoleAssignedTo" -o json | ConvertFrom-Json
    
    Write-Info ""
    Write-Info "Admin Consent Status:"
    
    $sitesFullControlGranted = $appRoles.value | Where-Object { $_.appRoleId -eq "678536fe-1083-478a-9c59-b99265e6b0d3" }
    if ($sitesFullControlGranted) {
        Write-Success "  ✓ Sites.FullControl.All - Admin consent GRANTED"
    } else {
        Write-Error "  ✗ Sites.FullControl.All - Admin consent NOT GRANTED"
        Write-Warning ""
        Write-Warning "ACTION REQUIRED:"
        Write-Warning "1. Go to: https://portal.azure.com -> Azure Active Directory -> App registrations"
        Write-Warning "2. Find: $APP_REGISTRATION_NAME"
        Write-Warning "3. Go to 'API permissions'"
        Write-Warning "4. Click 'Grant admin consent for [your tenant]'"
        Write-Warning "5. Confirm the consent"
    }
} else {
    Write-Error "Service Principal not found for App Registration"
}

Write-Info ""
Write-Info "=========================================="
Write-Info "IMPORTANT: With Application Permissions"
Write-Info "=========================================="
Write-Info ""
Write-Info "When using Sites.FullControl.All (Application permission) with admin consent:"
Write-Info "- The App Registration has access to ALL sites in your tenant"
Write-Info "- You do NOT need to add it to individual SharePoint sites"
Write-Info "- App Registrations don't appear in SharePoint's people picker"
Write-Info "- Access is granted automatically via Microsoft Graph API"
Write-Info ""
Write-Info "If you're still getting access denied errors:"
Write-Info "1. Verify admin consent is granted (see above)"
Write-Info "2. Wait 5-10 minutes for permissions to propagate"
Write-Info "3. Restart the Function App after granting consent"
Write-Info "4. Check Function App logs for authentication errors"

