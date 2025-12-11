# Fix frontend startup command for static site
# This clears the startup command so Azure serves static files from wwwroot

param(
    [string]$WebAppName,
    [string]$ResourceGroup
)

if ([string]::IsNullOrWhiteSpace($WebAppName) -or [string]::IsNullOrWhiteSpace($ResourceGroup)) {
    # Try to load from config
    if (Test-Path "config\deployment-config.env") {
        $config = @{}
        $fileLines = Get-Content "config\deployment-config.env" -Encoding UTF8
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
        $WebAppName = $config.WEB_APP_NAME
        $ResourceGroup = $config.RESOURCE_GROUP
    }
    
    if ([string]::IsNullOrWhiteSpace($WebAppName) -or [string]::IsNullOrWhiteSpace($ResourceGroup)) {
        Write-Host "[ERROR] Missing Web App name or Resource Group" -ForegroundColor Red
        Write-Host "Usage: .\scripts\fix-frontend-startup.ps1 -WebAppName <name> -ResourceGroup <rg>" -ForegroundColor Yellow
        exit 1
    }
}

Write-Host "[INFO] Fixing startup command for static site: $WebAppName" -ForegroundColor Blue

# Clear startup command
Write-Host "[INFO] Clearing startup command..." -ForegroundColor Blue
$ErrorActionPreference = 'SilentlyContinue'
az webapp config set `
    --name $WebAppName `
    --resource-group $ResourceGroup `
    --startup-file "" `
    --output none 2>&1 | Out-Null

# Clear linuxFxVersion (runtime stack)
az webapp config set `
    --name $WebAppName `
    --resource-group $ResourceGroup `
    --linux-fx-version "" `
    --output none 2>&1 | Out-Null
$ErrorActionPreference = 'Stop'

Write-Host "[SUCCESS] Startup command cleared" -ForegroundColor Green
Write-Host "[INFO] Restarting Web App..." -ForegroundColor Blue
az webapp restart --name $WebAppName --resource-group $ResourceGroup --output none

Write-Host "[SUCCESS] Web App restarted. It should now serve static files from wwwroot." -ForegroundColor Green
Write-Host "[INFO] Check your app at: https://$WebAppName.azurewebsites.net" -ForegroundColor Blue

