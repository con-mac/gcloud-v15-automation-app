"""SharePoint API routes for testing connectivity and folder management"""

from fastapi import APIRouter, HTTPException, Header
from typing import Optional, Literal
from pydantic import BaseModel
import os
import logging

logger = logging.getLogger(__name__)

router = APIRouter()


class SharePointTestResponse(BaseModel):
    """SharePoint connectivity test response"""
    connected: bool
    site_id: str
    site_url: str
    message: str
    error: Optional[str] = None


class CreateFolderRequest(BaseModel):
    """Request to create a folder in SharePoint"""
    service_name: str
    lot: Literal["2", "2a", "2b", "3"]
    gcloud_version: Optional[Literal["14", "15"]] = "15"


class CreateFolderResponse(BaseModel):
    """Response after creating a folder"""
    success: bool
    folder_path: str
    service_name: str
    lot: str
    gcloud_version: str
    error: Optional[str] = None


class CreateMetadataRequest(BaseModel):
    """Request to create a metadata file in SharePoint"""
    service_name: str
    owner: str
    sponsor: str
    lot: Literal["2", "2a", "2b", "3"]
    gcloud_version: Optional[Literal["14", "15"]] = "15"
    last_edited_by: Optional[str] = None


class CreateMetadataResponse(BaseModel):
    """Response after creating a metadata file"""
    success: bool
    folder_path: str
    service_name: str
    owner: str
    sponsor: str
    error: Optional[str] = None


