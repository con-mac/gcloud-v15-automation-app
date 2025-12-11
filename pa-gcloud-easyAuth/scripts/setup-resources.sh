#!/bin/bash

# Setup Azure Resources Script
# Creates all necessary Azure resources for PA deployment

set -e

# Load configuration
if [ ! -f config/deployment-config.env ]; then
    echo "Error: deployment-config.env not found. Please run deploy.sh first."
    exit 1
fi

source config/deployment-config.env

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

print_info "Setting up Azure resources..."

# Set subscription
az account set --subscription "$SUBSCRIPTION_ID"

# Handle Storage Account
if [ -z "${STORAGE_ACCOUNT_CHOICE:-}" ] || [ "$STORAGE_ACCOUNT_CHOICE" = "new" ]; then
    print_info "Creating Storage Account (for temporary files)..."
    if [ -z "${STORAGE_ACCOUNT_NAME:-}" ] || [ -z "$STORAGE_ACCOUNT_NAME" ]; then
        STORAGE_ACCOUNT_NAME=$(echo "${FUNCTION_APP_NAME}st" | tr '[:upper:]' '[:lower:]' | sed 's/-//g' | cut -c1-24)
    fi
    if ! az storage account show --name "$STORAGE_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        az storage account create \
            --name "$STORAGE_ACCOUNT_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --allow-blob-public-access false \
            --min-tls-version TLS1_2
        print_success "Storage Account created: $STORAGE_ACCOUNT_NAME"
    else
        print_warning "Storage Account already exists: $STORAGE_ACCOUNT_NAME"
    fi
elif [ "$STORAGE_ACCOUNT_CHOICE" = "existing" ]; then
    if [ -n "${STORAGE_ACCOUNT_NAME:-}" ] && [ -n "$STORAGE_ACCOUNT_NAME" ]; then
        if az storage account show --name "$STORAGE_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            print_success "Using existing Storage Account: $STORAGE_ACCOUNT_NAME"
        else
            print_warning "Storage Account '$STORAGE_ACCOUNT_NAME' not found, skipping"
            STORAGE_ACCOUNT_NAME=""
        fi
    else
        print_warning "No Storage Account name provided for existing choice, skipping"
        STORAGE_ACCOUNT_NAME=""
    fi
else
    print_info "Skipping Storage Account creation"
    STORAGE_ACCOUNT_NAME=""
fi

# Create Key Vault
print_info "Creating Key Vault..."
if ! az keyvault show --name "$KEY_VAULT_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
    az keyvault create \
        --name "$KEY_VAULT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku standard \
        --enable-rbac-authorization true
    print_success "Key Vault created: $KEY_VAULT_NAME"
else
    print_warning "Key Vault already exists: $KEY_VAULT_NAME"
fi

# Create or update Function App (Consumption plan for serverless)
print_info "Setting up Function App for backend API..."
if ! az functionapp show --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
    # Create storage account for function app (required)
    FUNC_STORAGE=$(echo "${FUNCTION_APP_NAME}func" | tr '[:upper:]' '[:lower:]' | sed 's/-//g' | cut -c1-24)
    if ! az storage account show --name "$FUNC_STORAGE" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        az storage account create \
            --name "$FUNC_STORAGE" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku Standard_LRS
    fi
    
    # Create Function App
    az functionapp create \
        --name "$FUNCTION_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --consumption-plan-location "$LOCATION" \
        --runtime python \
        --runtime-version 3.11 \
        --functions-version 4 \
        --storage-account "$FUNC_STORAGE" \
        --os-type Linux
    
    # Configure private endpoint (placeholder - requires VNet)
    print_warning "NOTE: Private endpoint configuration requires VNet integration"
    print_warning "Please configure VNet integration and private endpoints manually or via script"
    
    print_success "Function App created: $FUNCTION_APP_NAME"
else
    print_success "Using existing Function App: $FUNCTION_APP_NAME"
    print_info "Function App will be updated with new configuration during deployment"
fi

# Create or update Static Web App (or App Service for private hosting)
print_info "Setting up Web App for frontend..."
if ! az webapp show --name "$WEB_APP_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
    # Note: Static Web Apps have limited private endpoint support
    # May need to use App Service instead for full private access
    print_warning "Static Web Apps have limited private endpoint support"
    print_warning "Consider using App Service with private endpoints for full private access"
    
    # For now, create as App Service for better private endpoint support
    # Create App Service Plan
    APP_SERVICE_PLAN="${WEB_APP_NAME}-plan"
    if ! az appservice plan show --name "$APP_SERVICE_PLAN" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        az appservice plan create \
            --name "$APP_SERVICE_PLAN" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku B1 \
            --is-linux
    fi
    
    # Create Web App
    az webapp create \
        --name "$WEB_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --plan "$APP_SERVICE_PLAN" \
        --runtime "NODE:18-lts"
    
    print_success "Web App created: $WEB_APP_NAME"
