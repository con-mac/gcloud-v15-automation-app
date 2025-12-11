# Wrapper script to run configure-auth.ps1 without PowerShell profile
# This bypasses any profile error handlers that might intercept JSON parse errors
# Usage: .\pa-deployment\scripts\configure-auth-no-profile.ps1

# Get the script directory (this script's location)
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$authScript = Join-Path $scriptDir "configure-auth.ps1"

# Verify the auth script exists
if (-not (Test-Path $authScript)) {
    Write-Error "configure-auth.ps1 not found at: $authScript"
    Write-Host "Current directory: $(Get-Location)" -ForegroundColor Yellow
    Write-Host "Script directory: $scriptDir" -ForegroundColor Yellow
    exit 1
}

Write-Host "[INFO] Running configure-auth.ps1 without PowerShell profile..." -ForegroundColor Blue
Write-Host "[INFO] This bypasses any profile error handlers that might intercept JSON parse errors" -ForegroundColor Blue
Write-Host "[INFO] Auth script path: $authScript" -ForegroundColor Gray
Write-Host ""

# Change to the project root (parent of scripts directory)
$projectRoot = Split-Path -Parent $scriptDir
Set-Location $projectRoot

# Run the script without loading the profile
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $authScript

