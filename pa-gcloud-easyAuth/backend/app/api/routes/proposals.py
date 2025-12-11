"""Proposals API routes"""

from fastapi import APIRouter, HTTPException, Header, Query
from typing import List, Optional
from pydantic import BaseModel
from pathlib import Path
from datetime import datetime
import os
import shutil
import logging

logger = logging.getLogger(__name__)

# Lazy import for Lambda compatibility
try:
    from app.services.database import db_service
except ImportError:
    db_service = None

# Import SharePoint service (switches between local and S3)
try:
    # Try both import paths (local and Lambda)
    try:
        from sharepoint_service.sharepoint_service import MOCK_BASE_PATH, read_metadata_file, get_document_path, USE_S3
    except ImportError:
        from app.sharepoint_service.sharepoint_service import MOCK_BASE_PATH, read_metadata_file, get_document_path, USE_S3
except ImportError as e:
    logger.warning(f"Failed to import SharePoint service: {e}")
    MOCK_BASE_PATH = None
    read_metadata_file = None
    get_document_path = None
    USE_S3 = False

router = APIRouter()


class ProposalResponse(BaseModel):
    """Proposal response model"""
    id: str
    title: str
    framework_version: str
    status: str
    deadline: Optional[str] = None
    completion_percentage: float
    created_at: str
    updated_at: str
    created_by_name: str
    section_count: int
    valid_sections: int


class SectionResponse(BaseModel):
    """Section response model"""
    id: str
    section_type: str
    title: str
    order: int
    content: Optional[str] = None
    word_count: int
    validation_status: str
    is_mandatory: bool
    validation_errors: Optional[str] = None


class ProposalDetailResponse(BaseModel):
    """Proposal detail with sections"""
    id: str
    title: str
    framework_version: str
    status: str
    deadline: Optional[str] = None
    completion_percentage: float
    created_at: str
    updated_at: str
    created_by_name: str
    sections: List[dict]


def extract_name_from_email(email: str) -> str:
    """
    Extract name from email for backward compatibility with SharePoint metadata.
    
    SharePoint stores owner as name (e.g., "Firstname Lastname"), so we extract
    the name from the Entra ID email for matching.
    
    Handles formats:
    - Firstname.Lastname@paconsulting.com → "Firstname Lastname"
    - firstname.lastname@domain.com → "Firstname Lastname"
    - user@domain.com → "User" (fallback)
    
    Args:
        email: Email address from Entra ID
        
    Returns:
        Name in format "Firstname Lastname" for matching with SharePoint metadata
    """
    if not email or '@' not in email:
        return ''
    
    # Get local part (before @)
    local_part = email.split('@')[0]
    
    # If email contains dots, assume format: firstname.lastname
    if '.' in local_part:
        # Replace . with space and capitalize
        name_parts = local_part.split('.')
        name = ' '.join(word.capitalize() for word in name_parts if word)
    else:
        # Single word - capitalize first letter
        name = local_part.capitalize()
    
    # Capitalize first letter of each word
    name = ' '.join(word.capitalize() for word in name.split())
    
    return name


