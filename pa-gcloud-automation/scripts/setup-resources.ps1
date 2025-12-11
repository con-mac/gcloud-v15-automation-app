# Setup Azure Resources Script (PowerShell)
# Creates all necessary Azure resources for PA deployment

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

# Set variables
$RESOURCE_GROUP = $config.RESOURCE_GROUP
$FUNCTION_APP_NAME = $config.FUNCTION_APP_NAME
$WEB_APP_NAME = $config.WEB_APP_NAME
$KEY_VAULT_NAME = $config.KEY_VAULT_NAME
$LOCATION = $config.LOCATION
$SUBSCRIPTION_ID = $config.SUBSCRIPTION_ID

function Write-Info { param([string]$msg) Write-Host "[INFO] $msg" -ForegroundColor Blue }
function Write-Success { param([string]$msg) Write-Host "[SUCCESS] $msg" -ForegroundColor Green }
function Write-Warning { param([string]$msg) Write-Host "[WARNING] $msg" -ForegroundColor Yellow }

Write-Info "Setting up Azure resources..."

# Set subscription
az account set --subscription "$SUBSCRIPTION_ID" | Out-Null

# Handle Storage Account
$STORAGE_ACCOUNT_CHOICE = $config.STORAGE_ACCOUNT_CHOICE
$STORAGE_ACCOUNT_NAME = $config.STORAGE_ACCOUNT_NAME

# Clean storage account name if it contains invalid characters or expressions
if (-not [string]::IsNullOrWhiteSpace($STORAGE_ACCOUNT_NAME)) {
    # Remove any PowerShell expressions that might have been saved literally
    if ($STORAGE_ACCOUNT_NAME -match '\.ToLower\(\)|\.Substring\(|\[Math\]') {
        Write-Warning "Storage account name contains invalid expression, regenerating..."
        $STORAGE_ACCOUNT_NAME = ""
    }
}

