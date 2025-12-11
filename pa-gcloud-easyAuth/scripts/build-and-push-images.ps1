# Build and Push Docker Images Script (PowerShell)
# Builds frontend Docker image and pushes to Azure Container Registry
# This script should be run once before deployment, or when images need updating

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

$ACR_NAME = $config.ACR_NAME
$IMAGE_TAG = $config.IMAGE_TAG
$RESOURCE_GROUP = $config.RESOURCE_GROUP
$APP_REGISTRATION_NAME = $config.APP_REGISTRATION_NAME
$WEB_APP_NAME = $config.WEB_APP_NAME

function Write-Info { param([string]$msg) Write-Host "[INFO] $msg" -ForegroundColor Blue }
function Write-Success { param([string]$msg) Write-Host "[SUCCESS] $msg" -ForegroundColor Green }
function Write-Warning { param([string]$msg) Write-Host "[WARNING] $msg" -ForegroundColor Yellow }
function Write-Error { param([string]$msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }

Write-Info "Building and pushing Docker images to Azure Container Registry..."

# Note: Docker is only required for local builds (Option 2)
# ACR build (Option 1) builds in Azure cloud - no local Docker needed

# Validate configuration
if ([string]::IsNullOrWhiteSpace($ACR_NAME)) {
    Write-Error "ACR_NAME is missing in config file!"
    Write-Info "Please run deploy.ps1 and configure Container Registry"
    exit 1
}

if ([string]::IsNullOrWhiteSpace($IMAGE_TAG)) {
    $IMAGE_TAG = "latest"
    Write-Warning "IMAGE_TAG not specified, using 'latest'"
}

if ([string]::IsNullOrWhiteSpace($RESOURCE_GROUP)) {
    Write-Error "RESOURCE_GROUP is missing in config file!"
    exit 1
}

# Check if Docker is available (only needed for local builds, not ACR builds)
# ACR build option doesn't require Docker
$dockerCheck = Get-Command docker -ErrorAction SilentlyContinue
if ($dockerCheck) {
    $dockerVersion = docker --version 2>&1
    Write-Success "Docker found: $dockerVersion (optional - only needed for local builds)"
} else {
    Write-Info "Docker not found locally - this is fine! Use ACR build (Option 1) which builds in Azure cloud."
}

# Verify ACR exists
Write-Info "Verifying Azure Container Registry: $ACR_NAME..."
$ErrorActionPreference = 'SilentlyContinue'
$acrExists = az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" --query "name" -o tsv 2>&1
$ErrorActionPreference = 'Stop'

if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($acrExists)) {
    Write-Error "Azure Container Registry '$ACR_NAME' not found in resource group '$RESOURCE_GROUP'"
    Write-Info "Please run deploy.ps1 first to create the ACR"
    exit 1
}

Write-Success "ACR verified: $ACR_NAME"

# Check if frontend directory exists
# For Easy Auth version, use pa-gcloud-easyAuth/frontend (not root frontend)
$frontendPath = $null
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$possiblePaths = @(
    "$scriptDir\..\frontend",            # From pa-gcloud-easyAuth/scripts -> pa-gcloud-easyAuth/frontend (PREFERRED for Easy Auth)
    "$scriptDir\..\..\frontend",        # From pa-gcloud-easyAuth/scripts -> root/frontend (fallback)
    "..\frontend",                       # Relative from current directory (if in scripts)
    "frontend"                           # If frontend is in current directory
)

foreach ($path in $possiblePaths) {
    try {
        $resolvedPath = Resolve-Path $path -ErrorAction Stop
        if ($resolvedPath -and (Test-Path $resolvedPath)) {
            $frontendPath = $resolvedPath.Path
            Write-Info "Found frontend directory: $frontendPath"
            break
        }
    } catch {
        # Path doesn't exist, try next
        continue
    }
}

if ($null -eq $frontendPath) {
    Write-Error "Frontend directory not found!"
    Write-Info ""
    Write-Info "Searched in the following locations:"
    foreach ($path in $possiblePaths) {
        Write-Info "  - $path"
    }
    Write-Info ""
    Write-Info "Please ensure:"
    Write-Info "  1. Frontend directory exists (either in root or pa-deployment)"
    Write-Info "  2. You're running from the repository root or pa-deployment directory"
    Write-Info ""
    Write-Info "Current directory: $(Get-Location)"
    Write-Info "Script location: $scriptDir"
    exit 1
}

Write-Info "Frontend directory found: $frontendPath"

