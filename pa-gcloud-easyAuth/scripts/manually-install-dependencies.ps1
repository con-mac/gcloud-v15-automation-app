# Manually Install Dependencies via Kudu REST API
# This is a WORKAROUND when SCM_DO_BUILD_DURING_DEPLOYMENT doesn't work

$ErrorActionPreference = "Stop"

function Write-Info { param([string]$msg) Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Success { param([string]$msg) Write-Host "[SUCCESS] $msg" -ForegroundColor Green }
function Write-Warning { param([string]$msg) Write-Host "[WARNING] $msg" -ForegroundColor Yellow }
function Write-Error { param([string]$msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }

# Load configuration
$configPath = "config\deployment-config.env"
if (-not (Test-Path $configPath)) {
    $configPath = "..\config\deployment-config.env"
    if (-not (Test-Path $configPath)) {
        Write-Error "deployment-config.env not found. Please run deploy.ps1 first."
        exit 1
    }
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

$FUNCTION_APP_NAME = $config.FUNCTION_APP_NAME
$RESOURCE_GROUP = $config.RESOURCE_GROUP

if ([string]::IsNullOrWhiteSpace($FUNCTION_APP_NAME)) {
    Write-Error "Missing FUNCTION_APP_NAME in config"
    exit 1
}

Write-Info "Manually installing Python dependencies for: $FUNCTION_APP_NAME"
Write-Info ""
Write-Warning "This script will install dependencies via Kudu REST API"
Write-Info "This is a workaround when automatic installation fails."
Write-Info ""

# Get publishing credentials
Write-Info "Getting publishing credentials..."
$username = "`$$FUNCTION_APP_NAME"
$ErrorActionPreference = 'SilentlyContinue'
$password = (az webapp deployment list-publishing-profiles `
    --name $FUNCTION_APP_NAME `
    --resource-group $RESOURCE_GROUP `
    --query "[?publishMethod=='MSDeploy'].userPWD" -o tsv 2>&1)
$ErrorActionPreference = 'Stop'

if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($password)) {
    Write-Error "Failed to get publishing credentials"
    Write-Info ""
    Write-Info "Alternative: Install dependencies manually via Azure Portal:"
    Write-Info "1. Go to: https://$FUNCTION_APP_NAME.scm.azurewebsites.net"
    Write-Info "2. Click 'SSH' or 'Debug Console'"
    Write-Info "3. Run: cd /home/site/wwwroot && pip install -r requirements.txt --target .python_packages/lib/site-packages"
    exit 1
}

# Setup Kudu API authentication
$kuduUrl = "https://$FUNCTION_APP_NAME.scm.azurewebsites.net"
$base64Auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${username}:${password}"))
$headers = @{
    Authorization = "Basic $base64Auth"
    "Content-Type" = "application/json"
}

# Check if requirements.txt exists, upload if missing
Write-Info "Checking if requirements.txt exists..."
$requirementsExists = $false
try {
    $requirementsCheck = Invoke-RestMethod -Uri "$kuduUrl/api/vfs/site/wwwroot/requirements.txt" -Headers $headers -Method GET -ErrorAction SilentlyContinue
    if ($requirementsCheck) {
        Write-Success "✓ requirements.txt found in deployment"
        $requirementsExists = $true
    }
} catch {
    Write-Warning "requirements.txt not found in deployment"
    Write-Info "Attempting to upload requirements.txt from local source..."
    
    # Try to find requirements.txt locally
    $localRequirements = $null
    $possiblePaths = @(
        "backend\requirements.txt",
        "..\backend\requirements.txt",
        "..\..\backend\requirements.txt",
        "pa-deployment\backend\requirements.txt"
    )
    
    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            $localRequirements = $path
            Write-Info "Found requirements.txt at: $path"
            break
        }
    }
    
    if ($null -eq $localRequirements) {
        Write-Error "Could not find requirements.txt locally!"
        Write-Info "Please ensure requirements.txt exists in backend directory or redeploy."
        exit 1
    }
    
    # Read and upload requirements.txt
    Write-Info "Uploading requirements.txt to Function App..."
    $requirementsContent = Get-Content $localRequirements -Raw -Encoding UTF8
    
    try {
        $uploadBody = $requirementsContent
        $uploadHeaders = @{
            Authorization = "Basic $base64Auth"
            "Content-Type" = "text/plain"
        }
        
        Invoke-RestMethod -Uri "$kuduUrl/api/vfs/site/wwwroot/requirements.txt" `
            -Headers $uploadHeaders `
            -Method PUT `
            -Body $uploadBody `
            -ErrorAction Stop
        
        Write-Success "✓ requirements.txt uploaded successfully"
        $requirementsExists = $true
    } catch {
        Write-Error "Failed to upload requirements.txt: $($_.Exception.Message)"
        Write-Info "Please upload manually via Azure Portal or redeploy."
        exit 1
    }
}

# Execute pip install command via Kudu API
Write-Info ""
Write-Info "Installing dependencies via pip..."
Write-Info "This may take 5-10 minutes..."
Write-Info ""

$installCommand = "cd /home/site/wwwroot && pip install -r requirements.txt --target .python_packages/lib/site-packages --upgrade"
$body = @{
    command = $installCommand
    dir = "/home/site/wwwroot"
} | ConvertTo-Json

try {
    $response = Invoke-RestMethod -Uri "$kuduUrl/api/command" -Headers $headers -Method POST -Body $body -ContentType "application/json"
    
    Write-Info "Command output:"
    Write-Info $response.Output
    
    if ($response.ExitCode -eq 0) {
        Write-Success "✓ Dependencies installed successfully!"
        Write-Info ""
        Write-Info "Restarting Function App..."
        az functionapp restart --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP --output none
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Function App restarted"
            Write-Info ""
            Write-Info "Wait 30 seconds, then test your API endpoints."
        }
    } else {
        Write-Warning "Installation completed with exit code: $($response.ExitCode)"
        Write-Info "Output: $($response.Output)"
        Write-Info ""
        Write-Info "Some packages may have failed, but core packages should be installed."
        Write-Info "Restarting Function App anyway..."
        az functionapp restart --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP --output none
    }
} catch {
    Write-Error "Failed to execute pip install: $($_.Exception.Message)"
    Write-Info ""
    Write-Info "Manual installation via Azure Portal:"
    Write-Info "1. Go to: https://$FUNCTION_APP_NAME.scm.azurewebsites.net"
    Write-Info "2. Click 'SSH'"
    Write-Info "3. Run: cd /home/site/wwwroot"
    Write-Info "4. Run: pip install -r requirements.txt --target .python_packages/lib/site-packages"
    exit 1
}

Write-Info ""
Write-Success "Dependency installation process complete!"