if ([string]::IsNullOrWhiteSpace($STORAGE_ACCOUNT_CHOICE) -or $STORAGE_ACCOUNT_CHOICE -eq "new") {
    Write-Info "Creating Storage Account (for temporary files)..."
    if ([string]::IsNullOrWhiteSpace($STORAGE_ACCOUNT_NAME)) {
        # Generate storage account name: remove hyphens/underscores, lowercase, max 22 chars + "st"
        $cleanName = ($FUNCTION_APP_NAME -replace '-', '' -replace '_', '').ToLower()
        $maxLength = [Math]::Min(22, $cleanName.Length)
        $STORAGE_ACCOUNT_NAME = $cleanName.Substring(0, $maxLength) + "st"
    }
    # Validate and fix storage account name (alphanumeric only, 3-24 chars)
    $STORAGE_ACCOUNT_NAME = $STORAGE_ACCOUNT_NAME -replace '[^a-z0-9]', ''
    # Ensure minimum length of 3 characters
    if ($STORAGE_ACCOUNT_NAME.Length -lt 3) {
        $STORAGE_ACCOUNT_NAME = $STORAGE_ACCOUNT_NAME.PadRight(3, '0')
    }
    # Ensure maximum length of 24 characters
    if ($STORAGE_ACCOUNT_NAME.Length -gt 24) {
        $STORAGE_ACCOUNT_NAME = $STORAGE_ACCOUNT_NAME.Substring(0, 24)
    }
    if ($STORAGE_ACCOUNT_NAME.Length -lt 3 -or $STORAGE_ACCOUNT_NAME.Length -gt 24) {
        Write-Error "Invalid storage account name: $STORAGE_ACCOUNT_NAME (must be 3-24 alphanumeric characters)"
        exit 1
    }
    # Ensure variable is properly set and doesn't contain problematic characters
    if ([string]::IsNullOrWhiteSpace($STORAGE_ACCOUNT_NAME)) {
        Write-Error "Storage account name is empty or invalid"
        exit 1
    }
    Write-Info "Checking for Storage Account: $STORAGE_ACCOUNT_NAME"
    $ErrorActionPreference = 'SilentlyContinue'
    $storageExists = az storage account show --name "$STORAGE_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP" 2>&1
    $ErrorActionPreference = 'Stop'
    if ($LASTEXITCODE -ne 0) {
        # Check if name is available globally (storage accounts must be globally unique)
        Write-Info "Checking if storage account name is available globally..."
        $ErrorActionPreference = 'SilentlyContinue'
        $checkGlobal = az storage account check-name --name "$STORAGE_ACCOUNT_NAME" --query "nameAvailable" -o tsv 2>&1
        $ErrorActionPreference = 'Stop'
        
        if ($checkGlobal -eq "false") {
            Write-Error "Storage Account name '$STORAGE_ACCOUNT_NAME' is already taken globally."
            Write-Error "Storage account names must be globally unique across all Azure subscriptions."
            Write-Error "The deployment script should have added a random suffix. Please report this issue."
            exit 1
        }
        
        # Check if Microsoft.Storage provider is registered
        Write-Info "Verifying Microsoft.Storage provider is registered..."
        $ErrorActionPreference = 'SilentlyContinue'
        $storageProvider = az provider show --namespace "Microsoft.Storage" --query "registrationState" -o tsv 2>&1
        $ErrorActionPreference = 'Stop'
        
        if ($storageProvider -ne "Registered") {
            Write-Warning "Microsoft.Storage provider is not registered. Registering now..."
            az provider register --namespace "Microsoft.Storage" | Out-Null
            Write-Info "Waiting for registration to complete (30 seconds)..."
            Start-Sleep -Seconds 30
        }
        
        $ErrorActionPreference = 'SilentlyContinue'
        $createOutput = az storage account create `
            --name "$STORAGE_ACCOUNT_NAME" `
            --resource-group "$RESOURCE_GROUP" `
            --location "$LOCATION" `
            --sku Standard_LRS `
            --kind StorageV2 `
            --allow-blob-public-access false `
            --min-tls-version TLS1_2 2>&1 | Where-Object { $_ -notmatch 'WARNING:' } | Out-Null
        $ErrorActionPreference = 'Stop'
        
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Storage Account created: $STORAGE_ACCOUNT_NAME"
        } else {
            # Check if it exists globally
            $ErrorActionPreference = 'SilentlyContinue'
            $globalCheck = az storage account show --name "$STORAGE_ACCOUNT_NAME" --query id -o tsv 2>&1 | Out-Null
            $ErrorActionPreference = 'Stop'
            if ($LASTEXITCODE -eq 0) {
                Write-Info "Storage Account '$STORAGE_ACCOUNT_NAME' exists globally. Using existing account."
            } else {
                Write-Warning "Could not create Storage Account '$STORAGE_ACCOUNT_NAME'."
            }
        }
    } else {
        Write-Success "Using existing Storage Account: $STORAGE_ACCOUNT_NAME"
    }
} elseif ($STORAGE_ACCOUNT_CHOICE -eq "existing") {
    if (-not [string]::IsNullOrWhiteSpace($STORAGE_ACCOUNT_NAME)) {
        $storageExists = az storage account show --name "$STORAGE_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP" 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Using existing Storage Account: $STORAGE_ACCOUNT_NAME"
        } else {
            Write-Warning "Storage Account '$STORAGE_ACCOUNT_NAME' not found, skipping"
            $STORAGE_ACCOUNT_NAME = ""
        }
    } else {
        Write-Warning "No Storage Account name provided for existing choice, skipping"
        $STORAGE_ACCOUNT_NAME = ""
    }
} else {
    Write-Info "Skipping Storage Account creation"
    $STORAGE_ACCOUNT_NAME = ""
}

# Create or use existing Key Vault
Write-Info "Checking for Key Vault: $KEY_VAULT_NAME"
$ErrorActionPreference = 'SilentlyContinue'
$kvExists = az keyvault show --name "$KEY_VAULT_NAME" --resource-group "$RESOURCE_GROUP" 2>&1
$kvError = $kvExists | Out-String
$ErrorActionPreference = 'Stop'
if ($LASTEXITCODE -ne 0) {
    Write-Info "Key Vault not found. Creating new Key Vault..."
    # Check if Key Vault is soft-deleted (globally unique name conflict)
    if ($kvError -match "VaultAlreadyExists" -or $kvError -match "already in use") {
        Write-Warning "Key Vault name '$KEY_VAULT_NAME' is already in use (possibly soft-deleted)"
        Write-Info "Attempting to purge soft-deleted Key Vault..."
        
        # Try to purge if it's soft-deleted
        $ErrorActionPreference = 'SilentlyContinue'
        az keyvault purge --name "$KEY_VAULT_NAME" 2>&1 | Out-Null
        $ErrorActionPreference = 'Stop'
        Start-Sleep -Seconds 3
        
        # Try creating again
        $ErrorActionPreference = 'SilentlyContinue'
        $createResult = az keyvault create `
            --name "$KEY_VAULT_NAME" `
            --resource-group "$RESOURCE_GROUP" `
            --location "$LOCATION" `
            --sku standard `
            --enable-rbac-authorization true 2>&1
        $ErrorActionPreference = 'Stop'
        
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Key Vault created after purge: $KEY_VAULT_NAME"
        } else {
            Write-Error "Could not create Key Vault. The name is still in use."
            Write-Info "Please choose a different name or wait for soft-delete to expire (up to 90 days)"
            Write-Info "You can purge manually: az keyvault purge --name $KEY_VAULT_NAME"
            exit 1
        }
    } else {
        # Normal Key Vault creation (not soft-deleted)
        az keyvault create `
            --name "$KEY_VAULT_NAME" `
            --resource-group "$RESOURCE_GROUP" `
            --location "$LOCATION" `
            --sku standard `
            --enable-rbac-authorization true | Out-Null
        
        # Grant current user Key Vault Secrets Officer role for RBAC
        Write-Info "Granting Key Vault permissions to current user..."
        $currentUser = az ad signed-in-user show --query id -o tsv
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($currentUser)) {
            $kvScope = "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$KEY_VAULT_NAME"
            # Check if role assignment already exists
            $ErrorActionPreference = 'SilentlyContinue'
            $existingRole = az role assignment list --assignee "$currentUser" --scope "$kvScope" --role "Key Vault Secrets Officer" --query "[].id" -o tsv 2>&1
            $ErrorActionPreference = 'Stop'
            
            if ([string]::IsNullOrWhiteSpace($existingRole)) {
                az role assignment create `
                    --role "Key Vault Secrets Officer" `
                    --assignee "$currentUser" `
                    --scope "$kvScope" `
                    --output none 2>&1 | Out-Null
                Write-Success "Key Vault permissions granted"
                # Wait a moment for propagation
                Start-Sleep -Seconds 5
            } else {
                Write-Success "Key Vault permissions already granted"
            }
        } else {
            Write-Warning "Could not grant Key Vault permissions automatically. Please grant 'Key Vault Secrets Officer' role manually."
        }
        
        Write-Success "Key Vault created: $KEY_VAULT_NAME"
    }
} else {
    Write-Success "Using existing Key Vault: $KEY_VAULT_NAME"
        # Ensure permissions are granted even for existing Key Vault
        Write-Info "Ensuring Key Vault permissions..."
        $currentUser = az ad signed-in-user show --query id -o tsv
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($currentUser)) {
            $kvScope = "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$KEY_VAULT_NAME"
            $ErrorActionPreference = 'SilentlyContinue'
            $existingRole = az role assignment list --assignee "$currentUser" --scope "$kvScope" --role "Key Vault Secrets Officer" --query "[].id" -o tsv 2>&1
            $ErrorActionPreference = 'Stop'
            
            if ([string]::IsNullOrWhiteSpace($existingRole)) {
                az role assignment create `
                    --role "Key Vault Secrets Officer" `
                    --assignee "$currentUser" `
                    --scope "$kvScope" `
                    --output none 2>&1 | Out-Null
                Write-Success "Key Vault permissions granted"
                Start-Sleep -Seconds 5
            }
        }
    }

# Create or update Function App (Consumption plan for serverless)
Write-Info "Setting up Function App for backend API..."
$ErrorActionPreference = 'SilentlyContinue'
$funcExists = az functionapp show --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP" 2>&1
$ErrorActionPreference = 'Stop'
if ($LASTEXITCODE -ne 0) {
    # Create storage account for function app (required)
    $cleanFuncName = ($FUNCTION_APP_NAME -replace '-', '' -replace '_', '').ToLower()
    # Ensure minimum length
    if ($cleanFuncName.Length -lt 3) {
        $cleanFuncName = $cleanFuncName.PadRight(3, '0')
    }
    $maxFuncLength = [Math]::Min(20, $cleanFuncName.Length)
    $FUNC_STORAGE = $cleanFuncName.Substring(0, $maxFuncLength) + "func"
    # Validate function storage account name
    $FUNC_STORAGE = $FUNC_STORAGE -replace '[^a-z0-9]', ''
    # Ensure minimum length of 3
    if ($FUNC_STORAGE.Length -lt 3) {
        $FUNC_STORAGE = $FUNC_STORAGE.PadRight(3, '0')
    }
    # Ensure maximum length of 24
    if ($FUNC_STORAGE.Length -gt 24) {
        $FUNC_STORAGE = $FUNC_STORAGE.Substring(0, 24)
    }
    if ([string]::IsNullOrWhiteSpace($FUNC_STORAGE)) {
        Write-Error "Function storage account name is empty or invalid"
        exit 1
    }
    $ErrorActionPreference = 'SilentlyContinue'
    $funcStorageExists = az storage account show --name "$FUNC_STORAGE" --resource-group "$RESOURCE_GROUP" 2>&1 | Out-Null
    $ErrorActionPreference = 'Stop'
    if ($LASTEXITCODE -ne 0) {
        $ErrorActionPreference = 'SilentlyContinue'
        $createResult = az storage account create `
            --name "$FUNC_STORAGE" `
            --resource-group "$RESOURCE_GROUP" `
            --location "$LOCATION" `
            --sku Standard_LRS 2>&1 | Out-Null
        $ErrorActionPreference = 'Stop'
        
        if ($LASTEXITCODE -ne 0) {
            # Check if it exists globally
            $globalCheck = az storage account show --name "$FUNC_STORAGE" --query id -o tsv 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Warning "Function storage account '$FUNC_STORAGE' exists in a different resource group. Using existing account."
            } else {
                Write-Warning "Could not create Function storage account '$FUNC_STORAGE'. It may already exist globally."
            }
        }
    }
    
    # Create Function App
    az functionapp create `
        --name "$FUNCTION_APP_NAME" `
        --resource-group "$RESOURCE_GROUP" `
        --consumption-plan-location "$LOCATION" `
        --runtime python `
        --runtime-version 3.11 `
        --functions-version 4 `
        --storage-account "$FUNC_STORAGE" `
        --os-type Linux | Out-Null
    
    Write-Warning "NOTE: Private endpoint configuration requires VNet integration"
    Write-Warning "Please configure VNet integration and private endpoints manually or via script"
    
    Write-Success "Function App created: $FUNCTION_APP_NAME"
} else {
    Write-Success "Using existing Function App: $FUNCTION_APP_NAME"
    Write-Info "Function App will be updated with new configuration during deployment"
}

# Create or update Static Web App (or App Service for private hosting)
Write-Info "Setting up Web App for frontend..."
$ErrorActionPreference = 'SilentlyContinue'
$webAppExists = az webapp show --name "$WEB_APP_NAME" --resource-group "$RESOURCE_GROUP" 2>&1
$ErrorActionPreference = 'Stop'
if ($LASTEXITCODE -ne 0) {
    Write-Info "App Service (Web App) created - supports private endpoints when configured"
    
    # Create App Service Plan
    $APP_SERVICE_PLAN = "$WEB_APP_NAME-plan"
    $ErrorActionPreference = 'SilentlyContinue'
    $planExists = az appservice plan show --name "$APP_SERVICE_PLAN" --resource-group "$RESOURCE_GROUP" 2>&1
    $ErrorActionPreference = 'Stop'
    if ($LASTEXITCODE -ne 0) {
        Write-Info "Creating App Service Plan: $APP_SERVICE_PLAN"
        Write-Info "SKU: B1 (Basic) - Location: $LOCATION"
        
        # Try to create the plan
        $ErrorActionPreference = 'SilentlyContinue'
        $planResult = az appservice plan create `
            --name "$APP_SERVICE_PLAN" `
            --resource-group "$RESOURCE_GROUP" `
            --location "$LOCATION" `
            --sku B1 `
            --is-linux 2>&1
        $ErrorActionPreference = 'Stop'
        
        if ($LASTEXITCODE -ne 0) {
            # Check if it's a capacity issue
            if ($planResult -match "No available instances" -or $planResult -match "capacity") {
                Write-Warning "App Service Plan capacity issue in region: $LOCATION"
                Write-Warning "This region may be temporarily at capacity for B1 SKU"
                Write-Info ""
                Write-Info "SOLUTIONS:"
                Write-Host "  1. Try a different region (eastus, westeurope, northeurope)" -ForegroundColor Yellow
                Write-Host "  2. Create the plan manually in a different region:" -ForegroundColor Yellow
                Write-Host "     az appservice plan create --name `"$APP_SERVICE_PLAN`" --resource-group `"$RESOURCE_GROUP`" --location eastus --sku B1 --is-linux" -ForegroundColor White
                Write-Host "  3. Wait 10-15 minutes and retry (Azure is scaling capacity)" -ForegroundColor Yellow
                Write-Host "  4. Use a different SKU (F1 for free tier, or S1 for more capacity)" -ForegroundColor Yellow
                Write-Info ""
                Write-Error "Cannot proceed without App Service Plan. Please create it manually or try a different region."
                exit 1
            } else {
                Write-Error "Failed to create App Service Plan: $planResult"
                exit 1
            }
        } else {
            Write-Success "App Service Plan created: $APP_SERVICE_PLAN"
        }
    } else {
        Write-Success "Using existing App Service Plan: $APP_SERVICE_PLAN"
    }
    
    # Create Web App with a basic runtime first (required by Azure)
    # We'll configure Docker container during frontend deployment
    # Using NODE runtime as placeholder - will be replaced with Docker container
    az webapp create `
        --name "$WEB_APP_NAME" `
        --resource-group "$RESOURCE_GROUP" `
        --plan "$APP_SERVICE_PLAN" `
        --runtime "NODE:20-lts" `
        --output none | Out-Null
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to create Web App: $WEB_APP_NAME"
        Write-Info "Error: Azure requires a runtime or container configuration"
        exit 1
    }
    
    Write-Success "Web App created: $WEB_APP_NAME"
    Write-Info "Web App will be configured with Docker container during frontend deployment"
} else {
    Write-Success "Using existing Web App: $WEB_APP_NAME"
    Write-Info "Web App will be updated with Docker container configuration during deployment"
}

# Handle Application Insights
$APP_INSIGHTS_CHOICE = $config.APP_INSIGHTS_CHOICE
$APP_INSIGHTS_NAME = $config.APP_INSIGHTS_NAME

if ([string]::IsNullOrWhiteSpace($APP_INSIGHTS_CHOICE) -or $APP_INSIGHTS_CHOICE -eq "new") {
    Write-Info "Creating Application Insights..."
    if ([string]::IsNullOrWhiteSpace($APP_INSIGHTS_NAME)) {
        $APP_INSIGHTS_NAME = "$FUNCTION_APP_NAME-insights"
    }
    $ErrorActionPreference = 'SilentlyContinue'
    $aiExists = az monitor app-insights component show --app "$APP_INSIGHTS_NAME" --resource-group "$RESOURCE_GROUP" 2>&1
    $ErrorActionPreference = 'Stop'
    if ($LASTEXITCODE -ne 0) {
        az monitor app-insights component create `
            --app "$APP_INSIGHTS_NAME" `
            --location "$LOCATION" `
            --resource-group "$RESOURCE_GROUP" `
            --application-type web | Out-Null
        Write-Success "Application Insights created: $APP_INSIGHTS_NAME"
    } else {
        Write-Warning "Application Insights already exists: $APP_INSIGHTS_NAME"
    }
} elseif ($APP_INSIGHTS_CHOICE -eq "existing") {
    if (-not [string]::IsNullOrWhiteSpace($APP_INSIGHTS_NAME)) {
        $ErrorActionPreference = 'SilentlyContinue'
        $aiExists = az monitor app-insights component show --app "$APP_INSIGHTS_NAME" --resource-group "$RESOURCE_GROUP" 2>&1
        $ErrorActionPreference = 'Stop'
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Using existing Application Insights: $APP_INSIGHTS_NAME"
        } else {
            Write-Warning "Application Insights '$APP_INSIGHTS_NAME' not found, skipping"
            $APP_INSIGHTS_NAME = ""
        }
    } else {
        Write-Warning "No Application Insights name provided for existing choice, skipping"
        $APP_INSIGHTS_NAME = ""
    }
} else {
    Write-Info "Skipping Application Insights creation"
    $APP_INSIGHTS_NAME = ""
}

# Store App Insights connection string (if created/using existing)
if (-not [string]::IsNullOrWhiteSpace($APP_INSIGHTS_NAME)) {
    $ErrorActionPreference = 'SilentlyContinue'
    $APP_INSIGHTS_CONNECTION = az monitor app-insights component show `
        --app "$APP_INSIGHTS_NAME" `
        --resource-group "$RESOURCE_GROUP" `
        --query connectionString -o tsv
    $ErrorActionPreference = 'Stop'
    
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($APP_INSIGHTS_CONNECTION)) {
        # Save to Key Vault
        az keyvault secret set `
            --vault-name "$KEY_VAULT_NAME" `
            --name "AppInsightsConnectionString" `
            --value "$APP_INSIGHTS_CONNECTION" `
            --output none | Out-Null
        Write-Success "Application Insights connection string saved to Key Vault"
    } else {
        Write-Warning "Could not retrieve Application Insights connection string"
    }
}