def get_proposals_by_owner(owner_name: str) -> List[dict]:
    """
    Get all proposals where OWNER matches the given owner name.
    Works with both local (mock_sharepoint) and S3 storage.
    
    Args:
        owner_name: Owner name to match (e.g., "Firstname Lastname")
        
    Returns:
        List of proposals with metadata
    """
    proposals = []
    
    # Import SharePoint service functions (switches between local and S3)
    try:
        # Try both import paths (local and Lambda)
        try:
            from sharepoint_service.sharepoint_service import list_all_folders, read_metadata_file, get_document_path
        except ImportError:
            from app.sharepoint_service.sharepoint_service import list_all_folders, read_metadata_file, get_document_path
    except ImportError as e:
        logger.error(f"Failed to import SharePoint service functions: {e}")
        return []
    
    # Check if we're in Azure
    use_azure = not USE_S3 and bool(os.environ.get("AZURE_STORAGE_CONNECTION_STRING", ""))
    
    # If using S3, use list_all_folders
    if USE_S3:
        # Search through both GCloud 14 and 15
        for gcloud_version in ["14", "15"]:
            try:
                folders = list_all_folders(gcloud_version)
                
                for folder in folders:
                    service_name = folder.get('service_name', '')
                    lot = folder.get('lot', '2')
                    folder_owner = folder.get('owner', '')
                    
                    # Check if owner matches (case-insensitive)
                    if folder_owner.lower() != owner_name.lower():
                        continue
                    
                    folder_path = folder.get('folder_path', '')
                    if folder_path:
                        metadata = read_metadata_file(folder_path)
                        if metadata and metadata.get('owner', '').lower() == owner_name.lower():
                            # Check if documents exist
                            service_desc_exists = False
                            pricing_doc_exists = False
                            last_update = None
                            
                            if get_document_path:
                                # Check SERVICE DESC
                                service_desc_path = get_document_path(service_name, "SERVICE DESC", lot, gcloud_version)
                                if service_desc_path:
                                    service_desc_exists = True
                                    # Get S3 object last modified time
                                    try:
                                        import boto3
                                        s3_client = boto3.client('s3')
                                        bucket_name = os.environ.get('SHAREPOINT_BUCKET_NAME', '')
                                        if bucket_name:
                                            obj_response = s3_client.head_object(Bucket=bucket_name, Key=service_desc_path)
                                            last_update = obj_response['LastModified'].isoformat()
                                    except Exception as e:
                                        logger.warning(f"Could not get S3 object timestamp: {e}")
                                        last_update = datetime.now().isoformat()
                                
                                # Check Pricing Doc
                                pricing_doc_path = get_document_path(service_name, "Pricing Doc", lot, gcloud_version)
                                if pricing_doc_path:
                                    pricing_doc_exists = True
                                    # Update last_update if pricing doc is newer
                                    try:
                                        import boto3
                                        s3_client = boto3.client('s3')
                                        bucket_name = os.environ.get('SHAREPOINT_BUCKET_NAME', '')
                                        if bucket_name:
                                            obj_response = s3_client.head_object(Bucket=bucket_name, Key=pricing_doc_path)
                                            pricing_update = obj_response['LastModified'].isoformat()
                                            if not last_update or pricing_update > last_update:
                                                last_update = pricing_update
                                    except Exception:
                                        pass
                            
                            # Determine status
                            if service_desc_exists and pricing_doc_exists:
                                status = "complete"
                                completion_percentage = 100.0
                            elif service_desc_exists or pricing_doc_exists:
                                status = "incomplete"
                                completion_percentage = 50.0
                            else:
                                status = "draft"
                                completion_percentage = 0.0
                            
                            # Create proposal ID
                            proposal_id = f"{service_name}_{gcloud_version}_{lot}".replace(" ", "_").lower()
                            
                            proposals.append({
                                "id": proposal_id,
                                "title": service_name,
                                "framework_version": f"G-Cloud {gcloud_version}",
                                "gcloud_version": gcloud_version,
                                "lot": lot,
                                "status": status,
                                "completion_percentage": completion_percentage,
                                "section_count": 2,
                                "valid_sections": 2 if status == "complete" else 1 if status == "incomplete" else 0,
                                "created_at": last_update or datetime.now().isoformat(),
                                "updated_at": last_update or datetime.now().isoformat(),
                                "last_update": last_update,
                                "service_desc_exists": service_desc_exists,
                                "pricing_doc_exists": pricing_doc_exists,
                                "owner": folder_owner,
                                "sponsor": metadata.get('sponsor', '') if metadata else '',
                            })
            except Exception as e:
                logger.error(f"Error getting proposals for GCloud {gcloud_version}: {e}")
                continue
        
        # Sort by last update (most recent first)
        proposals.sort(key=lambda x: x.get("last_update") or "", reverse=True)
        return proposals
    
    # If using Azure, use Azure Blob Storage
    if use_azure:
        try:
            from app.services.azure_blob_service import AzureBlobService
            azure_blob_service = AzureBlobService()
            
            # Search in SharePoint folder structure
            # Format: GCloud {version}/PA Services/Cloud Support Services LOT {lot}/{service_folder}/{filename}
            for gcloud_version in ["14", "15"]:
                for lot in ["2", "2a", "2b", "3"]:
                    base_prefix = f"GCloud {gcloud_version}/PA Services/Cloud Support Services LOT {lot}/"
                    blob_list = azure_blob_service.list_blobs(prefix=base_prefix)
                    
                    # Group blobs by folder (service_folder)
                    service_folders = {}
                    for blob_name in blob_list:
                        # Extract folder name from blob path
                        # Format: GCloud {version}/PA Services/Cloud Support Services LOT {lot}/{folder}/{filename}
                        parts = blob_name.split('/')
                        if len(parts) >= 4:
                            folder_name = parts[3]
                            if folder_name not in service_folders:
                                service_folders[folder_name] = []
                            service_folders[folder_name].append(blob_name)
                    
                    # Check each service folder
                    for folder_name, blob_names in service_folders.items():
                        # Look for metadata file (metadata.json or OWNER *.txt)
                        metadata_blob = None
                        metadata_format = None  # 'json' or 'txt'
                        
                        for blob_name in blob_names:
                            # Check for metadata.json (can be at end or in path)
                            if 'metadata.json' in blob_name or blob_name.endswith('/metadata.json'):
                                metadata_blob = blob_name
                                metadata_format = 'json'
                                break
                            elif blob_name.endswith('.txt') and 'OWNER' in blob_name:
                                metadata_blob = blob_name
                                metadata_format = 'txt'
                                break
                        
                        if not metadata_blob:
                            continue
                        
                        # Read metadata
                        try:
                            metadata_bytes = azure_blob_service.get_file_bytes(metadata_blob)
                            
                            if metadata_format == 'json':
                                # Parse JSON metadata
                                import json
                                metadata = json.loads(metadata_bytes.decode('utf-8'))
                            else:
                                # Parse text metadata (legacy format)
                                metadata_content = metadata_bytes.decode('utf-8')
                                metadata = {}
                                for line in metadata_content.split('\n'):
                                    if ':' in line:
                                        key, value = line.split(':', 1)
                                        key = key.strip().lstrip('0123456789. ').strip()
                                        value = value.strip()
                                        if key:
                                            metadata[key.lower().replace(' ', '_')] = value
                            
                            folder_owner = metadata.get('owner', '').strip()
                            if not folder_owner or folder_owner.lower() != owner_name.lower():
                                logger.debug(f"Skipping folder {folder_name}: owner '{folder_owner}' doesn't match '{owner_name}'")
                                continue
                            
                            # Get service name from metadata (try both 'service' and 'service_name' keys)
                            service_name = metadata.get('service_name') or metadata.get('service') or folder_name
                            logger.debug(f"Found proposal: {service_name} (owner: {folder_owner}, lot: {lot}, version: {gcloud_version})")
                            
                            # Check if documents exist
                            service_desc_exists = False
                            pricing_doc_exists = False
                            last_update = None
                            
                            # Check for SERVICE DESC files (including drafts)
                            for blob_name in blob_names:
                                if 'SERVICE DESC' in blob_name and blob_name.endswith('.docx'):
                                    service_desc_exists = True
                                    # Get blob last modified time
                                    try:
                                        blob_client = azure_blob_service.blob_service_client.get_blob_client(
                                            container=azure_blob_service.container_name,
                                            blob=blob_name
                                        )
                                        props = blob_client.get_blob_properties()
                                        mtime = props.last_modified.timestamp()
                                        if last_update is None or mtime > last_update:
                                            last_update = mtime
                                    except Exception as e:
                                        logger.warning(f"Error getting blob timestamp: {e}")
                                elif 'Pricing Doc' in blob_name and blob_name.endswith('.docx'):
                                    pricing_doc_exists = True
                                    try:
                                        blob_client = azure_blob_service.blob_service_client.get_blob_client(
                                            container=azure_blob_service.container_name,
                                            blob=blob_name
                                        )
                                        props = blob_client.get_blob_properties()
                                        mtime = props.last_modified.timestamp()
                                        if last_update is None or mtime > last_update:
                                            last_update = mtime
                                    except Exception as e:
                                        logger.warning(f"Error getting blob timestamp: {e}")
                            
                            # Determine status
                            if service_desc_exists and pricing_doc_exists:
                                status = "complete"
                                completion_percentage = 100.0
                            elif service_desc_exists or pricing_doc_exists:
                                status = "incomplete"
                                completion_percentage = 50.0
                            else:
                                status = "draft"
                                completion_percentage = 0.0
                            
                            # Format last update
                            last_update_str = None
                            if last_update:
                                last_update_str = datetime.fromtimestamp(last_update).isoformat()
                            
                            # Create proposal ID
                            proposal_id = f"{service_name}_{gcloud_version}_{lot}".replace(" ", "_").lower()
                            
                            proposals.append({
                                "id": proposal_id,
                                "title": service_name,
                                "framework_version": f"G-Cloud {gcloud_version}",
                                "gcloud_version": gcloud_version,
                                "lot": lot,
                                "status": status,
                                "completion_percentage": completion_percentage,
                                "section_count": 2,
                                "valid_sections": 2 if status == "complete" else 1 if status == "incomplete" else 0,
                                "created_at": last_update_str or datetime.now().isoformat(),
                                "updated_at": last_update_str or datetime.now().isoformat(),
                                "last_update": last_update_str,
                                "service_desc_exists": service_desc_exists,
                                "pricing_doc_exists": pricing_doc_exists,
                                "owner": folder_owner,
                                "sponsor": metadata.get('sponsor', ''),
                            })
                        except Exception as e:
                            logger.warning(f"Error processing metadata blob {metadata_blob}: {e}")
                            continue
        except Exception as e:
            logger.error(f"Error getting proposals from Azure Blob Storage: {e}", exc_info=True)
        
        # Sort by last update (most recent first)
        proposals.sort(key=lambda x: x.get("last_update") or "", reverse=True)
        return proposals
    
    # Local filesystem path
    if not MOCK_BASE_PATH or not MOCK_BASE_PATH.exists():
        return proposals
    
    # Iterate through all GCloud versions
    for gcloud_dir in sorted(MOCK_BASE_PATH.glob("GCloud *")):
        if not gcloud_dir.is_dir():
            continue
        
        gcloud_version = gcloud_dir.name.replace("GCloud ", "")
        
        pa_services = gcloud_dir / "PA Services"
        if not pa_services.exists():
            continue
        
        # Check all LOTs (2, 2a, 2b, 3)
        for lot_num in ["2", "2a", "2b", "3"]:
            lot_folder = pa_services / f"Cloud Support Services LOT {lot_num}"
            if not lot_folder.exists() or not lot_folder.is_dir():
                continue
            
            # Check each service folder
            for service_dir in lot_folder.iterdir():
                if not service_dir.is_dir():
                    continue
                
                # Read metadata file
                if read_metadata_file:
                    metadata = read_metadata_file(service_dir)
                    if not metadata:
                        continue
                    
                    # Match owner name (case-insensitive)
                    folder_owner = metadata.get('owner', '').strip()
                    if folder_owner.lower() != owner_name.lower():
                        continue
                    
                    service_name = metadata.get('service', service_dir.name)
                    
                    # Check if both SERVICE DESC and Pricing Doc exist
                    service_desc_exists = False
                    pricing_doc_exists = False
                    last_update = None
                    
                    if get_document_path:
                        # Check SERVICE DESC
                        service_desc_path = get_document_path(service_name, "SERVICE DESC", lot_num, gcloud_version)
                        # Handle tuple return from Azure (blob_key, None) vs Path object for local
                        if service_desc_path:
                            if isinstance(service_desc_path, tuple):
                                # Azure Blob Storage: tuple (blob_key, None)
                                blob_key = service_desc_path[0]
                                if blob_key:
                                    try:
                                        from app.services.azure_blob_service import AzureBlobService
                                        azure_blob_service = AzureBlobService()
                                        if azure_blob_service.blob_exists(blob_key):
                                            service_desc_exists = True
                                            # Get blob last modified time
                                            blob_client = azure_blob_service.blob_service_client.get_blob_client(
                                                container=azure_blob_service.container_name,
                                                blob=blob_key
                                            )
                                            props = blob_client.get_blob_properties()
                                            mtime = props.last_modified.timestamp()
                                            if last_update is None or mtime > last_update:
                                                last_update = mtime
                                    except Exception as e:
                                        logger.warning(f"Error checking Azure blob for SERVICE DESC: {e}")
                            elif hasattr(service_desc_path, 'exists') and service_desc_path.exists():
                                # Local Path object
                                service_desc_exists = True
                                mtime = service_desc_path.stat().st_mtime
                                if last_update is None or mtime > last_update:
                                    last_update = mtime
                        
                        # Check Pricing Doc
                        pricing_doc_path = get_document_path(service_name, "Pricing Doc", lot_num, gcloud_version)
                        # Handle tuple return from Azure (blob_key, None) vs Path object for local
                        if pricing_doc_path:
                            if isinstance(pricing_doc_path, tuple):
                                # Azure Blob Storage: tuple (blob_key, None)
                                blob_key = pricing_doc_path[0]
                                if blob_key:
                                    try:
                                        from app.services.azure_blob_service import AzureBlobService
                                        azure_blob_service = AzureBlobService()
                                        if azure_blob_service.blob_exists(blob_key):
                                            pricing_doc_exists = True
                                            # Get blob last modified time
                                            blob_client = azure_blob_service.blob_service_client.get_blob_client(
                                                container=azure_blob_service.container_name,
                                                blob=blob_key
                                            )
                                            props = blob_client.get_blob_properties()
                                            mtime = props.last_modified.timestamp()
                                            if last_update is None or mtime > last_update:
                                                last_update = mtime
                                    except Exception as e:
                                        logger.warning(f"Error checking Azure blob for Pricing Doc: {e}")
                            elif hasattr(pricing_doc_path, 'exists') and pricing_doc_path.exists():
                                # Local Path object
                                pricing_doc_exists = True
                                mtime = pricing_doc_path.stat().st_mtime
                                if last_update is None or mtime > last_update:
                                    last_update = mtime
                    
                    # Determine status
                    if service_desc_exists and pricing_doc_exists:
                        status = "complete"
                        completion_percentage = 100.0
                    elif service_desc_exists or pricing_doc_exists:
                        status = "incomplete"
                        completion_percentage = 50.0
                    else:
                        status = "draft"
                        completion_percentage = 0.0
                    
                    # Format last update
                    last_update_str = None
                    if last_update:
                        last_update_str = datetime.fromtimestamp(last_update).isoformat()
                    
                    # Create proposal ID from service name and gcloud version
                    proposal_id = f"{service_name}_{gcloud_version}_{lot_num}".replace(" ", "_").lower()
                    
                    proposals.append({
                        "id": proposal_id,
                        "title": service_name,
                        "framework_version": f"G-Cloud {gcloud_version}",
                        "gcloud_version": gcloud_version,
                        "lot": lot_num,
                        "status": status,
                        "completion_percentage": completion_percentage,
                        "section_count": 2,  # SERVICE DESC and Pricing Doc
                        "valid_sections": 2 if status == "complete" else 1 if status == "incomplete" else 0,
                        "created_at": last_update_str or datetime.now().isoformat(),
                        "updated_at": last_update_str or datetime.now().isoformat(),
                        "last_update": last_update_str,
                        "service_desc_exists": service_desc_exists,
                        "pricing_doc_exists": pricing_doc_exists,
                        "owner": folder_owner,
                        "sponsor": metadata.get('sponsor', ''),
                    })
    
    # Sort by last update (most recent first)
    proposals.sort(key=lambda x: x.get("last_update") or "", reverse=True)
    
    return proposals


