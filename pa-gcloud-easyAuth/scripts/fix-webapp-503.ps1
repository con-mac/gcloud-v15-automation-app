# Fix Web App 503 Error - Container Troubleshooting

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

$WEB_APP_NAME = $config.WEB_APP_NAME
$RESOURCE_GROUP = $config.RESOURCE_GROUP
$ACR_NAME = $config.ACR_NAME

if ([string]::IsNullOrWhiteSpace($WEB_APP_NAME)) {
    Write-Error "Missing WEB_APP_NAME in config"
    exit 1
}
if ([string]::IsNullOrWhiteSpace($RESOURCE_GROUP)) {
    Write-Error "Missing RESOURCE_GROUP in config"
    exit 1
}

Write-Info "Fixing Web App 503 Error: $WEB_APP_NAME"
Write-Info ""

# Step 1: Restart Web App
Write-Info "1. Restarting Web App..."
az webapp restart --name "$WEB_APP_NAME" --resource-group "$RESOURCE_GROUP" 2>&1 | Out-Null
Write-Success "Web App restarted"
Start-Sleep -Seconds 10

# Step 2: Check if Docker image exists in ACR
if (-not [string]::IsNullOrWhiteSpace($ACR_NAME)) {
    Write-Info ""
    Write-Info "2. Checking if Docker image exists in ACR..."
    $ErrorActionPreference = 'SilentlyContinue'
    $images = az acr repository list --name "$ACR_NAME" -o tsv 2>&1
    $ErrorActionPreference = 'Stop'
    
    if ($LASTEXITCODE -eq 0 -and $images -like "*frontend*") {
        Write-Success "Frontend image found in ACR"
        
        # Check tags
        $ErrorActionPreference = 'SilentlyContinue'
        $tags = az acr repository show-tags --name "$ACR_NAME" --repository frontend -o tsv 2>&1
        $ErrorActionPreference = 'Stop'
        
        if ($LASTEXITCODE -eq 0 -and $tags) {
            Write-Info "   Available tags: $tags"
            if ($tags -notlike "*latest*") {
                Write-Warning "   ⚠ 'latest' tag not found. Image may need to be rebuilt."
            }
        }
    } else {
        Write-Warning "   ⚠ Frontend image not found in ACR"
        Write-Info "   Run: .\pa-deployment\scripts\build-and-push-images.ps1"
    }
}

# Step 3: Verify Docker container settings
Write-Info ""
Write-Info "3. Verifying Docker container settings..."
$ErrorActionPreference = 'SilentlyContinue'
$containerConfig = az webapp config container show --name "$WEB_APP_NAME" --resource-group "$RESOURCE_GROUP" -o json 2>&1 | ConvertFrom-Json
$ErrorActionPreference = 'Stop'

if ($LASTEXITCODE -eq 0 -and $containerConfig) {
    $imageName = ($containerConfig | Where-Object { $_.name -eq "DOCKER_CUSTOM_IMAGE_NAME" }).value
    Write-Info "   Docker Image: $imageName"
    
    if ([string]::IsNullOrWhiteSpace($imageName)) {
        Write-Warning "   ⚠ Docker image not configured!"
        Write-Info "   Run: .\pa-deployment\scripts\deploy-frontend.ps1"
    }
}

# Step 4: Check app settings
Write-Info ""
Write-Info "4. Checking critical app settings..."
$ErrorActionPreference = 'SilentlyContinue'
$appSettings = az webapp config appsettings list --name "$WEB_APP_NAME" --resource-group "$RESOURCE_GROUP" -o json 2>&1 | ConvertFrom-Json
$ErrorActionPreference = 'Stop'

if ($LASTEXITCODE -eq 0 -and $appSettings) {
    $storageSetting = $appSettings | Where-Object { $_.name -eq "WEBSITES_ENABLE_APP_SERVICE_STORAGE" }
    if (-not $storageSetting -or $storageSetting.value -ne "false") {
        Write-Warning "   ⚠ WEBSITES_ENABLE_APP_SERVICE_STORAGE is not 'false'"
        Write-Info "   Setting to 'false'..."
        az webapp config appsettings set `
            --name "$WEB_APP_NAME" `
            --resource-group "$RESOURCE_GROUP" `
            --settings "WEBSITES_ENABLE_APP_SERVICE_STORAGE=false" `
            2>&1 | Out-Null
        Write-Success "   Updated"
    } else {
        Write-Success "   WEBSITES_ENABLE_APP_SERVICE_STORAGE is 'false' ✓"
    }
}

# Step 5: Check if port is set
$portSetting = $appSettings | Where-Object { $_.name -eq "PORT" }
if (-not $portSetting) {
    Write-Info "   Setting PORT to 80..."
    az webapp config appsettings set `
        --name "$WEB_APP_NAME" `
        --resource-group "$RESOURCE_GROUP" `
        --settings "PORT=80" `
        2>&1 | Out-Null
    Write-Success "   PORT set to 80"
} else {
    Write-Info "   PORT: $($portSetting.value)"
}

# Step 6: Wait and check status
Write-Info ""
Write-Info "5. Waiting 30 seconds for container to start..."
Start-Sleep -Seconds 30

$ErrorActionPreference = 'SilentlyContinue'
$webAppState = az webapp show --name "$WEB_APP_NAME" --resource-group "$RESOURCE_GROUP" --query "state" -o tsv 2>&1
$ErrorActionPreference = 'Stop'

Write-Info ""
Write-Info "=== Summary ==="
Write-Info "Web App State: $webAppState"
Write-Info ""
Write-Info "Next steps:"
Write-Info "1. Check logs in Azure Portal:"
Write-Info "   https://portal.azure.com -> Web App -> Log stream"
Write-Info ""
Write-Info "2. Or view logs via Kudu:"
Write-Info "   https://$WEB_APP_NAME.scm.azurewebsites.net/api/logs/docker"
Write-Info ""
Write-Info "3. If container is still crashing, rebuild the image:"
Write-Info "   .\pa-deployment\scripts\build-and-push-images.ps1"
Write-Info "   .\pa-deployment\scripts\deploy-frontend.ps1"
Write-Info ""
Write-Info "4. Test the Web App:"
Write-Info "   curl https://$WEB_APP_NAME.azurewebsites.net"

