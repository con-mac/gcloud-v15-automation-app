# Check Kudu Files Script
# Verifies that function_app folder exists in deployed files

$ErrorActionPreference = "Stop"

function Write-Info { param([string]$msg) Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Success { param([string]$msg) Write-Host "[SUCCESS] $msg" -ForegroundColor Green }
function Write-Warning { param([string]$msg) Write-Host "[WARNING] $msg" -ForegroundColor Yellow }
function Write-Error { param([string]$msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }

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

if ([string]::IsNullOrWhiteSpace($FUNCTION_APP_NAME)) {
    Write-Error "Missing FUNCTION_APP_NAME in config"
    exit 1
}

Write-Info "Checking deployed files in Function App: $FUNCTION_APP_NAME"
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
    Write-Info "Alternative: Use Kudu REST API directly"
    Write-Info "1. Go to: https://$FUNCTION_APP_NAME.scm.azurewebsites.net"
    Write-Info "2. Click 'REST API' link"
    Write-Info "3. Navigate to: /api/vfs/site/wwwroot/"
    Write-Info "4. Look for 'function_app' in the JSON response"
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
    Write-Success "Found $($response.Count) items in wwwroot"
    Write-Info ""
    
    # Check for function_app folder
    $functionAppFolder = $response | Where-Object { $_.name -eq "function_app" -and $_.mime -eq "inode/directory" }
    
    if ($functionAppFolder) {
        Write-Success "✓ function_app folder EXISTS!"
        Write-Info ""
        Write-Info "Checking function_app contents..."
        
        $functionAppContents = Invoke-RestMethod -Uri "$kuduUrl/api/vfs/site/wwwroot/function_app/" -Headers $headers -Method GET
        Write-Info "Found $($functionAppContents.Count) items in function_app:"
        foreach ($item in $functionAppContents) {
            Write-Info "  - $($item.name) ($($item.mime))"
        }
        
        $hasInit = $functionAppContents | Where-Object { $_.name -eq "__init__.py" }
        $hasFunctionJson = $functionAppContents | Where-Object { $_.name -eq "function.json" }
        
        if ($hasInit) {
            Write-Success "  ✓ __init__.py exists"
        } else {
            Write-Error "  ✗ __init__.py MISSING!"
        }
        
        if ($hasFunctionJson) {
            Write-Success "  ✓ function.json exists"
        } else {
            Write-Error "  ✗ function.json MISSING!"
        }
        
        Write-Info ""
        if ($hasInit -and $hasFunctionJson) {
            Write-Warning "Files exist but function not registered. Possible causes:"
            Write-Info "1. Function discovery hasn't completed (wait 2-3 minutes)"
            Write-Info "2. function.json has syntax errors"
            Write-Info "3. __init__.py has import errors"
            Write-Info ""
            Write-Info "Check Function App logs in Azure Portal for errors"
        }
    } else {
        Write-Error "✗ function_app folder NOT FOUND!"
        Write-Info ""
        Write-Info "This means the deployment zip didn't include the function_app folder."
        Write-Info "The zip creation fix may not have been applied."
        Write-Info ""
        Write-Info "Root directory contents:"
        foreach ($item in $response | Select-Object -First 20) {
            Write-Info "  - $($item.name)"
        }
        Write-Info ""
        Write-Error "ACTION REQUIRED: Redeploy using the fixed script"
    }
} catch {
    Write-Error "Failed to check files via Kudu API: $($_.Exception.Message)"
    Write-Info ""
    Write-Info "MANUAL CHECK via REST API:"
    Write-Info "1. Go to: https://$FUNCTION_APP_NAME.scm.azurewebsites.net"
    Write-Info "2. Click 'REST API' link"
    Write-Info "3. Navigate to: /api/vfs/site/wwwroot/"
    Write-Info "4. Look for 'function_app' in the JSON response"
    Write-Info ""
    Write-Info "Or use this direct URL (requires authentication):"
    Write-Info "https://$FUNCTION_APP_NAME.scm.azurewebsites.net/api/vfs/site/wwwroot/"
}

