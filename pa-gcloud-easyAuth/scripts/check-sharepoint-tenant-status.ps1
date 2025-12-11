# Check SharePoint Online tenant status and enable if needed

$ErrorActionPreference = "Stop"

function Write-Info { param([string]$msg) Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Success { param([string]$msg) Write-Host "[SUCCESS] $msg" -ForegroundColor Green }
function Write-Warning { param([string]$msg) Write-Host "[WARNING] $msg" -ForegroundColor Yellow }
function Write-Error { param([string]$msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }

Write-Info "Checking SharePoint Online tenant status..."
Write-Info ""

# Get tenant ID
$tenant = az account show --query tenantId -o tsv
$tenantDomain = az account show --query user.name -o tsv
if ($tenantDomain -match '@([^.]+)') {
    $tenantName = $matches[1]
}

Write-Info "Tenant: $tenantDomain"
Write-Info ""

# Get access token
$token = az account get-access-token --resource https://graph.microsoft.com --query accessToken -o tsv

Write-Info "Checking SharePoint service status..."
Write-Info ""

# Check if we can access SharePoint admin
$ErrorActionPreference = 'SilentlyContinue'
$spAdmin = az rest --method GET `
    --uri "https://graph.microsoft.com/v1.0/admin/sharepoint/settings" `
    --headers "Authorization=Bearer $token" `
    -o json 2>&1
$ErrorActionPreference = 'Stop'

if ($LASTEXITCODE -eq 0) {
    Write-Success "✓ SharePoint admin settings accessible"
    $spSettings = $spAdmin | ConvertFrom-Json
    Write-Info "Settings: $($spSettings | ConvertTo-Json -Depth 3)"
} else {
    Write-Warning "Could not access SharePoint admin settings"
    Write-Info "Error: $spAdmin"
}

Write-Info ""
Write-Info "================================================"
Write-Info "SOLUTION: Enable SharePoint for API Access"
Write-Info "================================================"
Write-Info ""
Write-Info "The 'Tenant does not have SPO license' error from Graph API means"
Write-Info "SharePoint Online isn't enabled for API access, even though sites exist."
Write-Info ""
Write-Info "To fix this, you need to enable SharePoint Online for the tenant:"
Write-Info ""
Write-Host "1. Go to: https://admin.microsoft.com" -ForegroundColor Yellow
Write-Host "2. Navigate to: Settings -> Org settings" -ForegroundColor Yellow
Write-Host "3. Go to: Services tab" -ForegroundColor Yellow
Write-Host "4. Find: SharePoint" -ForegroundColor Yellow
Write-Host "5. Ensure it's enabled" -ForegroundColor Yellow
Write-Info ""
Write-Info "OR use PowerShell (SharePoint Admin):"
Write-Host "  Connect-SPOService -Url https://$tenantName-admin.sharepoint.com" -ForegroundColor Yellow
Write-Host "  Get-SPOTenant" -ForegroundColor Yellow
Write-Info ""
Write-Info "The key is: SharePoint sites can exist, but SharePoint Online service"
Write-Info "might not be fully enabled for Graph API access."
Write-Info ""
Write-Info "Once enabled, wait 10-15 minutes for changes to propagate, then test again."

