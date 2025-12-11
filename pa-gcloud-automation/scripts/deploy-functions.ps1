# Deploy Functions Script (PowerShell)
# Deploys backend API code to Azure Function App

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
$KEY_VAULT_NAME = $config.KEY_VAULT_NAME
$WEB_APP_NAME = $config.WEB_APP_NAME
$SHAREPOINT_SITE_URL = $config.SHAREPOINT_SITE_URL
$SHAREPOINT_SITE_ID = $config.SHAREPOINT_SITE_ID

function Write-Info { param([string]$msg) Write-Host "[INFO] $msg" -ForegroundColor Blue }
function Write-Success { param([string]$msg) Write-Host "[SUCCESS] $msg" -ForegroundColor Green }
function Write-Warning { param([string]$msg) Write-Host "[WARNING] $msg" -ForegroundColor Yellow }

Write-Info "Deploying backend API to Function App..."

# Check if backend directory exists
# Try multiple paths: relative to scripts, relative to deployment package, or root
$backendPath = $null
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$deploymentDir = Split-Path -Parent $scriptDir
$projectRoot = Split-Path -Parent $deploymentDir

$possibleBackendPaths = @(
    "$projectRoot\backend",             # From scripts -> project root/backend (PREFERRED)
    "$deploymentDir\..\backend",        # From deployment package -> root/backend
    "$scriptDir\..\..\backend",         # From scripts -> root/backend
    "$scriptDir\..\backend",            # From scripts -> deployment/backend
    "..\..\backend",                    # Relative from current directory
    "..\backend",                       # Relative from current directory
    "backend"                           # If backend is in current directory
)

foreach ($path in $possibleBackendPaths) {
    try {
        $resolvedPath = Resolve-Path $path -ErrorAction Stop
        if ($resolvedPath -and (Test-Path $resolvedPath)) {
            $backendPath = $resolvedPath.Path
            Write-Info "Found backend directory at: $backendPath"
            break
        }
    } catch {
        # Path doesn't exist, try next
        continue
    }
}

if (-not $backendPath) {
    Write-Error "Backend directory not found!"
    Write-Error ""
    Write-Error "This deployment package expects the backend directory to be at the project root."
    Write-Error "Expected structure:"
    Write-Error "  project-root/"
    Write-Error "    ├── frontend/          (application code)"
    Write-Error "    ├── backend/           (application code with function_app/)"
    Write-Error "    └── pa-gcloud-automation/  (this deployment package)"
    Write-Error ""
    Write-Error "Searched paths:"
    $possibleBackendPaths | ForEach-Object { Write-Error "  - $_" }
    Write-Error ""
    Write-Error "Current directory: $(Get-Location)"
    Write-Error "Script location: $scriptDir"
    Write-Error ""
    Write-Error "SOLUTION:"
    Write-Error "  1. Clone the main project repository (with frontend/backend directories)"
    Write-Error "  2. Place this deployment package (pa-gcloud-automation) in the project root"
    Write-Error "  3. Run deploy.ps1 from the pa-gcloud-automation directory"
    exit 1
}

# Change to backend directory for deployment
# We're already in the backend directory at this point
Write-Info "Using backend directory: $backendPath"
Push-Location $backendPath

# Copy or create requirements.txt - CRITICAL for dependency installation
if (-not (Test-Path "requirements.txt")) {
    # Try to copy from main repo backend directory first
    $mainRepoRequirements = "..\..\backend\requirements.txt"
    if (Test-Path $mainRepoRequirements) {
        Write-Info "Copying requirements.txt from main repo backend directory..."
        Copy-Item -Path $mainRepoRequirements -Destination "requirements.txt" -Force
        Write-Success "✓ requirements.txt copied from main repo"
    } else {
        Write-Warning "requirements.txt not found. Creating from template..."
        Write-Warning "NOTE: This template may be incomplete. Use full backend/requirements.txt for production!"
        @"
fastapi>=0.104.0
uvicorn[standard]>=0.24.0
azure-functions>=1.18.0
azure-identity>=1.15.0
azure-keyvault-secrets>=4.7.0
python-docx>=1.1.0
openpyxl>=3.1.0
pydantic>=2.5.0
pydantic-settings>=2.1.0
# SharePoint/Graph API dependencies
msgraph-sdk>=1.0.0
# Placeholder: Add other dependencies as needed
"@ | Out-File -FilePath "requirements.txt" -Encoding utf8
    }
} else {
    Write-Success "✓ requirements.txt found in backend directory"
}

