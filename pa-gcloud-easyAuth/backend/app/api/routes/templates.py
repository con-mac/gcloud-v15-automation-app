"""
G-Cloud Template API routes
Handles template-based proposal creation
"""

from fastapi import APIRouter, HTTPException, UploadFile, File
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field, validator, model_validator
from typing import List, Optional, Literal, Dict
import os
import uuid
import re
import logging

from app.services.document_generator import DocumentGenerator
from app.services.s3_service import S3Service

logger = logging.getLogger(__name__)

# Initialize services based on environment
_use_s3 = os.environ.get("USE_S3", "false").lower() == "true"
if _use_s3:
    s3_service = S3Service()
    document_generator = DocumentGenerator(s3_service=s3_service)
else:
    document_generator = DocumentGenerator()

router = APIRouter()


class ServiceDescriptionRequest(BaseModel):
    """Request model for G-Cloud Service Description"""
    title: str = Field(..., min_length=1, max_length=100, description="Service name")
    description: str = Field(..., max_length=2000, description="Service description (max 50 words)")
    features: List[str] = Field(..., min_items=0, max_items=10, description="Service features (max 10)")
    benefits: List[str] = Field(..., min_items=0, max_items=10, description="Service benefits (max 10)")
    # New: service definition subsections (no constraints)
    # Each block: { subtitle: str, content: str(HTML), images?: [url], table?: [][] }
    service_definition: Optional[List[dict]] = Field(default_factory=list, description="Service Definition subsections (rich HTML content)")
    # Update metadata (optional - for replacing existing documents)
    update_metadata: Optional[Dict] = Field(default=None, description="Metadata for updating existing document (service_name, lot, doc_type, gcloud_version, folder_path)")
    # New proposal metadata (optional - for saving to new folder)
    new_proposal_metadata: Optional[Dict] = Field(default=None, description="Metadata for new proposal (service, owner, sponsor, lot, gcloud_version)")
    # Save as draft (optional - adds _draft suffix)
    save_as_draft: Optional[bool] = Field(default=False, description="Save as draft with _draft suffix")
    
    @validator('title')
    def validate_title(cls, v):
        """Title should be just the service name, no extra keywords"""
        if len(v.split()) > 10:
            raise ValueError('Title should be concise - just the service name')
        return v.strip()
    
    @validator('description')
    def validate_description(cls, v):
        """Validate word count for description - maximum 50 words"""
        word_count = len(re.findall(r'\b\w+\b', v))
        if word_count > 50:
            raise ValueError(f'Description must not exceed 50 words (currently {word_count})')
        return v.strip()
    
    @model_validator(mode='after')
    def validate_completed_documents(self):
        """Validate that completed documents (not drafts) have at least 1 feature and 1 benefit"""
        if not self.save_as_draft:
            if len(self.features) < 1:
                raise ValueError('Features must have at least 1 item for completed documents')
            if len(self.benefits) < 1:
                raise ValueError('Benefits must have at least 1 item for completed documents')
        return self
    
    @validator('features', 'benefits', each_item=True)
    def validate_list_items(cls, v):
        """Each feature/benefit should be max 10 words (excluding numbered prefixes)"""
        # Strip numbered prefixes (e.g., "1. ", "2. ", "10. ", etc.) before counting words
        # Pattern matches: optional whitespace, one or more digits, optional period, optional whitespace
        stripped = re.sub(r'^\s*\d+\.?\s*', '', v.strip())
        
        # Count words in the stripped content
        word_count = len(re.findall(r'\b\w+\b', stripped))
        if word_count > 10:
            raise ValueError(f'Each item must be max 10 words (this item has {word_count})')
        if word_count < 1:
            raise ValueError('Item cannot be empty')
        return v.strip()


class GenerateResponse(BaseModel):
    """Response after generating documents"""
    success: bool
    message: str
    word_filename: str
    pdf_filename: str
    word_path: str
    pdf_path: str