@router.get("/test", response_model=SharePointTestResponse, tags=["SharePoint"])
async def test_sharepoint_connectivity(
    x_user_email: Optional[str] = Header(None, alias="X-User-Email")
):
    """
    Test SharePoint connectivity using App Registration credentials.
    
    This endpoint tests if the backend can connect to SharePoint using:
    - App Registration client credentials (client ID + secret from Key Vault)
    - SharePoint Site ID from configuration
    
    Returns:
        SharePointTestResponse with connection status
    """
    try:
        site_id = os.getenv("SHAREPOINT_SITE_ID", "")
        site_url = os.getenv("SHAREPOINT_SITE_URL", "")
        
        if not site_id or not site_url:
            return SharePointTestResponse(
                connected=False,
                site_id=site_id or "Not configured",
                site_url=site_url or "Not configured",
                message="SharePoint not configured",
                error="SHAREPOINT_SITE_ID or SHAREPOINT_SITE_URL not set"
            )
        
        # Try to get access token using client credentials
        try:
            from azure.identity import ClientSecretCredential
            from msal import ConfidentialClientApplication
            
            # Helper to read from Key Vault
            def _get_secret_from_keyvault(secret_name: str) -> Optional[str]:
                try:
                    from azure.keyvault.secrets import SecretClient
                    from azure.identity import DefaultAzureCredential
                    
                    key_vault_url = os.getenv("AZURE_KEY_VAULT_URL", "")
                    if not key_vault_url:
                        # Try to get from Key Vault name
                        kv_name = os.getenv("KEY_VAULT_NAME", "")
                        if kv_name:
                            key_vault_url = f"https://{kv_name}.vault.azure.net"
                    
                    if not key_vault_url:
                        logger.debug("No Key Vault URL configured")
                        return None
                    
                    logger.info(f"Reading {secret_name} from Key Vault: {key_vault_url}")
                    credential = DefaultAzureCredential()
                    client = SecretClient(vault_url=key_vault_url, credential=credential)
                    secret = client.get_secret(secret_name)
                    logger.info(f"Successfully read {secret_name} from Key Vault")
                    return secret.value
                except Exception as e:
                    logger.warning(f"Could not read {secret_name} from Key Vault: {e}")
                    return None
            
            # Try to get credentials from environment or Key Vault
            tenant_id = os.getenv("AZURE_AD_TENANT_ID", "")
            client_id = os.getenv("AZURE_AD_CLIENT_ID", "")
            client_secret = os.getenv("AZURE_AD_CLIENT_SECRET", "")
            
            # If values are Key Vault references or missing, try to read from Key Vault
            if not tenant_id or tenant_id.startswith("@Microsoft.KeyVault"):
                logger.info("Tenant ID missing or is Key Vault reference, reading from Key Vault...")
                tenant_id = _get_secret_from_keyvault("AzureADTenantId") or tenant_id
            
            if not client_id or client_id.startswith("@Microsoft.KeyVault"):
                logger.info("Client ID missing or is Key Vault reference, reading from Key Vault...")
                client_id = _get_secret_from_keyvault("AzureADClientId") or client_id
            
            if not client_secret or client_secret.startswith("@Microsoft.KeyVault"):
                logger.info("Client Secret missing or is Key Vault reference, reading from Key Vault...")
                client_secret = _get_secret_from_keyvault("AzureADClientSecret") or client_secret
            
            if not all([tenant_id, client_id, client_secret]):
                return SharePointTestResponse(
                    connected=False,
                    site_id=site_id,
                    site_url=site_url,
                    message="SharePoint credentials not configured",
                    error=f"AZURE_AD_TENANT_ID: {'Set' if tenant_id else 'Missing'}, AZURE_AD_CLIENT_ID: {'Set' if client_id else 'Missing'}, AZURE_AD_CLIENT_SECRET: {'Set' if client_secret else 'Missing'}"
                )
            
            # Get access token using client credentials flow
            app = ConfidentialClientApplication(
                client_id=client_id,
                client_credential=client_secret,
                authority=f"https://login.microsoftonline.com/{tenant_id}"
            )
            
            result = app.acquire_token_for_client(scopes=["https://graph.microsoft.com/.default"])
            
            if "access_token" not in result:
                error_msg = result.get("error_description", "Failed to acquire token")
                return SharePointTestResponse(
                    connected=False,
                    site_id=site_id,
                    site_url=site_url,
                    message="Failed to authenticate with Azure AD",
                    error=error_msg
                )
            
            access_token = result["access_token"]
            
            # Test Graph API call to SharePoint site
            # Try both site ID and site URL formats (some tenants work better with URL format)
            import requests
            
            # First try: Site ID format
            graph_url = f"https://graph.microsoft.com/v1.0/sites/{site_id}"
            
            response = requests.get(
                graph_url,
                headers={
                    "Authorization": f"Bearer {access_token}",
                    "Content-Type": "application/json"
                },
                timeout=10
            )
            
            # If site ID format fails, try site URL format
            if response.status_code != 200 and site_url:
                try:
                    # Extract hostname and path from site URL
                    # Format: https://{hostname}/sites/{sitename} or https://{hostname}/:u:/s/{sitename}
                    from urllib.parse import urlparse
                    parsed = urlparse(site_url)
                    hostname = parsed.netloc
                    path = parsed.path
                    
                    # Convert to Graph API format: /sites/{hostname}:{path}
                    graph_url = f"https://graph.microsoft.com/v1.0/sites/{hostname}:{path}"
                    
                    logger.info(f"Trying alternative Graph API format: {graph_url}")
                    response = requests.get(
                        graph_url,
                        headers={
                            "Authorization": f"Bearer {access_token}",
                            "Content-Type": "application/json"
                        },
                        timeout=10
                    )
                except Exception as e:
                    logger.warning(f"Failed to parse site URL for alternative format: {e}")
            
            if response.status_code == 200:
                site_data = response.json()
                return SharePointTestResponse(
                    connected=True,
                    site_id=site_id,
                    site_url=site_url,
                    message=f"Successfully connected to SharePoint site: {site_data.get('displayName', 'Unknown')}",
                    error=None
                )
            else:
                error_text = response.text[:500] if response.text else "No error details"
                # Check if this is the "SPO license" error
                if "SPO license" in error_text or "does not have a SPO license" in error_text:
                    return SharePointTestResponse(
                        connected=False,
                        site_id=site_id,
                        site_url=site_url,
                        message="SharePoint site exists but Graph API access is limited in this tenant",
                        error=f"Tenant limitation: {error_text}. This is a test tenant issue and should work in production (PA Consulting tenant)."
                    )
                else:
                    return SharePointTestResponse(
                        connected=False,
                        site_id=site_id,
                        site_url=site_url,
                        message="Failed to access SharePoint site",
                        error=f"Graph API returned status {response.status_code}: {error_text}"
                    )
                
        except ImportError as e:
            return SharePointTestResponse(
                connected=False,
                site_id=site_id,
                site_url=site_url,
                message="SharePoint libraries not available",
                error=f"Import error: {str(e)}"
            )
        except Exception as e:
            logger.error(f"SharePoint connectivity test error: {e}", exc_info=True)
            return SharePointTestResponse(
                connected=False,
                site_id=site_id,
                site_url=site_url,
                message="Error testing SharePoint connectivity",
                error=str(e)
            )
            
    except Exception as e:
        logger.error(f"Unexpected error in SharePoint test: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Internal error: {str(e)}")


