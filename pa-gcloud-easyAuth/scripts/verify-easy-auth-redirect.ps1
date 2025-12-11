# Verify and fix Easy Auth redirect configuration
# This script checks if the Web App URL is in the allowed external redirect URLs

$ErrorActionPreference = "Stop"

# Load configuration
if (-not (Test-Path "config\deployment-config.env")) {
    Write-Error "deployment-config.env not found. Please run deploy.ps1 first."
    exit 1
}

# Parse environment file
$config = @{}
$configPath = "config\deployment-config.env"
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

$FUNCTION_APP_NAME = $config.FUNCTION_APP_NAME
$RESOURCE_GROUP = $config.RESOURCE_GROUP
$WEB_APP_NAME = $config.WEB_APP_NAME

function Write-Info { param([string]$msg) Write-Host "[INFO] $msg" -ForegroundColor Blue }
function Write-Success { param([string]$msg) Write-Host "[SUCCESS] $msg" -ForegroundColor Green }
function Write-Warning { param([string]$msg) Write-Host "[WARNING] $msg" -ForegroundColor Yellow }
function Write-Error { param([string]$msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }

if (-not $WEB_APP_NAME) {
    Write-Error "WEB_APP_NAME not found in config"
    exit 1
}

$WEB_APP_URL = "https://$WEB_APP_NAME.azurewebsites.net"

Write-Info "Checking Easy Auth configuration for Function App: $FUNCTION_APP_NAME"
Write-Info "Web App URL that should be allowed: $WEB_APP_URL"

# Get current Easy Auth configuration
Write-Info "Retrieving current Easy Auth configuration..."
$authConfig = az webapp auth show --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP -o json 2>&1 | ConvertFrom-Json

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to retrieve Easy Auth configuration"
    exit 1
}

# Check if Web App URL is in allowed external redirect URLs
$allowedUrls = @()
if ($authConfig.properties.allowedExternalRedirectUrls) {
    $allowedUrls = $authConfig.properties.allowedExternalRedirectUrls
}

Write-Info "Current allowed external redirect URLs:"
foreach ($url in $allowedUrls) {
    Write-Info "  - $url"
}

if ($allowedUrls -contains $WEB_APP_URL) {
    Write-Success "Web App URL is already in allowed external redirect URLs"
} else {
    Write-Warning "Web App URL is NOT in allowed external redirect URLs"
    Write-Info "Adding Web App URL to allowed external redirect URLs..."
    
    # Add Web App URL to the list
    $newAllowedUrls = @($allowedUrls)
    if ($newAllowedUrls -notcontains $WEB_APP_URL) {
        $newAllowedUrls += $WEB_APP_URL
    }
    
    # Update Easy Auth configuration
    $urlsString = $newAllowedUrls -join " "
    az webapp auth update `
        --name $FUNCTION_APP_NAME `
        --resource-group $RESOURCE_GROUP `
        --allowed-external-redirect-urls $urlsString `
        --output none 2>&1 | Out-Null
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Updated allowed external redirect URLs"
        Write-Info "Restarting Function App to apply changes..."
        az functionapp restart --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP --output none 2>&1 | Out-Null
        Write-Success "Function App restarted"
    } else {
        Write-Error "Failed to update allowed external redirect URLs"
        exit 1
    }
}

Write-Success "Easy Auth redirect configuration verified!"
Write-Info ""
Write-Info "After login, users should be redirected to: $WEB_APP_URL"
Write-Info ""
Write-Info "IMPORTANT: If redirect still doesn't work, you may need to:"
Write-Info "1. Go to Azure Portal -> Function App -> Authentication"
Write-Info "2. Click 'Edit' on the Microsoft provider"
Write-Info "3. Under 'Allowed external redirect URLs', ensure $WEB_APP_URL is listed"
Write-Info "4. Save and restart the Function App"
Write-Info ""
Write-Info "Alternative: Enable Easy Auth on the Web App instead of Function App"
Write-Info "This would be simpler as users authenticate where they browse"