@router.get("/", response_model=List[dict])
async def get_all_proposals(
    owner_email: Optional[str] = Query(None, description="Owner email from Entra ID"),
    x_user_email: Optional[str] = Header(None, alias="X-User-Email", description="User email from Entra ID SSO token"),
    x_user_name: Optional[str] = Header(None, alias="X-User-Name", description="User display name from Entra ID SSO token")
):
    """
    Get all proposals filtered by owner.
    
    Uses Entra ID user display name (preferred) or extracts name from email for matching.
    SharePoint metadata stores owner as display name, so we match by name.
    
    Args:
        owner_email: Email address from Entra ID (query param)
        x_user_email: User email from Entra ID SSO token (header, preferred)
        x_user_name: User display name from Entra ID SSO token (header, preferred for matching)
        
    Returns:
        List of proposals matching the owner
    """
    try:
        # Use X-User-Name header if available (from SSO), this is the most reliable
        # since SharePoint stores owner as display name
        if x_user_name:
            owner_name = x_user_name
        else:
            # Fallback: extract name from email
            effective_email = x_user_email or owner_email
            if not effective_email:
                return []
            owner_name = extract_name_from_email(effective_email)
        
        if not owner_name:
            logger.warning(f"Could not determine owner name from headers or email")
            return []
        
        # Get proposals from SharePoint (matches by owner name)
        proposals = get_proposals_by_owner(owner_name)
        
        return proposals
        
    except Exception as e:
        logger.error(f"Error getting proposals: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Error getting proposals: {str(e)}")


