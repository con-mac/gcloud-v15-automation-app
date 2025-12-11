#!/bin/bash

# Deploy Functions Script
# Deploys backend API code to Azure Function App

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

print_info "Deploying backend API to Function App..."

# Check if backend directory exists
if [ ! -d "backend" ]; then
    print_warning "Backend directory not found. Creating structure..."
    mkdir -p backend
fi

# Create deployment package
print_info "Creating deployment package..."
cd backend

# Create requirements.txt if it doesn't exist
if [ ! -f requirements.txt ]; then
    print_warning "requirements.txt not found. Creating from template..."
    cat > requirements.txt <<EOF
fastapi>=0.104.0
uvicorn[standard]>=0.24.0
azure-functions>=1.18.0
azure-identity>=1.15.0
azure-keyvault-secrets>=4.7.0
python-docx>=1.1.0
openpyxl>=3.1.0
pydantic>=2.5.0
pydantic-settings>=2.1.0
# SharePoint/Graph API dependencies
msgraph-sdk>=1.0.0
# Placeholder: Add other dependencies as needed
EOF
fi

# Create .python_packages directory structure
mkdir -p .python_packages/lib/site-packages

# Deploy to Function App
print_info "Deploying to Function App: $FUNCTION_APP_NAME"
if command -v func &> /dev/null; then
    func azure functionapp publish "$FUNCTION_APP_NAME" --python
else
    print_warning "Azure Functions Core Tools not found. Skipping code deployment."
    print_warning "Install with: npm install -g azure-functions-core-tools@4"
    print_info "Function App exists and will be configured, but code deployment skipped."
fi

# Configure app settings (updates existing or creates new)
print_info "Configuring Function App settings..."

# Get Key Vault reference
KEY_VAULT_URI=$(az keyvault show --name "$KEY_VAULT_NAME" --resource-group "$RESOURCE_GROUP" --query properties.vaultUri -o tsv)

# Set app settings
az functionapp config appsettings set \
    --name "$FUNCTION_APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --settings \
        "AZURE_KEY_VAULT_URL=$KEY_VAULT_URI" \
        "SHAREPOINT_SITE_URL=$SHAREPOINT_SITE_URL" \
        "SHAREPOINT_SITE_ID=$SHAREPOINT_SITE_ID" \
        "USE_SHAREPOINT=true" \
        "AZURE_STORAGE_CONNECTION_STRING=@Microsoft.KeyVault(SecretUri=$KEY_VAULT_URI/secrets/StorageConnectionString/)" \
        "APPLICATIONINSIGHTS_CONNECTION_STRING=@Microsoft.KeyVault(SecretUri=$KEY_VAULT_URI/secrets/AppInsightsConnectionString/)" \
    --output none

print_success "Backend deployment complete!"
print_info "Note: SharePoint credentials need to be added to Key Vault"
print_info "Note: App Registration credentials need to be configured"

cd ..