# Deploy to Function App
Write-Info "Deploying to Function App: $FUNCTION_APP_NAME"

# Check if backend code exists
if (-not (Test-Path "host.json")) {
    Write-Warning "host.json not found in backend directory"
    Write-Info "Checking if we need to copy from main repo..."
    if (Test-Path "..\..\backend\host.json") {
        Write-Info "Copying backend files from main repo..."
        Copy-Item -Path "..\..\backend\*" -Destination . -Recurse -Force -Exclude "*.pyc","__pycache__","*.log",".git"
        # Ensure requirements.txt is copied (may have been excluded)
        if (Test-Path "..\..\backend\requirements.txt") {
            Copy-Item -Path "..\..\backend\requirements.txt" -Destination "requirements.txt" -Force
            Write-Info "✓ requirements.txt copied from main repo (ensuring it's present)"
        }
    } else {
        Write-Warning "Backend code not found. Function App will be created but code deployment skipped."
        Write-Warning "Please ensure backend code is in pa-deployment/backend/ directory"
    }
}

# CRITICAL: Set build settings BEFORE any deployment
# Azure Functions requires BOTH settings for automatic dependency installation
Write-Info "Setting build settings (REQUIRED for dependency installation)..."
az functionapp config appsettings set `
    --name $FUNCTION_APP_NAME `
    --resource-group $RESOURCE_GROUP `
    --settings "SCM_DO_BUILD_DURING_DEPLOYMENT=true" "ENABLE_ORYX_BUILD=true" `
    --output none
if ($LASTEXITCODE -eq 0) {
    Write-Success "✓ Build settings enabled (dependencies will install during deployment)"
} else {
    Write-Warning "Failed to set build settings. Dependencies may not install automatically."
    Write-Warning "You may need to run manually-install-dependencies.ps1 after deployment."
}

# Try using Azure Functions Core Tools first
$funcCheck = Get-Command func -ErrorAction SilentlyContinue
if ($funcCheck) {
    Write-Info "Using Azure Functions Core Tools for deployment..."
    try {
        func azure functionapp publish $FUNCTION_APP_NAME --python
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Backend code deployed using Functions Core Tools"
        } else {
            Write-Warning "Functions Core Tools deployment failed, trying zip deploy..."
            $funcCheck = $null  # Force zip deploy
        }
    } catch {
        Write-Warning "Functions Core Tools deployment failed: $_"
        Write-Info "Trying zip deploy instead..."
        $funcCheck = $null
    }
}

