# Diagnostic script to identify MSAL/SSO issues

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "MSAL/SSO Diagnostic Tool" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Load config
$scriptDir = $PSScriptRoot
$paDeploymentDir = Split-Path $scriptDir -Parent
$projectRoot = Split-Path $paDeploymentDir -Parent

$configPath = $null
$possibleConfigPaths = @(
    (Join-Path $paDeploymentDir "config" "deployment-config.env"),
    (Join-Path $projectRoot "config" "deployment-config.env"),
    (Join-Path $projectRoot "pa-deployment" "config" "deployment-config.env")
)

foreach ($path in $possibleConfigPaths) {
    try {
        $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($path)
        if (Test-Path $resolvedPath -ErrorAction SilentlyContinue) {
            $configPath = $resolvedPath
            break
        }
    } catch {
        if (Test-Path $path -ErrorAction SilentlyContinue) {
            $configPath = (Resolve-Path $path).Path
            break
        }
    }
}

if (-not $configPath) {
    Write-Host "[ERROR] Config file not found" -ForegroundColor Red
    exit 1
}

$config = @{}
Get-Content $configPath | ForEach-Object {
    if ($_ -match '^([^=]+)=(.*)$') {
        $config[$matches[1]] = $matches[2]
    }
}

$APP_REGISTRATION_NAME = $config['APP_REGISTRATION_NAME'] ?? "pa-gcloud15-app"
$WEB_APP_NAME = $config['WEB_APP_NAME'] ?? ""
$WEB_APP_URL = if ($WEB_APP_NAME) { "https://${WEB_APP_NAME}.azurewebsites.net" } else { "" }

Write-Host "[INFO] Configuration loaded" -ForegroundColor Green
Write-Host "  App Registration: $APP_REGISTRATION_NAME" -ForegroundColor Gray
Write-Host "  Web App: $WEB_APP_NAME" -ForegroundColor Gray
Write-Host "  Web App URL: $WEB_APP_URL" -ForegroundColor Gray
Write-Host ""

# 1. Check App Registration
Write-Host "=== 1. App Registration Check ===" -ForegroundColor Yellow
$appJson = az ad app list --display-name $APP_REGISTRATION_NAME --output json 2>&1 | ConvertFrom-Json
if (-not $appJson -or $appJson.Count -eq 0) {
    Write-Host "[ERROR] App Registration not found!" -ForegroundColor Red
    exit 1
}

$APP_ID = $appJson[0].appId
$appDetails = az ad app show --id $APP_ID --output json 2>&1 | ConvertFrom-Json

$spaUris = $appDetails.spa.redirectUris
$webUris = $appDetails.web.redirectUris

Write-Host "SPA Redirect URIs:" -ForegroundColor Cyan
if ($spaUris -and $spaUris.Count -gt 0) {
    $spaUris | ForEach-Object { Write-Host "  ✅ $_" -ForegroundColor Green }
    if ($WEB_APP_URL -and $spaUris -contains $WEB_APP_URL) {
        Write-Host "[SUCCESS] Base URL found in SPA redirect URIs" -ForegroundColor Green
    } else {
        Write-Host "[WARNING] Base URL NOT in SPA redirect URIs" -ForegroundColor Yellow
    }
} else {
    Write-Host "  ❌ (none) - THIS IS THE PROBLEM!" -ForegroundColor Red
}

Write-Host ""
Write-Host "Web Redirect URIs:" -ForegroundColor Cyan
if ($webUris -and $webUris.Count -gt 0) {
    $webUris | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
    # Check for /auth/callback (wrong for SPAs)
    $hasCallback = $webUris | Where-Object { $_ -like "*/auth/callback*" }
    if ($hasCallback) {
        Write-Host "[WARNING] Found /auth/callback in web URIs (should be removed for SPAs)" -ForegroundColor Yellow
    }
} else {
    Write-Host "  (none)" -ForegroundColor Gray
}

# 2. Check Docker image
Write-Host ""
Write-Host "=== 2. Docker Image Check ===" -ForegroundColor Yellow
$ACR_NAME = $config['ACR_NAME'] ?? ""
$IMAGE_TAG = $config['IMAGE_TAG'] ?? "latest"

