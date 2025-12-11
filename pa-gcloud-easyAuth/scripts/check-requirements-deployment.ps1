# Check Requirements.txt Deployment Script
# Verifies that requirements.txt exists in deployed files and dependencies are installed

$ErrorActionPreference = "Stop"

function Write-Info { param([string]$msg) Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Success { param([string]$msg) Write-Host "[SUCCESS] $msg" -ForegroundColor Green }
function Write-Warning { param([string]$msg) Write-Host "[WARNING] $msg" -ForegroundColor Yellow }
function Write-Error { param([string]$msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }

# Load configuration
$configPath = "config\deployment-config.env"
if (-not (Test-Path $configPath)) {
    # Try from pa-deployment directory
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

Write-Info "Checking requirements.txt deployment in Function App: $FUNCTION_APP_NAME"
Write-Info ""

# Get publishing credentials for Kudu API
Write-Info "Getting publishing credentials..."
$ErrorActionPreference = 'SilentlyContinue'
$username = "`$$FUNCTION_APP_NAME"
$password = (az webapp deployment list-publishing-profiles `
    --name $FUNCTION_APP_NAME `
    --resource-group $RESOURCE_GROUP `
    --query "[?publishMethod=='MSDeploy'].userPWD" -o tsv 2>&1)
$ErrorActionPreference = 'Stop'

if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($password)) {
    Write-Error "Failed to get publishing credentials"
    Write-Info ""
    Write-Info "MANUAL CHECK via Kudu:"
    Write-Info "1. Go to: https://$FUNCTION_APP_NAME.scm.azurewebsites.net"
    Write-Info "2. Navigate to: Debug Console > CMD"
    Write-Info "3. Check: site/wwwroot/requirements.txt"
    Write-Info "4. Check: site/wwwroot/.python_packages/lib/site-packages/"
    exit 1
}

# Use Kudu REST API to list files
$kuduUrl = "https://$FUNCTION_APP_NAME.scm.azurewebsites.net"
$base64Auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${username}:${password}"))
$headers = @{
    Authorization = "Basic $base64Auth"
}

Write-Info "Checking site/wwwroot directory..."
try {
    $response = Invoke-RestMethod -Uri "$kuduUrl/api/vfs/site/wwwroot/" -Headers $headers -Method GET
    Write-Info "Found $($response.Count) items in wwwroot"
    Write-Info ""
    
    # Check for requirements.txt
    $requirementsTxt = $response | Where-Object { $_.name -eq "requirements.txt" -and $_.mime -eq "text/plain" }
    
    if ($requirementsTxt) {
        Write-Success "✓ requirements.txt EXISTS at root!"
        Write-Info ""
        
        # Read requirements.txt content
        Write-Info "Reading requirements.txt content..."
        try {
            $requirementsContent = Invoke-RestMethod -Uri "$kuduUrl/api/vfs/site/wwwroot/requirements.txt" -Headers $headers -Method GET
            $requirementsText = $requirementsContent | Out-String
            Write-Info "First 500 characters of requirements.txt:"
            Write-Info $requirementsText.Substring(0, [Math]::Min(500, $requirementsText.Length))
            Write-Info ""
            
            # Check for fastapi
            if ($requirementsText -match "fastapi") {
                Write-Success "✓ requirements.txt contains 'fastapi'"
            } else {
                Write-Error "✗ requirements.txt does NOT contain 'fastapi'!"
            }
        } catch {
            Write-Warning "Could not read requirements.txt content: $($_.Exception.Message)"
        }
    } else {
        Write-Error "✗ requirements.txt NOT FOUND at root!"
        Write-Info ""
        Write-Info "Root directory contents:"
        foreach ($item in $response | Select-Object -First 20) {
            Write-Info "  - $($item.name) ($($item.mime))"
        }
        Write-Info ""
        Write-Error "ACTION REQUIRED: requirements.txt must be at zip root for Azure Functions to install dependencies"
    }
    
    Write-Info ""
    Write-Info "Checking for installed Python packages..."
    
    # Check for .python_packages directory
    $pythonPackages = $response | Where-Object { $_.name -eq ".python_packages" -and $_.mime -eq "inode/directory" }
    
    if ($pythonPackages) {
        Write-Success "✓ .python_packages directory EXISTS!"
        Write-Info ""
        Write-Info "Checking .python_packages/lib/site-packages/..."
        try {
            $sitePackages = Invoke-RestMethod -Uri "$kuduUrl/api/vfs/site/wwwroot/.python_packages/lib/site-packages/" -Headers $headers -Method GET
            Write-Info "Found $($sitePackages.Count) installed packages"
            
            # Check for fastapi
            $fastapiPackage = $sitePackages | Where-Object { $_.name -like "fastapi*" }
            if ($fastapiPackage) {
                Write-Success "✓ fastapi package is INSTALLED!"
            } else {
                Write-Error "✗ fastapi package NOT FOUND in installed packages!"
                Write-Info ""
                Write-Info "This means Azure Functions did not install dependencies from requirements.txt"
                Write-Info ""
                Write-Info "Possible causes:"
                Write-Info "1. requirements.txt was not at zip root during deployment"
                Write-Info "2. Azure Functions dependency installation failed silently"
                Write-Info "3. Function App needs to be restarted to trigger dependency installation"
                Write-Info ""
                Write-Info "First 10 installed packages:"
                foreach ($pkg in $sitePackages | Select-Object -First 10) {
                    Write-Info "  - $($pkg.name)"
                }
            }
        } catch {
            Write-Warning "Could not check site-packages: $($_.Exception.Message)"
        }
    } else {
        Write-Error "✗ .python_packages directory NOT FOUND!"
        Write-Info ""
        Write-Info "This means Azure Functions has NOT installed any Python packages."
        Write-Info "This happens when requirements.txt is missing or not at zip root."
        Write-Info ""
        Write-Error "ACTION REQUIRED: Redeploy with requirements.txt at zip root"
    }
    
} catch {
    Write-Error "Failed to check files via Kudu API: $($_.Exception.Message)"
    Write-Info ""
    Write-Info "MANUAL CHECK via Kudu:"
    Write-Info "1. Go to: https://$FUNCTION_APP_NAME.scm.azurewebsites.net"
    Write-Info "2. Navigate to: Debug Console > CMD"
    Write-Info "3. Check: site/wwwroot/requirements.txt"
    Write-Info "4. Check: site/wwwroot/.python_packages/lib/site-packages/"
}