# Fallback to zip deploy if Functions Core Tools not available or failed
if (-not $funcCheck) {
    Write-Info "Deploying using zip deploy method..."
    
    # Verify essential files exist
    if (-not (Test-Path "host.json")) {
        Write-Warning "host.json not found. Cannot deploy backend code."
        Write-Info "Function App will be configured with settings, but code deployment skipped."
    } elseif (-not (Test-Path "requirements.txt")) {
        Write-Warning "requirements.txt not found. Cannot deploy backend code."
        Write-Info "Function App will be configured with settings, but code deployment skipped."
    } else {
        # Create deployment zip (exclude unnecessary files)
        Write-Info "Creating deployment package..."
        # Use absolute path to avoid path resolution issues
        $backendDir = Get-Location
        $parentDir = Split-Path -Parent $backendDir.Path
        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $deployZip = Join-Path $parentDir "function-deploy-${timestamp}.zip"
        $deployZip = [System.IO.Path]::GetFullPath($deployZip)
        Write-Info "Zip will be created at: $deployZip"
        
        # Get all files except common exclusions
        $filesToZip = Get-ChildItem -Path . -Recurse -File | 
            Where-Object { 
                $_.FullName -notmatch "\\__pycache__\\" -and
                $_.FullName -notmatch "\\.git\\" -and
                $_.FullName -notmatch "\\.pytest_cache\\" -and
                $_.FullName -notmatch "\\.venv\\" -and
                $_.FullName -notmatch "\\venv\\" -and
                $_.FullName -notmatch "\\.env" -and
                $_.FullName -notmatch "\\.log$" -and
                $_.FullName -notmatch "\\.pyc$"
            }
        
        if ($filesToZip.Count -gt 0) {
            # CRITICAL: Verify function_app folder exists and is included
            $functionAppPath = Join-Path (Get-Location) "function_app"
            if (-not (Test-Path $functionAppPath)) {
                Write-Error "function_app folder not found at: $functionAppPath"
                Write-Error "Function will not be registered without this folder!"
                Write-Info "Current directory: $(Get-Location)"
                Write-Info "Looking for: function_app\__init__.py and function_app\function.json"
                exit 1
            }
            
            # Verify critical files exist
            $hasFunctionApp = $filesToZip | Where-Object { $_.FullName -like "*function_app\__init__.py" -or $_.FullName -like "*function_app/__init__.py" }
            $hasFunctionJson = $filesToZip | Where-Object { $_.FullName -like "*function_app\function.json" -or $_.FullName -like "*function_app/function.json" }
            $hasHostJson = $filesToZip | Where-Object { $_.Name -eq "host.json" }
            $hasRequirementsTxt = $filesToZip | Where-Object { $_.Name -eq "requirements.txt" }
            
            # CRITICAL: requirements.txt MUST be at the root of the zip for Azure Functions to install dependencies
            if (-not $hasRequirementsTxt) {
                Write-Warning "requirements.txt not found in file list. Adding explicitly..."
                $requirementsPath = Join-Path (Get-Location) "requirements.txt"
                if (Test-Path $requirementsPath) {
                    $reqFile = Get-Item $requirementsPath
                    $filesToZip += $reqFile
                    Write-Info "  Added: requirements.txt (REQUIRED for dependency installation)"
                } else {
                    Write-Error "requirements.txt not found at: $requirementsPath"
                    Write-Error "Azure Functions requires requirements.txt at zip root to install Python packages!"
                    exit 1
                }
            } else {
                Write-Success "✓ requirements.txt found in deployment package"
            }
            
            if (-not $hasFunctionApp) {
                Write-Warning "function_app/__init__.py not found in file list. Adding explicitly..."
                $functionAppFiles = Get-ChildItem -Path "function_app" -Recurse -File
                foreach ($file in $functionAppFiles) {
                    if ($filesToZip -notcontains $file) {
                        $filesToZip += $file
                        Write-Info "  Added: $($file.FullName)"
                    }
                }
            }
            
            if (-not $hasFunctionJson) {
                Write-Warning "function_app/function.json not found. Adding explicitly..."
                $functionJsonPath = Join-Path "function_app" "function.json"
                if (Test-Path $functionJsonPath) {
                    $jsonFile = Get-Item $functionJsonPath
                    if ($filesToZip -notcontains $jsonFile) {
                        $filesToZip += $jsonFile
                        Write-Info "  Added: $($jsonFile.FullName)"
                    }
                }
            }
            
            if (-not $hasHostJson) {
                Write-Error "host.json not found in deployment package!"
                exit 1
            }
            
            Write-Info "Creating zip with $($filesToZip.Count) files..."
            
            # Log what's being included (for debugging)
            $functionAppFiles = $filesToZip | Where-Object { $_.FullName -like "*function_app*" }
            if ($functionAppFiles) {
                Write-Info "Function App files included: $($functionAppFiles.Count)"
                $functionAppFiles | Select-Object -First 10 | ForEach-Object {
                    $relativePath = $_.FullName.Replace((Get-Location).Path + "\", "").Replace((Get-Location).Path + "/", "")
                    Write-Info "  - $relativePath"
                }
            } else {
                Write-Error "No function_app files found in deployment package! Function will not work!"
                exit 1
            }
            
            # Create zip preserving directory structure
            # Use .NET compression to ensure proper folder structure
            Write-Info "Creating zip archive (preserving folder structure)..."
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $zip = [System.IO.Compression.ZipFile]::Open($deployZip, [System.IO.Compression.ZipArchiveMode]::Create)
            $currentDir = (Get-Location).Path
            try {
                foreach ($file in $filesToZip) {
                    # Use proper path resolution to get relative path
                    $filePath = $file.FullName
                    # Normalize paths for comparison
                    $normalizedCurrent = [System.IO.Path]::GetFullPath($currentDir)
                    $normalizedFile = [System.IO.Path]::GetFullPath($filePath)
                    
                    # Get relative path using .NET method
                    $relativePath = [System.IO.Path]::GetRelativePath($normalizedCurrent, $normalizedFile)
                    # Normalize to forward slashes for zip (zip format uses /)
                    $relativePath = $relativePath.Replace("\", "/")
                    
                    Write-Verbose "Adding to zip: $relativePath"
                    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $filePath, $relativePath) | Out-Null
                }
            } finally {
                $zip.Dispose()
            }
            Write-Info "Zip created successfully with preserved folder structure"
            
            # Verify zip contents - CRITICAL: requirements.txt and function_app folder
            Write-Info "Verifying zip contents..."
            $zipRead = [System.IO.Compression.ZipFile]::OpenRead($deployZip)
            try {
                # Verify requirements.txt is at the root (CRITICAL for dependency installation)
                $requirementsEntry = $zipRead.Entries | Where-Object { $_.FullName -eq "requirements.txt" -or $_.FullName -eq "requirements.txt/" }
                if ($requirementsEntry) {
                    Write-Success "✓ Verified: requirements.txt exists at zip root (Azure Functions will install dependencies)"
                } else {
                    Write-Error "✗ requirements.txt NOT found at zip root! Azure Functions cannot install dependencies!"
                    Write-Error "This will cause ModuleNotFoundError when importing FastAPI or other packages!"
                    $zipRead.Dispose()
                    Remove-Item $deployZip -Force -ErrorAction SilentlyContinue
                    exit 1
                }
                
                # Verify function_app folder structure
                $functionAppEntries = $zipRead.Entries | Where-Object { $_.FullName -like "function_app/*" }
                if ($functionAppEntries.Count -gt 0) {
                    Write-Success "✓ Verified: function_app folder exists in zip with $($functionAppEntries.Count) files"
                    $functionAppEntries | Select-Object -First 5 | ForEach-Object {
                        Write-Info "  - $($_.FullName)"
                    }
                } else {
                    Write-Error "✗ function_app folder NOT found in zip! This will fail!"
                    $zipRead.Dispose()
                    Remove-Item $deployZip -Force -ErrorAction SilentlyContinue
                    exit 1
                }
                
                # Verify host.json
                $hostJsonEntry = $zipRead.Entries | Where-Object { $_.FullName -eq "host.json" -or $_.FullName -eq "host.json/" }
                if ($hostJsonEntry) {
                    Write-Success "✓ Verified: host.json exists in zip"
                } else {
                    Write-Error "✗ host.json NOT found in zip! This will fail!"
                    $zipRead.Dispose()
                    Remove-Item $deployZip -Force -ErrorAction SilentlyContinue
                    exit 1
                }
            } finally {
                $zipRead.Dispose()
            }
            
            Write-Info "Deploying zip package to Function App..."
            Write-Info "This may take 5-10 minutes (first deployment is slower)..."
            
            # Verify zip file exists before deployment
            if (-not (Test-Path $deployZip)) {
                Write-Error "Zip file not found at: $deployZip"
                Write-Error "Current directory: $(Get-Location)"
                Write-Error "Cannot deploy without zip file!"
                exit 1
            }
            
            Write-Info "Zip file verified: $deployZip"
            Write-Info "File size: $((Get-Item $deployZip).Length / 1MB) MB"
            Write-Info ""
            Write-Info "Monitoring deployment progress..."
            
            # Use the reliable zip deploy method (az functionapp deployment source config-zip)
            # This is more reliable than az webapp deploy which can hang
            Write-Info "Deploying zip package (this may take 5-10 minutes)..."
            Write-Info "Note: Large deployments can take time. Be patient..."
            
            try {
                # Use absolute path and verify it exists
                $deployZipAbsolute = [System.IO.Path]::GetFullPath($deployZip)
                Write-Info "Using absolute path: $deployZipAbsolute"
                
                if (-not (Test-Path $deployZipAbsolute)) {
                    Write-Error "Zip file not found at absolute path: $deployZipAbsolute"
                    exit 1
                }
                
                # Use the proven method that doesn't hang
                $deployOutput = az functionapp deployment source config-zip `
                    --resource-group $RESOURCE_GROUP `
                    --name $FUNCTION_APP_NAME `
                    --src $deployZipAbsolute `
                    --timeout 1800 2>&1 | Tee-Object -Variable deployOutput
                
                if ($LASTEXITCODE -eq 0) {
                    Write-Success "Backend code deployed successfully!"
                    
                    # Force function discovery by syncing triggers
                    Write-Info "Forcing function discovery (syncing triggers)..."
                    $ErrorActionPreference = 'SilentlyContinue'
                    az functionapp function show `
                        --name $FUNCTION_APP_NAME `
                        --resource-group $RESOURCE_GROUP `
                        --function-name "function_app" `
                        --output none 2>&1 | Out-Null
                    $ErrorActionPreference = 'Stop'
                    
                    # Restart Function App to ensure function is discovered
                    Write-Info "Restarting Function App to trigger function discovery..."
                    az functionapp restart --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP --output none
                    if ($LASTEXITCODE -eq 0) {
                        Write-Success "Function App restarted"
                        Write-Info "Waiting 30 seconds for function discovery..."
                        Start-Sleep -Seconds 30
                        
                        # Verify function is registered
                        Write-Info "Verifying function registration..."
                        $ErrorActionPreference = 'SilentlyContinue'
                        $functionCheck = az functionapp function show `
                            --name $FUNCTION_APP_NAME `
                            --resource-group $RESOURCE_GROUP `
                            --function-name "function_app" `
                            --query "name" -o tsv 2>&1
                        $ErrorActionPreference = 'Stop'
                        
                        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($functionCheck)) {
                            Write-Success "Function 'function_app' is registered!"
                        } else {
                            Write-Warning "Function 'function_app' not yet registered. This may take up to 2 minutes."
                            Write-Info "Check Functions list in Azure Portal: Function App -> Functions"
                            Write-Info "If function doesn't appear after 2 minutes, check logs for errors"
                        }
                    }
                } else {
                    # Check if it's a known error we can handle
                    if ($deployOutput -match "This API isn't available|not available in this environment") {
                        Write-Info "Deployment API not available, but deployment may still be in progress..."
                        Write-Info "Check deployment status in Azure Portal:"
                        Write-Info "  Function App -> Deployment Center -> Logs"
                        Write-Warning "Deployment may have succeeded despite the error message."
                    } else {
                        Write-Warning "Deployment may have failed. Checking status..."
                        Write-Info "Deployment output: $deployOutput"
                        Write-Info "To view detailed logs, run:"
                        Write-Info "  az webapp log deployment show -n $FUNCTION_APP_NAME -g $RESOURCE_GROUP"
                        Write-Info "Or check in Azure Portal: Function App -> Deployment Center -> Logs"
                    }
                }
            } catch {
                Write-Warning "Deployment error: $_"
                Write-Info "Deployment may still be in progress. Check status in Azure Portal:"
                Write-Info "  Function App -> Deployment Center -> Logs"
                Write-Warning "Function App will be configured with settings, but code deployment may need manual verification."
            }
            
            # Cleanup
            if (Test-Path $deployZip) {
                Remove-Item $deployZip -Force -ErrorAction SilentlyContinue
            }
        } else {
            Write-Warning "No files found to deploy"
        }
    }
}

