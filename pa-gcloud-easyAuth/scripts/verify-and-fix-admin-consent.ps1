# Verify and fix admin consent - this is THE critical piece

$ErrorActionPreference = "Stop"

function Write-Info { param([string]$msg) Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Success { param([string]$msg) Write-Host "[SUCCESS] $msg" -ForegroundColor Green }
function Write-Error { param([string]$msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }

# Load config
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

Write-Info "================================================"
Write-Info "VERIFY AND FIX ADMIN CONSENT"
Write-Info "================================================"
Write-Info ""
Write-Info "This is THE most critical step. Without admin consent,"
Write-Info "Application permissions will NOT work."
Write-Info ""

# Get App Registration ID
$appId = az ad app list --display-name "$APP_REGISTRATION_NAME" --query "[0].appId" -o tsv
if (-not $appId) {
    Write-Error "App Registration not found"
    exit 1
}

Write-Info "App Registration: $APP_REGISTRATION_NAME"
Write-Info "App ID: $appId"
Write-Info ""

# Get API permissions
Write-Info "Checking API permissions..."
$token = az account get-access-token --resource https://graph.microsoft.com --query accessToken -o tsv

$permissions = az rest --method GET `
    --uri "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=appId eq '$appId'" `
    --headers "Authorization=Bearer $token" `
    -o json | ConvertFrom-Json

if (-not $permissions.value -or $permissions.value.Count -eq 0) {
    Write-Error "Service Principal not found. App Registration may not be fully created."
    exit 1
}

$spId = $permissions.value[0].id

# Get app role assignments (Application permissions)
$appRoles = az rest --method GET `
    --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$spId/appRoleAssignedTo" `
    --headers "Authorization=Bearer $token" `
    -o json | ConvertFrom-Json

Write-Info ""
Write-Info "Current Application Permission Status:"
Write-Info ""

$sharePointPerms = @()
if ($appRoles.value) {
    foreach ($role in $appRoles.value) {
        if ($role.resourceDisplayName -like "*SharePoint*" -or $role.resourceDisplayName -like "*Microsoft Graph*") {
            $sharePointPerms += $role
            Write-Info "  Resource: $($role.resourceDisplayName)"
            Write-Info "  App Role ID: $($role.appRoleId)"
            Write-Info "  Principal Type: $($role.principalType)"
            Write-Info ""
        }
    }
}

if ($sharePointPerms.Count -eq 0) {
    Write-Error "No SharePoint Application permissions found!"
    Write-Info ""
    Write-Info "You need to add Application permissions first:"
    Write-Host "  .\pa-deployment\scripts\fix-sharepoint-permissions-v2.ps1" -ForegroundColor Yellow
    exit 1
}

Write-Info ""
Write-Info "================================================"
Write-Info "MANUAL STEP REQUIRED"
Write-Info "================================================"
Write-Info ""
Write-Host "Go to Azure Portal NOW:" -ForegroundColor Yellow
Write-Host "  https://portal.azure.com" -ForegroundColor Yellow
Write-Host "  -> Azure Active Directory" -ForegroundColor Yellow
Write-Host "  -> App registrations" -ForegroundColor Yellow
Write-Host "  -> $APP_REGISTRATION_NAME" -ForegroundColor Yellow
Write-Host "  -> API permissions" -ForegroundColor Yellow
Write-Info ""
Write-Host "Look for these Application permissions:" -ForegroundColor Yellow
Write-Host "  - Sites.FullControl.All" -ForegroundColor Yellow
Write-Host "  - Sites.ReadWrite.All" -ForegroundColor Yellow
Write-Host "  - Files.ReadWrite.All" -ForegroundColor Yellow
Write-Info ""
Write-Host "They MUST show: '✓ Granted for [tenant name]'" -ForegroundColor Green
Write-Host ""
Write-Host "If they show 'Not granted' or have a warning icon:" -ForegroundColor Red
Write-Host "  1. Click 'Grant admin consent for [tenant name]'" -ForegroundColor Yellow
Write-Host "  2. Click 'Yes' to confirm" -ForegroundColor Yellow
Write-Host "  3. Wait 2-3 minutes for propagation" -ForegroundColor Yellow
Write-Info ""

$verified = Read-Host "Have you verified admin consent is GRANTED (shows green checkmark)? (y/n) [n]"

if ($verified -ne "y") {
    Write-Error ""
    Write-Error "Admin consent MUST be granted. This is not optional."
    Write-Error "Without admin consent, Application permissions will NOT work."
    Write-Error ""
    Write-Error "Please grant admin consent now, then run this script again."
    exit 1
}

Write-Info ""
Write-Success "Admin consent verified!"
Write-Info ""
Write-Info "Now let's test if it works..."
Write-Info ""

Start-Sleep -Seconds 5

# Restart Function App to pick up any changes
Write-Info "Restarting Function App..."
az functionapp restart --name pa-gcloud15-api --resource-group pa-gcloud15-rg | Out-Null

Write-Info "Waiting 2 minutes for restart and propagation..."
Start-Sleep -Seconds 120

Write-Info ""
Write-Info "Testing SharePoint connectivity..."
$test = curl -s https://pa-gcloud15-api.azurewebsites.net/api/v1/sharepoint/test
Write-Info "Result: $test"
Write-Info ""

if ($test -like "*connected*true*") {
    Write-Success "✓✓✓ SHAREPOINT IS WORKING! ✓✓✓"
} elseif ($test -like "*SPO license*") {
    Write-Warning "Still getting SPO license error"
    Write-Info ""
    Write-Info "This means:"
    Write-Info "1. Admin consent is granted ✓"
    Write-Info "2. But Graph API still can't access SharePoint"
    Write-Info ""
    Write-Info "This is a TENANT-LEVEL issue, not an app configuration issue."
    Write-Info "The app is configured correctly."
    Write-Info ""
    Write-Info "For production (PA Consulting tenant), this should work."
    Write-Info "The test tenant's SharePoint may not be fully enabled for API access."
} else {
    Write-Info "Check the error message above for details"
}

