# Quick test script to verify path resolution works
# Run this to test if the script can find paths correctly

Write-Host "Testing path resolution..." -ForegroundColor Cyan
Write-Host ""

$scriptDir = $PSScriptRoot
$paDeploymentDir = Split-Path $scriptDir -Parent
$projectRoot = Split-Path $paDeploymentDir -Parent
$currentDir = Get-Location

Write-Host "Script directory: $scriptDir" -ForegroundColor Yellow
Write-Host "PA deployment directory: $paDeploymentDir" -ForegroundColor Yellow
Write-Host "Project root: $projectRoot" -ForegroundColor Yellow
Write-Host "Current directory: $currentDir" -ForegroundColor Yellow
Write-Host ""

# Test the config path
$testPath = Join-Path $paDeploymentDir "config" "deployment-config.env"
Write-Host "Testing config path: $testPath" -ForegroundColor Cyan
if (Test-Path $testPath) {
    Write-Host "[SUCCESS] Config file found!" -ForegroundColor Green
} else {
    Write-Host "[INFO] Config file not found (this is OK if deploy.ps1 hasn't been run)" -ForegroundColor Yellow
    Write-Host "Expected location: $testPath" -ForegroundColor Gray
}