# Check if Dockerfile exists (use absolute path)
$dockerfilePath = Join-Path $frontendPath "Dockerfile"
if (-not (Test-Path $dockerfilePath)) {
    Write-Warning "Dockerfile not found in frontend directory. Attempting to restore from git..."
    
    # Try to restore from git
    $ErrorActionPreference = 'SilentlyContinue'
    $gitContent = git show HEAD:frontend/Dockerfile 2>&1
    $ErrorActionPreference = 'Stop'
    
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($gitContent)) {
        Write-Info "Found Dockerfile in git, creating it..."
        $gitContent | Out-File -FilePath $dockerfilePath -Encoding utf8 -NoNewline
        Write-Success "Dockerfile restored from git: $dockerfilePath"
    } else {
        # If git restore fails, create a default Dockerfile
        Write-Warning "Could not restore from git. Creating default Dockerfile..."
        $defaultDockerfile = @"
# Multi-stage build for React application

# Stage 1: Build
FROM node:20-alpine AS builder

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm install

# Copy source code
COPY . .

# Build the application
RUN npm run build

# Stage 2: Production
FROM nginx:alpine

# Copy custom nginx config
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copy built assets from builder
COPY --from=builder /app/dist /usr/share/nginx/html

# Expose port
EXPOSE 80

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD wget --quiet --tries=1 --spider http://localhost/ || exit 1

# Start nginx
CMD ["nginx", "-g", "daemon off;"]
"@
        $defaultDockerfile | Out-File -FilePath $dockerfilePath -Encoding utf8
        Write-Success "Default Dockerfile created: $dockerfilePath"
    }
}

# Verify Dockerfile exists now
if (-not (Test-Path $dockerfilePath)) {
    Write-Error "Failed to create Dockerfile at: $dockerfilePath"
    Write-Info "Frontend directory contents:"
    Get-ChildItem $frontendPath -Name | Select-Object -First 10 | ForEach-Object { Write-Info "  - $_" }
    exit 1
}

Write-Success "Dockerfile verified: $dockerfilePath"

# Check and create nginx.conf if missing (required by Dockerfile)
$nginxConfPath = Join-Path $frontendPath "nginx.conf"
if (-not (Test-Path $nginxConfPath)) {
    Write-Warning "nginx.conf not found. Attempting to restore from git or create default..."
    
    # Try to restore from git
    $ErrorActionPreference = 'SilentlyContinue'
    $nginxContent = git show HEAD:frontend/nginx.conf 2>&1
    $ErrorActionPreference = 'Stop'
    
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($nginxContent)) {
        Write-Info "Found nginx.conf in git, creating it..."
        $nginxContent | Out-File -FilePath $nginxConfPath -Encoding utf8 -NoNewline
        Write-Success "nginx.conf restored from git: $nginxConfPath"
    } else {
        # Create default nginx.conf
        Write-Warning "Could not restore from git. Creating default nginx.conf..."
        $defaultNginx = @"
server {
    listen 80;
    server_name _;
    root /usr/share/nginx/html;
    index index.html;

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/x-javascript application/xml+rss application/javascript application/json;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Cache static assets
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    # Handle React Router
    location / {
        try_files `$uri `$uri/ /index.html;
    }

    # Health check endpoint
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
}
"@
        $defaultNginx | Out-File -FilePath $nginxConfPath -Encoding utf8
        Write-Success "Default nginx.conf created: $nginxConfPath"
    }
}

if (-not (Test-Path $nginxConfPath)) {
    Write-Error "Failed to create nginx.conf at: $nginxConfPath"
    exit 1
}
Write-Success "nginx.conf verified: $nginxConfPath"

# Login to ACR
Write-Info "Logging in to Azure Container Registry..."
az acr login --name "$ACR_NAME" | Out-Null

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to login to ACR"
    exit 1
}

Write-Success "Logged in to ACR"

# Build and push frontend image
Write-Info "Building frontend Docker image..."
Write-Info "This may take several minutes (first build is slower)..."
Write-Info ""

$acrLoginServer = "$ACR_NAME.azurecr.io"
$imageName = "frontend"
$fullImageName = "$acrLoginServer/${imageName}:$IMAGE_TAG"

# Check if called non-interactively (from deploy.ps1)
$nonInteractive = $env:DEPLOY_NON_INTERACTIVE -eq "true"