@router.post("/service-description/generate", response_model=GenerateResponse)
async def generate_service_description(request: ServiceDescriptionRequest):
    """
    Generate G-Cloud Service Description documents from template
    
    Creates both Word (.docx) and PDF versions following the official
    G-Cloud v15 template format with PA Consulting branding.
    
    If update_metadata is provided, replaces existing documents instead of creating new ones.
    """
    try:
        # If this is a new proposal, ensure metadata.json exists
        # This ensures proposals appear in the dashboard even if metadata wasn't created during folder creation
        if request.new_proposal_metadata and not request.update_metadata:
            try:
                from sharepoint_service.sharepoint_online import create_metadata_file
                import os
                
                service_name = request.new_proposal_metadata.get('service', title)
                lot = request.new_proposal_metadata.get('lot', '2')
                gcloud_version = request.new_proposal_metadata.get('gcloud_version', '15')
                owner = request.new_proposal_metadata.get('owner', '')
                sponsor = request.new_proposal_metadata.get('sponsor', '')
                
                if service_name and owner:
                    # Construct folder path
                    folder_path = f"GCloud {gcloud_version}/PA Services/{service_name}"
                    
                    # Prepare metadata
                    metadata = {
                        "service_name": service_name,
                        "owner": owner,
                        "sponsor": sponsor or '',
                        "lot": lot,
                        "gcloud_version": gcloud_version
                    }
                    
                    # Try to create/update metadata file (don't fail if it doesn't work)
                    try:
                        create_metadata_file(folder_path, metadata, gcloud_version)
                        logger.info(f"Created/updated metadata.json for {service_name}")
                    except Exception as e:
                        logger.warning(f"Failed to create/update metadata.json (non-fatal): {e}")
            except Exception as e:
                logger.warning(f"Failed to ensure metadata.json exists (non-fatal): {e}")
        
        result = document_generator.generate_service_description(
            title=request.title,
            description=request.description,
            features=request.features,
            benefits=request.benefits,
            service_definition=request.service_definition or [],
            update_metadata=request.update_metadata,
            save_as_draft=request.save_as_draft or False,
            new_proposal_metadata=request.new_proposal_metadata
        )
        
        # Handle PDF path - may be None in Lambda if PDF generation not implemented
        # Check for pdf_blob_key (Azure), pdf_s3_key (AWS), or pdf_path (local)
        pdf_path = result.get('pdf_path') or result.get('pdf_blob_key') or result.get('pdf_s3_key', '')
        
        # Check if we're in Azure
        use_azure = bool(os.environ.get("AZURE_STORAGE_CONNECTION_STRING", ""))
        
        if pdf_path and not pdf_path.startswith('http'):
            if use_azure and result.get('pdf_blob_key'):
                # Azure: Check if PDF blob exists and create download URL
                try:
                    from app.services.azure_blob_service import AzureBlobService
                    azure_blob_service = AzureBlobService()
                    pdf_blob_key = result.get('pdf_blob_key')
                    if pdf_blob_key and azure_blob_service.blob_exists(pdf_blob_key):
                        # Extract filename from blob key for download URL
                        pdf_filename_for_url = Path(pdf_blob_key).name
                        pdf_path = f"/api/v1/templates/service-description/download/{pdf_filename_for_url}"
                    else:
                        # PDF doesn't exist yet (conversion may have failed or is in progress)
                        pdf_path = ""
                except Exception as e:
                    logger.warning(f"Failed to check Azure blob for PDF: {e}")
                    pdf_path = ""
            elif _use_s3 and s3_service:
                # AWS: Convert S3 key to presigned URL
                try:
                    pdf_path = s3_service.get_presigned_url(pdf_path, expiration=3600)
                except:
                    pass
        
        # Convert local file paths to download URLs for frontend
        # Always provide download URL even if file is in folder (for local download)
        word_path = result.get('word_path', '')
        word_filename_for_url = None
        if word_path and not word_path.startswith('http'):
            # Extract filename from path (includes _draft if it's a draft)
            from pathlib import Path
            word_filename_for_url = Path(word_path).name if word_path else None
            if word_filename_for_url:
                # Convert to download URL (works for both /tmp/generated_documents and folder paths)
                word_path = f"/api/v1/templates/service-description/download/{word_filename_for_url}"
        
        # Convert PDF path to download URL if it's a local path (not Azure, not AWS, not already a URL)
        pdf_filename_for_url = None
        if pdf_path and not pdf_path.startswith('http') and not pdf_path.startswith('/api/'):
            from pathlib import Path
            pdf_filename_for_url = Path(pdf_path).name if pdf_path else None
            # Only convert if PDF file exists locally (for local development)
            pdf_path_local = Path(pdf_path)
            if pdf_path_local.exists() and pdf_filename_for_url:
                pdf_path = f"/api/v1/templates/service-description/download/{pdf_filename_for_url}"
            elif not use_azure and not _use_s3:
                # Local development: PDF doesn't exist yet, keep original path for "Coming Soon" message
                pdf_path = pdf_path
            # Azure/AWS: PDF path already handled above
        
        # Use actual filename from path if available, otherwise fallback to filename_base
        word_filename = word_filename_for_url if word_filename_for_url else f"{result['filename']}.docx"
        pdf_filename = pdf_filename_for_url if pdf_filename_for_url else f"{result['filename']}.pdf"
        
        return GenerateResponse(
            success=True,
            message="Documents generated successfully",
            word_filename=word_filename,
            pdf_filename=pdf_filename,
            word_path=word_path,
            pdf_path=pdf_path or f"{result.get('filename', 'document')}.pdf"  # Fallback to filename if no path
        )
    
    except FileNotFoundError as e:
        raise HTTPException(status_code=500, detail=f"Template not found: {str(e)}")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Document generation failed: {str(e)}")


