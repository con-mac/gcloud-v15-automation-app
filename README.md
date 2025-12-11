# G-Cloud Automation - Deployment Packages

This repository contains deployment packages for the G-Cloud automation system.

## Package Structure

```
deployment-packages/
├── pa-gcloud-automation/    # MSAL-based authentication (original)
└── pa-gcloud-easyAuth/      # Easy Auth-based authentication (recommended)
```

## Which Package Should I Use?

### Use `pa-gcloud-easyAuth` (Recommended)

**Advantages:**
- ✅ Simpler authentication setup
- ✅ No `authLevel` issues
- ✅ No CORS preflight problems
- ✅ Platform-level security
- ✅ Automatic token refresh
- ✅ More reliable and easier to maintain

**When to use:**
- New deployments
- When you want a simpler, more reliable authentication solution
- When you're experiencing CORS or authentication issues with MSAL

### Use `pa-gcloud-automation` (Legacy)

**Advantages:**
- More flexible authentication flow
- Can support multi-tenant scenarios
- More control over authentication process

**When to use:**
- Existing deployments already using MSAL
- When you need multi-tenant support
- When you need custom authentication flows

## Quick Start

### Easy Auth Version (Recommended)

```powershell
cd pa-gcloud-easyAuth
.\deploy.ps1
```

See [pa-gcloud-easyAuth/README.md](./pa-gcloud-easyAuth/README.md) for details.

### MSAL Version (Legacy)

```powershell
cd pa-gcloud-automation
.\deploy.ps1
```

See [pa-gcloud-automation/README.md](./pa-gcloud-automation/README.md) for details.

## Documentation

Each package contains its own documentation:

- **pa-gcloud-easyAuth/**
  - [README.md](./pa-gcloud-easyAuth/README.md) - Overview and differences
  - [DEPLOYMENT-GUIDE.md](./pa-gcloud-easyAuth/DEPLOYMENT-GUIDE.md) - Complete deployment guide
  - [TROUBLESHOOTING.md](./pa-gcloud-easyAuth/TROUBLESHOOTING.md) - Common issues and solutions

- **pa-gcloud-automation/**
  - [README.md](./pa-gcloud-automation/README.md) - Overview
  - [DEPLOYMENT-GUIDE.md](./pa-gcloud-automation/DEPLOYMENT-GUIDE.md) - Deployment guide
  - [TROUBLESHOOTING.md](./pa-gcloud-automation/TROUBLESHOOTING.md) - Troubleshooting guide

## Key Differences

| Feature | pa-gcloud-automation (MSAL) | pa-gcloud-easyAuth |
|---------|----------------------------|-------------------|
| Authentication | MSAL library in frontend | Azure Easy Auth (platform-level) |
| Token Management | Manual token handling | Automatic (cookies) |
| CORS Issues | Can occur | Handled by platform |
| authLevel Issues | Can occur | Not applicable |
| Setup Complexity | Higher | Lower |
| Flexibility | Higher | Lower |
| Reliability | Good | Excellent |

## Migration

If you're currently using `pa-gcloud-automation` and want to migrate to `pa-gcloud-easyAuth`:

1. Review the differences in [pa-gcloud-easyAuth/README.md](./pa-gcloud-easyAuth/README.md)
2. Follow the migration guide in that README
3. Test thoroughly before switching production deployments

## Support

For deployment issues:
1. Check the package-specific TROUBLESHOOTING.md
2. Review Azure Portal logs
3. Check Application Insights

## Repository Structure

This repository is organized as follows:

```
deployment-packages/
├── README.md (this file)
├── pa-gcloud-automation/
│   ├── README.md
│   ├── DEPLOYMENT-GUIDE.md
│   ├── TROUBLESHOOTING.md
│   ├── deploy.ps1
│   ├── scripts/
│   ├── config/
│   ├── backend/
│   └── frontend/
└── pa-gcloud-easyAuth/
    ├── README.md
    ├── DEPLOYMENT-GUIDE.md
    ├── TROUBLESHOOTING.md
    ├── deploy.ps1
    ├── scripts/
    ├── config/
    ├── backend/
    └── frontend/
```

## License

Internal use only - PA Consulting