# Ask user which build method to use (unless non-interactive)
if (-not $nonInteractive) {
    Write-Host ""
    Write-Host "Build method:"
    Write-Host "  [1] ACR build (builds in Azure cloud, no local Docker needed) - Recommended for dev team"
    Write-Host "  [2] Local build and push (requires Docker Desktop) - Recommended for initial setup"
    Write-Host ""
    $buildMethod = Read-Host "Select build method (1 or 2) [1]"
    if ([string]::IsNullOrWhiteSpace($buildMethod)) {
        $buildMethod = "1"
    }
} else {
    # Non-interactive mode: always use ACR build (no Docker needed)
    $buildMethod = "1"
    Write-Info "Non-interactive mode: Using ACR build (builds in Azure cloud)"
}

if ($buildMethod -eq "2") {
    # Local build method
    Write-Info "Using local Docker build..."
    
    # Build image locally
    Write-Info "Building Docker image locally..."
    Write-Info "Dockerfile: $dockerfilePath"
    Write-Info "Build context: $frontendPath"
    docker build -t "$fullImageName" -f "$dockerfilePath" "$frontendPath"
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to build Docker image locally"
        exit 1
    }
    
    Write-Success "Image built locally: $fullImageName"
    
    # Push to ACR
    Write-Info "Pushing image to ACR..."
    docker push "$fullImageName"
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to push image to ACR"
        exit 1
    }
    
    Write-Success "Image pushed to ACR: $fullImageName"
} else {
    # ACR build method (builds in Azure)
    Write-Info "Using ACR build task (builds in Azure cloud, no local Docker needed)..."
    
    # Verify Dockerfile exists and is readable before building
    if (-not (Test-Path $dockerfilePath)) {
        Write-Error "Dockerfile not found at: $dockerfilePath"
        Write-Info "Please ensure Dockerfile exists in frontend directory"
        exit 1
    }
    
    # Verify Dockerfile is readable and has content
    $dockerfileContent = Get-Content $dockerfilePath -Raw -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($dockerfileContent)) {
        Write-Error "Dockerfile exists but is empty or unreadable: $dockerfilePath"
        exit 1
    }
    
    Write-Info "Dockerfile verified: $dockerfilePath"
    Write-Info "Dockerfile size: $((Get-Item $dockerfilePath).Length) bytes"
    Write-Info "Build context: $frontendPath"
    Write-Info "Dockerfile: Dockerfile (relative to context)"
    
    # List files in build context to verify Dockerfile is there
    Write-Info "Verifying build context contents..."
    $contextFiles = Get-ChildItem $frontendPath -File -Name | Select-Object -First 10
    Write-Info "Files in build context: $($contextFiles -join ', ')"
    
    if ($contextFiles -notcontains "Dockerfile") {
        Write-Warning "Dockerfile not found in file listing, but path exists. This may be a path issue."
        Write-Info "Attempting build anyway..."
    }
    
    # CRITICAL FIX: Change to frontend directory and use relative paths
    # This fixes Windows path issues with ACR build
    $originalLocation = Get-Location
    try {
        Write-Info "Changing to frontend directory for ACR build..."
        Set-Location $frontendPath
        
        Write-Info "Build context: . (current directory: $frontendPath)"
        Write-Info "Dockerfile: Dockerfile (relative to context)"
        
        # Get SSO configuration values for build-time injection
        Write-Info "Getting SSO configuration for build-time injection..."
        $tenantId = az account show --query tenantId -o tsv
        if ([string]::IsNullOrWhiteSpace($tenantId)) {
            Write-Error "Failed to get tenant ID"
            exit 1
        }
        
        $clientId = ""
        if (-not [string]::IsNullOrWhiteSpace($APP_REGISTRATION_NAME)) {
            $clientId = az ad app list --display-name "$APP_REGISTRATION_NAME" --query "[0].appId" -o tsv 2>&1
            if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($clientId)) {
                Write-Warning "Could not get client ID from App Registration '$APP_REGISTRATION_NAME'"
                Write-Info "SSO may not work - you'll need to configure it manually"
            }
        }
        
        # Auto-detect Web App name if configured one doesn't exist
        if (-not [string]::IsNullOrWhiteSpace($WEB_APP_NAME)) {
            $ErrorActionPreference = 'SilentlyContinue'
            $webAppCheck = az webapp show --name "$WEB_APP_NAME" --resource-group "$RESOURCE_GROUP" --query name -o tsv 2>&1
            $ErrorActionPreference = 'Stop'
            if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($webAppCheck)) {
                Write-Warning "Web App '$WEB_APP_NAME' not found. Auto-detecting from resource group..."
                $ErrorActionPreference = 'SilentlyContinue'
                # List all web apps, exclude Function Apps
                $allWebApps = az webapp list --resource-group "$RESOURCE_GROUP" --query "[?kind!='functionapp'].name" -o tsv 2>&1
                $ErrorActionPreference = 'Stop'
                if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($allWebApps)) {
                    $detectedWebApp = ($allWebApps -split "`n" | Where-Object { $_ -match "web" } | Select-Object -First 1).Trim()
                    if ($detectedWebApp) {
                        $WEB_APP_NAME = $detectedWebApp
                        Write-Success "✓ Auto-detected Web App: $WEB_APP_NAME"
                    }
                }
            }
        }
        
        $redirectUri = "https://${WEB_APP_NAME}.azurewebsites.net"
        $adminGroupId = $config.ADMIN_GROUP_ID
        
        # Get Function App URL for API configuration
        $FUNCTION_APP_NAME = $config.FUNCTION_APP_NAME
        if ([string]::IsNullOrWhiteSpace($FUNCTION_APP_NAME)) {
            Write-Error "FUNCTION_APP_NAME not found in config"
            exit 1
        }
        $apiBaseUrl = "https://${FUNCTION_APP_NAME}.azurewebsites.net"
        
        Write-Info "SSO Configuration:"
        Write-Info "  Tenant ID: $($tenantId.Substring(0,8))..."
        if (-not [string]::IsNullOrWhiteSpace($clientId)) {
            Write-Info "  Client ID: $($clientId.Substring(0,8))..."
        } else {
            Write-Warning "  Client ID: Not found (SSO may not work until App Registration is configured)"
        }
        Write-Info "  Redirect URI: $redirectUri"
        Write-Info "  API Base URL: $apiBaseUrl"
        if ($adminGroupId) {
            Write-Info "  Admin Group ID: $($adminGroupId.Substring(0,8))..."
        }
        
        # Build build args array
        $buildArgs = @(
            "--build-arg", "VITE_AZURE_AD_TENANT_ID=$tenantId",
            "--build-arg", "VITE_AZURE_AD_CLIENT_ID=$clientId",
            "--build-arg", "VITE_AZURE_AD_REDIRECT_URI=$redirectUri",
            "--build-arg", "VITE_API_BASE_URL=$apiBaseUrl"
        )
        
        if (-not [string]::IsNullOrWhiteSpace($adminGroupId)) {
            $buildArgs += "--build-arg", "VITE_AZURE_AD_ADMIN_GROUP_ID=$adminGroupId"
        }
        
        Write-Info "Starting ACR build with SSO configuration (this may take 5-10 minutes)..."
        Write-Info "Note: ACR will upload the build context and build in Azure cloud"
        
        # Use "." as build context (current directory) and "Dockerfile" as relative path
        # Pass build args for SSO configuration
        az acr build `
            --registry "$ACR_NAME" `
            --image "${imageName}:$IMAGE_TAG" `
            --file "Dockerfile" `
            $buildArgs `
            "." `
            --timeout 1800 `
            --output table
        
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to build frontend image in ACR"
            Write-Info "Check the error above for details"
            exit 1
        }
        
        Write-Success "Frontend image built and pushed successfully: ${imageName}:$IMAGE_TAG"
    } finally {
        # Always return to original directory
        Set-Location $originalLocation
    }
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to build frontend image in ACR"
        Write-Info "Check the error above for details"
        Write-Info "Build context was: $absoluteFrontendPath"
        exit 1
    }
    
    Write-Success "Frontend image built successfully in ACR: $fullImageName"
}

# Verify image was pushed
Write-Info "Verifying image in ACR..."
$ErrorActionPreference = 'SilentlyContinue'
$imageTags = az acr repository show-tags --name "$ACR_NAME" --repository "$imageName" --query "[?name=='$IMAGE_TAG'].name" -o tsv 2>&1
$ErrorActionPreference = 'Stop'

if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($imageTags)) {
    Write-Success "Image verified in ACR: ${imageName}:$IMAGE_TAG"
} else {
    Write-Warning "Could not verify image tag, but build completed"
}

Write-Success "Build and push complete!"
Write-Info ""
Write-Info "Image details:"
Write-Info "  Registry: $acrLoginServer"
Write-Info "  Image: ${imageName}:$IMAGE_TAG"
Write-Info "  Full name: $fullImageName"
Write-Info ""
Write-Info "Next steps:"
Write-Info "  1. Run deployment: .\deploy.ps1"
Write-Info "  2. Or deploy frontend only: .\scripts\deploy-frontend.ps1"
Write-Info ""
Write-Info "To view images in ACR:"
Write-Info "  az acr repository show-tags --name $ACR_NAME --repository $imageName --output table"