@router.get("/{proposal_id}", response_model=dict)
async def get_proposal(proposal_id: str):
    """Get proposal by ID with all sections"""
    try:
        proposal = db_service.get_proposal_by_id(proposal_id)
        if not proposal:
            raise HTTPException(status_code=404, detail="Proposal not found")
        return proposal
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/admin/all")
async def get_all_proposals_admin():
    """
    Get all proposals (admin endpoint - no owner filtering).
    
    Returns:
        List of all proposals across all owners
    """
    try:
        # Check if we're in Azure
        use_azure = not USE_S3 and bool(os.environ.get("AZURE_STORAGE_CONNECTION_STRING", ""))
        
        if USE_S3:
            # For S3, we need to use list_all_folders and search_documents
            try:
                from sharepoint_service.sharepoint_service import list_all_folders, search_documents
            except ImportError:
                from app.sharepoint_service.sharepoint_service import list_all_folders, search_documents
            proposals = []
            
            # Get all proposals from both GCloud 14 and 15
            for version in ["14", "15"]:
                folders = list_all_folders(version)
                for folder in folders:
                    service_name = folder.get('service_name', '')
                    lot = folder.get('lot', '2')
                    owner = folder.get('owner', '')
                    
                    # Check if both SERVICE DESC and Pricing Doc exist
                    service_desc_exists = False
                    pricing_doc_exists = False
                    last_update = None
                    
                    if get_document_path:
                        # Check SERVICE DESC
                        service_desc_path = get_document_path(service_name, "SERVICE DESC", lot, version)
                        if service_desc_path:
                            service_desc_exists = True
                            # For S3, we'd need to get object metadata for last_update
                            # For now, we'll use current time as placeholder
                            from datetime import datetime
                            last_update = datetime.now().timestamp()
                        
                        # Check Pricing Doc
                        pricing_doc_path = get_document_path(service_name, "Pricing Doc", lot, version)
                        if pricing_doc_path:
                            pricing_doc_exists = True
                            from datetime import datetime
                            if last_update is None:
                                last_update = datetime.now().timestamp()
                    
                    # Determine status
                    if service_desc_exists and pricing_doc_exists:
                        status = "complete"
                        completion_percentage = 100.0
                    elif service_desc_exists or pricing_doc_exists:
                        status = "incomplete"
                        completion_percentage = 50.0
                    else:
                        status = "draft"
                        completion_percentage = 0.0
                    
                    # Format last update
                    last_update_str = None
                    if last_update:
                        last_update_str = datetime.fromtimestamp(last_update).isoformat()
                    
                    # Create proposal ID
                    proposal_id = f"{service_name}_{version}_{lot}".replace(" ", "_").lower()
                    
                    proposals.append({
                        "id": proposal_id,
                        "title": service_name,
                        "framework_version": f"G-Cloud {version}",
                        "gcloud_version": version,
                        "lot": lot,
                        "status": status,
                        "completion_percentage": completion_percentage,
                        "section_count": 2,
                        "valid_sections": 2 if status == "complete" else 1 if status == "incomplete" else 0,
                        "created_at": last_update_str or datetime.now().isoformat(),
                        "updated_at": last_update_str or datetime.now().isoformat(),
                        "last_update": last_update_str,
                        "service_desc_exists": service_desc_exists,
                        "pricing_doc_exists": pricing_doc_exists,
                        "owner": owner,
                        "sponsor": folder.get('sponsor', ''),
                    })
            
            # Sort by last update (most recent first)
            proposals.sort(key=lambda x: x.get("last_update") or "", reverse=True)
            return proposals
        
        # If using Azure, use Azure Blob Storage
        if use_azure:
            try:
                from app.services.azure_blob_service import AzureBlobService
                azure_blob_service = AzureBlobService()
                
                proposals = []
                
                # Search in SharePoint folder structure
                for gcloud_version in ["14", "15"]:
                    for lot in ["2", "2a", "2b", "3"]:
                        base_prefix = f"GCloud {gcloud_version}/PA Services/Cloud Support Services LOT {lot}/"
                        blob_list = azure_blob_service.list_blobs(prefix=base_prefix)
                        
                        # Group blobs by folder (service_folder)
                        service_folders = {}
                        for blob_name in blob_list:
                            parts = blob_name.split('/')
                            if len(parts) >= 4:
                                folder_name = parts[3]
                                if folder_name not in service_folders:
                                    service_folders[folder_name] = []
                                service_folders[folder_name].append(blob_name)
                        
                        # Check each service folder
                        for folder_name, blob_names in service_folders.items():
                            # Look for metadata file (OWNER *.txt)
                            metadata_blob = None
                            for blob_name in blob_names:
                                if blob_name.endswith('.txt') and 'OWNER' in blob_name:
                                    metadata_blob = blob_name
                                    break
                            
                            if not metadata_blob:
                                continue
                            
                            # Read metadata
                            try:
                                metadata_bytes = azure_blob_service.get_file_bytes(metadata_blob)
                                metadata_content = metadata_bytes.decode('utf-8')
                                
                                # Parse metadata
                                metadata = {}
                                for line in metadata_content.split('\n'):
                                    if ':' in line:
                                        key, value = line.split(':', 1)
                                        key = key.strip().lstrip('0123456789. ').strip()
                                        value = value.strip()
                                        if key:
                                            metadata[key.lower().replace(' ', '_')] = value
                                
                                folder_owner = metadata.get('owner', '').strip()
                                service_name = metadata.get('service', folder_name)
                                
                                # Check if documents exist
                                service_desc_exists = False
                                pricing_doc_exists = False
                                last_update = None
                                
                                # Check for SERVICE DESC files
                                for blob_name in blob_names:
                                    if 'SERVICE DESC' in blob_name and blob_name.endswith('.docx') and '_draft' not in blob_name:
                                        service_desc_exists = True
                                        try:
                                            blob_client = azure_blob_service.blob_service_client.get_blob_client(
                                                container=azure_blob_service.container_name,
                                                blob=blob_name
                                            )
                                            props = blob_client.get_blob_properties()
                                            mtime = props.last_modified.timestamp()
                                            if last_update is None or mtime > last_update:
                                                last_update = mtime
                                        except Exception as e:
                                            logger.warning(f"Error getting blob timestamp: {e}")
                                    elif 'Pricing Doc' in blob_name and blob_name.endswith('.docx'):
                                        pricing_doc_exists = True
                                        try:
                                            blob_client = azure_blob_service.blob_service_client.get_blob_client(
                                                container=azure_blob_service.container_name,
                                                blob=blob_name
                                            )
                                            props = blob_client.get_blob_properties()
                                            mtime = props.last_modified.timestamp()
                                            if last_update is None or mtime > last_update:
                                                last_update = mtime
                                        except Exception as e:
                                            logger.warning(f"Error getting blob timestamp: {e}")
                                
                                # Determine status
                                if service_desc_exists and pricing_doc_exists:
                                    status = "complete"
                                    completion_percentage = 100.0
                                elif service_desc_exists or pricing_doc_exists:
                                    status = "incomplete"
                                    completion_percentage = 50.0
                                else:
                                    status = "draft"
                                    completion_percentage = 0.0
                                
                                # Format last update
                                last_update_str = None
                                if last_update:
                                    last_update_str = datetime.fromtimestamp(last_update).isoformat()
                                
                                # Create proposal ID
                                proposal_id = f"{service_name}_{gcloud_version}_{lot}".replace(" ", "_").lower()
                                
                                proposals.append({
                                    "id": proposal_id,
                                    "title": service_name,
                                    "framework_version": f"G-Cloud {gcloud_version}",
                                    "gcloud_version": gcloud_version,
                                    "lot": lot,
                                    "status": status,
                                    "completion_percentage": completion_percentage,
                                    "section_count": 2,
                                    "valid_sections": 2 if status == "complete" else 1 if status == "incomplete" else 0,
                                    "created_at": last_update_str or datetime.now().isoformat(),
                                    "updated_at": last_update_str or datetime.now().isoformat(),
                                    "last_update": last_update_str,
                                    "service_desc_exists": service_desc_exists,
                                    "pricing_doc_exists": pricing_doc_exists,
                                    "owner": folder_owner,
                                    "sponsor": metadata.get('sponsor', ''),
                                })
                            except Exception as e:
                                logger.warning(f"Error processing metadata blob {metadata_blob}: {e}")
                                continue
                
                # Sort by last update (most recent first)
                proposals.sort(key=lambda x: x.get("last_update") or "", reverse=True)
                return proposals
            except Exception as e:
                logger.error(f"Error getting proposals from Azure Blob Storage: {e}", exc_info=True)
                raise HTTPException(status_code=500, detail=f"Error loading proposals: {str(e)}")
        
        # Local file system path
        if not MOCK_BASE_PATH or not MOCK_BASE_PATH.exists():
            return []
        
        proposals = []
        
        # Iterate through all GCloud versions
        for gcloud_dir in sorted(MOCK_BASE_PATH.glob("GCloud *")):
            if not gcloud_dir.is_dir():
                continue
            
            gcloud_version = gcloud_dir.name.replace("GCloud ", "")
            
            pa_services = gcloud_dir / "PA Services"
            if not pa_services.exists():
                continue
            
            # Check all LOTs (2, 2a, 2b, 3)
            for lot_num in ["2", "2a", "2b", "3"]:
                lot_folder = pa_services / f"Cloud Support Services LOT {lot_num}"
                if not lot_folder.exists() or not lot_folder.is_dir():
                    continue
                
                # Check each service folder
                for service_dir in lot_folder.iterdir():
                    if not service_dir.is_dir():
                        continue
                    
                    # Read metadata file
                    if read_metadata_file:
                        metadata = read_metadata_file(service_dir)
                        if not metadata:
                            continue
                        
                        service_name = metadata.get('service', service_dir.name)
                        folder_owner = metadata.get('owner', '').strip()
                        
                        # Check if both SERVICE DESC and Pricing Doc exist
                        service_desc_exists = False
                        pricing_doc_exists = False
                        last_update = None
                        
                        if get_document_path:
                            # Check SERVICE DESC
                            service_desc_path = get_document_path(service_name, "SERVICE DESC", lot_num, gcloud_version)
                            # Handle tuple return from Azure (blob_key, None) vs Path object for local
                            if service_desc_path:
                                if isinstance(service_desc_path, tuple):
                                    # Azure Blob Storage: tuple (blob_key, None)
                                    blob_key = service_desc_path[0]
                                    if blob_key:
                                        try:
                                            from app.services.azure_blob_service import AzureBlobService
                                            azure_blob_service = AzureBlobService()
                                            if azure_blob_service.blob_exists(blob_key):
                                                service_desc_exists = True
                                                # Get blob last modified time
                                                blob_client = azure_blob_service.blob_service_client.get_blob_client(
                                                    container=azure_blob_service.container_name,
                                                    blob=blob_key
                                                )
                                                props = blob_client.get_blob_properties()
                                                mtime = props.last_modified.timestamp()
                                                if last_update is None or mtime > last_update:
                                                    last_update = mtime
                                        except Exception as e:
                                            logger.warning(f"Error checking Azure blob for SERVICE DESC: {e}")
                                elif hasattr(service_desc_path, 'exists') and service_desc_path.exists():
                                    # Local Path object
                                    service_desc_exists = True
                                    mtime = service_desc_path.stat().st_mtime
                                    if last_update is None or mtime > last_update:
                                        last_update = mtime
                            
                            # Check Pricing Doc
                            pricing_doc_path = get_document_path(service_name, "Pricing Doc", lot_num, gcloud_version)
                            # Handle tuple return from Azure (blob_key, None) vs Path object for local
                            if pricing_doc_path:
                                if isinstance(pricing_doc_path, tuple):
                                    # Azure Blob Storage: tuple (blob_key, None)
                                    blob_key = pricing_doc_path[0]
                                    if blob_key:
                                        try:
                                            from app.services.azure_blob_service import AzureBlobService
                                            azure_blob_service = AzureBlobService()
                                            if azure_blob_service.blob_exists(blob_key):
                                                pricing_doc_exists = True
                                                # Get blob last modified time
                                                blob_client = azure_blob_service.blob_service_client.get_blob_client(
                                                    container=azure_blob_service.container_name,
                                                    blob=blob_key
                                                )
                                                props = blob_client.get_blob_properties()
                                                mtime = props.last_modified.timestamp()
                                                if last_update is None or mtime > last_update:
                                                    last_update = mtime
                                        except Exception as e:
                                            logger.warning(f"Error checking Azure blob for Pricing Doc: {e}")
                                elif hasattr(pricing_doc_path, 'exists') and pricing_doc_path.exists():
                                    # Local Path object
                                    pricing_doc_exists = True
                                    mtime = pricing_doc_path.stat().st_mtime
                                    if last_update is None or mtime > last_update:
                                        last_update = mtime
                        
                        # Determine status
                        if service_desc_exists and pricing_doc_exists:
                            status = "complete"
                            completion_percentage = 100.0
                        elif service_desc_exists or pricing_doc_exists:
                            status = "incomplete"
                            completion_percentage = 50.0
                        else:
                            status = "draft"
                            completion_percentage = 0.0
                        
                        # Format last update
                        last_update_str = None
                        if last_update:
                            last_update_str = datetime.fromtimestamp(last_update).isoformat()
                        
                        # Create proposal ID from service name and gcloud version
                        proposal_id = f"{service_name}_{gcloud_version}_{lot_num}".replace(" ", "_").lower()
                        
                        proposals.append({
                            "id": proposal_id,
                            "title": service_name,
                            "framework_version": f"G-Cloud {gcloud_version}",
                            "gcloud_version": gcloud_version,
                            "lot": lot_num,
                            "status": status,
                            "completion_percentage": completion_percentage,
                            "section_count": 2,
                            "valid_sections": 2 if status == "complete" else 1 if status == "incomplete" else 0,
                            "created_at": last_update_str or datetime.now().isoformat(),
                            "updated_at": last_update_str or datetime.now().isoformat(),
                            "last_update": last_update_str,
                            "service_desc_exists": service_desc_exists,
                            "pricing_doc_exists": pricing_doc_exists,
                            "owner": folder_owner,
                            "sponsor": metadata.get('sponsor', ''),
                        })
        
        # Sort by last update (most recent first)
        proposals.sort(key=lambda x: x.get("last_update") or "", reverse=True)
        
        return proposals
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error getting all proposals: {str(e)}")


