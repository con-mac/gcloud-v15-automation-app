"""
S3 service for template storage and document retrieval
Used in AWS Lambda deployment
"""

import os
import boto3
from pathlib import Path
from typing import Optional
from botocore.exceptions import ClientError


class S3Service:
    """Handles S3 operations for templates and generated documents"""
    
    def __init__(
        self,
        template_bucket: Optional[str] = None,
        output_bucket: Optional[str] = None,
        upload_bucket: Optional[str] = None
    ):
        self.template_bucket = template_bucket or os.environ.get("TEMPLATE_BUCKET_NAME")
        self.output_bucket = output_bucket or os.environ.get("OUTPUT_BUCKET_NAME")
        self.upload_bucket = upload_bucket or os.environ.get("UPLOAD_BUCKET_NAME")
        
        # Initialize S3 client
        self.s3_client = boto3.client('s3')
    
    def download_template(self, template_key: str, local_path: Path) -> Path:
        """
        Download template from S3 to local path (Lambda /tmp directory)
        
        Args:
            template_key: S3 key for the template (e.g., "templates/service_description_template.docx")
            local_path: Local path where template will be saved
            
        Returns:
            Path to downloaded template
        """
        if not self.template_bucket:
            raise ValueError("Template bucket not configured")
        
        try:
            local_path.parent.mkdir(parents=True, exist_ok=True)
            self.s3_client.download_file(self.template_bucket, template_key, str(local_path))
            return local_path
        except ClientError as e:
            raise FileNotFoundError(f"Failed to download template from S3: {e}")
    
    def upload_document(self, local_path: Path, s3_key: str, bucket: Optional[str] = None) -> str:
        """
        Upload generated document to S3
        
        Args:
            local_path: Local path to the file
            s3_key: S3 key where file will be stored
            bucket: Bucket name (defaults to output_bucket)
            
        Returns:
            S3 key of uploaded file
        """
        bucket = bucket or self.output_bucket
        if not bucket:
            raise ValueError("Output bucket not configured")
        
        try:
            self.s3_client.upload_file(str(local_path), bucket, s3_key)
            return s3_key
        except ClientError as e:
            raise IOError(f"Failed to upload document to S3: {e}")
    
    def get_presigned_url(self, s3_key: str, expiration: int = 3600, bucket: Optional[str] = None) -> str:
        """
        Generate presigned URL for document download
        
        Args:
            s3_key: S3 key of the file
            expiration: URL expiration time in seconds (default: 1 hour)
            bucket: Bucket name (defaults to output_bucket)
            
        Returns:
            Presigned URL
        """
        bucket = bucket or self.output_bucket
        if not bucket:
            raise ValueError("Output bucket not configured")
        
        try:
            url = self.s3_client.generate_presigned_url(
                'get_object',
                Params={'Bucket': bucket, 'Key': s3_key},
                ExpiresIn=expiration
            )
            return url
        except ClientError as e:
            raise IOError(f"Failed to generate presigned URL: {e}")
    
    def upload_file(self, file_content: bytes, s3_key: str, content_type: str, bucket: Optional[str] = None) -> str:
        """
        Upload file content directly to S3 (for file uploads)
        
        Args:
            file_content: File content as bytes
            s3_key: S3 key where file will be stored
            content_type: MIME type of the file
            bucket: Bucket name (defaults to upload_bucket)
            
        Returns:
            S3 key of uploaded file
        """
        bucket = bucket or self.upload_bucket or self.output_bucket
        if not bucket:
            raise ValueError("Upload bucket not configured")
        
        try:
            self.s3_client.put_object(
                Bucket=bucket,
                Key=s3_key,
                Body=file_content,
                ContentType=content_type
            )
            return s3_key
        except ClientError as e:
            raise IOError(f"Failed to upload file to S3: {e}")
    
    def delete_file(self, s3_key: str, bucket: Optional[str] = None) -> None:
        """
        Delete a file from S3
        
        Args:
            s3_key: S3 key of the file to delete
            bucket: Bucket name (defaults to output_bucket)
        """
        bucket = bucket or self.output_bucket
        if not bucket:
            raise ValueError("Bucket not configured")
        
        try:
            self.s3_client.delete_object(Bucket=bucket, Key=s3_key)
        except ClientError as e:
            # Log error but don't raise - deletion is best effort
            print(f"Failed to delete file from S3: {e}")