# Handle Private DNS Zone
$PRIVATE_DNS_CHOICE = $config.PRIVATE_DNS_CHOICE
$PRIVATE_DNS_ZONE_NAME = $config.PRIVATE_DNS_ZONE_NAME

if ([string]::IsNullOrWhiteSpace($PRIVATE_DNS_CHOICE) -or $PRIVATE_DNS_CHOICE -eq "new") {
    Write-Info "Creating Private DNS Zone..."
    if ([string]::IsNullOrWhiteSpace($PRIVATE_DNS_ZONE_NAME)) {
        $PRIVATE_DNS_ZONE_NAME = "privatelink.azurewebsites.net"
    }
    $ErrorActionPreference = 'SilentlyContinue'
    $dnsExists = az network private-dns zone show --name "$PRIVATE_DNS_ZONE_NAME" --resource-group "$RESOURCE_GROUP" 2>&1
    $ErrorActionPreference = 'Stop'
    if ($LASTEXITCODE -ne 0) {
        az network private-dns zone create `
            --name "$PRIVATE_DNS_ZONE_NAME" `
            --resource-group "$RESOURCE_GROUP" | Out-Null
        Write-Success "Private DNS Zone created: $PRIVATE_DNS_ZONE_NAME"
    } else {
        Write-Warning "Private DNS Zone already exists: $PRIVATE_DNS_ZONE_NAME"
    }
} elseif ($PRIVATE_DNS_CHOICE -eq "existing") {
    if (-not [string]::IsNullOrWhiteSpace($PRIVATE_DNS_ZONE_NAME)) {
        $ErrorActionPreference = 'SilentlyContinue'
        $dnsExists = az network private-dns zone show --name "$PRIVATE_DNS_ZONE_NAME" --resource-group "$RESOURCE_GROUP" 2>&1
        $ErrorActionPreference = 'Stop'
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Using existing Private DNS Zone: $PRIVATE_DNS_ZONE_NAME"
        } else {
            Write-Warning "Private DNS Zone '$PRIVATE_DNS_ZONE_NAME' not found, skipping"
            $PRIVATE_DNS_ZONE_NAME = ""
        }
    } else {
        Write-Warning "No Private DNS Zone name provided for existing choice, skipping"
        $PRIVATE_DNS_ZONE_NAME = ""
    }
} else {
    Write-Info "Skipping Private DNS Zone creation"
    $PRIVATE_DNS_ZONE_NAME = ""
}