@router.post("/create-folder", response_model=CreateFolderResponse, tags=["SharePoint"])
async def create_sharepoint_folder(
    request: CreateFolderRequest,
    x_user_email: Optional[str] = Header(None, alias="X-User-Email")
):
    """
    Create a folder structure in SharePoint for a service.
    
    Creates the folder path: GCloud {version}/PA Services/{service_name}
    Parent folders are created automatically if they don't exist.
    
    Args:
        request: CreateFolderRequest with service_name, lot, and gcloud_version
        x_user_email: Optional user email from frontend (for logging)
    
    Returns:
        CreateFolderResponse with success status and folder path
    """
    try:
        # Import SharePoint service
        try:
            from sharepoint_service.sharepoint_online import create_folder
        except ImportError:
            logger.error("SharePoint Online service not available")
            raise HTTPException(
                status_code=500,
                detail="SharePoint service not configured. Ensure USE_SHAREPOINT=true and SharePoint credentials are set."
            )
        
        # Validate configuration
        site_id = os.getenv("SHAREPOINT_SITE_ID", "")
        if not site_id:
            raise HTTPException(
                status_code=500,
                detail="SHAREPOINT_SITE_ID not configured"
            )
        
        # Construct folder path: GCloud {version}/PA Services/{service_name}
        gcloud_version = request.gcloud_version or "15"
        folder_path = request.service_name
        
        logger.info(f"Creating SharePoint folder: {folder_path} (GCloud {gcloud_version}, Lot {request.lot})")
        
        # Create folder (this function handles creating parent folders if needed)
        folder_id = create_folder(folder_path, gcloud_version)
        
        if not folder_id:
            error_msg = f"Failed to create folder: {folder_path}"
            logger.error(error_msg)
            return CreateFolderResponse(
                success=False,
                folder_path=f"GCloud {gcloud_version}/PA Services/{folder_path}",
                service_name=request.service_name,
                lot=request.lot,
                gcloud_version=gcloud_version,
                error=error_msg
            )
        
        # Construct full folder path for response
        full_folder_path = f"GCloud {gcloud_version}/PA Services/{folder_path}"
        
        logger.info(f"Successfully created folder: {full_folder_path} (ID: {folder_id})")
        
        return CreateFolderResponse(
            success=True,
            folder_path=full_folder_path,
            service_name=request.service_name,
            lot=request.lot,
            gcloud_version=gcloud_version,
            error=None
        )
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error creating SharePoint folder: {e}", exc_info=True)
        raise HTTPException(
            status_code=500,
            detail=f"Internal error creating folder: {str(e)}"
        )


@router.post("/create-metadata", response_model=CreateMetadataResponse, tags=["SharePoint"])
async def create_sharepoint_metadata(
    request: CreateMetadataRequest,
    x_user_email: Optional[str] = Header(None, alias="X-User-Email")
):
    """
    Create a metadata.json file in a SharePoint folder.
    
    The folder should already exist (created via /create-folder).
    Creates metadata.json with service information.
    
    Args:
        request: CreateMetadataRequest with service_name, owner, sponsor, lot, and gcloud_version
        x_user_email: Optional user email from frontend (for logging)
    
    Returns:
        CreateMetadataResponse with success status and folder path
    """
    try:
        # Import SharePoint service
        try:
            from sharepoint_service.sharepoint_online import create_metadata_file
        except ImportError:
            logger.error("SharePoint Online service not available")
            raise HTTPException(
                status_code=500,
                detail="SharePoint service not configured. Ensure USE_SHAREPOINT=true and SharePoint credentials are set."
            )
        
        # Validate configuration
        site_id = os.getenv("SHAREPOINT_SITE_ID", "")
        if not site_id:
            raise HTTPException(
                status_code=500,
                detail="SHAREPOINT_SITE_ID not configured"
            )
        
        # Construct folder path: GCloud {version}/PA Services/{service_name}
        gcloud_version = request.gcloud_version or "15"
        full_folder_path = f"GCloud {gcloud_version}/PA Services/{request.service_name}"
        
        logger.info(f"Creating metadata file in folder: {full_folder_path} (Owner: {request.owner}, Sponsor: {request.sponsor})")
        
        # Prepare metadata dictionary
        metadata = {
            "service_name": request.service_name,
            "owner": request.owner,
            "sponsor": request.sponsor,
            "lot": request.lot,
            "gcloud_version": gcloud_version
        }
        
        if request.last_edited_by:
            metadata["last_edited_by"] = request.last_edited_by
        
        # Create metadata file
        success = create_metadata_file(full_folder_path, metadata, gcloud_version)
        
        if not success:
            error_msg = f"Failed to create metadata file in folder: {full_folder_path}"
            logger.error(error_msg)
            return CreateMetadataResponse(
                success=False,
                folder_path=full_folder_path,
                service_name=request.service_name,
                owner=request.owner,
                sponsor=request.sponsor,
                error=error_msg
            )
        
        logger.info(f"Successfully created metadata file in folder: {full_folder_path}")
        
        return CreateMetadataResponse(
            success=True,
            folder_path=full_folder_path,
            service_name=request.service_name,
            owner=request.owner,
            sponsor=request.sponsor,
            error=None
        )
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error creating SharePoint metadata: {e}", exc_info=True)
        raise HTTPException(
            status_code=500,
            detail=f"Internal error creating metadata: {str(e)}"
        )
