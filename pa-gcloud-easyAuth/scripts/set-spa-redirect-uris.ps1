# Helper function to set SPA redirect URIs using Microsoft Graph API
# This is needed because Azure CLI doesn't always support --spa-redirect-uris

param(
    [Parameter(Mandatory=$true)]
    [string]$AppId,
    
    [Parameter(Mandatory=$true)]
    [string[]]$RedirectUris
)

$tenantId = az account show --query tenantId -o tsv
if (-not $tenantId) {
    Write-Error "Could not get tenant ID"
    exit 1
}

# Get access token for Graph API
$token = az account get-access-token --resource "https://graph.microsoft.com" --query accessToken -o tsv
if (-not $token) {
    Write-Error "Could not get access token"
    exit 1
}

# Get current app registration
$appUri = "https://graph.microsoft.com/v1.0/applications(appId='$AppId')"
$headers = @{
    "Authorization" = "Bearer $token"
    "Content-Type" = "application/json"
}

$currentApp = Invoke-RestMethod -Uri $appUri -Method Get -Headers $headers

# Update SPA redirect URIs
$spaRedirectUris = @()
foreach ($uri in $RedirectUris) {
    $spaRedirectUris += $uri
}

$body = @{
    spa = @{
        redirectUris = $spaRedirectUris
    }
} | ConvertTo-Json -Depth 10

try {
    Invoke-RestMethod -Uri $appUri -Method Patch -Headers $headers -Body $body | Out-Null
    Write-Host "[SUCCESS] SPA redirect URIs updated" -ForegroundColor Green
    return $true
} catch {
    Write-Warning "Could not update SPA redirect URIs via Graph API: $_"
    return $false
}

