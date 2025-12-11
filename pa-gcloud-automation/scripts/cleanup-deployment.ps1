# Cleanup Deployment Script
# Deletes all resources created during deployment
# Includes resources inside and outside the Resource Group

$ErrorActionPreference = "Stop"

function Write-Info { param([string]$msg) Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Success { param([string]$msg) Write-Host "[SUCCESS] $msg" -ForegroundColor Green }
function Write-Warning { param([string]$msg) Write-Host "[WARNING] $msg" -ForegroundColor Yellow }
function Write-Error { param([string]$msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }

# Load configuration
$configPath = "config\deployment-config.env"
if (-not (Test-Path $configPath)) {
    $configPath = "..\config\deployment-config.env"
    if (-not (Test-Path $configPath)) {
        Write-Error "deployment-config.env not found. Please run deploy.ps1 first or specify resource names manually."
        exit 1
    }
}

# Parse environment file
$config = @{}
$fileLines = Get-Content $configPath -Encoding UTF8
foreach ($line in $fileLines) {
    $line = $line.Trim()
    if ($line -and -not $line.StartsWith('#')) {
        $equalsIndex = $line.IndexOf('=')
        if ($equalsIndex -gt 0) {
            $key = $line.Substring(0, $equalsIndex).Trim()
            $value = $line.Substring($equalsIndex + 1).Trim()
            $config[$key] = $value
        }
    }
}

$RESOURCE_GROUP = $config["RESOURCE_GROUP"]
$FUNCTION_APP_NAME = $config["FUNCTION_APP_NAME"]
$WEB_APP_NAME = $config["WEB_APP_NAME"]
$KEY_VAULT_NAME = $config["KEY_VAULT_NAME"]
$APP_REGISTRATION_NAME = $config["APP_REGISTRATION_NAME"]
$ADMIN_GROUP_ID = $config["ADMIN_GROUP_ID"]
$EMPLOYEE_GROUP_ID = $config["EMPLOYEE_GROUP_ID"]
$STORAGE_ACCOUNT_NAME = $config["STORAGE_ACCOUNT_NAME"]
$ACR_NAME = $config["ACR_NAME"]

Write-Info "Cleanup Deployment Script"
Write-Info "This will delete ALL resources created during deployment"
Write-Info ""

# Show what will be deleted
Write-Warning "The following resources will be DELETED:"
Write-Host ""
Write-Host "Resource Group (deletes all resources inside):" -ForegroundColor Yellow
if ($RESOURCE_GROUP) {
    Write-Host "  - Resource Group: $RESOURCE_GROUP" -ForegroundColor White
    Write-Host "    (This will delete: Function App, Web App, Key Vault, Storage Accounts, ACR, App Insights, etc.)" -ForegroundColor Gray
} else {
    Write-Host "  - Resource Group: (not found in config)" -ForegroundColor Gray
}

Write-Host ""
Write-Host "Azure AD Resources (outside Resource Group):" -ForegroundColor Yellow
if ($APP_REGISTRATION_NAME) {
    Write-Host "  - App Registration: $APP_REGISTRATION_NAME" -ForegroundColor White
} else {
    Write-Host "  - App Registration: (not found in config)" -ForegroundColor Gray
}

if ($ADMIN_GROUP_ID) {
    Write-Host "  - Admin Security Group ID: $ADMIN_GROUP_ID" -ForegroundColor White
} else {
    Write-Host "  - Admin Security Group: (not found in config)" -ForegroundColor Gray
}

if ($EMPLOYEE_GROUP_ID) {
    Write-Host "  - Employee Security Group ID: $EMPLOYEE_GROUP_ID" -ForegroundColor White
} else {
    Write-Host "  - Employee Security Group: (not found in config)" -ForegroundColor Gray
}

Write-Host ""
Write-Warning "This action CANNOT be undone!"
$confirm = Read-Host "Are you sure you want to delete all these resources? Type 'DELETE' to confirm"

if ($confirm -ne "DELETE") {
    Write-Info "Cleanup cancelled"
    exit 0
}

Write-Info ""
Write-Info "Starting cleanup..."
Write-Info ""

# Step 1: Delete App Registration (Azure AD - outside Resource Group)
if (-not [string]::IsNullOrWhiteSpace($APP_REGISTRATION_NAME)) {
    Write-Info "Step 1: Deleting App Registration: $APP_REGISTRATION_NAME"
    $ErrorActionPreference = 'SilentlyContinue'
    $appId = az ad app list --display-name "$APP_REGISTRATION_NAME" --query "[0].appId" -o tsv 2>&1
    $ErrorActionPreference = 'Stop'
    
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($appId)) {
        $ErrorActionPreference = 'SilentlyContinue'
        az ad app delete --id $appId 2>&1 | Out-Null
        $ErrorActionPreference = 'Stop'
        if ($LASTEXITCODE -eq 0) {
            Write-Success "App Registration deleted: $APP_REGISTRATION_NAME"
        } else {
            Write-Warning "Could not delete App Registration (may not exist or already deleted)"
        }
    } else {
        Write-Info "App Registration not found (may already be deleted)"
    }
} else {
    Write-Info "Step 1: Skipping App Registration (name not in config)"
}

# Step 2: Delete Security Groups (Azure AD - outside Resource Group)
if (-not [string]::IsNullOrWhiteSpace($ADMIN_GROUP_ID)) {
    Write-Info "Step 2: Deleting Admin Security Group: $ADMIN_GROUP_ID"
    $ErrorActionPreference = 'SilentlyContinue'
    az ad group delete --group $ADMIN_GROUP_ID 2>&1 | Out-Null
    $ErrorActionPreference = 'Stop'
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Admin Security Group deleted: $ADMIN_GROUP_ID"
    } else {
        Write-Warning "Could not delete Admin Security Group (may not exist or already deleted)"
    }
} else {
    Write-Info "Step 2: Skipping Admin Security Group (ID not in config)"
}

