#!/bin/bash

# Configure Authentication Script
# Sets up Microsoft 365 SSO integration

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

print_info "Configuring Microsoft 365 SSO authentication..."

# Check if App Registration exists
print_info "Checking for App Registration: $APP_REGISTRATION_NAME"
APP_ID=$(az ad app list --display-name "$APP_REGISTRATION_NAME" --query "[0].appId" -o tsv)

if [ -z "$APP_ID" ] || [ "$APP_ID" == "null" ]; then
    print_warning "App Registration not found. Creating..."
    
    # Get Web App URL
    WEB_APP_URL="https://${WEB_APP_NAME}.azurewebsites.net"
    
    # Create App Registration
    APP_ID=$(az ad app create \
        --display-name "$APP_REGISTRATION_NAME" \
        --web-redirect-uris "${WEB_APP_URL}/auth/callback" \
        --query appId -o tsv)
    
    print_success "App Registration created: $APP_ID"
    
    # Create service principal
    az ad sp create --id "$APP_ID" --output none
    
    # Add API permissions for SharePoint/Graph
    print_info "Adding API permissions for SharePoint/Graph API..."
    
    # Microsoft Graph API ID
    GRAPH_API_ID="00000003-0000-0000-c000-000000000000"
    
    # Get existing permissions
    EXISTING_PERMS=$(az ad app show --id "$APP_ID" --query "requiredResourceAccess" -o json)
    
    # Add User.Read permission
    print_info "Adding User.Read permission..."
    az ad app permission add \
        --id "$APP_ID" \
        --api "$GRAPH_API_ID" \
        --api-permissions "e1fe6dd8-ba31-4d61-89e7-88639da4683d=Scope" \
        --output none 2>/dev/null || true
    
    # Add Sites.ReadWrite.All permission (for SharePoint)
    print_info "Adding Sites.ReadWrite.All permission..."
    az ad app permission add \
        --id "$APP_ID" \
        --api "$GRAPH_API_ID" \
        --api-permissions "205e70e5-aba6-4c52-a976-6d2d8c5c5e77=Scope" \
        --output none 2>/dev/null || true
    
    # Add Files.ReadWrite.All permission (alternative/additional for file operations)
    print_info "Adding Files.ReadWrite.All permission..."
    az ad app permission add \
        --id "$APP_ID" \
        --api "$GRAPH_API_ID" \
        --api-permissions "75359482-378d-4052-8f01-80520e7db3cd=Scope" \
        --output none 2>/dev/null || true
    
    # Add offline_access permission
    print_info "Adding offline_access permission..."
    az ad app permission add \
        --id "$APP_ID" \
        --api "$GRAPH_API_ID" \
        --api-permissions "7427e0e9-2fba-42fe-b0c0-848c9e6a8182=Scope" \
        --output none 2>/dev/null || true
    
    # Grant admin consent
    print_info "Granting admin consent for API permissions..."
    read -p "Grant admin consent now? (y/n) [y]: " grant_consent
    if [[ "${grant_consent:-y}" == "y" ]]; then
        az ad app permission admin-consent --id "$APP_ID" --output none
        print_success "Admin consent granted"
    else
        print_warning "Admin consent not granted. You'll need to grant it manually in Azure Portal."
        print_warning "Go to: App Registration -> API permissions -> Grant admin consent"
    fi
else
    print_success "App Registration found: $APP_ID"
fi

# Create client secret
print_info "Creating client secret..."
SECRET=$(az ad app credential reset --id "$APP_ID" --query password -o tsv)

# Store in Key Vault
az keyvault secret set \
    --vault-name "$KEY_VAULT_NAME" \
    --name "AzureADClientId" \
    --value "$APP_ID" \
    --output none

az keyvault secret set \
    --vault-name "$KEY_VAULT_NAME" \
    --name "AzureADClientSecret" \
    --value "$SECRET" \
    --output none

# Get tenant ID
TENANT_ID=$(az account show --query tenantId -o tsv)

az keyvault secret set \
    --vault-name "$KEY_VAULT_NAME" \
    --name "AzureADTenantId" \
    --value "$TENANT_ID" \
    --output none

# Update Function App settings
print_info "Updating Function App with authentication settings..."
az functionapp config appsettings set \
    --name "$FUNCTION_APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --settings \
        "AZURE_AD_TENANT_ID=@Microsoft.KeyVault(SecretUri=https://${KEY_VAULT_NAME}.vault.azure.net/secrets/AzureADTenantId/)" \
        "AZURE_AD_CLIENT_ID=@Microsoft.KeyVault(SecretUri=https://${KEY_VAULT_NAME}.vault.azure.net/secrets/AzureADClientId/)" \
        "AZURE_AD_CLIENT_SECRET=@Microsoft.KeyVault(SecretUri=https://${KEY_VAULT_NAME}.vault.azure.net/secrets/AzureADClientSecret/)" \
    --output none

# Update Web App settings
print_info "Updating Web App with authentication settings..."
az webapp config appsettings set \
    --name "$WEB_APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --settings \
        "VITE_AZURE_AD_TENANT_ID=$TENANT_ID" \
        "VITE_AZURE_AD_CLIENT_ID=$APP_ID" \
        "VITE_AZURE_AD_REDIRECT_URI=${WEB_APP_URL}/auth/callback" \
    --output none

# Configure SharePoint site permissions (if SharePoint is configured)
if [ -n "$SHAREPOINT_SITE_URL" ] && [ -n "$SHAREPOINT_SITE_ID" ]; then
    print_info "Configuring SharePoint site permissions..."
    read -p "Grant App Registration access to SharePoint site? (y/n) [y]: " grant_sharepoint
    if [[ "${grant_sharepoint:-y}" == "y" ]]; then
        print_info "To grant SharePoint permissions, you can:"
        print_info "1. Go to SharePoint site: $SHAREPOINT_SITE_URL"
        print_info "2. Settings -> Site permissions -> Grant permissions"
        print_info "3. Add App Registration: $APP_REGISTRATION_NAME"
        print_info "4. Grant 'Edit' or 'Full Control' permissions"
        print_info ""
        print_info "Or use PowerShell:"
        print_info "  \$siteId = '$SHAREPOINT_SITE_ID'"
        print_info "  \$appId = '$APP_ID'"
        print_info "  az rest --method POST --uri \"https://graph.microsoft.com/v1.0/sites/\$siteId/permissions\" --body \"{'roles':['write'],'grantedToIdentities':[{'application':{'id':'\$appId'}}]}\""
    fi
fi

print_success "Authentication configuration complete!"
if [ -z "$SHAREPOINT_SITE_URL" ] || [ -z "$SHAREPOINT_SITE_ID" ]; then
    print_warning "SharePoint not configured. Configure SharePoint site permissions manually if needed."
fi

