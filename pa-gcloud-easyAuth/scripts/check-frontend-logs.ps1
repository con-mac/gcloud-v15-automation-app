# Quick script to check frontend logs and diagnose blank page issues

param(
    [string]$WebAppName,
    [string]$ResourceGroup
)

# Load from config if not provided
if ([string]::IsNullOrWhiteSpace($WebAppName) -or [string]::IsNullOrWhiteSpace($ResourceGroup)) {
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
}

if ([string]::IsNullOrWhiteSpace($WebAppName) -or [string]::IsNullOrWhiteSpace($ResourceGroup)) {
    Write-Host "[ERROR] Missing Web App name or Resource Group" -ForegroundColor Red
    Write-Host "Usage: .\scripts\check-frontend-logs.ps1 -WebAppName <name> -ResourceGroup <rg>" -ForegroundColor Yellow
    exit 1
}

Write-Host "[INFO] Checking frontend logs for: $WebAppName" -ForegroundColor Blue
Write-Host ""

# Check app status
Write-Host "[INFO] App Status:" -ForegroundColor Blue
az webapp show --name $WebAppName --resource-group $ResourceGroup --query "{State:state, DefaultHostName:defaultHostName}" -o table

Write-Host ""
Write-Host "[INFO] Recent Logs (last 50 lines):" -ForegroundColor Blue
Write-Host "================================================" -ForegroundColor Yellow
az webapp log tail --name $WebAppName --resource-group $ResourceGroup --output table | Select-Object -Last 50

Write-Host ""
Write-Host "[INFO] To view live logs, run:" -ForegroundColor Blue
Write-Host "  az webapp log tail --name $WebAppName --resource-group $ResourceGroup" -ForegroundColor Cyan

Write-Host ""
Write-Host "[INFO] To check deployment logs:" -ForegroundColor Blue
Write-Host "  az webapp log deployment show --name $WebAppName --resource-group $ResourceGroup" -ForegroundColor Cyan

Write-Host ""
Write-Host "[INFO] To check if files exist in wwwroot:" -ForegroundColor Blue
Write-Host "  az webapp ssh --name $WebAppName --resource-group $ResourceGroup" -ForegroundColor Cyan
Write-Host "  Then run: ls -la /home/site/wwwroot" -ForegroundColor Cyan

