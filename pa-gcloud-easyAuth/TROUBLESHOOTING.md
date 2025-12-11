# Troubleshooting Guide - Easy Auth Version

Common issues and solutions for the Easy Auth deployment.

## Table of Contents

1. [Authentication Issues](#authentication-issues)
2. [Redirect Issues](#redirect-issues)
3. [CORS Errors](#cors-errors)
4. [Backend API Issues](#backend-api-issues)
5. [Deployment Issues](#deployment-issues)
6. [Configuration Issues](#configuration-issues)

## Authentication Issues

### Issue: "You have successfully signed in" page appears instead of redirecting to app

**Symptoms:**
- After login, user sees Azure's success page
- "Return to the website" link doesn't redirect properly
- User stuck on Function App success page

**Cause:**
- "Allowed external redirect URLs" not configured
- Web App URL not in allowed list

**Solution:**

1. **Using Azure CLI:**
   ```powershell
   az webapp auth update `
       --name <function-app-name> `
       --resource-group <resource-group-name> `
       --allowed-external-redirect-urls "https://<web-app-name>.azurewebsites.net"
   
   az functionapp restart --name <function-app-name> --resource-group <rg-name>
   ```

2. **Using Azure Portal:**
   - Go to Function App → Authentication
   - Click "Edit" on Microsoft provider
   - Find "Allowed external redirect URLs" or "Advanced settings"
   - Add: `https://<web-app-name>.azurewebsites.net`
   - Save and restart Function App

3. **Verify redirect URL in frontend:**
   - Check `EasyAuthContext.tsx` - login function should use Web App URL
   - Verify `post_login_redirect_url` parameter includes Web App URL

### Issue: "AADSTS50011: Redirect URI mismatch"

**Symptoms:**
- Error during login: "The redirect URI specified in the request does not match..."
- Login fails immediately

**Cause:**
- Redirect URI not configured in App Registration
- Mismatch between configured and requested redirect URI

**Solution:**

1. **Check App Registration:**
   - Go to Azure Portal → Azure AD → App registrations
   - Find your app registration
   - Go to Authentication → Redirect URIs

2. **Add missing redirect URI:**
   ```
   https://<function-app-name>.azurewebsites.net/.auth/login/aad/callback
   https://<web-app-name>.azurewebsites.net
   ```

3. **Verify redirect URI format:**
   - Must be exact match (including https://, no trailing slash)
   - Case-sensitive

### Issue: "AADSTS700054: response_type 'id_token' is not enabled"

**Symptoms:**
- Error: "response_type 'id_token' is not enabled for the application"
- Login fails

**Cause:**
- ID tokens not enabled in App Registration

**Solution:**

1. **Go to App Registration → Authentication**
2. **Under "Implicit grant and hybrid flows":**
   - ✅ Check **ID tokens**
   - Click **Save**

3. **Wait 1-2 minutes for changes to propagate**

### Issue: "401 Unauthorized" from API

**Symptoms:**
- Frontend loads but API calls fail with 401
- User appears logged in but can't access data

**Cause:**
- Easy Auth not properly configured
- Client secret missing or incorrect
- `X-MS-CLIENT-PRINCIPAL` header not present

**Solution:**

1. **Verify Easy Auth is enabled:**
   ```powershell
   az webapp auth show --name <function-app-name> --resource-group <rg-name>
   ```
   - Should show `"enabled": true`

2. **Check client secret:**
   ```powershell
   az functionapp config appsettings list `
       --name <function-app-name> `
       --resource-group <rg-name> `
       --query "[?name=='MICROSOFT_PROVIDER_AUTHENTICATION_SECRET']"
   ```
   - Should have a value (not empty)

3. **Verify Function App is running:**
   - Go to Function App → Overview
   - Status should be "Running" (not "Stopped")

4. **Check backend logs:**
   ```powershell
   az functionapp log tail --name <function-app-name> --resource-group <rg-name>
   ```
   - Look for errors parsing `X-MS-CLIENT-PRINCIPAL` header

### Issue: User info not available in backend

**Symptoms:**
- Backend can't read user email/name
- `get_easy_auth_user()` returns None

**Cause:**
- `X-MS-CLIENT-PRINCIPAL` header not present
- Header format incorrect
- Easy Auth middleware not working

**Solution:**

1. **Check if header is present:**
   - Add logging in backend to print all headers
   - Look for `X-MS-CLIENT-PRINCIPAL` header

2. **Verify Easy Auth middleware:**
   - Check `backend/app/middleware/easy_auth.py`
   - Ensure it's imported and used in routes

3. **Test Easy Auth endpoint:**
   ```powershell
   # After logging in, test this endpoint
   curl "https://<function-app-name>.azurewebsites.net/.auth/me" `
        -H "Cookie: <cookies-from-browser>"
   ```
   - Should return user information

## Redirect Issues

### Issue: Redirect loop between /login and /proposals

**Symptoms:**
- Page constantly refreshes
- Alternates between login and proposals page
- Browser console shows 401 errors

**Cause:**
- Frontend checking auth status incorrectly
- Easy Auth not returning user info
- CORS issues preventing auth check

**Solution:**

1. **Check Easy Auth endpoint:**
   ```powershell
   # Test in browser console after login
   fetch('https://<function-app-name>.azurewebsites.net/.auth/me', {
     credentials: 'include'
   }).then(r => r.json()).then(console.log)
   ```
   - Should return user info, not 401

2. **Verify frontend auth check:**
   - Check `EasyAuthContext.tsx` - `checkAuth()` function
   - Ensure it handles 401 correctly (doesn't cause loop)

3. **Check CORS:**
   - Verify `CORS_ORIGINS` includes Web App URL
   - Frontend must use `withCredentials: true`

### Issue: Redirect goes to wrong URL

**Symptoms:**
- After login, redirects to Function App instead of Web App
- Wrong domain in redirect URL

**Cause:**
- `post_login_redirect_url` parameter incorrect
- Frontend login function using wrong URL

**Solution:**

1. **Check `EasyAuthContext.tsx`:**
   ```typescript
   const login = (): void => {
     const apiBaseUrl = getApiBaseUrl(); // Function App URL
     const webAppUrl = window.location.origin; // Web App URL
     const loginUrl = `${apiBaseUrl}/.auth/login/aad?post_login_redirect_url=${encodeURIComponent(webAppUrl)}`;
     window.location.href = loginUrl;
   };
   ```
   - Ensure `post_login_redirect_url` uses Web App URL, not Function App URL

2. **Verify allowed external redirect URLs:**
   - Must include Web App URL (see Authentication Issues above)

## CORS Errors

### Issue: "Access to XMLHttpRequest blocked by CORS policy"

**Symptoms:**
- Browser console shows CORS errors
- API calls fail with CORS error
- Preflight OPTIONS requests fail

**Cause:**
- CORS not configured on Function App
- Web App URL not in allowed origins
- Frontend not sending credentials

**Solution:**

1. **Check CORS configuration:**
   ```powershell
   az functionapp cors show --name <function-app-name> --resource-group <rg-name>
   ```
   - Should include Web App URL

2. **Add Web App URL to CORS:**
   ```powershell
   az functionapp cors add `
       --name <function-app-name> `
       --resource-group <rg-name> `
       --allowed-origins "https://<web-app-name>.azurewebsites.net"
   ```

3. **Verify frontend API configuration:**
   - Check `frontend/src/services/api.ts`
   - Must have `withCredentials: true` in axios config

4. **Check Function App CORS settings:**
   - Go to Function App → CORS
   - Ensure Web App URL is in allowed origins
   - Enable "Allow Credentials" if available

### Issue: CORS works but cookies not sent

**Symptoms:**
- No CORS errors but authentication fails
- Cookies not included in requests

**Cause:**
- `withCredentials` not set in frontend
- CORS not configured to allow credentials

**Solution:**

1. **Verify frontend API config:**
   ```typescript
   // In api.ts
   axios.create({
     withCredentials: true  // Must be true
   })
   ```

2. **Check CORS allows credentials:**
   - Function App CORS should allow credentials
   - Backend should return `Access-Control-Allow-Credentials: true`

## Backend API Issues

### Issue: Function App returns 404 for API routes

**Symptoms:**
- API calls return 404 Not Found
- Routes not found

**Cause:**
- Function App not deployed correctly
- Routes not configured
- `function.json` missing or incorrect

**Solution:**

1. **Verify deployment:**
   ```powershell
   az functionapp function list --name <function-app-name> --resource-group <rg-name>
   ```
   - Should list your function

2. **Check function.json:**
   - Verify `backend/function_app/function.json` exists
   - Should have correct route bindings

3. **Redeploy backend:**
   ```powershell
   .\scripts\deploy-functions.ps1
   ```

### Issue: Backend can't read Easy Auth headers

**Symptoms:**
- Backend logs show no `X-MS-CLIENT-PRINCIPAL` header
- `get_easy_auth_user()` returns None

**Cause:**
- Easy Auth not enabled
- Function App in read-only mode
- Headers not being forwarded

**Solution:**

1. **Verify Easy Auth enabled:**
   ```powershell
   az webapp auth show --name <function-app-name> --resource-group <rg-name>
   ```

2. **Check Function App mode:**
   - Go to Function App → Configuration
   - Check `WEBSITE_RUN_FROM_PACKAGE`
   - If set to a URL, Function App is read-only (this is OK for Easy Auth)

3. **Test Easy Auth endpoint:**
   - After logging in, call `/.auth/me` endpoint
   - Should return user info

## Deployment Issues

### Issue: "ParserError" in deploy-functions.ps1

**Symptoms:**
- Script fails with syntax error
- "Unexpected token" error

**Cause:**
- Syntax error in PowerShell script
- Missing closing brace or quote

**Solution:**

1. **Check script syntax:**
   ```powershell
   # Validate PowerShell syntax
   $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content .\scripts\deploy-functions.ps1 -Raw), [ref]$null)
   ```

2. **Pull latest changes:**
   ```powershell
   git pull origin main
   ```

3. **Check for recent changes:**
   - Review recent commits
   - Look for syntax errors

### Issue: "pip install" hangs during deployment

**Symptoms:**
- Deployment hangs on "Running pip install..."
- No progress for 10+ minutes

**Cause:**
- Remote build enabled
- Complex dependencies (e.g., grpcio)

**Solution:**

1. **Script should handle this automatically:**
   - `deploy-functions.ps1` disables remote build before zip deploy
   - Re-enables it after deployment

2. **If still hanging:**
   - Cancel deployment
   - Check `SCM_DO_BUILD_DURING_DEPLOYMENT` setting:
     ```powershell
     az functionapp config appsettings list `
         --name <function-app-name> `
         --resource-group <rg-name> `
         --query "[?name=='SCM_DO_BUILD_DURING_DEPLOYMENT']"
     ```
   - Should be `false` during deployment

### Issue: Docker build fails

**Symptoms:**
- Frontend Docker build fails in ACR
- TypeScript compilation errors

**Cause:**
- Code errors in frontend
- Missing dependencies
- Build configuration issues

**Solution:**

1. **Check build logs:**
   - ACR build logs show specific errors
   - Look for TypeScript errors

2. **Test build locally:**
   ```powershell
   cd frontend
   npm install
   npm run build
   ```
   - Fix any errors locally first

3. **Verify frontend directory:**
   - Ensure `build-and-push-images.ps1` uses correct frontend path
   - Should use `pa-gcloud-easyAuth/frontend`, not root `frontend`

## Configuration Issues

### Issue: App Registration not found

**Symptoms:**
- Script fails: "App Registration not found"
- Can't configure Easy Auth

**Cause:**
- App Registration doesn't exist
- Wrong name in config
- Permissions issue

**Solution:**

1. **Check App Registration exists:**
   ```powershell
   az ad app list --display-name <app-registration-name>
   ```

2. **Create if missing:**
   - Go to Azure Portal → Azure AD → App registrations
   - Click "New registration"
   - Name: `<app-registration-name>`
   - Supported account types: "Accounts in this organizational directory only"
   - Click "Register"

3. **Update config:**
   - Edit `config/deployment-config.env`
   - Set correct `APP_REGISTRATION_NAME`

### Issue: Key Vault access denied

**Symptoms:**
- Can't read/write secrets
- "Access denied" errors

**Cause:**
- No permissions on Key Vault
- Managed identity not configured

**Solution:**

1. **Grant Key Vault access:**
   ```powershell
   # Get your user object ID
   $userId = az ad signed-in-user show --query "id" -o tsv
   
   # Grant permissions
   az keyvault set-policy `
       --name <key-vault-name> `
       --object-id $userId `
       --secret-permissions get set list delete
   ```

2. **Grant Function App access:**
   ```powershell
   # Get Function App managed identity
   $principalId = az functionapp identity show `
       --name <function-app-name> `
       --resource-group <rg-name> `
       --query "principalId" -o tsv
   
   # Grant permissions
   az keyvault set-policy `
       --name <key-vault-name> `
       --object-id $principalId `
       --secret-permissions get list
   ```

## Quick Diagnostic Commands

```powershell
# Check Easy Auth status
az webapp auth show --name <function-app-name> --resource-group <rg-name> -o json

# Check app settings
az functionapp config appsettings list --name <function-app-name> --resource-group <rg-name> -o table

# Check CORS
az functionapp cors show --name <function-app-name> --resource-group <rg-name>

# View logs
az functionapp log tail --name <function-app-name> --resource-group <rg-name>

# Test Easy Auth endpoint (after login)
curl "https://<function-app-name>.azurewebsites.net/.auth/me" -H "Cookie: <cookies>"

# Check Function App status
az functionapp show --name <function-app-name> --resource-group <rg-name> --query "state"
```

## Still Having Issues?

1. **Check Azure Portal logs:**
   - Function App → Log stream
   - Application Insights → Logs

2. **Review deployment script output:**
   - Look for warnings or errors
   - Check exit codes

3. **Verify all manual steps completed:**
   - See [DEPLOYMENT-GUIDE.md](./DEPLOYMENT-GUIDE.md) manual steps section

4. **Test in incognito/private browser:**
   - Rules out browser cache issues

5. **Check browser console:**
   - Look for JavaScript errors
   - Check network tab for failed requests