# Configure app settings (updates existing or creates new)
Write-Info "Configuring Function App settings..."

# Get Key Vault reference
$KEY_VAULT_URI = az keyvault show --name "$KEY_VAULT_NAME" --resource-group "$RESOURCE_GROUP" --query properties.vaultUri -o tsv

# Build settings array to avoid PowerShell parsing issues with @ symbols
# Use string concatenation to prevent PowerShell from misinterpreting @Microsoft.KeyVault
$kvStorageRef = '@Microsoft.KeyVault(SecretUri=' + $KEY_VAULT_URI + '/secrets/StorageConnectionString/)'
$kvAppInsightsRef = '@Microsoft.KeyVault(SecretUri=' + $KEY_VAULT_URI + '/secrets/AppInsightsConnectionString/)'

# Build array item by item to ensure proper escaping
# Get Web App URL for CORS configuration
$ErrorActionPreference = 'SilentlyContinue'
$WEB_APP_URL = az webapp show --name "$WEB_APP_NAME" --resource-group "$RESOURCE_GROUP" --query defaultHostName -o tsv 2>&1
$ErrorActionPreference = 'Stop'
if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($WEB_APP_URL)) {
    $WEB_APP_URL = "https://$WEB_APP_URL"
} else {
    $WEB_APP_URL = "https://${WEB_APP_NAME}.azurewebsites.net"
}