# Handle Azure Container Registry
$ACR_NAME = $config.ACR_NAME
$IMAGE_TAG = $config.IMAGE_TAG

if (-not [string]::IsNullOrWhiteSpace($ACR_NAME)) {
    Write-Info "Setting up Azure Container Registry..."
    $ErrorActionPreference = 'SilentlyContinue'
    $acrExists = az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" 2>&1
    $ErrorActionPreference = 'Stop'
    
    if ($LASTEXITCODE -ne 0) {
        Write-Info "Creating Azure Container Registry: $ACR_NAME"
        # ACR name must be globally unique, lowercase alphanumeric, 5-50 chars
        $acrNameClean = $ACR_NAME.ToLower() -replace '[^a-z0-9]', ''
        if ($acrNameClean.Length -lt 5) {
            $acrNameClean = $acrNameClean.PadRight(5, '0')
        }
        if ($acrNameClean.Length -gt 50) {
            $acrNameClean = $acrNameClean.Substring(0, 50)
        }
        
        # Create ACR with Basic SKU (sufficient for dev, can upgrade later)
        az acr create `
            --name "$acrNameClean" `
            --resource-group "$RESOURCE_GROUP" `
            --sku Basic `
            --admin-enabled true `
            --location "$LOCATION" `
            --output none
        
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Azure Container Registry created: $acrNameClean"
            $ACR_NAME = $acrNameClean
        } else {
            Write-Warning "Failed to create ACR. It may already exist globally or name is taken."
            Write-Info "Please ensure ACR '$ACR_NAME' exists or choose a different name."
        }
    } else {
        Write-Success "Using existing Azure Container Registry: $ACR_NAME"
    }
    
    # Set default image tag if not provided
    if ([string]::IsNullOrWhiteSpace($IMAGE_TAG)) {
        $IMAGE_TAG = "latest"
    }
} else {
    Write-Warning "ACR_NAME not specified in config. Container deployment will require ACR to be configured."
}

