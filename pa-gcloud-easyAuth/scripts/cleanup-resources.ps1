# Cleanup script to delete all Azure resources for a fresh deployment
# This deletes everything EXCEPT the App Registration (which persists across resource groups)

param(
    [string]$ResourceGroup,
    [string]$AppRegistrationName
)

# Color output functions
function Write-Info { param([string]$msg) Write-Host "[INFO] $msg" -ForegroundColor Blue }
function Write-Success { param([string]$msg) Write-Host "[SUCCESS] $msg" -ForegroundColor Green }
function Write-Warning { param([string]$msg) Write-Host "[WARNING] $msg" -ForegroundColor Yellow }
function Write-Error { param([string]$msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }

# Try to load from config if not provided
if ([string]::IsNullOrWhiteSpace($ResourceGroup)) {
    if (Test-Path "config\deployment-config.env") {
        Write-Info "Loading configuration from config\deployment-config.env..."
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
        $ResourceGroup = $config.RESOURCE_GROUP
        $AppRegistrationName = $config.APP_REGISTRATION_NAME
    }
}

if ([string]::IsNullOrWhiteSpace($ResourceGroup)) {
    Write-Error "Resource Group name is required"
    Write-Info "Usage: .\scripts\cleanup-resources.ps1 -ResourceGroup <rg-name> [-AppRegistrationName <app-name>]"
    Write-Info "Or run from pa-deployment directory with config\deployment-config.env present"
    exit 1
}

Write-Warning "================================================"
Write-Warning "WARNING: This will DELETE ALL resources in:"
Write-Warning "  Resource Group: $ResourceGroup"
Write-Warning ""
Write-Warning "This includes:"
Write-Warning "  - Function App"
Write-Warning "  - Web App"
Write-Warning "  - Key Vault"
Write-Warning "  - Storage Account"
Write-Warning "  - Application Insights"
Write-Warning "  - Private DNS Zone"
Write-Warning "  - VNet and Subnets"
Write-Warning "  - Private Endpoints"
Write-Warning "  - App Service Plan"
Write-Warning ""
Write-Warning "The App Registration will NOT be deleted (it persists)"
Write-Warning "================================================"

$confirm = Read-Host "Type 'DELETE' to confirm deletion"
if ($confirm -ne "DELETE") {
    Write-Info "Deletion cancelled"
    exit 0
}

Write-Info "Starting cleanup of resource group: $ResourceGroup"

# Check if resource group exists
$ErrorActionPreference = 'SilentlyContinue'
$rgExists = az group show --name $ResourceGroup 2>&1
$ErrorActionPreference = 'Stop'

if ($LASTEXITCODE -ne 0) {
    Write-Warning "Resource group '$ResourceGroup' does not exist or you don't have access"
    exit 1
}

# Delete the entire resource group (this deletes all resources within it)
Write-Info "Deleting resource group and all resources..."
Write-Warning "This may take 5-10 minutes..."

az group delete --name $ResourceGroup --yes --no-wait

if ($LASTEXITCODE -eq 0) {
    Write-Success "Resource group deletion initiated"
    Write-Info "Deletion is running in the background"
    Write-Info "You can check status with: az group show --name $ResourceGroup"
    Write-Info ""
    Write-Info "Note: App Registration '$AppRegistrationName' was NOT deleted"
    Write-Info "It persists and can be reused in the next deployment"
} else {
    Write-Error "Failed to delete resource group"
    exit 1
}

Write-Info ""
Write-Info "Cleanup complete! You can now run .\deploy.ps1 for a fresh deployment"
Write-Info "The App Registration will be reused if it exists, or you can create a new one"

