# Use Existing Config Script
# This script allows you to deploy using existing configuration without prompts
# Usage: .\scripts\use-existing-config.ps1
# Or: .\deploy.ps1 -UseExistingConfig

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Using Existing Configuration" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check if config exists
$configPath = "config\deployment-config.env"
if (-not (Test-Path $configPath)) {
    Write-Error "Configuration file not found: $configPath"
    Write-Info "Please run deploy.ps1 first to create the configuration file"
    Write-Info "Or manually create config\deployment-config.env with your values"
    exit 1
}

Write-Success "Found existing configuration file"
Write-Info "All values will be loaded from: $configPath"
Write-Info ""
Write-Info "To modify values, edit the config file and run this script again"
Write-Host ""

# Load config
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

Write-Success "Loaded $($config.Count) configuration values"
Write-Host ""

# Display key values
Write-Info "Configuration Summary:"
Write-Host "  Resource Group: $($config.RESOURCE_GROUP)"
Write-Host "  Function App: $($config.FUNCTION_APP_NAME)"
Write-Host "  Web App: $($config.WEB_APP_NAME)"
Write-Host "  Key Vault: $($config.KEY_VAULT_NAME)"
Write-Host "  Location: $($config.LOCATION)"
Write-Host ""

$confirm = Read-Host "Proceed with deployment using these values? (y/n) [y]"
if ([string]::IsNullOrWhiteSpace($confirm) -or $confirm -eq "y") {
    Write-Info "Calling deploy.ps1 with -UseExistingConfig flag..."
    Write-Host ""
    
    # Call deploy.ps1 with UseExistingConfig flag
    & ".\deploy.ps1" -UseExistingConfig
} else {
    Write-Info "Cancelled. Edit config\deployment-config.env to modify values."
    exit 0
}



