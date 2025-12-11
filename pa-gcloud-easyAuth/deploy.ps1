# PA Environment Deployment Script (PowerShell)
# Interactive deployment script for PA's Azure dev environment
#
# BAKED-IN FIXES (as of latest update):
# - SPA platform configuration using Graph API (prevents MSAL login errors)
# - Managed identity for Function App with Key Vault access
# - Reliable dependency installation using Azure Functions Core Tools
# - SharePoint permissions configuration support
# - Automatic SPA platform verification after deployment
# - Comprehensive next steps with fix scripts

$ErrorActionPreference = "Stop"

# Colors for output
function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Blue
}

function Write-Success {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

# Check prerequisites
function Test-Prerequisites {
    Write-Info "Checking prerequisites..."
    
    # Check Azure CLI
    try {
        $azVersion = az version 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Azure CLI not found"
        }
    } catch {
        Write-Error "Azure CLI is not installed. Please install it first."
        exit 1
    }
    
    # Check if logged in
    try {
        $account = az account show 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Not logged in"
        }
    } catch {
        Write-Error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    }
    
    Write-Success "Prerequisites check passed"
}

# Search for existing resources
function Search-ResourceGroups {
    try {
        $ErrorActionPreference = 'SilentlyContinue'
        $output = az group list --query "[].{Name:name}" -o json 2>&1
        $ErrorActionPreference = 'Stop'
        
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($output)) {
            try {
                $rgsObjects = $output | ConvertFrom-Json
                if ($rgsObjects) {
                    $rgs = @()
                    # Handle both single object and array
                    if ($rgsObjects -is [System.Array]) {
                        foreach ($obj in $rgsObjects) {
                            if ($obj.Name -and $obj.Name.Length -gt 1) {
                                $rgs += $obj.Name
                            }
                        }
                    } else {
                        if ($rgsObjects.Name -and $rgsObjects.Name.Length -gt 1) {
                            $rgs += $rgsObjects.Name
                        }
                    }
                    if ($rgs.Count -gt 0) {
                        return $rgs
                    }
                }
            } catch {
                # Try direct string parsing as fallback
                $lines = $output -split "`r?`n"
                $rgs = @()
                foreach ($line in $lines) {
                    $line = $line.Trim()
                    # Remove JSON brackets and quotes
                    $line = $line -replace '^\[|\]$|"|,', ''
                    if ($line -and $line.Length -gt 1 -and $line -ne "Name") {
                        $rgs += $line
                    }
                }
                if ($rgs.Count -gt 0) {
                    return $rgs
                }
            }
        }
    } catch {
        Write-Warning "Could not search for resource groups: $_"
    }
    return @()
}

function Search-FunctionApps {
    param([string]$ResourceGroup)
    try {
        $apps = az functionapp list --resource-group $ResourceGroup --query "[].name" -o tsv 2>&1
        if ($LASTEXITCODE -eq 0 -and $apps) {
            return $apps -split "`n" | Where-Object { $_ -ne "" }
        }
    } catch {}
    return @()
}

function Search-WebApps {
    param([string]$ResourceGroup)
    try {
        $apps = az webapp list --resource-group $ResourceGroup --query "[].name" -o tsv 2>&1
        if ($LASTEXITCODE -eq 0 -and $apps) {
            return $apps -split "`n" | Where-Object { $_ -ne "" }
        }
    } catch {}
    return @()
}

function Search-StorageAccounts {
    param([string]$ResourceGroup)
    try {
        $accounts = az storage account list --resource-group $ResourceGroup --query "[].name" -o tsv 2>&1
        if ($LASTEXITCODE -eq 0 -and $accounts) {
            return $accounts -split "`n" | Where-Object { $_ -ne "" }
        }
    } catch {}
    return @()
}

function Search-PrivateDnsZones {
    param([string]$ResourceGroup)
    try {
        $zones = az network private-dns zone list --resource-group $ResourceGroup --query "[].name" -o tsv 2>&1
        if ($LASTEXITCODE -eq 0 -and $zones) {
            return $zones -split "`n" | Where-Object { $_ -ne "" }
        }
    } catch {}
    return @()
}

function Search-AppInsights {
    param([string]$ResourceGroup)
    try {
        $insights = az resource list --resource-group $ResourceGroup --resource-type "Microsoft.Insights/components" --query "[].name" -o tsv 2>&1
        if ($LASTEXITCODE -eq 0 -and $insights) {
            return $insights -split "`n" | Where-Object { $_ -ne "" }
        }
    } catch {}
    return @()
}

function Search-VNets {
    param([string]$ResourceGroup)
    try {
        $vnets = az network vnet list --resource-group $ResourceGroup --query "[].name" -o tsv 2>&1
        if ($LASTEXITCODE -eq 0 -and $vnets) {
            return $vnets -split "`n" | Where-Object { $_ -ne "" }
        }
    } catch {}
    return @()
}

function Search-Subnets {
    param([string]$VNetName, [string]$ResourceGroup)
    try {
        $subnets = az network vnet subnet list --vnet-name $VNetName --resource-group $ResourceGroup --query "[].name" -o tsv 2>&1
        if ($LASTEXITCODE -eq 0 -and $subnets) {
            return $subnets -split "`n" | Where-Object { $_ -ne "" }
        }
    } catch {}
    return @()
}

function Search-KeyVaults {
    param([string]$ResourceGroup)
    $ErrorActionPreference = 'SilentlyContinue'
    try {
        # Key Vaults can be listed by resource group or across all subscriptions
        # Try resource group first, then all if needed
        $kvList = az keyvault list --resource-group $ResourceGroup --query "[].name" -o tsv 2>&1
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($kvList)) {
            $results = $kvList -split "`n" | Where-Object { $_ -ne "" -and $_ -ne $null }
            if ($results.Count -gt 0) {
                return $results
            }
        }
        
        # If no results in resource group, try listing all and filter by resource group
        $allKVs = az keyvault list --query "[?resourceGroup=='$ResourceGroup'].name" -o tsv 2>&1
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($allKVs)) {
            $results = $allKVs -split "`n" | Where-Object { $_ -ne "" -and $_ -ne $null }
            if ($results.Count -gt 0) {
                return $results
            }
        }
    } catch {
        Write-Warning "Error searching for Key Vaults: $_"
    }
    $ErrorActionPreference = 'Stop'
    return @()
}

function Search-ContainerRegistries {
    param([string]$ResourceGroup)
    $ErrorActionPreference = 'SilentlyContinue'
    try {
        # ACR names are globally unique, so search in resource group first
        $acrs = az acr list --resource-group $ResourceGroup --query "[].name" -o tsv 2>&1
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($acrs)) {
            $results = @()
            foreach ($line in ($acrs -split "`n")) {
                $line = $line.Trim()
                # Filter: must be 5-50 chars, alphanumeric lowercase only, not empty
                if ($line -and $line.Length -ge 5 -and $line.Length -le 50 -and $line -match '^[a-z0-9]+$') {
                    $results += $line
                }
            }
            if ($results.Count -gt 0) {
                return $results
            }
        }
        
        # Also search across all subscriptions (ACR names are globally unique)
        $allACRs = az acr list --query "[].name" -o tsv 2>&1
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($allACRs)) {
            $results = @()
            foreach ($line in ($allACRs -split "`n")) {
                $line = $line.Trim()
                # Filter: must be 5-50 chars, alphanumeric lowercase only, not empty
                if ($line -and $line.Length -ge 5 -and $line.Length -le 50 -and $line -match '^[a-z0-9]+$') {
                    $results += $line
                }
            }
            if ($results.Count -gt 0) {
                return $results
            }
        }
    } catch {
        Write-Warning "Error searching for Container Registries: $_"
    }
    $ErrorActionPreference = 'Stop'
    return @()
}

# Prompt for resource choice: existing, new, or skip
function Get-ResourceChoice {
    param(
        [string]$ResourceType,
        [string]$DefaultName,
        [string]$ResourceGroup,
        [scriptblock]$SearchFunction
    )
    
    Write-Host ""
    Write-Info "Configuring $ResourceType"
    
    # Search for existing resources
    $existingResources = @()
    if (-not [string]::IsNullOrWhiteSpace($ResourceGroup)) {
        try {
            $rgCheck = az group show --name $ResourceGroup 2>&1
            if ($LASTEXITCODE -eq 0) {
                $existingResources = & $SearchFunction $ResourceGroup
            }
        } catch {}
    }
    
    # Build options
    $options = @()
    $optionCount = 0
    
    if ($existingResources.Count -gt 0) {
        Write-Host "Existing $ResourceType resources found:"
        foreach ($resource in $existingResources) {
            Write-Host "  [$optionCount] Use existing: $resource"
            $options += "existing:$resource"
            $optionCount++
        }
    }
    
    Write-Host "  [$optionCount] Create new"
    $options += "new"
    $optionCount++
    
    Write-Host "  [$optionCount] Skip"
    $options += "skip"
    
    # Get user choice
    $choice = Read-Host "Select option (0-$optionCount) [0]"
    if ([string]::IsNullOrWhiteSpace($choice)) {
        $choice = 0
    }
    
    if ($choice -match '^\d+$' -and [int]$choice -le $optionCount) {
        $selected = $options[[int]$choice]
        
        if ($selected -like "existing:*") {
            return "existing:$($selected -replace 'existing:','')"
        } elseif ($selected -eq "new") {
            $name = Read-Host "Enter $ResourceType name [$DefaultName]"
            if ([string]::IsNullOrWhiteSpace($name)) {
                $name = $DefaultName
            }
            return "new:$name"
        } else {
            return "skip:"
        }
    } else {
        Write-Warning "Invalid choice, defaulting to create new"
        $name = Read-Host "Enter $ResourceType name [$DefaultName]"
        if ([string]::IsNullOrWhiteSpace($name)) {
            $name = $DefaultName
        }
        return "new:$name"
    }
}