@router.delete("/{service_name}")
async def delete_proposal(
    service_name: str,
    lot: str = Query(..., description="LOT number (2 or 3)"),
    gcloud_version: str = Query(..., description="G-Cloud version (14 or 15)")
):
    """
    Delete a proposal folder and all its contents.
    
    Args:
        service_name: Name of the service (URL encoded)
        lot: LOT number (2 or 3)
        gcloud_version: G-Cloud version (14 or 15)
        
    Returns:
        Success message
    """
    try:
        if not MOCK_BASE_PATH or not MOCK_BASE_PATH.exists():
            raise HTTPException(status_code=404, detail="SharePoint mock path not found")
        
        # Decode service name
        from urllib.parse import unquote
        service_name = unquote(service_name)
        
        # Construct folder path
        folder_path = (
            MOCK_BASE_PATH 
            / f"GCloud {gcloud_version}" 
            / "PA Services" 
            / f"Cloud Support Services LOT {lot}" 
            / service_name
        )
        
        # Check if folder exists
        if not folder_path.exists() or not folder_path.is_dir():
            raise HTTPException(status_code=404, detail=f"Proposal folder not found: {service_name}")
        
        # Delete the entire folder and all its contents
        shutil.rmtree(folder_path)
        
        return {"message": f"Proposal '{service_name}' deleted successfully"}
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error deleting proposal: {str(e)}")

