# G-Cloud 15 Automation Tool - PA Deployment Guide

Complete deployment guide for deploying the G-Cloud 15 automation tool to PA Consulting's Azure dev environment.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Initial Deployment](#initial-deployment)
3. [SSO Configuration](#sso-configuration)
4. [Frontend Docker Image Rebuild](#frontend-docker-image-rebuild)
5. [Redeployment](#redeployment)
6. [Troubleshooting](#troubleshooting)

## Prerequisites

### Required Software
- Azure CLI installed and configured
- PowerShell 5.1 or later
- Access to PA Consulting's Azure subscription
- Appropriate Azure AD permissions (for App Registration and security groups)

### **CRITICAL: Register Resource Providers (New Subscriptions Only)**

**If this is a new Azure subscription, you MUST register resource providers BEFORE running deploy.ps1:**

1. **Go to Azure Portal:**
   - Navigate to: **Subscriptions** → **Your Subscription** → **Resource providers**

2. **Register the following providers** (click "Register" for each):
   - `Microsoft.KeyVault`
   - `Microsoft.Web`
   - `Microsoft.Storage`
   - `Microsoft.ContainerRegistry`
   - `Microsoft.Insights`
   - `Microsoft.Network`

3. **Wait 1-2 minutes** for registration to complete (status will show "Registered")

4. **Alternative: Use Azure CLI** (if you prefer):
   ```powershell
   az provider register --namespace Microsoft.KeyVault
   az provider register --namespace Microsoft.Web
   az provider register --namespace Microsoft.Storage
   az provider register --namespace Microsoft.ContainerRegistry
   az provider register --namespace Microsoft.Insights
   az provider register --namespace Microsoft.Network
   
   # Check status
   az provider show --namespace Microsoft.KeyVault --query "registrationState" -o tsv
   # Should return: "Registered"
   ```

**Why this is needed:** New Azure subscriptions don't have all resource providers registered by default. Without registration, resource creation will fail with "namespace not registered" errors.

## Initial Deployment

### Step 1: Run Main Deployment Script

From the deployment package directory:

```powershell
cd C:\path\to\pa-gcloud-automation
.\deploy.ps1
```

The script will guide you through:
- Resource group selection/creation
- Function App configuration
- Web App configuration
- Key Vault setup
- SharePoint site configuration
- App Registration selection/creation
- Storage Account configuration
- Azure Container Registry (ACR) configuration
- Private DNS Zone configuration
- Application Insights configuration
- VNet and Private Endpoint configuration (optional)
- Admin and Employee Security Group configuration

**Important Notes:**
- You can use existing resources or create new ones
- Private endpoints can be configured now or later (for testing, skip initially)
- Security groups are required for SSO - the admin group determines access to the admin dashboard

### Step 2: Deployment Process

The `deploy.ps1` script automatically:
1. Creates/verifies all Azure resources
2. Deploys the backend (Function App)
3. Builds and pushes the frontend Docker image to ACR (if needed)
4. Deploys the frontend (Web App) using the Docker image
5. Configures SSO authentication (runs `configure-auth.ps1` without PowerShell profile)

## SSO Configuration

SSO configuration is handled automatically by `deploy.ps1`, but if you need to run it separately:

### Running SSO Configuration Manually

**Important:** Due to PowerShell profile error handlers that can intercept JSON parsing, run the script without the profile:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\configure-auth.ps1
```

```powershell
cd C:\Users\conor\Documents\Projects\G-Cloud
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\configure-auth.ps1
```

This script:
- Creates/updates the App Registration client secret
- Configures Function App with SSO settings (using Key Vault references)
- Configures Web App with SSO settings (including admin group ID)
- Stores credentials in Key Vault
- Attempts to grant SharePoint permissions

**Why -NoProfile?**
The PowerShell profile may contain error handlers that intercept JSON parsing errors when Azure CLI outputs warnings. Running without the profile bypasses these handlers and allows the script to use regex extraction for the client secret.

## SharePoint Configuration

**IMPORTANT:** SharePoint access requires **THREE security layers** to be configured correctly. See the detailed step-by-step guide:

📖 **[SharePoint Setup - Step-by-Step Guide](./SHAREPOINT-SETUP-STEP-BY-STEP.md)**

### Quick Overview

After running `deploy.ps1` and `configure-auth.ps1`, you must complete these **REQUIRED** manual steps:

1. **Grant Admin Consent** (Azure Portal - REQUIRED)
   - Azure AD → App registrations → `pa-gcloud15-app` → API permissions → Grant admin consent
   - See [Step 2 in SharePoint Setup Guide](./SHAREPOINT-SETUP-STEP-BY-STEP.md#step-2-grant-admin-consent-required---manual)

2. **Grant Site-Level Permissions** (SharePoint - REQUIRED)
   - SharePoint Site → Settings → Site permissions → Add App Registration
   - See [Step 3 in SharePoint Setup Guide](./SHAREPOINT-SETUP-STEP-BY-STEP.md#step-3-grant-site-level-permissions-required---manual)

3. **Verify Key Vault Access** (Automated script)
   ```powershell
   # See TROUBLESHOOTING.md for Key Vault access fix steps
   ```

4. **Set Key Vault References** (Azure Portal recommended)
   - Function App → Configuration → Add Key Vault references for Azure AD credentials
   - See [Step 5 in SharePoint Setup Guide](./SHAREPOINT-SETUP-STEP-BY-STEP.md#step-5-set-key-vault-references-in-function-app)

5. **Restart and Test**
   ```powershell
   az functionapp restart --name pa-gcloud15-api --resource-group pa-gcloud15-rg
   curl https://pa-gcloud15-api.azurewebsites.net/api/v1/sharepoint/test
   ```

**For complete instructions with copy-paste commands and verification steps, see: [SHAREPOINT-SETUP-STEP-BY-STEP.md](./SHAREPOINT-SETUP-STEP-BY-STEP.md)**

## Frontend Docker Image Rebuild

After SSO configuration, you **must** rebuild the frontend Docker image so it includes the actual SSO configuration values (Tenant ID, Client ID, Admin Group ID) at build time.

### Step 1: Rebuild Frontend Image

```powershell
cd C:\Users\conor\Documents\Projects\G-Cloud
.\scripts\build-and-push-images.ps1
```

When prompted:
- Select **Option 1** (ACR build) - builds in Azure cloud, no local Docker needed
- The script automatically retrieves SSO configuration and passes it as build arguments

### Step 2: Redeploy Frontend

After the image is built:

```powershell
.\scripts\build-and-push-images.ps1
```

This pulls the new image with SSO configuration and updates the Web App.

## Redeployment

### Full Redeployment

If you need to redeploy everything:

1. **Keep these resources** (don't delete):
   - App Registration (contains SSO configuration)
   - Security Groups (Admin and Employee groups)
   - Key Vault (contains secrets)

2. **Run deployment:**
   ```powershell
   .\pa-deployment\deploy.ps1
   ```
   - Select existing App Registration
   - Select existing Security Groups
   - Select existing Key Vault

3. **Rebuild frontend image** (SSO values are embedded at build time):
   ```powershell
   .\scripts\build-and-push-images.ps1
   ```

4. **Redeploy frontend:**
   ```powershell
   .\scripts\build-and-push-images.ps1
   ```

### Code-Only Updates

For backend code changes:
```powershell
.\scripts\deploy-functions.ps1
```

For frontend code changes:
1. Rebuild image: `.\scripts\build-and-push-images.ps1`
2. Redeploy: `.\scripts\build-and-push-images.ps1`

## Config File Override

The deployment uses `config\deployment-config.env` to store resource names. You can override values in two ways:

### Method 1: Edit Config File Before Deployment

1. Edit `config\deployment-config.env`
2. Change any values (e.g., `FUNCTION_APP_NAME`, `WEB_APP_NAME`)
3. Run `.\deploy.ps1` - it will use your values

### Method 2: Auto-Fix Config File

If your config file has wrong values (e.g., wrong Function App name):

```powershell
# Auto-fix config (see TROUBLESHOOTING.md for manual steps)
```

This script:
- Detects actual Function App name from Azure
- Updates `FUNCTION_APP_NAME` in config file
- Shows next steps

### Method 3: Delete and Recreate

To start fresh:
1. Delete `config\deployment-config.env`
2. Run `.\deploy.ps1`
3. Answer prompts to create new config

### After Config Changes

If you change `FUNCTION_APP_NAME` or `WEB_APP_NAME`, you must:

1. **Rebuild Docker image** (to include correct API URL):
   ```powershell
   .\scripts\build-and-push-images.ps1
   ```

2. **Redeploy frontend**:
   ```powershell
   .\scripts\build-and-push-images.ps1
   ```

3. **Restart Web App**:
   ```powershell
   az webapp restart --name <WEB_APP_NAME> --resource-group <RESOURCE_GROUP>
   ```

## Testing SharePoint Connectivity

After deployment, test SharePoint connectivity:

### Automated Test

```powershell
# Manual test (see below)
```

### Manual Test (curl)

```powershell
curl https://<FUNCTION_APP_NAME>.azurewebsites.net/api/v1/sharepoint/test
```

Replace `<FUNCTION_APP_NAME>` with your actual Function App name (e.g., `pa-gcloud15-api-14sxir`).

**Expected Response:**
```json
{
  "connected": true,
  "site_id": "...",
  "site_url": "https://...",
  "message": "Successfully connected to SharePoint"
}
```

**If you see "Tenant does not have SPO license":**
- This is a test tenant limitation
- Will work in production tenant
- Not a blocker for deployment verification

**If you see "SharePoint credentials not configured":**
- Run: `.\pa-deployment\scripts\fix-keyvault-access.ps1`
- Verify Key Vault secrets are set
- Check managed identity is enabled

## Troubleshooting

### SSO Not Working / "SSO is not configured" Message

**Cause:** Frontend Docker image was built before SSO configuration.

**Solution:**
1. Ensure SSO is configured: `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\configure-auth.ps1`
2. Rebuild frontend image: `.\scripts\build-and-push-images.ps1`
3. Redeploy frontend: `.\scripts\build-and-push-images.ps1`

### "Failed to parse client secret response" Error

**Cause:** PowerShell profile error handlers intercepting JSON parsing.

**Solution:** Always run `configure-auth.ps1` without profile:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\configure-auth.ps1
```

The script uses regex extraction to get the password, which works even when warnings are present in the output.

### Frontend Shows Blank Page

**Possible causes:**
1. Docker image not deployed correctly
2. Container failed to start

**Solution:**
1. Check Web App logs: `az webapp log tail --name <WEB_APP_NAME> --resource-group <RESOURCE_GROUP>`
2. Verify image exists in ACR: `az acr repository show-tags --name <ACR_NAME> --repository frontend`
3. Redeploy frontend: `.\scripts\build-and-push-images.ps1`

### Backend Not Responding

**Possible causes:**
1. Function App not deployed
2. CORS configuration issue
3. Python dependencies not installed

   **IMPORTANT:** Azure Function Apps have built-in CORS settings that override application-level CORS.
   
   **Fix via Azure Portal (REQUIRED):**
   1. Go to Azure Portal: https://portal.azure.com
   2. Navigate to your Function App: `pa-gcloud15-api-14sxir` (or your actual Function App name)
   3. In the left menu, under **Settings**, click **"CORS"**
   4. In the **"Allowed Origins"** section, add each origin (one per line or comma-separated):
      - `https://pa-gcloud15-web-14sxir.azurewebsites.net` (use your actual Web App name)
      - `http://localhost:3000` (for local development)
      - `http://localhost:5173` (for local development)
   5. **Enable** "Access-Control-Allow-Credentials" if you're using authentication
   6. Click **"Save"** at the top
   7. Restart the Function App: Go to **Overview** → Click **"Restart"**
   8. Wait 30 seconds for changes to take effect
   
   **Note:** Replace `pa-gcloud15-web-14sxir` with your actual Web App name (check your `deployment-config.env` file for `WEB_APP_NAME`)
   
   **Alternative - PowerShell script:**
   ```powershell
   # See TROUBLESHOOTING.md for CORS fix steps
   ```
   
   **Note:** The `CORS_ORIGINS` app setting is not sufficient - you must configure CORS at the Function App level in Azure Portal.

**Solution:**
1. Check Function App status: `az functionapp show --name <FUNCTION_APP_NAME> --resource-group <RESOURCE_GROUP>`
2. Redeploy backend: `.\scripts\deploy-functions.ps1`
3. Verify CORS settings in `backend/app/core/config.py` include the frontend URL

### ModuleNotFoundError: No module named 'fastapi' (Dependency Installation)

**Cause:** Azure Functions Python dependencies are not automatically installed with zip deployment. The `SCM_DO_BUILD_DURING_DEPLOYMENT` setting alone is unreliable for Function Apps.

**Solution: Use Azure Functions Core Tools (REQUIRED)**

Azure Functions Core Tools is the **only reliable method** to install Python dependencies in Azure Functions. Zip deployment does not reliably trigger dependency installation.

**Step 1: Install Azure Functions Core Tools**

Download and install from:
- **Direct Download:** https://github.com/Azure/azure-functions-core-tools/releases/latest
- Download `Azure.Functions.Cli.win-x64.msi` and install it
- Or use npm: `npm install -g azure-functions-core-tools@4`

**Step 2: Verify Installation**

```powershell
func --version
```

You should see a version number (e.g., `4.5.0`).

**Step 3: Deploy with Dependencies**

```powershell
.\scripts\deploy-functions.ps1
```

This script:
- Uses `func azure functionapp publish` which properly installs dependencies
- Automatically installs all packages from `requirements.txt` during deployment
- Uses remote build in Azure (no local Python/Docker needed)

**Why This Works:**
- Azure Functions Core Tools uses remote build which properly installs dependencies
- Zip deployment with `SCM_DO_BUILD_DURING_DEPLOYMENT` is unreliable
- Manual installation via SSH is not possible (pip not available in runtime)

**Note:** The main `deploy.ps1` script uses zip deployment for speed, but for dependency installation, always use `deploy-with-dependencies.ps1` after initial deployment.

### SharePoint Permissions

If SharePoint permissions fail to grant automatically:

1. Go to SharePoint site: `https://<tenant>.sharepoint.com/sites/<site-name>`
2. Settings → Site permissions → Grant permissions
3. Add App Registration: `<APP_REGISTRATION_NAME>`
4. Grant 'Edit' or 'Full Control' permissions

## Key Configuration Files

- `config/deployment-config.env` - Deployment configuration (auto-generated by deploy.ps1)
- `deploy.ps1` - Main deployment script
- `scripts/configure-auth.ps1` - SSO configuration script
- `scripts/build-and-push-images.ps1` - Docker image build script
- `scripts/deploy-functions.ps1` - Backend deployment script
- `scripts/setup-resources.ps1` - Azure resource creation script

## Architecture Overview

- **Frontend:** React app served via Nginx in Docker container (Azure Web App)
- **Backend:** FastAPI application (Azure Function App)
- **Authentication:** Microsoft 365 SSO via Azure AD App Registration
- **Storage:** SharePoint for document storage
- **Secrets:** Azure Key Vault
- **Container Registry:** Azure Container Registry (ACR) for Docker images
- **Security:** Azure AD Security Groups for role-based access (Admin vs Employee)

## Support

For issues or questions, refer to:
- Azure Portal logs for detailed error messages
- Application Insights for application telemetry
- Azure CLI commands for resource status

---

**Last Updated:** After SSO milestone - All fixes for JSON parsing and SSO configuration are now integrated into the deployment scripts.

