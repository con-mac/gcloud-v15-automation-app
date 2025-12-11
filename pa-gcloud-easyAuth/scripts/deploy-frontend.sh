#!/bin/bash

# Deploy Frontend Script
# Deploys React frontend to Static Web App or App Service

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

print_info "Deploying frontend to Web App..."

# Check if frontend directory exists
if [ ! -d "frontend" ]; then
    print_warning "Frontend directory not found. Creating structure..."
    mkdir -p frontend
fi

cd frontend

# Build frontend
print_info "Building frontend..."
if [ ! -f package.json ]; then
    print_warning "package.json not found. Frontend may need to be copied from main repo."
    cd ..
    exit 1
fi

npm install
npm run build

# Get Function App URL for API configuration
FUNCTION_APP_URL=$(az functionapp show \
    --name "$FUNCTION_APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query defaultHostName -o tsv)

# Create .env.production with API URL
# Note: For private endpoints, this will be the private DNS name
cat > .env.production <<EOF
VITE_API_BASE_URL=https://${FUNCTION_APP_URL}/api/v1
VITE_AZURE_AD_TENANT_ID=PLACEHOLDER_TENANT_ID
VITE_AZURE_AD_CLIENT_ID=PLACEHOLDER_CLIENT_ID
VITE_AZURE_AD_REDIRECT_URI=https://${WEB_APP_NAME}.azurewebsites.net
EOF

# Rebuild with production env
npm run build

# Deploy to App Service
print_info "Deploying to Web App: $WEB_APP_NAME"

# Check if frontend dist exists
if [ ! -d "dist" ] || [ -z "$(ls -A dist 2>/dev/null)" ]; then
    print_warning "Frontend dist folder not found or empty. Skipping code deployment."
    print_warning "Build frontend first with: npm run build"
    print_info "Web App exists and will be configured, but code deployment skipped."
else
    # Create deployment package
    cd dist
    zip -r ../deployment.zip .
    cd ..
    
    # Deploy using zip deploy
    az webapp deployment source config-zip \
        --resource-group "$RESOURCE_GROUP" \
        --name "$WEB_APP_NAME" \
        --src deployment.zip
fi

# Configure app settings (updates existing or creates new)
print_info "Configuring Web App settings..."

az webapp config appsettings set \
    --name "$WEB_APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --settings \
        "WEBSITES_ENABLE_APP_SERVICE_STORAGE=false" \
        "SCM_DO_BUILD_DURING_DEPLOYMENT=false" \
    --output none

print_success "Frontend deployment complete!"
print_info "Note: Azure AD configuration needs to be updated with actual values"
print_info "Note: Private endpoint configuration may be required"

cd ..