else
    print_success "Using existing Web App: $WEB_APP_NAME"
    print_info "Web App will be updated with new configuration during deployment"
fi

# Handle Application Insights
if [ -z "${APP_INSIGHTS_CHOICE:-}" ] || [ "$APP_INSIGHTS_CHOICE" = "new" ]; then
    print_info "Creating Application Insights..."
    if [ -z "${APP_INSIGHTS_NAME:-}" ] || [ -z "$APP_INSIGHTS_NAME" ]; then
        APP_INSIGHTS_NAME="${FUNCTION_APP_NAME}-insights"
    fi
    if ! az monitor app-insights component show --app "$APP_INSIGHTS_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        az monitor app-insights component create \
            --app "$APP_INSIGHTS_NAME" \
            --location "$LOCATION" \
            --resource-group "$RESOURCE_GROUP" \
            --application-type web
        print_success "Application Insights created: $APP_INSIGHTS_NAME"
    else
        print_warning "Application Insights already exists: $APP_INSIGHTS_NAME"
    fi
elif [ "$APP_INSIGHTS_CHOICE" = "existing" ]; then
    if [ -n "${APP_INSIGHTS_NAME:-}" ] && [ -n "$APP_INSIGHTS_NAME" ]; then
        if az monitor app-insights component show --app "$APP_INSIGHTS_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            print_success "Using existing Application Insights: $APP_INSIGHTS_NAME"
        else
            print_warning "Application Insights '$APP_INSIGHTS_NAME' not found, skipping"
            APP_INSIGHTS_NAME=""
        fi
    else
        print_warning "No Application Insights name provided for existing choice, skipping"
        APP_INSIGHTS_NAME=""
    fi
else
    print_info "Skipping Application Insights creation"
    APP_INSIGHTS_NAME=""
fi

# Store App Insights connection string (if created/using existing)
if [ -n "$APP_INSIGHTS_NAME" ]; then
    APP_INSIGHTS_CONNECTION=$(az monitor app-insights component show \
        --app "$APP_INSIGHTS_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query connectionString -o tsv)
    
    # Save to Key Vault
    az keyvault secret set \
        --vault-name "$KEY_VAULT_NAME" \
        --name "AppInsightsConnectionString" \
        --value "$APP_INSIGHTS_CONNECTION" \
        --output none
fi

# Handle Private DNS Zone
if [ -z "${PRIVATE_DNS_CHOICE:-}" ] || [ "$PRIVATE_DNS_CHOICE" = "new" ]; then
    print_info "Creating Private DNS Zone..."
    if [ -z "${PRIVATE_DNS_ZONE_NAME:-}" ] || [ -z "$PRIVATE_DNS_ZONE_NAME" ]; then
        PRIVATE_DNS_ZONE_NAME="privatelink.azurewebsites.net"
    fi
    if ! az network private-dns zone show --name "$PRIVATE_DNS_ZONE_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        az network private-dns zone create \
            --name "$PRIVATE_DNS_ZONE_NAME" \
            --resource-group "$RESOURCE_GROUP"
        print_success "Private DNS Zone created: $PRIVATE_DNS_ZONE_NAME"
    else
        print_warning "Private DNS Zone already exists: $PRIVATE_DNS_ZONE_NAME"
    fi
elif [ "$PRIVATE_DNS_CHOICE" = "existing" ]; then
    if [ -n "${PRIVATE_DNS_ZONE_NAME:-}" ] && [ -n "$PRIVATE_DNS_ZONE_NAME" ]; then
        if az network private-dns zone show --name "$PRIVATE_DNS_ZONE_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            print_success "Using existing Private DNS Zone: $PRIVATE_DNS_ZONE_NAME"
        else
            print_warning "Private DNS Zone '$PRIVATE_DNS_ZONE_NAME' not found, skipping"
            PRIVATE_DNS_ZONE_NAME=""
        fi
    else
        print_warning "No Private DNS Zone name provided for existing choice, skipping"
        PRIVATE_DNS_ZONE_NAME=""
    fi
else
    print_info "Skipping Private DNS Zone creation"
    PRIVATE_DNS_ZONE_NAME=""
fi

print_success "Resources setup complete!"
print_info "Next: Configure private endpoints and VNet integration"
print_info "Next: Run deploy-functions.sh to deploy backend code"

