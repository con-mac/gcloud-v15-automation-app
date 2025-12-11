# G-Cloud Automation - Easy Auth Deployment Guide

Complete deployment guide for the Easy Auth version of the G-Cloud automation system.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Initial Setup](#initial-setup)
3. [Automated Deployment](#automated-deployment)
4. [Manual Configuration Steps](#manual-configuration-steps)
5. [Verification](#verification)
6. [Post-Deployment Configuration](#post-deployment-configuration)

## Prerequisites

### Required Tools

- **Azure CLI** (latest version)
  ```powershell
  az --version  # Verify installation
  ```
- **PowerShell 5.1 or later**
- **Git** (for cloning repositories)
- **Access to Azure Subscription** with appropriate permissions:
  - Contributor or Owner role
  - Azure AD App Registration creation permissions

### Azure Resource Providers

Register required resource providers (first time only):

```powershell
az provider register --namespace Microsoft.KeyVault
az provider register --namespace Microsoft.Web
az provider register --namespace Microsoft.Storage
az provider register --namespace Microsoft.ContainerRegistry
az provider register --namespace Microsoft.Insights
az provider register --namespace Microsoft.Network
```

Wait 1-2 minutes for registration to complete. Verify:

```powershell
az provider list --query "[?namespace=='Microsoft.Web'].registrationState" -o table
```

## Initial Setup

### 1. Clone Repository

```powershell
# Navigate to your project root
cd C:\path\to\project-root

# Clone the deployment package
git clone https://github.com/con-mac/gcloud-v15-automation-app.git pa-gcloud-easyAuth

# Navigate to deployment folder
cd pa-gcloud-easyAuth
```

### 2. Login to Azure

```powershell
az login
az account set --subscription "Your-Subscription-Name"
```

### 3. Verify Azure CLI Access

```powershell
az account show
az ad signed-in-user show
```

## Automated Deployment

### Step 1: Run Main Deployment Script

```powershell
.\deploy.ps1
```

The script will:

1. **Prompt for configuration:**
   - Resource Group name
   - Function App name
   - Web App name
   - Key Vault name
   - SharePoint site URL
   - App Registration name
   - Security groups (admin/employee)
   - Storage Account
   - Container Registry
   - Application Insights

2. **Create Azure resources:**
   - Resource Group
   - Key Vault
   - Function App (Linux Consumption)
   - Web App (Linux)
   - Storage Account
   - Container Registry
   - Application Insights
   - Private DNS Zone (optional)

3. **Deploy backend:**
   - Package Function App code
   - Deploy to Function App
   - Configure app settings
   - Set CORS origins

4. **Build and push frontend:**
   - Build Docker image in ACR
   - Push to Container Registry
   - Configure Web App to use container

5. **Configure Easy Auth:**
   - Enable Easy Auth on Function App
   - Set up Microsoft identity provider
   - Configure redirect URIs
   - Set client secret

### Step 2: Verify Deployment

```powershell
# Check Function App status
az functionapp show --name <function-app-name> --resource-group <rg-name> --query "state"

# Check Web App status
az webapp show --name <web-app-name> --resource-group <rg-name> --query "state"

# View deployment logs
az functionapp log tail --name <function-app-name> --resource-group <rg-name>
```

## Manual Configuration Steps

### ⚠️ IMPORTANT: These steps are required for Easy Auth to work correctly

### Step 1: Verify Easy Auth Configuration

1. **Go to Azure Portal:**
   - Navigate to: `https://portal.azure.com`
   - Find your Function App: `<function-app-name>`

2. **Open Authentication:**
   - Click **Authentication** in the left menu
   - Verify **Microsoft** provider is listed and enabled

3. **Check Identity Provider Settings:**
   - Click **Edit** on the Microsoft provider
   - Verify:
     - **App registration**: Your app registration name
     - **Supported account types**: "Current tenant - Single tenant"
     - **Client secret setting name**: `MICROSOFT_PROVIDER_AUTHENTICATION_SECRET`

### Step 2: Configure Allowed External Redirect URLs

**This is critical for redirecting back to the Web App after login.**

#### Option A: Using Azure CLI (Recommended)

```powershell
# Set the Web App URL as allowed external redirect
az webapp auth update `
    --name <function-app-name> `
    --resource-group <resource-group-name> `
    --allowed-external-redirect-urls "https://<web-app-name>.azurewebsites.net"

# Restart Function App
az functionapp restart --name <function-app-name> --resource-group <resource-group-name>
```

#### Option B: Using Azure Portal

1. **Go to Function App → Authentication**
2. **Click "Edit" on Microsoft provider**
3. **Scroll down to find "Advanced settings" or "Redirect URLs"**
4. **Add Web App URL:**
   ```
   https://<web-app-name>.azurewebsites.net
   ```
5. **Click "Save"**
6. **Restart Function App:**
   - Go to **Overview** → Click **Restart**

### Step 3: Verify App Registration Redirect URIs

1. **Go to Azure Portal:**
   - Navigate to **Azure Active Directory** → **App registrations**
   - Find your app registration: `<app-registration-name>`

2. **Open Authentication:**
   - Click **Authentication** in the left menu

3. **Verify Redirect URIs:**
   - Should include:
     ```
     https://<function-app-name>.azurewebsites.net/.auth/login/aad/callback
     https://<web-app-name>.azurewebsites.net
     ```

4. **If missing, add them:**
   - Click **Add a platform** → **Web**
   - Add the Function App callback URL
   - Add the Web App URL
   - Click **Save**

### Step 4: Enable ID Tokens (Required)

1. **In App Registration → Authentication:**
2. **Under "Implicit grant and hybrid flows":**
   - ✅ Check **ID tokens**
   - This is required for Easy Auth to work

3. **Click "Save"**

### Step 5: Verify Client Secret App Setting

1. **Go to Function App → Configuration:**
2. **Check Application settings:**
   - Look for: `MICROSOFT_PROVIDER_AUTHENTICATION_SECRET`
   - Should have a value (not empty)

3. **If missing or empty:**
   ```powershell
   # Get client secret from Key Vault
   $secret = az keyvault secret show --vault-name <key-vault-name> --name "AzureAdClientSecret" --query "value" -o tsv
   
   # Set as app setting
   az functionapp config appsettings set `
       --name <function-app-name> `
       --resource-group <resource-group-name> `
       --settings "MICROSOFT_PROVIDER_AUTHENTICATION_SECRET=$secret"
   ```

### Step 6: Configure SharePoint Credentials (If Needed)

If your app uses SharePoint:

1. **Go to Key Vault:**
   - Navigate to your Key Vault in Azure Portal
   - Click **Secrets**

2. **Add SharePoint credentials:**
   - **Name**: `SHAREPOINT-USERNAME`
   - **Value**: Your SharePoint username/email
   - **Name**: `SHAREPOINT-PASSWORD`
   - **Value**: Your SharePoint password (or app password)

3. **Grant Function App access:**
   ```powershell
   # Get Function App managed identity
   $principalId = az functionapp identity show --name <function-app-name> --resource-group <rg-name> --query "principalId" -o tsv
   
   # Grant Key Vault access
   az keyvault set-policy `
       --name <key-vault-name> `
       --object-id $principalId `
       --secret-permissions get list
   ```

## Verification

### Test Authentication Flow

1. **Open Web App in browser:**
   ```
   https://<web-app-name>.azurewebsites.net
   ```

2. **Click "Sign in with Microsoft 365"**

3. **Expected behavior:**
   - Redirects to Microsoft login
   - After login, redirects back to Web App (not Function App success page)
   - User should see the application, not "You have successfully signed in" page

4. **If you see success page instead:**
   - Verify "Allowed external redirect URLs" is configured (Step 2 above)
   - Check browser console for errors
   - Verify redirect URL in login link matches Web App URL

### Test Easy Auth Endpoint

```powershell
# Test Function App Easy Auth endpoint
curl -X GET "https://<function-app-name>.azurewebsites.net/.auth/me" `
     -H "Cookie: <cookies-from-browser>"

# Should return user information if authenticated
```

### Verify Backend API

1. **After logging in, check browser console:**
   - Should see API calls succeeding
   - No 401 Unauthorized errors
   - No CORS errors

2. **Check Function App logs:**
   ```powershell
   az functionapp log tail --name <function-app-name> --resource-group <rg-name>
   ```

## Post-Deployment Configuration

### Update CORS Origins (If Needed)

If you add new frontend URLs:

```powershell
az functionapp cors add `
    --name <function-app-name> `
    --resource-group <rg-name> `
    --allowed-origins "https://new-frontend-url.com"
```

### Update App Registration Redirect URIs

If you change Web App URL:

1. **Update in App Registration → Authentication**
2. **Update in Function App Easy Auth → Allowed external redirect URLs**
3. **Restart Function App**

### Monitor Application

1. **Application Insights:**
   - Go to Function App → **Application Insights**
   - View logs, metrics, and traces

2. **Function App Logs:**
   ```powershell
   az functionapp log tail --name <function-app-name> --resource-group <rg-name>
   ```

3. **Web App Logs:**
   ```powershell
   az webapp log tail --name <web-app-name> --resource-group <rg-name>
   ```

## Troubleshooting

See [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) for common issues and solutions.

## Quick Reference

### Key URLs

- **Function App**: `https://<function-app-name>.azurewebsites.net`
- **Web App**: `https://<web-app-name>.azurewebsites.net`
- **Easy Auth Login**: `https://<function-app-name>.azurewebsites.net/.auth/login/aad`
- **Easy Auth User Info**: `https://<function-app-name>.azurewebsites.net/.auth/me`
- **App Registration**: Azure Portal → Azure AD → App registrations → `<app-registration-name>`

### Key App Settings

- `MICROSOFT_PROVIDER_AUTHENTICATION_SECRET`: Client secret for Easy Auth
- `CORS_ORIGINS`: Allowed CORS origins (comma-separated)
- `KEY_VAULT_URI`: Key Vault URL for secrets
- `SHAREPOINT_SITE_ID`: SharePoint site ID
- `AZURE_AD_ADMIN_GROUP_ID`: Admin security group ID

### Useful Commands

```powershell
# Check Easy Auth status
az webapp auth show --name <function-app-name> --resource-group <rg-name>

# View app settings
az functionapp config appsettings list --name <function-app-name> --resource-group <rg-name>

# Restart Function App
az functionapp restart --name <function-app-name> --resource-group <rg-name>

# View Function App logs
az functionapp log tail --name <function-app-name> --resource-group <rg-name>
```

## Support

For issues not covered in this guide:

1. Check [TROUBLESHOOTING.md](./TROUBLESHOOTING.md)
2. Review Azure Portal logs (Function App → Log stream)
3. Check Application Insights for errors
4. Review deployment script output for errors

## Next Steps

After successful deployment:

1. Test all application features
2. Configure SharePoint integration (if needed)
3. Set up monitoring and alerts
4. Configure backup and disaster recovery
5. Set up CI/CD pipeline (optional)

