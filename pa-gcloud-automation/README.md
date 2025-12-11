# G-Cloud 15 Automation Tool - PA Deployment Package

This package contains everything needed to deploy the G-Cloud 15 automation tool to PA Consulting's Azure environment.

## Quick Start

### IMPORTANT: Project Structure Required

This deployment package must be placed in the **project root** alongside the `frontend` and `backend` directories:

```
project-root/
├── frontend/              # Frontend application code (with Dockerfile)
├── backend/               # Backend application code (with function_app/)
└── pa-gcloud-automation/ # This deployment package
    ├── deploy.ps1
    ├── scripts/
    └── config/
```

### Setup Steps

1. **Clone the main project repository** (contains frontend/backend code)

2. **Clone this deployment package** into the project root:
   ```powershell
   cd <project-root>
   git clone https://github.com/con-mac/gcloud-v15-automation-app.git pa-gcloud-automation
   ```

3. **Prerequisites:**
   - Azure CLI installed and configured
   - PowerShell 5.1 or later
   - Access to PA Consulting's Azure subscription
   - Appropriate Azure AD permissions

4. **Register Resource Providers (First Time Only):**
   ```powershell
   az provider register --namespace Microsoft.KeyVault
   az provider register --namespace Microsoft.Web
   az provider register --namespace Microsoft.Storage
   az provider register --namespace Microsoft.ContainerRegistry
   az provider register --namespace Microsoft.Insights
   az provider register --namespace Microsoft.Network
   ```

5. **Deploy:**
   
   **First Time (Interactive):**
   ```powershell
   cd pa-gcloud-automation
   .\deploy.ps1
   ```
   This will prompt for all configuration values and save them to `config\deployment-config.env`.
   
   **Subsequent Deployments (Using Existing Config):**
   ```powershell
   # Option 1: Use the helper script
   .\scripts\use-existing-config.ps1
   
   # Option 2: Use the flag directly
   .\deploy.ps1 -UseExistingConfig
   ```
   
   **Hardcode Config Values:**
   Edit `config\deployment-config.env` directly with your values, then use one of the options above.
   The script will use your hardcoded values without prompting.

## Documentation

- **[DEPLOYMENT-GUIDE.md](./DEPLOYMENT-GUIDE.md)** - Complete deployment instructions
- **[TROUBLESHOOTING.md](./TROUBLESHOOTING.md)** - Common issues and solutions

## Structure

```
pa-gcloud-automation/
├── deploy.ps1                    # Main deployment script
├── DEPLOYMENT-GUIDE.md           # Complete deployment guide
├── TROUBLESHOOTING.md            # Troubleshooting guide
├── README.md                     # This file
├── scripts/
│   ├── configure-auth.ps1        # SSO configuration
│   ├── deploy-functions.ps1      # Backend deployment
│   ├── build-and-push-images.ps1 # Frontend Docker build
│   ├── setup-resources.ps1       # Azure resource creation
│   ├── register-resource-providers.ps1 # Resource provider registration
│   └── cleanup-deployment.ps1   # Cleanup script
└── config/
    └── deployment-config.env.template # Configuration template
```

## Key Features

- **Automated Deployment:** Single script deploys all resources
- **SSO Integration:** Automatic Microsoft 365 SSO setup
- **Docker Support:** Frontend deployed as Docker container
- **Key Vault Integration:** Secure secret management
- **SharePoint Integration:** Automatic SharePoint site configuration

## Support

For issues not covered in the troubleshooting guide, check:
- Azure Portal logs (Function App → Log stream)
- Application Insights
- Deployment script output

## License

Internal use only - PA Consulting