@router.get("/service-description/download/{filename:path}")
async def download_document(filename: str):
    """Download generated Word or PDF document"""
    from pathlib import Path
    from fastapi.responses import FileResponse
    from urllib.parse import unquote
    
    # URL decode the filename in case it was encoded
    filename = unquote(filename)
    
    if _use_s3 and s3_service:
        # AWS Lambda: search for file in S3 SharePoint bucket
        import boto3
        import os
        from urllib.parse import unquote
        
        sharepoint_bucket = os.environ.get('SHAREPOINT_BUCKET_NAME', '')
        output_bucket = os.environ.get('OUTPUT_BUCKET_NAME', '')
        if not sharepoint_bucket:
            raise HTTPException(status_code=500, detail="SHAREPOINT_BUCKET_NAME not set")
        
        s3_client = boto3.client('s3')
        s3_key = None
        target_bucket = output_bucket or sharepoint_bucket

        def head_exists(bucket: str, key: str) -> bool:
            if not bucket:
                return False
            try:
                s3_client.head_object(Bucket=bucket, Key=key)
                return True
            except Exception:
                return False

        candidate_keys = []
        # First, prefer generated/ locations in the output bucket (PDF converter target)
        candidate_keys.append(f"generated/{filename}")
        if filename.lower().startswith("pa gc"):
            try:
                service_part = filename.split("SERVICE DESC", 1)[1].strip()
                if service_part.lower().endswith(".pdf") or service_part.lower().endswith(".docx"):
                    service_part = service_part[:-4]
                candidate_keys.append(f"generated/{service_part}.pdf")
            except Exception:
                pass

        for key in candidate_keys:
            if head_exists(output_bucket, key):
                s3_key = key
                target_bucket = output_bucket
                break

        # Fall back to SharePoint hierarchy
        if not s3_key:
            if head_exists(sharepoint_bucket, f"generated/{filename}"):
                s3_key = f"generated/{filename}"
                target_bucket = sharepoint_bucket
            else:
                try:
                    # Search structured folders
                    for gcloud_version in ["14", "15"]:
                        for lot in ["2", "3"]:
                            base_prefix = f"GCloud {gcloud_version}/PA Services/Cloud Support Services LOT {lot}/"
                            paginator = s3_client.get_paginator('list_objects_v2')
                            pages = paginator.paginate(Bucket=sharepoint_bucket, Prefix=base_prefix)

                            for page in pages:
                                if 'Contents' not in page:
                                    continue
                                for obj in page['Contents']:
                                    if obj['Key'].endswith(filename):
                                        s3_key = obj['Key']
                                        target_bucket = sharepoint_bucket
                                        break
                                if s3_key:
                                    break
                            if s3_key:
                                break
                        if s3_key:
                            break
                except Exception as e:
                    logger.error(f"Error searching for file in S3: {e}")

        # Final attempt: direct object with exact filename in output bucket
        if not s3_key and head_exists(output_bucket, filename):
            s3_key = filename
            target_bucket = output_bucket
        
        if not s3_key:
            raise HTTPException(status_code=404, detail=f"File not found in S3: {filename}")
        
        try:
            # Generate presigned URL using the correct bucket
            presigned_url = s3_client.generate_presigned_url(
                'get_object',
                Params={'Bucket': target_bucket, 'Key': s3_key},
                ExpiresIn=3600
            )
            from fastapi.responses import RedirectResponse
            return RedirectResponse(url=presigned_url)
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Error generating presigned URL: {str(e)}")
    else:
        # Docker/local: serve from filesystem
        # Check if we're running in Docker (/app exists) or locally
        is_docker = Path("/app").exists()
        
        file_path = None
        
        if is_docker:
            # Docker environment: use /app paths
            file_path = Path(f"/app/generated_documents/{filename}")
        else:
            # Local development: check multiple locations
            # Get project root for mock_sharepoint search
            backend_dir = Path(__file__).parent.parent.parent.parent
            project_root = backend_dir.parent
            
            # Priority 1: /tmp/generated_documents (where files are actually saved in local dev)
            file_path = Path(f"/tmp/generated_documents/{filename}")
            
            # Priority 2: backend/generated_documents (if /tmp doesn't exist)
            if not file_path.exists():
                file_path = backend_dir / "generated_documents" / filename
            
            # Priority 3: mock_sharepoint folders (for updated documents)
            if not file_path.exists():
                # Try to find the file in mock_sharepoint structure
                # Path structure: mock_sharepoint/GCloud {version}/PA Services/Cloud Support Services LOT {lot}/{service_name}/{filename}
                mock_base = project_root / "mock_sharepoint"
                if mock_base.exists():
                    # Search more thoroughly - check all service folders
                    for gcloud_dir in sorted(mock_base.glob("GCloud *")):
                        if not gcloud_dir.is_dir():
                            continue
                        pa_services = gcloud_dir / "PA Services"
                        if not pa_services.exists():
                            continue
                        # Search in both LOT 2 and LOT 3 folders
                        for lot_num in ["2", "3"]:
                            lot_folder = pa_services / f"Cloud Support Services LOT {lot_num}"
                            if not lot_folder.exists() or not lot_folder.is_dir():
                                continue
                            # Check each service folder
                            for service_dir in lot_folder.iterdir():
                                if not service_dir.is_dir():
                                    continue
                                potential_file = service_dir / filename
                                if potential_file.exists():
                                    file_path = potential_file
                                    break
                                # Also check for draft file if regular file doesn't exist
                                if '_draft' not in filename:
                                    draft_filename = filename.replace('.docx', '_draft.docx').replace('.pdf', '_draft.pdf')
                                    draft_file = service_dir / draft_filename
                                    if draft_file.exists():
                                        file_path = draft_file
                                        break
                            if file_path and file_path.exists():
                                break
                        if file_path and file_path.exists():
                            break
        
        if not file_path or not file_path.exists():
            raise HTTPException(status_code=404, detail=f"File not found: {filename}")
        
        media_type = "application/vnd.openxmlformats-officedocument.wordprocessingml.document" \
            if filename.endswith('.docx') else "application/pdf"
        
        return FileResponse(
            path=str(file_path),
            media_type=media_type,
            filename=filename
        )


