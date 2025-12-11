# Set Key Vault References via Azure Portal

If the PowerShell script fails, set Key Vault references manually in Azure Portal:

## Steps

1. **Go to Azure Portal:**
   - https://portal.azure.com

2. **Navigate to Function App:**
   - Function App → `pa-gcloud15-api-14sxir` (or your Function App name)
   - Settings → **Configuration**

3. **Add each setting:**
   - Click **"+ New application setting"** for each:

   **Setting 1:**
   - Name: `AZURE_AD_TENANT_ID`
   - Value: `@Microsoft.KeyVault(SecretUri=https://pa-gcloud15-kv-14sxir.vault.azure.net/secrets/AzureADTenantId/)`
   - Click **OK**

   **Setting 2:**
   - Name: `AZURE_AD_CLIENT_ID`
   - Value: `@Microsoft.KeyVault(SecretUri=https://pa-gcloud15-kv-14sxir.vault.azure.net/secrets/AzureADClientId/)`
   - Click **OK**

   **Setting 3:**
   - Name: `AZURE_AD_CLIENT_SECRET`
   - Value: `@Microsoft.KeyVault(SecretUri=https://pa-gcloud15-kv-14sxir.vault.azure.net/secrets/AzureADClientSecret/)`
   - Click **OK**

4. **Save:**
   - Click **Save** at the top
   - Click **Continue** to confirm

5. **Restart Function App:**
   - Go to **Overview** → Click **Restart**
   - Wait 2-3 minutes

6. **Test:**
   ```powershell
   curl https://pa-gcloud15-api-14sxir.azurewebsites.net/api/v1/sharepoint/test
   ```

## Note

Replace `pa-gcloud15-kv-14sxir` with your actual Key Vault name from `deployment-config.env`.