if ($ACR_NAME) {
    Write-Host "Checking if frontend image exists in ACR..." -ForegroundColor Cyan
    $tags = az acr repository show-tags --name $ACR_NAME --repository frontend --output tsv 2>&1
    if ($tags -and $tags -contains $IMAGE_TAG) {
        Write-Host "[SUCCESS] Frontend image found: frontend:$IMAGE_TAG" -ForegroundColor Green
    } else {
        Write-Host "[WARNING] Frontend image not found or tag mismatch" -ForegroundColor Yellow
        Write-Host "  Run: .\pa-deployment\scripts\build-and-push-images.ps1" -ForegroundColor Gray
    }
} else {
    Write-Host "[WARNING] ACR_NAME not in config" -ForegroundColor Yellow
}

# 3. Check Web App configuration
Write-Host ""
Write-Host "=== 3. Web App Configuration ===" -ForegroundColor Yellow
if ($WEB_APP_NAME) {
    Write-Host "Checking Web App app settings..." -ForegroundColor Cyan
    $appSettings = az webapp config appsettings list --name $WEB_APP_NAME --resource-group $config['RESOURCE_GROUP'] --output json 2>&1 | ConvertFrom-Json
    
    $hasClientId = $appSettings | Where-Object { $_.name -eq "VITE_AZURE_AD_CLIENT_ID" -and $_.value -ne "PLACEHOLDER_CLIENT_ID" }
    $hasTenantId = $appSettings | Where-Object { $_.name -eq "VITE_AZURE_AD_TENANT_ID" -and $_.value -ne "PLACEHOLDER_TENANT_ID" }
    $hasRedirectUri = $appSettings | Where-Object { $_.name -eq "VITE_AZURE_AD_REDIRECT_URI" }
    
    if ($hasClientId) {
        Write-Host "[SUCCESS] VITE_AZURE_AD_CLIENT_ID is configured" -ForegroundColor Green
    } else {
        Write-Host "[WARNING] VITE_AZURE_AD_CLIENT_ID missing or placeholder" -ForegroundColor Yellow
    }
    
    if ($hasTenantId) {
        Write-Host "[SUCCESS] VITE_AZURE_AD_TENANT_ID is configured" -ForegroundColor Green
    } else {
        Write-Host "[WARNING] VITE_AZURE_AD_TENANT_ID missing or placeholder" -ForegroundColor Yellow
    }
    
    if ($hasRedirectUri) {
        Write-Host "[SUCCESS] VITE_AZURE_AD_REDIRECT_URI is configured" -ForegroundColor Green
        $redirectValue = ($appSettings | Where-Object { $_.name -eq "VITE_AZURE_AD_REDIRECT_URI" }).value
        if ($redirectValue -ne $WEB_APP_URL) {
            Write-Host "[WARNING] Redirect URI mismatch: $redirectValue (expected: $WEB_APP_URL)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "[WARNING] VITE_AZURE_AD_REDIRECT_URI missing" -ForegroundColor Yellow
    }
} else {
    Write-Host "[WARNING] WEB_APP_NAME not in config" -ForegroundColor Yellow
}

# 4. Summary and recommendations
Write-Host ""
Write-Host "=== Summary & Recommendations ===" -ForegroundColor Yellow

$issues = @()

if (-not $spaUris -or $spaUris.Count -eq 0) {
    $issues += "App Registration is NOT configured as SPA platform"
}

if ($WEB_APP_URL -and $spaUris -and $spaUris -notcontains $WEB_APP_URL) {
    $issues += "Base URL not in SPA redirect URIs"
}

if ($issues.Count -eq 0) {
    Write-Host "[SUCCESS] Configuration looks correct!" -ForegroundColor Green
    Write-Host ""
    Write-Host "If SSO still not working, check:" -ForegroundColor Cyan
    Write-Host "  1. Browser console for specific MSAL errors" -ForegroundColor Gray
    Write-Host "  2. Network tab for redirect responses" -ForegroundColor Gray
    Write-Host "  3. Ensure Docker image was built with actual SSO values (not placeholders)" -ForegroundColor Gray
    Write-Host "  4. Clear browser cache and try again" -ForegroundColor Gray
} else {
    Write-Host "[ISSUES FOUND]:" -ForegroundColor Red
    $issues | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    Write-Host ""
    Write-Host "Fix by running:" -ForegroundColor Yellow
    Write-Host "  .\pa-deployment\scripts\configure-auth.ps1" -ForegroundColor Cyan
}