# Handle VNet and Private Endpoint Configuration
$CONFIGURE_PRIVATE_ENDPOINTS = $config.CONFIGURE_PRIVATE_ENDPOINTS
$VNET_NAME = $config.VNET_NAME
$SUBNET_NAME = $config.SUBNET_NAME

# Only configure private endpoints if explicitly requested
if ($CONFIGURE_PRIVATE_ENDPOINTS -eq "true" -and -not [string]::IsNullOrWhiteSpace($VNET_NAME)) {
    Write-Info "Configuring private endpoints as requested..."
    Write-Info "Configuring VNet and Private Endpoints..."
    
    # Check if VNet exists
    $ErrorActionPreference = 'SilentlyContinue'
    $vnetExists = az network vnet show --name "$VNET_NAME" --resource-group "$RESOURCE_GROUP" 2>&1
    $ErrorActionPreference = 'Stop'
    
    if ($LASTEXITCODE -ne 0) {
        Write-Info "Creating VNet: $VNET_NAME"
        az network vnet create `
            --name "$VNET_NAME" `
            --resource-group "$RESOURCE_GROUP" `
            --location "$LOCATION" `
            --address-prefix "10.0.0.0/16" `
            --output none | Out-Null
        Write-Success "VNet created: $VNET_NAME"
    } else {
        Write-Success "Using existing VNet: $VNET_NAME"
    }
    
    # Check if subnet exists
    $ErrorActionPreference = 'SilentlyContinue'
    $subnetExists = az network vnet subnet show --vnet-name "$VNET_NAME" --name "$SUBNET_NAME" --resource-group "$RESOURCE_GROUP" 2>&1
    $ErrorActionPreference = 'Stop'
    
    if ($LASTEXITCODE -ne 0) {
        Write-Info "Creating subnet: $SUBNET_NAME"
        az network vnet subnet create `
            --vnet-name "$VNET_NAME" `
            --name "$SUBNET_NAME" `
            --resource-group "$RESOURCE_GROUP" `
            --address-prefix "10.0.1.0/24" `
            --output none | Out-Null
        Write-Success "Subnet created: $SUBNET_NAME"
    } else {
        Write-Success "Using existing subnet: $SUBNET_NAME"
    }
    
    # Configure VNet integration for Function App (check if already configured)
    Write-Info "Configuring VNet integration for Function App..."
    $ErrorActionPreference = 'SilentlyContinue'
    $funcVnetCheck = az functionapp vnet-integration list --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>&1
    $ErrorActionPreference = 'Stop'
    
    if ([string]::IsNullOrWhiteSpace($funcVnetCheck)) {
        az functionapp vnet-integration add `
            --name "$FUNCTION_APP_NAME" `
            --resource-group "$RESOURCE_GROUP" `
            --vnet "$VNET_NAME" `
            --subnet "$SUBNET_NAME" `
            --output none 2>&1 | Out-Null
        Write-Success "VNet integration configured for Function App"
    } else {
        Write-Success "VNet integration already configured for Function App"
    }
    
    # Configure VNet integration for Web App (check if already configured)
    Write-Info "Configuring VNet integration for Web App..."
    $ErrorActionPreference = 'SilentlyContinue'
    $webVnetCheck = az webapp vnet-integration list --name "$WEB_APP_NAME" --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>&1
    $ErrorActionPreference = 'Stop'
    
    if ([string]::IsNullOrWhiteSpace($webVnetCheck)) {
        az webapp vnet-integration add `
            --name "$WEB_APP_NAME" `
            --resource-group "$RESOURCE_GROUP" `
            --vnet "$VNET_NAME" `
            --subnet "$SUBNET_NAME" `
            --output none 2>&1 | Out-Null
        Write-Success "VNet integration configured for Web App"
    } else {
        Write-Success "VNet integration already configured for Web App"
    }
    
    # Create or use existing private endpoint for Function App
    Write-Info "Configuring private endpoint for Function App..."
    $funcPeName = "$FUNCTION_APP_NAME-pe"
    $ErrorActionPreference = 'SilentlyContinue'
    $funcPeExists = az network private-endpoint show --name "$funcPeName" --resource-group "$RESOURCE_GROUP" --query id -o tsv 2>&1
    $ErrorActionPreference = 'Stop'
    
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($funcPeExists)) {
        # Get Function App resource ID
        $ErrorActionPreference = 'SilentlyContinue'
        $FUNC_APP_ID = az functionapp show --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP" --query id -o tsv 2>&1
        $ErrorActionPreference = 'Stop'
        
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($FUNC_APP_ID)) {
            az network private-endpoint create `
                --name "$funcPeName" `
                --resource-group "$RESOURCE_GROUP" `
                --vnet-name "$VNET_NAME" `
                --subnet "$SUBNET_NAME" `
                --private-connection-resource-id "$FUNC_APP_ID" `
                --group-id "sites" `
                --connection-name "$FUNCTION_APP_NAME-connection" `
                --output none 2>&1 | Out-Null
            Write-Success "Private endpoint created for Function App"
        } else {
            Write-Warning "Could not create private endpoint for Function App. Function App may not exist yet."
        }
    } else {
        Write-Success "Using existing private endpoint for Function App: $funcPeName"
    }
    
    # Create or use existing private endpoint for Web App
    Write-Info "Configuring private endpoint for Web App..."
    $webPeName = "$WEB_APP_NAME-pe"
    $ErrorActionPreference = 'SilentlyContinue'
    $webPeExists = az network private-endpoint show --name "$webPeName" --resource-group "$RESOURCE_GROUP" --query id -o tsv 2>&1
    $ErrorActionPreference = 'Stop'
    
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($webPeExists)) {
        # Get Web App resource ID
        $ErrorActionPreference = 'SilentlyContinue'
        $WEB_APP_ID = az webapp show --name "$WEB_APP_NAME" --resource-group "$RESOURCE_GROUP" --query id -o tsv 2>&1
        $ErrorActionPreference = 'Stop'
        
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($WEB_APP_ID)) {
            az network private-endpoint create `
                --name "$webPeName" `
                --resource-group "$RESOURCE_GROUP" `
                --vnet-name "$VNET_NAME" `
                --subnet "$SUBNET_NAME" `
                --private-connection-resource-id "$WEB_APP_ID" `
                --group-id "sites" `
                --connection-name "$WEB_APP_NAME-connection" `
                --output none 2>&1 | Out-Null
            Write-Success "Private endpoint created for Web App"
        } else {
            Write-Warning "Could not create private endpoint for Web App. Web App may not exist yet."
        }
    } else {
        Write-Success "Using existing private endpoint for Web App: $webPeName"
    }
    
    # Link Private DNS Zone to VNet (if DNS zone was created)
    if (-not [string]::IsNullOrWhiteSpace($PRIVATE_DNS_ZONE_NAME) -and $PRIVATE_DNS_CHOICE -ne "skip") {
        Write-Info "Linking Private DNS Zone to VNet..."
        $ErrorActionPreference = 'SilentlyContinue'
        $dnsLinkExists = az network private-dns link vnet show --name "$VNET_NAME-link" --zone-name "$PRIVATE_DNS_ZONE_NAME" --resource-group "$RESOURCE_GROUP" 2>&1
        $ErrorActionPreference = 'Stop'
        
        if ($LASTEXITCODE -ne 0) {
            az network private-dns link vnet create `
                --name "$VNET_NAME-link" `
                --zone-name "$PRIVATE_DNS_ZONE_NAME" `
                --resource-group "$RESOURCE_GROUP" `
                --virtual-network "$VNET_NAME" `
                --registration-enabled false `
                --output none | Out-Null
            Write-Success "Private DNS Zone linked to VNet"
        } else {
            Write-Success "Private DNS Zone already linked to VNet"
        }
    }
    
    Write-Success "Private endpoint configuration complete!"
} else {
    Write-Info "Skipping private endpoint configuration (can be configured later)"
}

Write-Success "Resources setup complete!"
Write-Info "Next: Run deploy-functions.ps1 to deploy backend code"