# Prompt for resource name with option to select existing
function Get-ResourceName {
    param(
        [string]$ResourceType,
        [string]$DefaultName,
        [string[]]$ExistingResources = @()
    )
    
    Write-Host ""
    Write-Info "Configuring $ResourceType"
    
    if ($ExistingResources.Count -gt 0) {
        Write-Host "Existing resources found:"
        for ($i = 0; $i -lt $ExistingResources.Count; $i++) {
            Write-Host "  [$i] $($ExistingResources[$i])"
        }
        Write-Host "  [n] Create new"
        $choice = Read-Host "Select option (0-$($ExistingResources.Count - 1)) or 'n' for new"
        
        if ($choice -match '^\d+$' -and [int]$choice -lt $ExistingResources.Count) {
            return $ExistingResources[[int]$choice]
        }
    }
    
    $name = Read-Host "Enter $ResourceType name [$DefaultName]"
    if ([string]::IsNullOrWhiteSpace($name)) {
        return $DefaultName
    }
    return $name
}

# Main deployment function
function Start-Deployment {
    Write-Info "Starting PA Environment Deployment"
    Write-Info "This script will deploy the G-Cloud 15 automation tool to PA's Azure dev environment"
    Write-Host ""
    
    Test-Prerequisites
    
    # Get subscription info
    $subscription = az account show | ConvertFrom-Json
    $SUBSCRIPTION_ID = $subscription.id
    $SUBSCRIPTION_NAME = $subscription.name
    Write-Info "Using subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"
    
    # Generate random suffix EARLY (before any prompts) for globally unique names
    Write-Info "Generating random suffix for globally unique resource names..."
    $randomSuffix = -join ((48..57) + (97..122) | Get-Random -Count 6 | ForEach-Object {[char]$_})
    Write-Info "Random suffix: $randomSuffix (will be added to all globally unique resource names)"
    Write-Info ""
    
    # Prompt for resource group
    Write-Info "Step 1: Resource Group Configuration"
    
    # Search for existing resource groups
    $existingRGs = Search-ResourceGroups
    
    # Filter out invalid entries (single characters, empty, etc.)
    $validRGs = $existingRGs | Where-Object { $_ -and $_.Trim().Length -gt 1 }
    
    if ($validRGs.Count -gt 0) {
        Write-Host "Existing resource groups found:"
        for ($i = 0; $i -lt $validRGs.Count; $i++) {
            $rgName = $validRGs[$i]
            Write-Host "  [$i] $rgName"
        }
        Write-Host "  [n] Create new"
        $rgChoice = Read-Host "Select option (0-$($validRGs.Count - 1)) or 'n' for new"
        
        if ($rgChoice -match '^\d+$' -and [int]$rgChoice -lt $validRGs.Count) {
            $RESOURCE_GROUP = $validRGs[[int]$rgChoice]
            Write-Success "Using existing resource group: $RESOURCE_GROUP"
            # Get location from existing RG
            $LOCATION = az group show --name $RESOURCE_GROUP --query location -o tsv
        } else {
            $RESOURCE_GROUP = Read-Host "Enter resource group name [pa-gcloud15-rg]"
            if ([string]::IsNullOrWhiteSpace($RESOURCE_GROUP)) {
                $RESOURCE_GROUP = "pa-gcloud15-rg"
            }
            
            # Check if name already exists (suppress errors)
            $ErrorActionPreference = 'SilentlyContinue'
            $rgCheck = az group show --name $RESOURCE_GROUP 2>&1
            $ErrorActionPreference = 'Stop'
            if ($LASTEXITCODE -eq 0) {
                Write-Error "Resource group '$RESOURCE_GROUP' already exists. Please choose a different name."
                exit 1
            }
            
            $LOCATION = Read-Host "Enter location for resource group [uksouth]"
            if ([string]::IsNullOrWhiteSpace($LOCATION)) {
                $LOCATION = "uksouth"
            }
            Write-Info "Creating resource group '$RESOURCE_GROUP' in '$LOCATION'..."
            az group create --name $RESOURCE_GROUP --location $LOCATION | Out-Null
            Write-Success "Resource group created"
        }
    } else {
        $RESOURCE_GROUP = Read-Host "Enter resource group name [pa-gcloud15-rg]"
        if ([string]::IsNullOrWhiteSpace($RESOURCE_GROUP)) {
            $RESOURCE_GROUP = "pa-gcloud15-rg"
        }
        
        # Check if resource group exists (suppress errors)
        $ErrorActionPreference = 'SilentlyContinue'
        $rgCheck = az group show --name $RESOURCE_GROUP 2>&1
        $ErrorActionPreference = 'Stop'
        if ($LASTEXITCODE -eq 0) {
            Write-Warning "Resource group '$RESOURCE_GROUP' already exists"
            $useExisting = Read-Host "Use existing resource group? (y/n) [y]"
            if ([string]::IsNullOrWhiteSpace($useExisting) -or $useExisting -ne "n") {
                # Use existing - get location
                $LOCATION = az group show --name $RESOURCE_GROUP --query location -o tsv
            } else {
                Write-Error "Please choose a different resource group name"
                exit 1
            }
        } else {
            $LOCATION = Read-Host "Enter location for resource group [uksouth]"
            if ([string]::IsNullOrWhiteSpace($LOCATION)) {
                $LOCATION = "uksouth"
            }
            Write-Info "Creating resource group '$RESOURCE_GROUP' in '$LOCATION'..."
            az group create --name $RESOURCE_GROUP --location $LOCATION | Out-Null
            Write-Success "Resource group created"
        }
    }
    
    # Prompt for Function App name
    Write-Info "Step 2: Function App Configuration"
    $existingFunctionApps = Search-FunctionApps -ResourceGroup $RESOURCE_GROUP
    
    if ($existingFunctionApps.Count -gt 0) {
        Write-Host "Existing Function Apps found in resource group:"
        for ($i = 0; $i -lt $existingFunctionApps.Count; $i++) {
            Write-Host "  [$i] $($existingFunctionApps[$i])"
        }
        Write-Host "  [n] Create new"
        $faChoice = Read-Host "Select option (0-$($existingFunctionApps.Count - 1)) or 'n' for new"
        
        if ($faChoice -match '^\d+$' -and [int]$faChoice -lt $existingFunctionApps.Count) {
            $FUNCTION_APP_NAME = $existingFunctionApps[[int]$faChoice]
            Write-Success "Using existing Function App: $FUNCTION_APP_NAME"
        } else {
            $defaultFuncName = "pa-gcloud15-api-$randomSuffix"
            $FUNCTION_APP_NAME = Read-Host "Enter Function App name for backend API [$defaultFuncName]"
            if ([string]::IsNullOrWhiteSpace($FUNCTION_APP_NAME)) {
                $FUNCTION_APP_NAME = $defaultFuncName
            }
            # Trim and validate
            $FUNCTION_APP_NAME = $FUNCTION_APP_NAME.Trim()
            # Check if suffix already added, if not add it
            if (-not $FUNCTION_APP_NAME.EndsWith($randomSuffix)) {
                $baseFuncName = $FUNCTION_APP_NAME -replace '[^a-zA-Z0-9-]', ''
                $maxBaseLength = 54
                if ($baseFuncName.Length -gt $maxBaseLength) {
                    $baseFuncName = $baseFuncName.Substring(0, $maxBaseLength)
                }
                $FUNCTION_APP_NAME = $baseFuncName + "-" + $randomSuffix
            }
            if ($FUNCTION_APP_NAME.Length -lt 3) {
                Write-Warning "Function App name too short, using default: $defaultFuncName"
                $FUNCTION_APP_NAME = $defaultFuncName
            }
        }
    } else {
        $defaultFuncName = "pa-gcloud15-api-$randomSuffix"
        $FUNCTION_APP_NAME = Read-Host "Enter Function App name for backend API [$defaultFuncName]"
        if ([string]::IsNullOrWhiteSpace($FUNCTION_APP_NAME)) {
            $FUNCTION_APP_NAME = $defaultFuncName
        }
        # Trim and validate
        $FUNCTION_APP_NAME = $FUNCTION_APP_NAME.Trim()
        # Check if suffix already added, if not add it
        if (-not $FUNCTION_APP_NAME.EndsWith($randomSuffix)) {
            $baseFuncName = $FUNCTION_APP_NAME -replace '[^a-zA-Z0-9-]', ''
            $maxBaseLength = 54
            if ($baseFuncName.Length -gt $maxBaseLength) {
                $baseFuncName = $baseFuncName.Substring(0, $maxBaseLength)
            }
            $FUNCTION_APP_NAME = $baseFuncName + "-" + $randomSuffix
        }
        if ($FUNCTION_APP_NAME.Length -lt 3) {
            Write-Warning "Function App name too short, using default: $defaultFuncName"
            $FUNCTION_APP_NAME = $defaultFuncName
        }
    }
    
    # Prompt for Static Web App / App Service name
    Write-Info "Step 3: Frontend Configuration"
    $existingWebApps = Search-WebApps -ResourceGroup $RESOURCE_GROUP
    
    if ($existingWebApps.Count -gt 0) {
        Write-Host "Existing Web Apps found in resource group:"
        for ($i = 0; $i -lt $existingWebApps.Count; $i++) {
            Write-Host "  [$i] $($existingWebApps[$i])"
        }
        Write-Host "  [n] Create new"
        $waChoice = Read-Host "Select option (0-$($existingWebApps.Count - 1)) or 'n' for new"
        
        if ($waChoice -match '^\d+$' -and [int]$waChoice -lt $existingWebApps.Count) {
            $WEB_APP_NAME = $existingWebApps[[int]$waChoice]
            Write-Success "Using existing Web App: $WEB_APP_NAME"
        } else {
            $defaultWebName = "pa-gcloud15-web-$randomSuffix"
            $WEB_APP_NAME = Read-Host "Enter Static Web App name [$defaultWebName]"
            if ([string]::IsNullOrWhiteSpace($WEB_APP_NAME)) {
                $WEB_APP_NAME = $defaultWebName
            }
            # Trim and validate
            $WEB_APP_NAME = $WEB_APP_NAME.Trim()
            # Check if suffix already added, if not add it
            if (-not $WEB_APP_NAME.EndsWith($randomSuffix)) {
                $baseWebName = $WEB_APP_NAME -replace '[^a-zA-Z0-9-]', ''
                $maxBaseLength = 54
                if ($baseWebName.Length -gt $maxBaseLength) {
                    $baseWebName = $baseWebName.Substring(0, $maxBaseLength)
                }
                $WEB_APP_NAME = $baseWebName + "-" + $randomSuffix
            }
            if ($WEB_APP_NAME.Length -lt 3) {
                Write-Warning "Web App name too short, using default: $defaultWebName"
                $WEB_APP_NAME = $defaultWebName
            }
        }
    } else {
        $defaultWebName = "pa-gcloud15-web-$randomSuffix"
        $WEB_APP_NAME = Read-Host "Enter Static Web App name [$defaultWebName]"
        if ([string]::IsNullOrWhiteSpace($WEB_APP_NAME)) {
            $WEB_APP_NAME = $defaultWebName
        }
        # Check if suffix already added, if not add it
        if (-not $WEB_APP_NAME.EndsWith($randomSuffix)) {
            $baseWebName = $WEB_APP_NAME -replace '[^a-zA-Z0-9-]', ''
            $maxBaseLength = 54
            if ($baseWebName.Length -gt $maxBaseLength) {
                $baseWebName = $baseWebName.Substring(0, $maxBaseLength)
            }
            $WEB_APP_NAME = $baseWebName + "-" + $randomSuffix
        }
        # Trim and validate
        $WEB_APP_NAME = $WEB_APP_NAME.Trim()
        if ($WEB_APP_NAME.Length -lt 3) {
            Write-Warning "Web App name too short, using default: pa-gcloud15-web"
            $WEB_APP_NAME = "pa-gcloud15-web"
        }
    }
    
    # Prompt for Key Vault
    Write-Info "Step 4: Key Vault Configuration"
    
    # Search for existing Key Vaults in the resource group
    # Note: az keyvault list doesn't support --resource-group, so we list all and filter
    $existingKeyVaults = @()
    $ErrorActionPreference = 'SilentlyContinue'
    
    # List all Key Vaults and filter by resource group using query
    $kvJson = az keyvault list --query "[?resourceGroup=='$RESOURCE_GROUP']" -o json 2>&1
    $ErrorActionPreference = 'Stop'
    
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($kvJson)) {
        try {
            $kvObjects = $kvJson | ConvertFrom-Json
            if ($kvObjects -and $kvObjects.Count -gt 0) {
                $existingKeyVaults = $kvObjects | ForEach-Object { $_.name } | Where-Object { $_ -ne $null }
            }
        } catch {
            Write-Warning "Could not parse Key Vault list: $_"
        }
    }
    
    if ($existingKeyVaults -and $existingKeyVaults.Count -gt 0) {
        Write-Host "Existing Key Vaults found in resource group:"
        for ($i = 0; $i -lt $existingKeyVaults.Count; $i++) {
            Write-Host "  [$i] $($existingKeyVaults[$i])"
        }
        Write-Host "  [n] Create new"
        $kvChoice = Read-Host "Select option (0-$($existingKeyVaults.Count - 1)) or 'n' for new"
        
        if ($kvChoice -match '^\d+$' -and [int]$kvChoice -lt $existingKeyVaults.Count) {
            $KEY_VAULT_NAME = $existingKeyVaults[[int]$kvChoice]
            Write-Success "Using existing Key Vault: $KEY_VAULT_NAME"
        } else {
            $defaultKvName = "pa-gcloud15-kv-$randomSuffix"
            $KEY_VAULT_NAME = Read-Host "Enter Key Vault name [$defaultKvName]"
            if ([string]::IsNullOrWhiteSpace($KEY_VAULT_NAME)) {
                $KEY_VAULT_NAME = $defaultKvName
            }
            # Trim and validate
            $KEY_VAULT_NAME = $KEY_VAULT_NAME.Trim()
            # Check if suffix already added, if not add it
            if (-not $KEY_VAULT_NAME.EndsWith($randomSuffix)) {
                $baseKvName = $KEY_VAULT_NAME -replace '[^a-zA-Z0-9-]', ''
                $maxBaseLength = 17  # Key Vault max is 24, suffix is 7 chars (including hyphen)
                if ($baseKvName.Length -gt $maxBaseLength) {
                    $baseKvName = $baseKvName.Substring(0, $maxBaseLength)
                }
                $KEY_VAULT_NAME = $baseKvName + "-" + $randomSuffix
            }
            if ($KEY_VAULT_NAME.Length -lt 3) {
                Write-Warning "Key Vault name too short, using default: $defaultKvName"
                $KEY_VAULT_NAME = $defaultKvName
            }
            if ($KEY_VAULT_NAME.Length -gt 24) {
                # Truncate if too long
                $KEY_VAULT_NAME = $KEY_VAULT_NAME.Substring(0, 17) + "-" + $randomSuffix
            }
        }
    } else {
        $defaultKvName = "pa-gcloud15-kv-$randomSuffix"
        $KEY_VAULT_NAME = Read-Host "Enter Key Vault name [$defaultKvName]"
        if ([string]::IsNullOrWhiteSpace($KEY_VAULT_NAME)) {
            $KEY_VAULT_NAME = $defaultKvName
        }
        # Trim and validate
        $KEY_VAULT_NAME = $KEY_VAULT_NAME.Trim()
        # Check if suffix already added, if not add it
        if (-not $KEY_VAULT_NAME.EndsWith($randomSuffix)) {
            $baseKvName = $KEY_VAULT_NAME -replace '[^a-zA-Z0-9-]', ''
            $maxBaseLength = 17  # Key Vault max is 24, suffix is 7 chars (including hyphen)
            if ($baseKvName.Length -gt $maxBaseLength) {
                $baseKvName = $baseKvName.Substring(0, $maxBaseLength)
            }
            $KEY_VAULT_NAME = $baseKvName + "-" + $randomSuffix
        }
        if ($KEY_VAULT_NAME.Length -lt 3) {
            Write-Warning "Key Vault name too short, using default: $defaultKvName"
            $KEY_VAULT_NAME = $defaultKvName
        }
        if ($KEY_VAULT_NAME.Length -gt 24) {
            # Truncate if too long
            $KEY_VAULT_NAME = $KEY_VAULT_NAME.Substring(0, 17) + "-" + $randomSuffix
        }
    }
    
    # Prompt for SharePoint configuration
    Write-Info "Step 5: SharePoint Configuration"
    Write-Host "Enter SharePoint site URL."
    Write-Host "  Examples:"
    Write-Host "    - Site URL: https://conmacdev.sharepoint.com/sites/Gcloud"
    Write-Host "    - Sharing link: https://conmacdev.sharepoint.com/:u:/s/Gcloud/..."
    Write-Host ""
    $SHAREPOINT_SITE_URL = Read-Host "Enter SharePoint site URL or sharing link"
    
    if (-not [string]::IsNullOrWhiteSpace($SHAREPOINT_SITE_URL)) {
        # Handle sharing links (format: https://domain.sharepoint.com/:u:/s/SiteName/ID?e=token)
        if ($SHAREPOINT_SITE_URL -match '^https://([^/]+)\.sharepoint\.com/:u:/s/([^/]+)/([^?]+)') {
            $domain = $matches[1]
            $siteName = $matches[2]
            $siteIdFromUrl = $matches[3]
            
            Write-Info "Detected sharing link format. Extracting information..."
            # Convert sharing link to proper site URL
            $SHAREPOINT_SITE_URL = "https://$domain.sharepoint.com/sites/$siteName"
            Write-Info "Converted to site URL: $SHAREPOINT_SITE_URL"
            
            # Extract site ID from sharing link (remove query parameters if present)
            $SHAREPOINT_SITE_ID = $siteIdFromUrl -replace '\?.*$', ''
            Write-Info "Extracted Site ID from sharing link: $SHAREPOINT_SITE_ID"
        }
        # If not a sharing link, use as-is
        
        # Prompt for site ID if not already extracted
        if ([string]::IsNullOrWhiteSpace($SHAREPOINT_SITE_ID)) {
            $rawSiteId = Read-Host "Enter SharePoint site ID (leave empty to auto-detect)"
            
            # Clean site ID immediately if provided (remove query parameters and whitespace)
            if (-not [string]::IsNullOrWhiteSpace($rawSiteId)) {
                $SHAREPOINT_SITE_ID = ($rawSiteId -replace '\?.*$', '').Trim()
                if ($rawSiteId -ne $SHAREPOINT_SITE_ID) {
                    Write-Info "Cleaned Site ID (removed query parameters): $SHAREPOINT_SITE_ID"
                }
            }
        }
        
        # Auto-detect site ID if not provided
        if ([string]::IsNullOrWhiteSpace($SHAREPOINT_SITE_ID)) {
            Write-Info "Attempting to auto-detect SharePoint site ID..."
            try {
                $siteUrl = $SHAREPOINT_SITE_URL -replace '^https://', ''
                $siteId = az rest --method GET `
                    --uri "https://graph.microsoft.com/v1.0/sites/$siteUrl" `
                    --query "id" -o tsv 2>&1
                
                if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($siteId)) {
                    $SHAREPOINT_SITE_ID = $siteId
                    Write-Success "Auto-detected Site ID: $SHAREPOINT_SITE_ID"
                } else {
                    Write-Warning "Could not auto-detect Site ID. You can find it later in SharePoint site settings."
                    $SHAREPOINT_SITE_ID = ""
                }
            } catch {
                Write-Warning "Could not auto-detect Site ID. You can find it later in SharePoint site settings."
                $SHAREPOINT_SITE_ID = ""
            }
        }
    } else {
        $SHAREPOINT_SITE_ID = ""
    }
    
    # Prompt for App Registration
    Write-Info "Step 6: App Registration Configuration"
    
    # Search for existing App Registrations
    function Search-AppRegistrations {
        param([string]$Filter = "")
        $ErrorActionPreference = 'SilentlyContinue'
        $appsJson = az ad app list --query "[].{DisplayName:displayName, AppId:appId}" -o json 2>&1
        $ErrorActionPreference = 'Stop'
        
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($appsJson)) {
            try {
                $apps = $appsJson | ConvertFrom-Json
                if ($apps -and $apps.Count -gt 0) {
                    $appNames = @()
                    foreach ($app in $apps) {
                        if ($app.DisplayName) {
                            if ([string]::IsNullOrWhiteSpace($Filter) -or $app.DisplayName -like "*$Filter*") {
                                $appNames += $app.DisplayName
                            }
                        }
                    }
                    return $appNames
                }
            } catch {
                Write-Warning "Could not parse App Registration list: $_"
            }
        }
        return @()
    }
    
    # Search for all App Registrations (no filter to see all)
    $existingAppRegs = Search-AppRegistrations -Filter ""
    
    # Also try a more specific search
    if ($existingAppRegs.Count -eq 0) {
        $existingAppRegs = Search-AppRegistrations -Filter "gcloud"
    }
    
    if ($existingAppRegs.Count -gt 0) {
        Write-Host "Existing App Registrations found:"
        for ($i = 0; $i -lt $existingAppRegs.Count; $i++) {
            Write-Host "  [$i] $($existingAppRegs[$i])"
        }
        Write-Host "  [n] Create new"
        $arChoice = Read-Host "Select option (0-$($existingAppRegs.Count - 1)) or 'n' for new"
        
        if ($arChoice -match '^\d+$' -and [int]$arChoice -lt $existingAppRegs.Count) {
            $APP_REGISTRATION_NAME = $existingAppRegs[[int]$arChoice]
            Write-Success "Using existing App Registration: $APP_REGISTRATION_NAME"
        } else {
            $APP_REGISTRATION_NAME = Read-Host "Enter App Registration name [pa-gcloud15-app]"
            if ([string]::IsNullOrWhiteSpace($APP_REGISTRATION_NAME)) {
                $APP_REGISTRATION_NAME = "pa-gcloud15-app"
            }
            # Trim and validate
            $APP_REGISTRATION_NAME = $APP_REGISTRATION_NAME.Trim()
            if ($APP_REGISTRATION_NAME.Length -lt 3) {
                Write-Warning "App Registration name too short, using default: pa-gcloud15-app"
                $APP_REGISTRATION_NAME = "pa-gcloud15-app"
            }
        }
    } else {
        $APP_REGISTRATION_NAME = Read-Host "Enter App Registration name [pa-gcloud15-app]"
        if ([string]::IsNullOrWhiteSpace($APP_REGISTRATION_NAME)) {
            $APP_REGISTRATION_NAME = "pa-gcloud15-app"
        }
        # Trim and validate
        $APP_REGISTRATION_NAME = $APP_REGISTRATION_NAME.Trim()
        if ($APP_REGISTRATION_NAME.Length -lt 3) {
            Write-Warning "App Registration name too short, using default: pa-gcloud15-app"
            $APP_REGISTRATION_NAME = "pa-gcloud15-app"
        }
    }
    
    # ========================================
    # PROMPT FOR ADMIN SECURITY GROUP
    # ========================================
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Info "Step 6.5: Admin Security Group Configuration"
    Write-Info "Admin security group controls who can access the admin dashboard."
    Write-Info "Standard employees will have regular access (no admin dashboard)."
    Write-Host ""  # Blank line for visibility
    
    function Search-SecurityGroups {
        param([string]$Filter = "")
        try {
            $ErrorActionPreference = 'SilentlyContinue'
            $groupsJson = az ad group list --query "[].{DisplayName:displayName, Id:id}" -o json 2>&1
            $exitCode = $LASTEXITCODE
            $ErrorActionPreference = 'Stop'
            
            if ($exitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($groupsJson)) {
            try {
                $groups = $groupsJson | ConvertFrom-Json
                if ($groups -and $groups.Count -gt 0) {
                    $groupNames = @()
                    foreach ($group in $groups) {
                        if ($group.DisplayName) {
                            if ([string]::IsNullOrWhiteSpace($Filter) -or $group.DisplayName -like "*$Filter*") {
                                $groupNames += $group.DisplayName
                            }
                        }
                    }
                    return $groupNames
                }
            } catch {
                Write-Warning "Could not parse security group list: $_"
            }
            }
        } catch {
            Write-Warning "Error searching for security groups: $_"
        }
        return @()
    }
    
    $existingGroups = Search-SecurityGroups -Filter "admin"
    if ($existingGroups.Count -eq 0) {
        $existingGroups = Search-SecurityGroups -Filter "gcloud"
    }
    
    $ADMIN_GROUP_ID = ""
    $ADMIN_GROUP_NAME = ""
    
    # Filter out invalid group names (single chars, null, etc.)
    $validGroups = $existingGroups | Where-Object { $_ -and $_.Length -gt 1 }
    if ($validGroups.Count -gt 0) {
        Write-Host "Existing security groups found:"
        for ($i = 0; $i -lt $validGroups.Count; $i++) {
            Write-Host "  [$i] $($validGroups[$i])"
        }
        Write-Host "  [n] Create new"
        $groupChoice = Read-Host "Select option (0-$($validGroups.Count - 1)) or 'n' for new"
        
        if ($groupChoice -match '^\d+$' -and [int]$groupChoice -lt $validGroups.Count) {
            $ADMIN_GROUP_NAME = $validGroups[[int]$groupChoice]
            Write-Info "Getting group ID for: $ADMIN_GROUP_NAME"
            $ErrorActionPreference = 'SilentlyContinue'
            $groupJson = az ad group list --display-name "$ADMIN_GROUP_NAME" --query "[0].{Id:id}" -o json 2>&1
            $ErrorActionPreference = 'Stop'
            if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($groupJson)) {
                try {
                    $groupObj = $groupJson | ConvertFrom-Json
                    $ADMIN_GROUP_ID = $groupObj.Id
                    Write-Success "Using existing admin group: $ADMIN_GROUP_NAME"
                } catch {
                    Write-Warning "Could not parse group response"
                }
            }
        } else {
            $ADMIN_GROUP_NAME = Read-Host "Enter admin security group name [G-Cloud-Admins]"
            if ([string]::IsNullOrWhiteSpace($ADMIN_GROUP_NAME)) {
                $ADMIN_GROUP_NAME = "G-Cloud-Admins"
            }
        }
    } else {
        $ADMIN_GROUP_NAME = Read-Host "Enter admin security group name [G-Cloud-Admins]"
        if ([string]::IsNullOrWhiteSpace($ADMIN_GROUP_NAME)) {
            $ADMIN_GROUP_NAME = "G-Cloud-Admins"
        }
    }
    
    # Create group if ID not found
    if ([string]::IsNullOrWhiteSpace($ADMIN_GROUP_ID) -and -not [string]::IsNullOrWhiteSpace($ADMIN_GROUP_NAME)) {
        $createGroup = Read-Host "Create admin security group '$ADMIN_GROUP_NAME'? (y/n) [y]"
        if ([string]::IsNullOrWhiteSpace($createGroup) -or $createGroup -eq "y") {
            Write-Info "Creating admin security group: $ADMIN_GROUP_NAME"
            $ErrorActionPreference = 'SilentlyContinue'
            $newGroup = az ad group create --display-name "$ADMIN_GROUP_NAME" --mail-nickname "$($ADMIN_GROUP_NAME -replace ' ', '')" --query "{Id:id}" -o json 2>&1
            $ErrorActionPreference = 'Stop'
            
            if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($newGroup)) {
                try {
                    $groupObj = $newGroup | ConvertFrom-Json
                    $ADMIN_GROUP_ID = $groupObj.Id
                    Write-Success "Admin security group created: $ADMIN_GROUP_NAME ($ADMIN_GROUP_ID)"
                } catch {
                    Write-Warning "Could not parse new group response"
                }
            } else {
                Write-Warning "Could not create admin group. You can create it manually and configure later."
            }
        }
    }
    
    if ([string]::IsNullOrWhiteSpace($ADMIN_GROUP_ID)) {
        Write-Warning "No admin group ID configured. Admin dashboard access will be disabled."
        Write-Info "You can configure this later by running configure-auth.ps1"
    }
    
    # Prompt for Employee Security Group (optional - for standard employee access)
    Write-Info "Step 6.6: Employee Security Group Configuration (Optional)"
    Write-Info "Employee security group is optional. Users not in admin group will have standard employee view."
    Write-Info "You can skip this if you want all non-admin users to have standard access automatically."
    
    $EMPLOYEE_GROUP_ID = ""
    $EMPLOYEE_GROUP_NAME = ""
    
    $configureEmployeeGroup = Read-Host "Configure employee security group? (y/n) [n]"
    if ($configureEmployeeGroup -eq "y") {
        $existingEmployeeGroups = Search-SecurityGroups -Filter "employee"
        if ($existingEmployeeGroups.Count -eq 0) {
            $existingEmployeeGroups = Search-SecurityGroups -Filter "gcloud"
        }
        
        # Filter out invalid group names (single chars, null, etc.)
        $validEmpGroups = $existingEmployeeGroups | Where-Object { $_ -and $_.Length -gt 1 }
        if ($validEmpGroups.Count -gt 0) {
            Write-Host "Existing security groups found:"
            for ($i = 0; $i -lt $validEmpGroups.Count; $i++) {
                Write-Host "  [$i] $($validEmpGroups[$i])"
            }
            Write-Host "  [n] Create new"
            $empGroupChoice = Read-Host "Select option (0-$($validEmpGroups.Count - 1)) or 'n' for new"
            
            if ($empGroupChoice -match '^\d+$' -and [int]$empGroupChoice -lt $validEmpGroups.Count) {
                $EMPLOYEE_GROUP_NAME = $validEmpGroups[[int]$empGroupChoice]
                Write-Info "Getting group ID for: $EMPLOYEE_GROUP_NAME"
                $ErrorActionPreference = 'SilentlyContinue'
                $empGroupJson = az ad group list --display-name "$EMPLOYEE_GROUP_NAME" --query "[0].{Id:id}" -o json 2>&1
                $ErrorActionPreference = 'Stop'
                if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($empGroupJson)) {
                    try {
                        $empGroupObj = $empGroupJson | ConvertFrom-Json
                        $EMPLOYEE_GROUP_ID = $empGroupObj.Id
                        Write-Success "Using existing employee group: $EMPLOYEE_GROUP_NAME"
                    } catch {
                        Write-Warning "Could not parse group response"
                    }
                }
            } else {
                $EMPLOYEE_GROUP_NAME = Read-Host "Enter employee security group name [G-Cloud-Employees]"
                if ([string]::IsNullOrWhiteSpace($EMPLOYEE_GROUP_NAME)) {
                    $EMPLOYEE_GROUP_NAME = "G-Cloud-Employees"
                }
            }
        } else {
            $EMPLOYEE_GROUP_NAME = Read-Host "Enter employee security group name [G-Cloud-Employees]"
            if ([string]::IsNullOrWhiteSpace($EMPLOYEE_GROUP_NAME)) {
                $EMPLOYEE_GROUP_NAME = "G-Cloud-Employees"
            }
        }
        
        # Create group if ID not found
        if ([string]::IsNullOrWhiteSpace($EMPLOYEE_GROUP_ID) -and -not [string]::IsNullOrWhiteSpace($EMPLOYEE_GROUP_NAME)) {
            $createEmpGroup = Read-Host "Create employee security group '$EMPLOYEE_GROUP_NAME'? (y/n) [y]"
            if ([string]::IsNullOrWhiteSpace($createEmpGroup) -or $createEmpGroup -eq "y") {
                Write-Info "Creating employee security group: $EMPLOYEE_GROUP_NAME"
                $ErrorActionPreference = 'SilentlyContinue'
                $newEmpGroup = az ad group create --display-name "$EMPLOYEE_GROUP_NAME" --mail-nickname "$($EMPLOYEE_GROUP_NAME -replace ' ', '')" --query "{Id:id}" -o json 2>&1
                $ErrorActionPreference = 'Stop'
                
                if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($newEmpGroup)) {
                    try {
                        $empGroupObj = $newEmpGroup | ConvertFrom-Json
                        $EMPLOYEE_GROUP_ID = $empGroupObj.Id
                        Write-Success "Employee security group created: $EMPLOYEE_GROUP_NAME ($EMPLOYEE_GROUP_ID)"
                    } catch {
                        Write-Warning "Could not parse new group response"
                    }
                } else {
                    Write-Warning "Could not create employee group. You can create it manually and configure later."
                }
            }
        }
    } else {
        Write-Info "Skipping employee group configuration. All non-admin users will have standard employee access."
    }
    
    # Prompt for custom domain
    Write-Info "Step 7: Custom Domain Configuration"
    $CUSTOM_DOMAIN = Read-Host "Enter custom domain name [PA-G-Cloud15] (for private DNS)"
    if ([string]::IsNullOrWhiteSpace($CUSTOM_DOMAIN)) {
        $CUSTOM_DOMAIN = "PA-G-Cloud15"
    }
    
    # Prompt for Storage Account
    Write-Info "Step 8: Storage Account Configuration"
    # Remove suffix from Function App name first (if it has one) to get base name
    $funcBaseName = $FUNCTION_APP_NAME
    if ($funcBaseName.EndsWith("-$randomSuffix")) {
        $funcBaseName = $funcBaseName -replace "-$randomSuffix$", ""
    }
    $baseStorageName = (($funcBaseName -replace '-', '') -replace '_', '').ToLower()
    if ($baseStorageName.Length -gt 18) {  # Leave room for "st" (2) + suffix (6) = 8 chars
        $baseStorageName = $baseStorageName.Substring(0, 18)
    }
    $defaultStorageName = ($baseStorageName + "st" + $randomSuffix).ToLower()
    $storageChoice = Get-ResourceChoice -ResourceType "Storage Account" -DefaultName $defaultStorageName -ResourceGroup $RESOURCE_GROUP -SearchFunction ${function:Search-StorageAccounts}
    $STORAGE_CHOICE_TYPE = ($storageChoice -split ':')[0]
    $STORAGE_ACCOUNT_NAME = ($storageChoice -split ':', 2)[1]
    # Ensure storage account name has suffix (if user typed custom name)
    if ($STORAGE_CHOICE_TYPE -eq "new" -and -not [string]::IsNullOrWhiteSpace($STORAGE_ACCOUNT_NAME) -and -not $STORAGE_ACCOUNT_NAME.EndsWith($randomSuffix)) {
        $baseStorageName = ($STORAGE_ACCOUNT_NAME -replace '[^a-z0-9]', '').ToLower()
        $maxBaseLength = 18
        if ($baseStorageName.Length -gt $maxBaseLength) {
            $baseStorageName = $baseStorageName.Substring(0, $maxBaseLength)
        }
        $STORAGE_ACCOUNT_NAME = ($baseStorageName + $randomSuffix).ToLower()
    }
    
    # Prompt for Azure Container Registry
    Write-Info "Step 8.5: Azure Container Registry Configuration"
    Write-Host "Container Registry stores Docker images for the frontend deployment."
    Write-Host ""
    
    # Search for existing ACRs (globally, since ACR names are globally unique)
    $existingACRs = Search-ContainerRegistries -ResourceGroup $RESOURCE_GROUP
    
    # Additional filtering: ensure we only show valid ACR names (5-50 chars, alphanumeric lowercase)
    $validACRs = $existingACRs | Where-Object { 
        $_ -match '^[a-z0-9]{5,50}$' -and $_.Length -ge 5 -and $_.Length -le 50
    }
    
    if ($validACRs -and $validACRs.Count -gt 0) {
        Write-Host "Existing Container Registries found:"
        for ($i = 0; $i -lt $validACRs.Count; $i++) {
            Write-Host "  [$i] Use existing: $($validACRs[$i])"
        }
        Write-Host "  [n] Create new"
        Write-Host ""
        $acrChoice = Read-Host "Select option (0-$($validACRs.Count - 1)) or 'n' for new"
        
        if ($acrChoice -match '^\d+$' -and [int]$acrChoice -lt $validACRs.Count) {
            $ACR_NAME = $validACRs[[int]$acrChoice]
            Write-Success "Using existing Container Registry: $ACR_NAME"
        } else {
            # Create new
            $baseAcrName = "pagcloud15acr"
            $defaultAcrName = ($baseAcrName + $randomSuffix).ToLower()
            $ACR_NAME = Read-Host "Enter Container Registry name (5-50 alphanumeric, lowercase) [$defaultAcrName]"
            if ([string]::IsNullOrWhiteSpace($ACR_NAME)) {
                $ACR_NAME = $defaultAcrName
            }
            # Validate ACR name: lowercase alphanumeric, 5-50 chars
            $ACR_NAME = $ACR_NAME.ToLower() -replace '[^a-z0-9]', ''
            # Check if suffix already added, if not add it
            if (-not $ACR_NAME.EndsWith($randomSuffix)) {
                $maxBaseLength = 44
                if ($ACR_NAME.Length -gt $maxBaseLength) {
                    $ACR_NAME = $ACR_NAME.Substring(0, $maxBaseLength)
                }
                $ACR_NAME = ($ACR_NAME + $randomSuffix).ToLower()
            }
            if ($ACR_NAME.Length -lt 5) {
                $ACR_NAME = ($ACR_NAME + "0").PadRight(5, '0')
            }
            if ($ACR_NAME.Length -gt 50) {
                $ACR_NAME = $ACR_NAME.Substring(0, 50)
            }
        }
    } else {
        # No existing ACRs found, create new
        $baseAcrName = "pagcloud15acr"
        $defaultAcrName = ($baseAcrName + $randomSuffix).ToLower()
        $ACR_NAME = Read-Host "Enter Container Registry name (5-50 alphanumeric, lowercase) [$defaultAcrName]"
        if ([string]::IsNullOrWhiteSpace($ACR_NAME)) {
            $ACR_NAME = $defaultAcrName
        }
        # Validate ACR name
        $ACR_NAME = $ACR_NAME.ToLower() -replace '[^a-z0-9]', ''
        # Check if suffix already added, if not add it
        if (-not $ACR_NAME.EndsWith($randomSuffix)) {
            $maxBaseLength = 44
            if ($ACR_NAME.Length -gt $maxBaseLength) {
                $ACR_NAME = $ACR_NAME.Substring(0, $maxBaseLength)
            }
            $ACR_NAME = ($ACR_NAME + $randomSuffix).ToLower()
        }
        if ($ACR_NAME.Length -lt 5) {
            $ACR_NAME = ($ACR_NAME + "0").PadRight(5, '0')
        }
        if ($ACR_NAME.Length -gt 50) {
            $ACR_NAME = $ACR_NAME.Substring(0, 50)
        }
    }
    
    # Prompt for image tag
    $IMAGE_TAG = Read-Host "Enter Docker image tag [latest]"
    if ([string]::IsNullOrWhiteSpace($IMAGE_TAG)) {
        $IMAGE_TAG = "latest"
    }
    
    # Prompt for Private DNS Zone
    Write-Info "Step 9: Private DNS Zone Configuration"
    $dnsChoice = Get-ResourceChoice -ResourceType "Private DNS Zone" -DefaultName "privatelink.azurewebsites.net" -ResourceGroup $RESOURCE_GROUP -SearchFunction ${function:Search-PrivateDnsZones}
    $PRIVATE_DNS_CHOICE_TYPE = ($dnsChoice -split ':')[0]
    $PRIVATE_DNS_ZONE_NAME = ($dnsChoice -split ':', 2)[1]
    
    # Prompt for Application Insights
    Write-Info "Step 10: Application Insights Configuration"
    $aiChoice = Get-ResourceChoice -ResourceType "Application Insights" -DefaultName "$FUNCTION_APP_NAME-insights" -ResourceGroup $RESOURCE_GROUP -SearchFunction ${function:Search-AppInsights}
    $APP_INSIGHTS_CHOICE_TYPE = ($aiChoice -split ':')[0]
    $APP_INSIGHTS_NAME = ($aiChoice -split ':', 2)[1]
    
    # Prompt for VNet and Private Endpoint Configuration
    Write-Info "Step 11: VNet and Private Endpoint Configuration"
    Write-Host ""
    Write-Host "Private endpoints enable private-only access (no public internet access)."
    Write-Host "You can configure them now or add them later for testing."
    Write-Host ""
    Write-Host "  [y] Configure private endpoints now (recommended for production)"
    Write-Host "  [n] Skip for now - configure later (allows public access for testing)"
    Write-Host ""
    $peChoice = Read-Host "Configure private endpoints now? (y/n) [n]"
    if ([string]::IsNullOrWhiteSpace($peChoice)) {
        $peChoice = "n"
    }
    
    $CONFIGURE_PRIVATE_ENDPOINTS = "false"
    $VNET_NAME = ""
    $SUBNET_NAME = ""
    
    if ($peChoice -eq "y" -or $peChoice -eq "Y") {
        $CONFIGURE_PRIVATE_ENDPOINTS = "true"
        # Search for existing VNets
        $existingVNets = Search-VNets -ResourceGroup $RESOURCE_GROUP
        if ($existingVNets.Count -gt 0) {
            Write-Host "Existing VNets found:"
            for ($i = 0; $i -lt $existingVNets.Count; $i++) {
                Write-Host "  [$i] $($existingVNets[$i])"
            }
            Write-Host "  [n] Create new"
            $vnetSelect = Read-Host "Select option (0-$($existingVNets.Count - 1)) or 'n' for new"
            
            if ($vnetSelect -match '^\d+$' -and [int]$vnetSelect -lt $existingVNets.Count) {
                $VNET_NAME = $existingVNets[[int]$vnetSelect]
                Write-Success "Using existing VNet: $VNET_NAME"
                
                # Get subnets in this VNet
                $subnets = Search-Subnets -VNetName $VNET_NAME -ResourceGroup $RESOURCE_GROUP
                if ($subnets.Count -gt 0) {
                    Write-Host "Existing subnets found:"
                    for ($i = 0; $i -lt $subnets.Count; $i++) {
                        Write-Host "  [$i] $($subnets[$i])"
                    }
                    Write-Host "  [n] Create new"
                    $subnetSelect = Read-Host "Select option (0-$($subnets.Count - 1)) or 'n' for new"
                    
                    if ($subnetSelect -match '^\d+$' -and [int]$subnetSelect -lt $subnets.Count) {
                        $SUBNET_NAME = $subnets[[int]$subnetSelect]
                        Write-Success "Using existing subnet: $SUBNET_NAME"
                    } else {
                        $SUBNET_NAME = Read-Host "Enter subnet name [functions-subnet]"
                        if ([string]::IsNullOrWhiteSpace($SUBNET_NAME)) {
                            $SUBNET_NAME = "functions-subnet"
                        }
                    }
                } else {
                    $SUBNET_NAME = Read-Host "Enter subnet name [functions-subnet]"
                    if ([string]::IsNullOrWhiteSpace($SUBNET_NAME)) {
                        $SUBNET_NAME = "functions-subnet"
                    }
                }
            } else {
                $VNET_NAME = Read-Host "Enter VNet name [pa-gcloud15-vnet]"
                if ([string]::IsNullOrWhiteSpace($VNET_NAME)) {
                    $VNET_NAME = "pa-gcloud15-vnet"
                }
                $SUBNET_NAME = Read-Host "Enter subnet name [functions-subnet]"
                if ([string]::IsNullOrWhiteSpace($SUBNET_NAME)) {
                    $SUBNET_NAME = "functions-subnet"
                }
            }
        } else {
            $VNET_NAME = Read-Host "Enter VNet name [pa-gcloud15-vnet]"
            if ([string]::IsNullOrWhiteSpace($VNET_NAME)) {
                $VNET_NAME = "pa-gcloud15-vnet"
            }
            $SUBNET_NAME = Read-Host "Enter subnet name [functions-subnet]"
            if ([string]::IsNullOrWhiteSpace($SUBNET_NAME)) {
                $SUBNET_NAME = "functions-subnet"
            }
        }
    } else {
        Write-Info "Skipping private endpoint configuration"
        Write-Info "You can add private endpoints later by running deploy.ps1 again and selecting 'y'"
        $CONFIGURE_PRIVATE_ENDPOINTS = "false"
        $VNET_NAME = ""
        $SUBNET_NAME = ""
    }
    
    # Summary
    Write-Host ""
    Write-Info "Deployment Configuration Summary:"
    Write-Host "  Resource Group: $RESOURCE_GROUP"
    Write-Host "  Function App: $FUNCTION_APP_NAME"
    Write-Host "  Web App: $WEB_APP_NAME"
    Write-Host "  Key Vault: $KEY_VAULT_NAME"
    Write-Host "  SharePoint Site: $SHAREPOINT_SITE_URL"
    Write-Host "  App Registration: $APP_REGISTRATION_NAME"
    Write-Host "  Custom Domain: $CUSTOM_DOMAIN"
    Write-Host "  Storage Account: $STORAGE_CHOICE_TYPE ($STORAGE_ACCOUNT_NAME)"
    Write-Host "  Container Registry: $ACR_NAME (tag: $IMAGE_TAG)"
    Write-Host "  Private DNS Zone: $PRIVATE_DNS_CHOICE_TYPE ($PRIVATE_DNS_ZONE_NAME)"
    Write-Host "  Application Insights: $APP_INSIGHTS_CHOICE_TYPE ($APP_INSIGHTS_NAME)"
    if ($CONFIGURE_PRIVATE_ENDPOINTS -eq "true") {
        Write-Host "  VNet: $VNET_NAME"
        Write-Host "  Subnet: $SUBNET_NAME"
        Write-Host "  Private Endpoints: Enabled"
    } else {
        Write-Host "  Private Endpoints: Disabled (will be configured later)"
    }
    Write-Host ""
    
    $confirm = Read-Host "Proceed with deployment? (y/n) [y]"
    if ([string]::IsNullOrWhiteSpace($confirm) -or $confirm -eq "y") {
        # Save configuration
        if (-not (Test-Path "config")) {
            New-Item -ItemType Directory -Path "config" | Out-Null
        }
        
        # Set default location if not set
        if ([string]::IsNullOrWhiteSpace($LOCATION)) {
            $LOCATION = 'uksouth'
        }
        
        # Validate critical values before writing
        Write-Info "Validating configuration values..."
        $validationErrors = @()
        
        if ([string]::IsNullOrWhiteSpace($FUNCTION_APP_NAME) -or $FUNCTION_APP_NAME.Length -lt 3) {
            $validationErrors += "FUNCTION_APP_NAME is missing or too short: '$FUNCTION_APP_NAME'"
        }
        if ([string]::IsNullOrWhiteSpace($WEB_APP_NAME) -or $WEB_APP_NAME.Length -lt 3) {
            $validationErrors += "WEB_APP_NAME is missing or too short: '$WEB_APP_NAME'"
        }
        if ([string]::IsNullOrWhiteSpace($RESOURCE_GROUP) -or $RESOURCE_GROUP.Length -lt 3) {
            $validationErrors += "RESOURCE_GROUP is missing or too short: '$RESOURCE_GROUP'"
        }
        
        if ($validationErrors.Count -gt 0) {
            Write-Error "Configuration validation failed:"
            foreach ($error in $validationErrors) {
                Write-Host "  - $error" -ForegroundColor Red
            }
            Write-Error "Please fix the configuration and try again."
            exit 1
        }
        
        # Ensure config directory exists
        if (-not (Test-Path "config")) {
            New-Item -ItemType Directory -Path "config" | Out-Null
        }
        
        # All names should already have suffixes from prompts above
        # No additional processing needed - suffixes are added during prompts
        Write-Info "Resource names configured with random suffixes"
        $configLines = @(
            "RESOURCE_GROUP=$RESOURCE_GROUP",
            "FUNCTION_APP_NAME=$FUNCTION_APP_NAME",
            "WEB_APP_NAME=$WEB_APP_NAME",
            "KEY_VAULT_NAME=$KEY_VAULT_NAME",
            "SHAREPOINT_SITE_URL=$SHAREPOINT_SITE_URL",
            "SHAREPOINT_SITE_ID=$($SHAREPOINT_SITE_ID -replace '\?.*$', '')",
            "APP_REGISTRATION_NAME=$APP_REGISTRATION_NAME",
            "ADMIN_GROUP_ID=$ADMIN_GROUP_ID",
            "EMPLOYEE_GROUP_ID=$EMPLOYEE_GROUP_ID",
            "CUSTOM_DOMAIN=$CUSTOM_DOMAIN",
            "LOCATION=$LOCATION",
            "SUBSCRIPTION_ID=$SUBSCRIPTION_ID",
            "STORAGE_ACCOUNT_CHOICE=$STORAGE_CHOICE_TYPE",
            "STORAGE_ACCOUNT_NAME=$STORAGE_ACCOUNT_NAME",
            "ACR_NAME=$ACR_NAME",
            "IMAGE_TAG=$IMAGE_TAG",
            "PRIVATE_DNS_CHOICE=$PRIVATE_DNS_CHOICE_TYPE",
            "PRIVATE_DNS_ZONE_NAME=$PRIVATE_DNS_ZONE_NAME",
            "APP_INSIGHTS_CHOICE=$APP_INSIGHTS_CHOICE_TYPE",
            "APP_INSIGHTS_NAME=$APP_INSIGHTS_NAME",
            "CONFIGURE_PRIVATE_ENDPOINTS=$CONFIGURE_PRIVATE_ENDPOINTS",
            "VNET_NAME=$VNET_NAME",
            "SUBNET_NAME=$SUBNET_NAME"
        )
        $configLines | Set-Content -Path "config\deployment-config.env" -Encoding UTF8
        Write-Success "Configuration saved with actual resource names (including random suffixes)"
        
        # Check resource providers (informational only - user should register manually)
        Write-Info ""
        Write-Warning "IMPORTANT: Ensure resource providers are registered before deployment!"
        Write-Warning "If this is a new subscription, register providers in Azure Portal:"
        Write-Host "  1. Go to: Subscriptions -> Your Subscription -> Resource providers" -ForegroundColor Yellow
        Write-Host "  2. Search and register: Microsoft.KeyVault, Microsoft.Web, Microsoft.Storage" -ForegroundColor Yellow
        Write-Host "  3. Also register: Microsoft.ContainerRegistry, Microsoft.Insights, Microsoft.Network" -ForegroundColor Yellow
        Write-Host "  4. Wait 1-2 minutes for registration to complete" -ForegroundColor Yellow
        Write-Info ""
        $continue = Read-Host "Have you registered the resource providers? (y/n) [y]"
        if ([string]::IsNullOrWhiteSpace($continue) -or $continue -eq "y") {
            Write-Info "Continuing with deployment..."
        } else {
            Write-Error "Please register resource providers first, then run deploy.ps1 again"
            exit 1
        }
        
        # All names should already have suffixes from prompts above
        # This section removed - suffixes are added during prompts
        $configLines = @(
            "RESOURCE_GROUP=$RESOURCE_GROUP",
            "FUNCTION_APP_NAME=$FUNCTION_APP_NAME",
            "WEB_APP_NAME=$WEB_APP_NAME",
            "KEY_VAULT_NAME=$KEY_VAULT_NAME",
            "SHAREPOINT_SITE_URL=$SHAREPOINT_SITE_URL",
            "SHAREPOINT_SITE_ID=$($SHAREPOINT_SITE_ID -replace '\?.*$', '')",
            "APP_REGISTRATION_NAME=$APP_REGISTRATION_NAME",
            "ADMIN_GROUP_ID=$ADMIN_GROUP_ID",
            "EMPLOYEE_GROUP_ID=$EMPLOYEE_GROUP_ID",
            "CUSTOM_DOMAIN=$CUSTOM_DOMAIN",
            "LOCATION=$LOCATION",
            "SUBSCRIPTION_ID=$SUBSCRIPTION_ID",
            "STORAGE_ACCOUNT_CHOICE=$STORAGE_CHOICE_TYPE",
            "STORAGE_ACCOUNT_NAME=$STORAGE_ACCOUNT_NAME",
            "ACR_NAME=$ACR_NAME",
            "IMAGE_TAG=$IMAGE_TAG",
            "PRIVATE_DNS_CHOICE=$PRIVATE_DNS_CHOICE_TYPE",
            "PRIVATE_DNS_ZONE_NAME=$PRIVATE_DNS_ZONE_NAME",
            "APP_INSIGHTS_CHOICE=$APP_INSIGHTS_CHOICE_TYPE",
            "APP_INSIGHTS_NAME=$APP_INSIGHTS_NAME",
            "CONFIGURE_PRIVATE_ENDPOINTS=$CONFIGURE_PRIVATE_ENDPOINTS",
            "VNET_NAME=$VNET_NAME",
            "SUBNET_NAME=$SUBNET_NAME"
        )
        $configLines | Set-Content -Path "config\deployment-config.env" -Encoding UTF8
        Write-Success "Config file updated with actual resource names"
        
        # Run deployment scripts
        Write-Info "Starting deployment..."
        & ".\scripts\setup-resources.ps1"
        & ".\scripts\deploy-functions.ps1"
        
        # Build and push frontend Docker image (if not already built)
        Write-Info "Checking if frontend Docker image needs to be built..."
        $ErrorActionPreference = 'SilentlyContinue'
        $allTagsList = az acr repository show-tags --name "$ACR_NAME" --repository "frontend" --output tsv 2>&1
        $ErrorActionPreference = 'Stop'
        
        $imageExists = $false
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($allTagsList)) {
            $tags = $allTagsList -split "`n" | Where-Object { $_ -and $_.Trim() -ne "" }
            foreach ($tag in $tags) {
                if ($tag.Trim() -eq $IMAGE_TAG) {
                    $imageExists = $true
                    break
                }
            }
        }
        
        if (-not $imageExists) {
            Write-Info "Frontend Docker image not found. Building and pushing to ACR..."
            Write-Info "This will build in Azure cloud (no local Docker needed)..."
            Write-Info ""
            
            # Call build script in non-interactive mode (uses ACR build automatically)
            $env:DEPLOY_NON_INTERACTIVE = "true"
            & ".\scripts\build-and-push-images.ps1"
            $env:DEPLOY_NON_INTERACTIVE = $null
            
            if ($LASTEXITCODE -ne 0) {
                Write-Error "Failed to build frontend Docker image"
                Write-Info "You can build it manually later with: .\scripts\build-and-push-images.ps1"
                Write-Info "Continuing with deployment (frontend will be deployed when image is ready)..."
            } else {
                Write-Success "Frontend Docker image built and pushed successfully"
            }
        } else {
            Write-Success "Frontend Docker image already exists in ACR: frontend:$IMAGE_TAG"
        }
        
        # Configure Easy Auth for Function App (platform-level authentication)
        Write-Info "Configuring Easy Auth (platform-level authentication)..."
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\configure-easy-auth.ps1"
        
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "configure-easy-auth.ps1 exited with error code $LASTEXITCODE"
            Write-Warning "Easy Auth may not be configured correctly"
            Write-Warning "You may need to run configure-easy-auth.ps1 manually to fix issues"
        } else {
            Write-Success "Easy Auth configured successfully"
        }
        
        # Rebuild Docker image with API URL (Easy Auth doesn't need SSO config in frontend)
        Write-Info "Rebuilding frontend Docker image with API configuration..."
        Write-Info "Note: Easy Auth handles authentication at platform level, no SSO config needed in frontend"
        $env:DEPLOY_NON_INTERACTIVE = "true"
        & ".\scripts\build-and-push-images.ps1"
        $env:DEPLOY_NON_INTERACTIVE = $null
        
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Failed to rebuild Docker image"
            Write-Warning "Frontend may not work correctly until image is rebuilt"
            Write-Info "You can rebuild manually: .\scripts\build-and-push-images.ps1"
            Write-Info "Then redeploy: .\scripts\deploy-frontend.ps1"
        } else {
            Write-Success "Frontend Docker image rebuilt with API configuration"
        }
        
        # Deploy frontend to Web App
        Write-Info "Deploying frontend to Web App using Docker container from ACR..."
        & ".\scripts\deploy-frontend.ps1"
        
        # Verify Easy Auth configuration
        Write-Info "Verifying Easy Auth configuration..."
        $ErrorActionPreference = 'SilentlyContinue'
        $authConfig = az webapp auth show --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP -o json 2>&1
        $ErrorActionPreference = 'Stop'
        
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($authConfig)) {
            try {
                $auth = $authConfig | ConvertFrom-Json
                if ($auth.enabled -eq $true) {
                    Write-Success "✓ Easy Auth is enabled"
                    if ($auth.identityProviders.azureActiveDirectory.enabled -eq $true) {
                        Write-Success "✓ Microsoft Identity Provider is configured"
                    } else {
                        Write-Warning "⚠ Microsoft Identity Provider may not be configured"
                    }
                } else {
                    Write-Warning "⚠ Easy Auth is not enabled"
                    Write-Warning "Run: .\scripts\configure-easy-auth.ps1 to fix this"
                }
            } catch {
                Write-Warning "Could not parse Easy Auth configuration: $_"
            }
        } else {
            Write-Warning "Could not verify Easy Auth configuration"
        }
        
        Write-Success "Deployment complete!"
        Write-Info ""
        Write-Info "═══════════════════════════════════════════════════════════════"
        Write-Info "POST-DEPLOYMENT STEPS (Manual & Automated)"
        Write-Info "═══════════════════════════════════════════════════════════════"
        Write-Host ""
        Write-Host "STEP 1: VERIFY EASY AUTH (CRITICAL - Do this first!)" -ForegroundColor Yellow
        Write-Host "─────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
        Write-Host "Easy Auth should be automatically configured during deployment." -ForegroundColor Cyan
        Write-Host "If authentication fails, verify Easy Auth is enabled:" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Option A - Automated (recommended):" -ForegroundColor Cyan
        Write-Host "   .\scripts\configure-easy-auth.ps1" -ForegroundColor White
        Write-Host ""
        Write-Host "Option B - Manual (if script fails):" -ForegroundColor Cyan
        Write-Host "   1. Go to: https://portal.azure.com -> Function App: $FUNCTION_APP_NAME" -ForegroundColor White
        Write-Host "   2. Go to 'Authentication' (under Settings)" -ForegroundColor White
        Write-Host "   3. Click 'Add identity provider'" -ForegroundColor White
        Write-Host "   4. Select 'Microsoft'" -ForegroundColor White
        Write-Host "   5. Choose 'From this tenant only'" -ForegroundColor White
        Write-Host "   6. Select App Registration: $APP_REGISTRATION_NAME" -ForegroundColor White
        Write-Host "   7. Click 'Add'" -ForegroundColor White
        Write-Host ""
        Write-Host "Note: Easy Auth handles authentication at platform level - no MSAL needed!" -ForegroundColor Gray
        Write-Host ""
        Write-Host "STEP 2: CONFIGURE SHAREPOINT PERMISSIONS" -ForegroundColor Yellow
        Write-Host "─────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
        Write-Host "Option A - Automated (removes old, adds correct permissions):" -ForegroundColor Cyan
        Write-Host "   .\scripts\fix-sharepoint-permissions-v2.ps1" -ForegroundColor White
        Write-Host ""
        Write-Host "Option B - Manual (if you prefer):" -ForegroundColor Cyan
        Write-Host "   1. Go to: https://portal.azure.com -> Azure AD -> App registrations" -ForegroundColor White
        Write-Host "   2. Find: $APP_REGISTRATION_NAME" -ForegroundColor White
        Write-Host "   3. Go to 'API permissions'" -ForegroundColor White
        Write-Host "   4. Remove any Delegated SharePoint permissions" -ForegroundColor White
        Write-Host "   5. Click 'Add a permission' -> Microsoft Graph -> Application permissions" -ForegroundColor White
        Write-Host "   6. Add: Sites.FullControl.All, Sites.ReadWrite.All, Files.ReadWrite.All" -ForegroundColor White
        Write-Host "   7. Click 'Grant admin consent for [your tenant]'" -ForegroundColor White
        Write-Host "   8. Confirm the consent" -ForegroundColor White
        Write-Host ""
        Write-Host "STEP 3: VERIFY KEY VAULT ACCESS (if SharePoint test fails)" -ForegroundColor Yellow
        Write-Host "─────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
        Write-Host "Run this diagnostic:" -ForegroundColor Cyan
        Write-Host "   .\scripts\check-keyvault-access.ps1" -ForegroundColor White
        Write-Host ""
        Write-Host "If managed identity is not enabled, run:" -ForegroundColor Cyan
        Write-Host "   .\scripts\fix-keyvault-access.ps1" -ForegroundColor White
        Write-Host ""
        Write-Host "STEP 4: TEST AUTHENTICATION" -ForegroundColor Yellow
        Write-Host "─────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
        Write-Host "   Open: https://$FUNCTION_APP_NAME.azurewebsites.net" -ForegroundColor White
        Write-Host "   You should be automatically redirected to Microsoft login" -ForegroundColor White
        Write-Host "   After login, you'll be redirected back to the app" -ForegroundColor White
        Write-Host "   Easy Auth handles authentication - no frontend code needed!" -ForegroundColor Gray
        Write-Host ""
        Write-Host "   To test Easy Auth endpoint directly:" -ForegroundColor Cyan
        Write-Host "   curl https://$FUNCTION_APP_NAME.azurewebsites.net/.auth/me" -ForegroundColor White
        Write-Host ""
        Write-Host "STEP 5: TEST SHAREPOINT CONNECTIVITY" -ForegroundColor Yellow
        Write-Host "─────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
        Write-Host "Option A - Automated:" -ForegroundColor Cyan
        Write-Host "   .\scripts\test-sharepoint-connectivity.ps1" -ForegroundColor White
        Write-Host ""
        Write-Host "Option B - Manual (curl):" -ForegroundColor Cyan
        Write-Host "   curl https://$FUNCTION_APP_NAME.azurewebsites.net/api/v1/sharepoint/test" -ForegroundColor White
        Write-Host ""
        Write-Host "Expected: If test tenant, may show 'tenant limitation' (this is OK for production)" -ForegroundColor Gray
        Write-Host ""
        Write-Host "STEP 6: VERIFY PRIVATE ENDPOINTS (if configured)" -ForegroundColor Yellow
        Write-Host "─────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
        Write-Host "   Check Azure Portal -> Resource Group -> Private Endpoints" -ForegroundColor White
        Write-Host ""
        Write-Info "═══════════════════════════════════════════════════════════════"
        Write-Info ""
        Write-Info "QUICK COPY-PASTE COMMANDS (for manual verification):"
        Write-Host ""
        Write-Host "# Test SharePoint connectivity:" -ForegroundColor Cyan
        Write-Host "curl https://$FUNCTION_APP_NAME.azurewebsites.net/api/v1/sharepoint/test" -ForegroundColor White
        Write-Host ""
        Write-Host "# Check Function App settings:" -ForegroundColor Cyan
        Write-Host "az functionapp config appsettings list --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP" -ForegroundColor White
        Write-Host ""
        Write-Host "# Restart Function App (if needed):" -ForegroundColor Cyan
        Write-Host "az functionapp restart --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP" -ForegroundColor White
        Write-Host ""
        Write-Host "# Check App Registration SPA platform (Graph API):" -ForegroundColor Cyan
        Write-Host '$appId = az ad app list --display-name "' + $APP_REGISTRATION_NAME + '" --query "[0].appId" -o tsv' -ForegroundColor White
        Write-Host '$token = az account get-access-token --resource "https://graph.microsoft.com" --query accessToken -o tsv' -ForegroundColor White
        Write-Host 'Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/applications(appId=''$appId'')" -Headers @{Authorization="Bearer $token"} | Select-Object -ExpandProperty spa' -ForegroundColor White
        Write-Host ""
        Write-Info "═══════════════════════════════════════════════════════════════"
        Write-Info ""
        Write-Info "TROUBLESHOOTING:"
        Write-Host "  - Login fails? -> Run Step 1 (SPA platform)" -ForegroundColor Yellow
        Write-Host "  - SharePoint test fails? -> Run Step 2 (permissions) and Step 3 (Key Vault)" -ForegroundColor Yellow
        Write-Host "  - 'Tenant does not have SPO license'? -> This is a test tenant limitation, production will work" -ForegroundColor Yellow
        Write-Host "  - Need to verify something manually? -> Use the copy-paste commands above" -ForegroundColor Yellow
        Write-Info ""
        Write-Info "NOTE: Manual steps are perfectly fine! Use automated scripts when they work," -ForegroundColor Gray
        Write-Info "      but don't hesitate to use portal or manual commands if needed." -ForegroundColor Gray
        Write-Info ""
    } else {
        Write-Info "Deployment cancelled"
        exit 0
    }
}

# Run main function
Start-Deployment

