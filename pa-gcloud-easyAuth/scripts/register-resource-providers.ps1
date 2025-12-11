# Register Azure Resource Providers
# Ensures all required resource providers are registered before deployment

$ErrorActionPreference = "Stop"

function Write-Info { param([string]$msg) Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Success { param([string]$msg) Write-Host "[SUCCESS] $msg" -ForegroundColor Green }
function Write-Warning { param([string]$msg) Write-Host "[WARNING] $msg" -ForegroundColor Yellow }

# Required resource providers
$requiredProviders = @(
    "Microsoft.KeyVault",
    "Microsoft.Web",
    "Microsoft.Storage",
    "Microsoft.ContainerRegistry",
    "Microsoft.Insights",
    "Microsoft.Network"
)

Write-Info "Registering required Azure resource providers..."
Write-Info "This may take 2-5 minutes (registration happens in background)..."
Write-Info ""

$registered = 0
$alreadyRegistered = 0
$failed = 0

foreach ($provider in $requiredProviders) {
    Write-Info "Checking provider: $provider"
    
    # Check if already registered
    $status = az provider show --namespace $provider --query "registrationState" -o tsv 2>&1
    
    if ($status -eq "Registered") {
        Write-Success "  ✓ $provider is already registered"
        $alreadyRegistered++
    } else {
        Write-Info "  Registering $provider..."
        $ErrorActionPreference = 'SilentlyContinue'
        $result = az provider register --namespace $provider 2>&1
        $ErrorActionPreference = 'Stop'
        
        if ($LASTEXITCODE -eq 0) {
            Write-Success "  ✓ $provider registration initiated"
            $registered++
        } else {
            Write-Warning "  Failed to register $provider : $result"
            $failed++
        }
    }
}

Write-Info ""
Write-Info "Registration Summary:"
Write-Host "  Already registered: $alreadyRegistered" -ForegroundColor Green
Write-Host "  Newly registered: $registered" -ForegroundColor Cyan
if ($failed -gt 0) {
    Write-Host "  Failed: $failed" -ForegroundColor Yellow
}

Write-Info ""
Write-Info "Waiting for registrations to complete (this may take 2-5 minutes)..."
Write-Info "Checking registration status..."

$maxWait = 300 # 5 minutes
$waitInterval = 10 # Check every 10 seconds
$elapsed = 0

foreach ($provider in $requiredProviders) {
    $status = az provider show --namespace $provider --query "registrationState" -o tsv 2>&1
    
    if ($status -ne "Registered") {
        Write-Info "Waiting for $provider to register..."
        $waited = 0
        while ($status -ne "Registered" -and $waited -lt $maxWait) {
            Start-Sleep -Seconds $waitInterval
            $waited += $waitInterval
            $status = az provider show --namespace $provider --query "registrationState" -o tsv 2>&1
            
            if ($waited % 30 -eq 0) {
                Write-Info "  Still waiting... ($waited seconds elapsed)"
            }
        }
        
        if ($status -eq "Registered") {
            Write-Success "  ✓ $provider is now registered"
        } else {
            Write-Warning "  ⚠ $provider registration still pending (may complete in background)"
        }
    }
}

Write-Info ""
Write-Success "Resource provider registration complete!"
Write-Info "You can now proceed with deployment."