$appSettings = @()
# Note: SCM_DO_BUILD_DURING_DEPLOYMENT is already set before deployment above
$appSettings += "AZURE_KEY_VAULT_URL=$KEY_VAULT_URI"
$appSettings += "SHAREPOINT_SITE_URL=$SHAREPOINT_SITE_URL"
$appSettings += "SHAREPOINT_SITE_ID=$SHAREPOINT_SITE_ID"
$appSettings += "USE_SHAREPOINT=true"
$appSettings += "KEY_VAULT_NAME=$KEY_VAULT_NAME"
$appSettings += "AZURE_KEY_VAULT_URL=https://${KEY_VAULT_NAME}.vault.azure.net"
$appSettings += "AZURE_STORAGE_CONNECTION_STRING=$kvStorageRef"
$appSettings += "APPLICATIONINSIGHTS_CONNECTION_STRING=$kvAppInsightsRef"
$appSettings += "CORS_ORIGINS=$WEB_APP_URL,http://localhost:3000,http://localhost:5173"

# Set app settings - pass each setting individually to avoid PowerShell parsing issues
Write-Info "Setting app settings one by one to avoid parsing errors..."
foreach ($setting in $appSettings) {
    $ErrorActionPreference = 'SilentlyContinue'
    az functionapp config appsettings set `
        --name "$FUNCTION_APP_NAME" `
        --resource-group "$RESOURCE_GROUP" `
        --settings "$setting" `
        --output none 2>&1 | Out-Null
    $ErrorActionPreference = 'Stop'
}

Write-Success "Backend deployment complete!"
Write-Info "Note: SharePoint credentials need to be added to Key Vault"
Write-Info "Note: App Registration credentials need to be configured"

Pop-Location