@router.get("/")
async def list_templates():
    """List available G-Cloud templates"""
    return {
        "templates": [
            {
                "id": "service-description",
                "name": "G-Cloud Service Description",
                "description": "Official G-Cloud v15 Service Description template with PA Consulting branding",
                "sections": [
                    {"name": "title", "label": "Service Name", "required": True, "editable": True},
                    {"name": "description", "label": "Short Service Description", "required": True, "editable": False},
                    {"name": "features", "label": "Key Service Features", "required": True, "editable": False},
                    {"name": "benefits", "label": "Key Service Benefits", "required": True, "editable": False},
                    {"name": "service_definition", "label": "Service Definition", "required": False, "editable": True}
                ],
                "validation": {
                    "title": "Service name only, no extra keywords",
                    "description": "max 50 words",
                    "features": "10 words each, max 10 features",
                    "benefits": "10 words each, max 10 benefits"
                }
            },
            {
                "id": "pricing-document",
                "name": "G-Cloud Pricing Document",
                "description": "Official G-Cloud v15 Pricing Document template",
                "status": "Coming soon"
            }
        ]
    }


@router.post("/upload")
async def upload_file(file: UploadFile = File(...)):
    """Upload a file for embedding/linking in Service Definition content.

    Returns a URL that can be used in the editor. Images will be detected by content type.
    """
    content = await file.read()
    unique = str(uuid.uuid4())[:8]
    filename = f"{unique}_{file.filename}"
    is_image = (file.content_type or "").startswith("image/")
    
    if _use_s3 and s3_service:
        # AWS Lambda: upload to S3
        s3_key = f"uploads/{filename}"
        try:
            s3_service.upload_file(content, s3_key, file.content_type or "application/octet-stream")
            # Return presigned URL
            url = s3_service.get_presigned_url(s3_key, expiration=86400)  # 24 hours
            return {"url": url, "filename": file.filename, "content_type": file.content_type, "is_image": is_image}
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Upload to S3 failed: {e}")
    else:
        # Docker/local: save to filesystem
        uploads_dir = "/app/uploads"
        os.makedirs(uploads_dir, exist_ok=True)
        dest_path = os.path.join(uploads_dir, filename)
        try:
            with open(dest_path, "wb") as f:
                f.write(content)
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Upload failed: {e}")

        url = f"/api/v1/templates/upload/{filename}"
        return {"url": url, "filename": file.filename, "content_type": file.content_type, "is_image": is_image}


@router.get("/upload/{filename}")
async def serve_upload(filename: str):
    """Serve uploaded file (only for Docker/local, S3 uses presigned URLs)"""
    if _use_s3 and s3_service:
        # AWS Lambda: generate presigned URL
        s3_key = f"uploads/{filename}"
        try:
            presigned_url = s3_service.get_presigned_url(s3_key, expiration=3600)
            from fastapi.responses import RedirectResponse
            return RedirectResponse(url=presigned_url)
        except Exception as e:
            raise HTTPException(status_code=404, detail=f"File not found in S3: {str(e)}")
    else:
        # Docker/local: serve from filesystem
        uploads_dir = "/app/uploads"
        file_path = os.path.join(uploads_dir, filename)
        if not os.path.exists(file_path):
            raise HTTPException(status_code=404, detail="File not found")
        return FileResponse(path=file_path, filename=filename)