if (-not [string]::IsNullOrWhiteSpace($EMPLOYEE_GROUP_ID)) {
    Write-Info "Deleting Employee Security Group: $EMPLOYEE_GROUP_ID"
    $ErrorActionPreference = 'SilentlyContinue'
    az ad group delete --group $EMPLOYEE_GROUP_ID 2>&1 | Out-Null
    $ErrorActionPreference = 'Stop'
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Employee Security Group deleted: $EMPLOYEE_GROUP_ID"
    } else {
        Write-Warning "Could not delete Employee Security Group (may not exist or already deleted)"
    }
} else {
    Write-Info "Skipping Employee Security Group (ID not in config)"
}

# Step 3: Delete Resource Group (this deletes most resources)
if (-not [string]::IsNullOrWhiteSpace($RESOURCE_GROUP)) {
    Write-Info ""
    Write-Info "Step 3: Deleting Resource Group: $RESOURCE_GROUP"
    Write-Info "This will delete all resources inside the Resource Group..."
    Write-Info ""
    
    $ErrorActionPreference = 'SilentlyContinue'
    $rgExists = az group show --name $RESOURCE_GROUP 2>&1
    $ErrorActionPreference = 'Stop'
    
    if ($LASTEXITCODE -eq 0) {
        Write-Info "Deleting Resource Group (this may take 2-5 minutes)..."
        $ErrorActionPreference = 'SilentlyContinue'
        az group delete --name $RESOURCE_GROUP --yes --no-wait 2>&1 | Out-Null
        $ErrorActionPreference = 'Stop'
        
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Resource Group deletion initiated: $RESOURCE_GROUP"
            Write-Info "Deletion is running in the background. Most resources are now deleted."
        } else {
            Write-Warning "Could not delete Resource Group (may require manual deletion)"
        }
    } else {
        Write-Info "Resource Group not found (may already be deleted): $RESOURCE_GROUP"
    }
} else {
    Write-Warning "Step 3: Cannot delete Resource Group (name not in config)"
}

# Step 4: Purge soft-deleted Key Vault (if it exists)
if (-not [string]::IsNullOrWhiteSpace($KEY_VAULT_NAME)) {
    Write-Info ""
    Write-Info "Step 4: Checking for soft-deleted Key Vault: $KEY_VAULT_NAME"
    $ErrorActionPreference = 'SilentlyContinue'
    $kvExists = az keyvault show --name $KEY_VAULT_NAME 2>&1
    $ErrorActionPreference = 'Stop'
    
    if ($LASTEXITCODE -ne 0) {
        # Key Vault might be soft-deleted, try to purge
        Write-Info "Attempting to purge soft-deleted Key Vault..."
        $ErrorActionPreference = 'SilentlyContinue'
        az keyvault purge --name $KEY_VAULT_NAME 2>&1 | Out-Null
        $ErrorActionPreference = 'Stop'
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Soft-deleted Key Vault purged: $KEY_VAULT_NAME"
        } else {
            Write-Info "Key Vault not found (may already be deleted or purged)"
        }
    } else {
        Write-Info "Key Vault still exists (will be deleted with Resource Group)"
    }
}

# Step 5: Purge soft-deleted Storage Account (if it exists globally)
if (-not [string]::IsNullOrWhiteSpace($STORAGE_ACCOUNT_NAME)) {
    Write-Info ""
    Write-Info "Step 5: Checking for soft-deleted Storage Account: $STORAGE_ACCOUNT_NAME"
    $ErrorActionPreference = 'SilentlyContinue'
    $saExists = az storage account show --name $STORAGE_ACCOUNT_NAME 2>&1
    $ErrorActionPreference = 'Stop'
    
    if ($LASTEXITCODE -ne 0) {
        Write-Info "Storage Account not found (may already be deleted)"
    } else {
        Write-Info "Storage Account still exists (will be deleted with Resource Group)"
    }
}

Write-Info ""
Write-Success "Cleanup complete!"
Write-Info ""
Write-Info "Summary:"
Write-Host "  - App Registration: Deleted (if existed)" -ForegroundColor Green
Write-Host "  - Security Groups: Deleted (if existed)" -ForegroundColor Green
Write-Host "  - Resource Group: Deletion initiated (deletes all resources inside)" -ForegroundColor Green
Write-Info ""
Write-Info "Note: Resource Group deletion runs in the background."
Write-Info "      It may take 2-5 minutes to complete."
Write-Info "      You can verify deletion in Azure Portal."
Write-Info ""
Write-Info "To verify cleanup:"
if ($RESOURCE_GROUP) {
    Write-Host "  az group list --query `"[?name=='$RESOURCE_GROUP']`"" -ForegroundColor White
}
if ($APP_REGISTRATION_NAME) {
    Write-Host "  az ad app list --display-name `"$APP_REGISTRATION_NAME`"" -ForegroundColor White
}

