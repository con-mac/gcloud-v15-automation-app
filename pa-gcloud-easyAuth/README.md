# G-Cloud Automation - Easy Auth Version

This is a version of the G-Cloud automation system that uses **Azure App Service Easy Auth** for authentication instead of MSAL (Microsoft Authentication Library).

## Key Differences from pa-deployment

### Authentication Approach

**pa-deployment (MSAL):**
- Frontend uses MSAL library to authenticate users
- Frontend obtains access tokens and sends them to backend
- Backend validates tokens
- Requires SPA platform configuration in Azure AD
- More complex, but more flexible

**pa-gcloud-easyAuth (Easy Auth):**
- Azure App Service handles authentication at platform level
- Users authenticate via `/.auth/login/aad` endpoint
- Easy Auth sets cookies and adds `X-MS-CLIENT-PRINCIPAL` header to requests
- Backend reads user info from Easy Auth headers
- Simpler, more reliable, but less flexible

### Advantages of Easy Auth

1. **No authLevel issues**: Easy Auth runs before your code, so `authLevel` in `function.json` doesn't matter
2. **No CORS preflight issues**: Easy Auth handles authentication, so OPTIONS requests work correctly
3. **Simpler frontend**: No MSAL library needed, no token management
4. **Platform-level security**: Authentication handled by Azure, not your code
5. **Automatic token refresh**: Easy Auth handles token refresh automatically

### Disadvantages of Easy Auth

1. **Less flexible**: Can't customize authentication flow as much
2. **Tenant restriction**: Must use "From this tenant only" (can't support multi-tenant easily)
3. **Cookie-based**: Relies on cookies, which can have CORS implications for cross-domain scenarios
4. **Platform dependency**: Tied to Azure App Service

## File Structure

```
pa-gcloud-easyAuth/
├── backend/
│   ├── app/
│   │   ├── middleware/
│   │   │   ├── easy_auth.py      # Easy Auth header parsing
│   │   │   └── __init__.py
│   │   ├── main.py               # Updated to use Easy Auth
│   │   └── api/                  # API routes (same as pa-deployment)
│   └── function_app/
│       └── __init__.py           # Function App entry point
├── frontend/
│   └── src/
│       ├── contexts/
│       │   └── EasyAuthContext.tsx  # Easy Auth context (replaces AuthContext.tsx)
│       ├── services/
│       │   └── api.ts            # Updated to use cookies (no tokens)
│       └── main.tsx              # Updated to use EasyAuthProvider
├── scripts/
│   └── configure-easy-auth.ps1  # Configures Easy Auth in Function App
└── deploy.ps1                    # Updated deployment script
```

## Deployment

1. **Run deployment script:**
   ```powershell
   .\deploy.ps1
   ```

2. **The script will:**
   - Create/configure Azure resources
   - Configure Easy Auth automatically
   - Deploy backend and frontend
   - Set up redirect URIs

3. **Verify Easy Auth:**
   ```powershell
   .\scripts\configure-easy-auth.ps1
   ```

## How It Works

### Backend

1. Easy Auth intercepts requests before they reach your function
2. If not authenticated, redirects to `/.auth/login/aad`
3. After authentication, adds `X-MS-CLIENT-PRINCIPAL` header with user info
4. Backend reads header using `get_easy_auth_user(request)`
5. User info extracted from header claims

### Frontend

1. User visits frontend
2. Frontend checks auth status via `/.auth/me` endpoint
3. If not authenticated, redirects to `/.auth/login/aad`
4. After login, Easy Auth redirects back with cookies set
5. All API requests include cookies automatically (`withCredentials: true`)
6. Backend reads user from Easy Auth headers

## API Changes

### Backend

**Before (MSAL):**
```python
# Read token from Authorization header
token = request.headers.get("Authorization")
# Validate token
user = validate_token(token)
```

**After (Easy Auth):**
```python
# Read user from Easy Auth header
from app.middleware.easy_auth import get_easy_auth_user
user = get_easy_auth_user(request)
email = user.get("email")
```

### Frontend

**Before (MSAL):**
```typescript
// Get token from MSAL
const token = await msalInstance.acquireTokenSilent(...)
// Send token in Authorization header
headers.Authorization = `Bearer ${token}`
```

**After (Easy Auth):**
```typescript
// No tokens needed - Easy Auth handles via cookies
// Just include credentials
axios.create({
  withCredentials: true  // Cookies sent automatically
})
```

## Configuration

### App Registration

- **Redirect URI**: `https://<function-app>.azurewebsites.net/.auth/login/aad/callback`
- **Platform**: Web (not SPA)
- **Tenant**: "From this tenant only"

### Function App Settings

- `MICROSOFT_PROVIDER_AUTHENTICATION_SECRET`: Client secret from App Registration
- `CORS_ORIGINS`: Allowed origins for CORS

## Troubleshooting

### Authentication not working

1. Check Easy Auth is enabled:
   ```powershell
   az webapp auth show --name <function-app> --resource-group <rg>
   ```

2. Verify redirect URI in App Registration matches Function App URL

3. Check client secret is set:
   ```powershell
   az functionapp config appsettings list --name <function-app> --resource-group <rg> --query "[?name=='MICROSOFT_PROVIDER_AUTHENTICATION_SECRET']"
   ```

### CORS errors

- Easy Auth should handle CORS, but verify `CORS_ORIGINS` is set correctly
- Frontend must use `withCredentials: true` in API calls

### User info not available

- Check `X-MS-CLIENT-PRINCIPAL` header is present in requests
- Verify Easy Auth middleware is parsing header correctly
- Check backend logs for parsing errors

## Migration from pa-deployment

If you want to migrate from MSAL to Easy Auth:

1. Copy this folder structure
2. Update your deployment config
3. Run `.\deploy.ps1`
4. Update App Registration redirect URIs
5. Test authentication flow

## Notes

- Easy Auth requires Function App to be running (not stopped)
- Cookies are domain-specific, so frontend and backend should be on same domain or configure CORS properly
- Easy Auth tokens are stored in App Service token store (can be disabled)
- Admin group checking still works via claims in Easy Auth header

