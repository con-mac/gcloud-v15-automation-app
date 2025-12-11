# G-Cloud 15 Automation Tool - Troubleshooting Guide

This guide covers common issues encountered during deployment and their solutions.

## Table of Contents

1. [Pre-Deployment Issues](#pre-deployment-issues)
2. [Deployment Issues](#deployment-issues)
3. [Post-Deployment Issues](#post-deployment-issues)
4. [Application Issues](#application-issues)
5. [Azure Portal Manual Fixes](#azure-portal-manual-fixes)

---

## Pre-Deployment Issues

### Issue: Resource Provider Not Registered

**Error Message:**
```
ERROR: (InvalidResourceNamespace) The resource namespace 'Microsoft.KeyVault' is not registered in the subscription
```

**Root Cause:** New Azure subscriptions don't have all resource providers registered by default.

**Solution:**
1. **Via Azure Portal:**
   - Navigate to: **Subscriptions** → **Your Subscription** → **Resource providers**
   - Search for and register: `Microsoft.KeyVault`, `Microsoft.Web`, `Microsoft.Storage`, `Microsoft.ContainerRegistry`, `Microsoft.Insights`, `Microsoft.Network`
   - Wait 1-2 minutes for registration to complete

2. **Via Azure CLI:**
   ```powershell
   az provider register --namespace Microsoft.KeyVault
   az provider register --namespace Microsoft.Web
   az provider register --namespace Microsoft.Storage
   az provider register --namespace Microsoft.ContainerRegistry
   az provider register --namespace Microsoft.Insights
   az provider register --namespace Microsoft.Network
   ```

**Prevention:** Always register resource providers before first deployment.

---

### Issue: Key Vault Name Already Exists (Soft-Deleted)

**Error Message:**
```
ERROR: (VaultAlreadyExists) The vault name 'pa-gcloud15-kv' is already in use.
```

**Root Cause:** Key Vault was previously deleted but is still in soft-delete state (90-day retention).

**Solution:**
1. **Purge the soft-deleted vault:**
   ```powershell
   az keyvault purge --name pa-gcloud15-kv --location <region>
   ```
   Or use a different name with random suffix (recommended).

2. **Use random suffix (recommended):** The deployment script now automatically adds a random 3-digit suffix to prevent conflicts.

**Prevention:** Always use unique names with random suffixes for globally unique resources.

---

### Issue: Key Vault Name Too Long

**Error Message:**
```
ERROR: (VaultNameNotValid) The vault name 'pa-gcloud15-kv-0tl-0tlqir' is invalid.
```

**Root Cause:** Key Vault names must be 3-24 characters, alphanumeric and hyphens only.

**Solution:** Ensure the random suffix doesn't make the name exceed 24 characters. The deployment script validates this automatically.

---

## Deployment Issues

### Issue: Storage Account Name Already Exists

**Error Message:**
```
ERROR: The storage account name 'pagcloud15st' is already taken.
```

**Root Cause:** Storage account names must be globally unique across all Azure subscriptions.

**Solution:** The deployment script now automatically adds a random 3-digit suffix to storage account names.

**Prevention:** Always use random suffixes for globally unique resources.

---

### Issue: Function App Name Mismatch in Config

**Symptom:** Scripts fail with `ResourceNotFound` errors, but the Function App exists in Azure Portal.

**Root Cause:** The `FUNCTION_APP_NAME` in `config/deployment-config.env` doesn't match the actual Function App name (often due to double suffix or manual changes).

**Solution:**
1. **Find actual Function App name:**
   ```powershell
   az functionapp list --resource-group pa-gcloud15-rg --query "[0].name" -o tsv
   ```

2. **Update config file:**
   ```powershell
   $configPath = "config\deployment-config.env"
   $actualFunctionApp = az functionapp list --resource-group pa-gcloud15-rg --query "[0].name" -o tsv
   $content = Get-Content $configPath -Raw
   $content = $content -replace "FUNCTION_APP_NAME=.*", "FUNCTION_APP_NAME=$actualFunctionApp"
   $content | Set-Content $configPath -Encoding UTF8
   ```

**Prevention:** Always verify resource names match between config file and Azure Portal after deployment.

---

## Post-Deployment Issues

### Issue: CORS Policy Error

**Error Message (Browser Console):**
```
Access to XMLHttpRequest at 'https://pa-gcloud15-api-14sxir.azurewebsites.net/api/v1/...' 
from origin 'https://pa-gcloud15-web-14sxir.azurewebsites.net' has been blocked by CORS policy: 
No 'Access-Control-Allow-Origin' header is present on the requested resource.
```

**Root Cause:** Function App CORS settings are not configured correctly or don't include the frontend URL.

**Solution - Azure Portal (Recommended):**

1. **Navigate to Function App:**
   - Go to Azure Portal → **Function Apps** → `pa-gcloud15-api-14sxir` (or your Function App name)

2. **Open CORS Settings:**
   - Click **API** → **CORS** in the left menu

3. **Add Frontend URL:**
   - Click **+ Add** 
   - Enter your frontend URL: `https://pa-gcloud15-web-14sxir.azurewebsites.net` (replace with your actual Web App URL)
   - Also add: `http://localhost:3000`, `http://localhost:5173` (for local development)

4. **Enable Access-Control-Allow-Credentials:**
   - Check the box: **Enable Access-Control-Allow-Credentials**
   - This is **CRITICAL** for SSO to work

5. **Save:**
   - Click **Save** at the top

6. **Restart Function App:**
   ```powershell
   az functionapp restart --name pa-gcloud15-api-14sxir --resource-group pa-gcloud15-rg
   ```

**Solution - Azure CLI:**
```powershell
$FUNCTION_APP_NAME = "pa-gcloud15-api-14sxir"
$RESOURCE_GROUP = "pa-gcloud15-rg"
$WEB_APP_URL = "https://pa-gcloud15-web-14sxir.azurewebsites.net"

az functionapp cors add \
  --name $FUNCTION_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --allowed-origins $WEB_APP_URL http://localhost:3000 http://localhost:5173

az functionapp cors credential enable \
  --name $FUNCTION_APP_NAME \
  --resource-group $RESOURCE_GROUP

az functionapp restart --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP
```

**Prevention:** CORS should be configured automatically during deployment, but verify after deployment.

---

### Issue: Key Vault Reference Errors

**Error Message:**
```
MSINotEnabled: Reference was not able to be resolved because site Managed Identity not enabled
```

**Or:**
```
AccessToKeyVaultDenied: Access denied to Key Vault
```

**Root Cause:** Function App's managed identity is not enabled or doesn't have Key Vault access.

**Solution:**

1. **Enable Managed Identity:**
   ```powershell
   $FUNCTION_APP_NAME = "pa-gcloud15-api-14sxir"
   $RESOURCE_GROUP = "pa-gcloud15-rg"
   
   az functionapp identity assign --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP
   ```

2. **Get Principal ID:**
   ```powershell
   $principalId = az functionapp identity show --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP --query principalId -o tsv
   ```

3. **Get Key Vault Resource ID:**
   ```powershell
   $KEY_VAULT_NAME = "pa-gcloud15-kv-14sxir"  # Your actual Key Vault name
   $kvId = az keyvault show --name $KEY_VAULT_NAME --resource-group $RESOURCE_GROUP --query id -o tsv
   ```

4. **Grant Key Vault Access:**
   ```powershell
   az role assignment create --role "Key Vault Secrets User" --assignee $principalId --scope $kvId
   ```

5. **Refresh Key Vault References (Azure Portal):**
   - Go to Function App → **Configuration** → **Application settings**
   - Find settings with Key Vault references (showing "Key vault" as source)
   - Click **Edit** on each Key Vault reference setting
   - Click **Save** (even without changes) - this forces Azure to refresh the reference
   - Repeat for all Key Vault references:
     - `AZURE_AD_TENANT_ID`
     - `AZURE_AD_CLIENT_ID`
     - `AZURE_AD_CLIENT_SECRET`

6. **Restart Function App:**
   ```powershell
   az functionapp restart --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP
   ```

**Prevention:** Managed identity and Key Vault access should be configured automatically during deployment.

---

### Issue: SSO Not Working - "SSO is not configured"

**Symptom:** Frontend shows "SSO is not configured" message, MSAL login fails.

**Root Cause:** SSO environment variables are not injected into the frontend Docker image at build time.

**Solution:**

1. **Rebuild Frontend Image with SSO Config:**
   ```powershell
   .\scripts\build-and-push-images.ps1
   ```
   This script automatically injects SSO configuration as build arguments.

2. **Verify SSO Configuration in Portal:**
   - Go to Web App → **Configuration** → **Application settings**
   - Verify these are set (should be set automatically):
     - `VITE_AZURE_AD_TENANT_ID`
     - `VITE_AZURE_AD_CLIENT_ID`
     - `VITE_AZURE_AD_REDIRECT_URI`
     - `VITE_AZURE_AD_ADMIN_GROUP_ID`
     - `VITE_API_BASE_URL`

3. **Restart Web App:**
   ```powershell
   az webapp restart --name pa-gcloud15-web-14sxir --resource-group pa-gcloud15-rg
   ```

**Prevention:** SSO configuration should be handled automatically by `configure-auth.ps1` and `build-and-push-images.ps1`.

---

### Issue: Web App 503 Error

**Error Message:**
```
503 Service Unavailable
Application Error
```

**Root Cause:** Docker container is crashing or not starting properly.

**Solution:**

1. **Check Docker Configuration:**
   ```powershell
   az webapp config container show --name pa-gcloud15-web-14sxir --resource-group pa-gcloud15-rg
   ```
   Verify the image name is correct: `DOCKER|pagcloud15acr14sxir.azurecr.io/frontend:latest`

2. **Check Logs:**
   - Go to Web App → **Log stream** in Azure Portal
   - Look for startup errors

3. **Verify Image Exists in ACR:**
   ```powershell
   az acr repository show-tags --name pagcloud15acr14sxir --repository frontend --output table
   ```

4. **Restart Web App:**
   ```powershell
   az webapp restart --name pa-gcloud15-web-14sxir --resource-group pa-gcloud15-rg
   ```

**Prevention:** Ensure Docker image is built and pushed before deploying Web App.

---

## Application Issues

### Issue: Questionnaire 500 Error

**Error Message:**
```
GET https://pa-gcloud15-api-14sxir.azurewebsites.net/api/v1/questionnaire/questions/2a 500 (Internal Server Error)
```

**Root Cause:** Questionnaire Excel file is not deployed to Azure Functions, or parser initialization failed.

**Solution:**

1. **Check if Excel File Exists:**
   - The file should be at: `backend/docs/RM1557.15-G-Cloud-question-export (1).xlsx`
   - Verify it's included in the Function App deployment

2. **Deploy Excel File:**
   - Ensure the `docs` folder is included when deploying Function App
   - The `deploy-functions.ps1` script should include it automatically

3. **Check Function App Logs:**
   - Go to Function App → **Log stream** in Azure Portal
   - Look for "Questionnaire Excel file not found" errors

**Prevention:** Ensure `docs` folder is included in Function App deployment package.

---

### Issue: Proposals Not Appearing on Dashboard

**Symptom:** Saved drafts don't appear in the proposals list.

**Root Cause:** 
1. `metadata.json` file is not being created when saving drafts
2. Owner name mismatch between metadata and SSO user display name
3. Proposals list is looking for wrong metadata file format

**Solution:**

1. **Verify Metadata File Creation:**
   - When saving a draft, the system should automatically create/update `metadata.json`
   - Check Azure Blob Storage or SharePoint for the file

2. **Verify Owner Name:**
   - The owner in `metadata.json` should match the SSO user's display name (not email)
   - Check the `X-User-Name` header is being sent from frontend

3. **Check Proposals List Logic:**
   - The proposals list looks for `metadata.json` files
   - Verify the file exists in: `GCloud 15/PA Services/Cloud Support Services LOT {lot}/{service_name}/metadata.json`

**Prevention:** Metadata creation is handled automatically by the document generation endpoint.

---

### Issue: Document Generation Error

**Error Message:**
```
Error: Document generation failed: unsupported operand type(s) for /: 'NoneType' and 'str'
```

**Root Cause:** `MOCK_BASE_PATH` or `folder_path` is `None` in Azure environment.

**Solution:** This should be fixed in the latest code. If it persists:

1. **Verify Azure Storage Connection:**
   ```powershell
   az functionapp config appsettings list --name pa-gcloud15-api-14sxir --resource-group pa-gcloud15-rg --query "[?name=='AZURE_STORAGE_CONNECTION_STRING']"
   ```

2. **Check Function App Logs:**
   - Look for "MOCK_BASE_PATH is None" errors
   - Verify Azure Blob Storage is being used instead of local filesystem

**Prevention:** Code now includes comprehensive `None` checks for path operations.

---

## Azure Portal Manual Fixes

### Updating Function App Configuration

1. **Navigate to Function App:**
   - Azure Portal → **Function Apps** → `pa-gcloud15-api-14sxir`

2. **Open Configuration:**
   - Click **Configuration** → **Application settings**

3. **Edit Settings:**
   - Click **+ New application setting** to add
   - Click **Edit** (pencil icon) to modify
   - Click **Delete** to remove

4. **Save Changes:**
   - Click **Save** at the top
   - Function App will restart automatically

### Updating Web App Configuration

1. **Navigate to Web App:**
   - Azure Portal → **App Services** → `pa-gcloud15-web-14sxir`

2. **Open Configuration:**
   - Click **Configuration** → **Application settings**

3. **Edit Settings:**
   - Same process as Function App

4. **Save and Restart:**
   - Click **Save**
   - Restart Web App if needed

### Viewing Logs

**Function App Logs:**
1. Go to Function App → **Log stream**
2. Or: **Monitoring** → **Log stream**

**Web App Logs:**
1. Go to Web App → **Log stream**
2. Or: **Monitoring** → **Log stream**

**Application Insights:**
1. Go to Function App → **Application Insights**
2. Click **View Application Insights data**
3. Use **Logs** or **Metrics** for detailed analysis

---

## Quick Reference Commands

### Check Resource Status
```powershell
# List all resources in resource group
az resource list --resource-group pa-gcloud15-rg --output table

# Check Function App status
az functionapp show --name pa-gcloud15-api-14sxir --resource-group pa-gcloud15-rg --query "state" -o tsv

# Check Web App status
az webapp show --name pa-gcloud15-web-14sxir --resource-group pa-gcloud15-rg --query "state" -o tsv
```

### Restart Services
```powershell
# Restart Function App
az functionapp restart --name pa-gcloud15-api-14sxir --resource-group pa-gcloud15-rg

# Restart Web App
az webapp restart --name pa-gcloud15-web-14sxir --resource-group pa-gcloud15-rg
```

### View Configuration
```powershell
# Function App settings
az functionapp config appsettings list --name pa-gcloud15-api-14sxir --resource-group pa-gcloud15-rg --output table

# Web App settings
az webapp config appsettings list --name pa-gcloud15-web-14sxir --resource-group pa-gcloud15-rg --output table
```

### Fix Config File
```powershell
# Auto-fix FUNCTION_APP_NAME in config
$configPath = "config\deployment-config.env"
$actualFunctionApp = az functionapp list --resource-group pa-gcloud15-rg --query "[0].name" -o tsv
$content = Get-Content $configPath -Raw
$content = $content -replace "FUNCTION_APP_NAME=.*", "FUNCTION_APP_NAME=$actualFunctionApp"
$content | Set-Content $configPath -Encoding UTF8
Write-Host "Fixed! FUNCTION_APP_NAME is now: $actualFunctionApp" -ForegroundColor Green
```

---

## Getting Help

If you encounter issues not covered in this guide:

1. **Check Azure Portal Logs:**
   - Function App → **Log stream**
   - Web App → **Log stream**
   - Application Insights → **Logs**

2. **Verify Configuration:**
   - Compare `config/deployment-config.env` with actual Azure resources
   - Ensure all resource names match

3. **Check Deployment Scripts:**
   - Review script output for errors
   - Verify all prerequisites are met

4. **Contact Support:**
   - Include error messages
   - Include relevant log snippets
   - Include configuration (redact secrets)



