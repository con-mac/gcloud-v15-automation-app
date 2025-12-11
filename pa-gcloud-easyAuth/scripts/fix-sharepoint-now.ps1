# Fix SharePoint access - Focus on what we CAN control
# Skip the site-level permissions for now - Application permissions with admin consent should work

$ErrorActionPreference = "Stop"

function Write-Info { param([string]$msg) Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Success { param([string]$msg) Write-Host "[SUCCESS] $msg" -ForegroundColor Green }
function Write-Warning { param([string]$msg) Write-Host "[WARNING] $msg" -ForegroundColor Yellow }
function Write-Error { param([string]$msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }

Write-Info "================================================"
Write-Info "SHAREPOINT FIX - FOCUS ON WHAT WE CAN CONTROL"
Write-Info "================================================"
Write-Info ""

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

Write-Info "Step 1: Verify API Permissions and Admin Consent"
Write-Info ""

# Check API permissions
Write-Info "Checking API permissions..."
$appId = az ad app list --display-name "$APP_REGISTRATION_NAME" --query "[0].appId" -o tsv
if (-not $appId) {
    Write-Error "App Registration not found"
    exit 1
}

Write-Info "App Registration ID: $appId"
Write-Info ""
Write-Info "CRITICAL: Verify Admin Consent is granted"
Write-Info ""
Write-Host "Go to: https://portal.azure.com -> Azure Active Directory -> App registrations -> $APP_REGISTRATION_NAME -> API permissions" -ForegroundColor Yellow
Write-Host "Look for Application permissions:" -ForegroundColor Yellow
Write-Host "  - Sites.FullControl.All" -ForegroundColor Yellow
Write-Host "  - Sites.ReadWrite.All" -ForegroundColor Yellow
Write-Host "  - Files.ReadWrite.All" -ForegroundColor Yellow
Write-Host ""
Write-Host "They MUST show: '✓ Granted for [tenant name]'" -ForegroundColor Yellow
Write-Host ""
Write-Host "If they show 'Not granted', click 'Grant admin consent for [tenant]' and confirm" -ForegroundColor Yellow
Write-Info ""

$consent = Read-Host "Have you verified admin consent is granted? (y/n) [n]"
if ($consent -ne "y") {
    Write-Error "Admin consent is REQUIRED. Please grant it now, then run this script again."
    exit 1
}

Write-Info ""
Write-Info "Step 2: Test if Application permissions work WITHOUT site-level permissions"
Write-Info ""
Write-Info "For Application permissions with admin consent, the App Registration should"
Write-Info "be able to access SharePoint WITHOUT being added to a group."
Write-Info ""
Write-Info "Testing SharePoint connectivity..."
Write-Info ""

Start-Sleep -Seconds 2

$testResult = curl -s https://pa-gcloud15-api.azurewebsites.net/api/v1/sharepoint/test
Write-Info "Test result: $testResult"
Write-Info ""

if ($testResult -like "*connected*true*" -or $testResult -like "*Successfully*") {
    Write-Success "✓ SharePoint is working! Application permissions with admin consent are sufficient!"
    Write-Info ""
    Write-Info "Site-level permissions are NOT required when using Application permissions"
    Write-Info "with admin consent. The App Registration can access SharePoint directly."
} elseif ($testResult -like "*SPO license*") {
    Write-Warning "Still getting SPO license error"
    Write-Info ""
    Write-Info "This might be because:"
    Write-Info "1. Admin consent hasn't propagated yet (wait 5-10 minutes)"
    Write-Info "2. The Function App needs to be restarted to pick up new permissions"
    Write-Info ""
    Write-Info "Let's restart the Function App..."
    az functionapp restart --name pa-gcloud15-api --resource-group pa-gcloud15-rg
    Write-Info ""
    Write-Info "Wait 2-3 minutes, then test again:"
    Write-Host "  curl https://pa-gcloud15-api.azurewebsites.net/api/v1/sharepoint/test" -ForegroundColor Yellow
} else {
    Write-Info "Current error: $testResult"
    Write-Info ""
    Write-Info "Check Function App logs for more details:"
    Write-Host "  https://portal.azure.com -> pa-gcloud15-api -> Log stream" -ForegroundColor Yellow
}

Write-Info ""
Write-Info "================================================"
Write-Info "KEY INSIGHT"
Write-Info "================================================"
Write-Info ""
Write-Info "Application permissions with admin consent should allow the App Registration"
Write-Info "to access SharePoint WITHOUT needing site-level permissions."
Write-Info ""
Write-Info "The 'SPO license' error might be misleading - it could be:"
Write-Info "1. Admin consent not fully propagated"
Write-Info "2. Function App needs restart"
Write-Info "3. A temporary Graph API issue"
Write-Info ""
Write-Info "Focus on: Admin Consent (Step 1) - that's the critical piece."

