"""
Azure Blob Storage service for document storage and retrieval
Used in Azure Functions deployment
"""

import os
from pathlib import Path
from typing import Optional
from azure.storage.blob import BlobServiceClient, BlobClient, ContainerClient
from azure.core.exceptions import AzureError, ResourceNotFoundError
import logging

logger = logging.getLogger(__name__)


class AzureBlobService:
    """Handles Azure Blob Storage operations for templates and generated documents"""
    
    def __init__(
        self,
        connection_string: Optional[str] = None,
        container_name: Optional[str] = None
    ):
        self.connection_string = connection_string or os.environ.get("AZURE_STORAGE_CONNECTION_STRING", "")
        self.container_name = container_name or os.environ.get("AZURE_STORAGE_CONTAINER_NAME", "sharepoint")
        
        if not self.connection_string:
            raise ValueError("Azure Storage connection string not configured")
        
        # Initialize Blob Service Client
        try:
            self.blob_service_client = BlobServiceClient.from_connection_string(self.connection_string)
            self.container_client = self.blob_service_client.get_container_client(self.container_name)
            # Ensure container exists
            try:
                self.container_client.get_container_properties()
            except ResourceNotFoundError:
                logger.info(f"Container {self.container_name} does not exist, creating it...")
                self.container_client.create_container()
        except Exception as e:
            logger.error(f"Failed to initialize Azure Blob Service: {e}")
            raise
    
    def upload_file(self, local_path: Path, blob_name: str) -> str:
        """
        Upload a file to Azure Blob Storage
        
        Args:
            local_path: Local path to the file
            blob_name: Blob name (key) where file will be stored
            
        Returns:
            Blob name of uploaded file
        """
        try:
            blob_client = self.blob_service_client.get_blob_client(
                container=self.container_name,
                blob=blob_name
            )
            
            with open(local_path, 'rb') as data:
                blob_client.upload_blob(data, overwrite=True)
            
            logger.info(f"Uploaded {local_path} to {blob_name}")
            return blob_name
        except AzureError as e:
            logger.error(f"Failed to upload file to Azure Blob Storage: {e}")
            raise IOError(f"Failed to upload document to Azure Blob Storage: {e}")
    
    def download_file(self, blob_name: str, local_path: Path) -> Path:
        """
        Download a file from Azure Blob Storage
        
        Args:
            blob_name: Blob name (key) of the file
            local_path: Local path where file will be saved
            
        Returns:
            Path to downloaded file
        """
        try:
            blob_client = self.blob_service_client.get_blob_client(
                container=self.container_name,
                blob=blob_name
            )
            
            local_path.parent.mkdir(parents=True, exist_ok=True)
            
            with open(local_path, 'wb') as download_file:
                download_file.write(blob_client.download_blob().readall())
            
            logger.info(f"Downloaded {blob_name} to {local_path}")
            return local_path
        except ResourceNotFoundError:
            raise FileNotFoundError(f"Blob not found: {blob_name}")
        except AzureError as e:
            logger.error(f"Failed to download file from Azure Blob Storage: {e}")
            raise IOError(f"Failed to download document from Azure Blob Storage: {e}")
    
    def get_file_bytes(self, blob_name: str) -> bytes:
        """
        Get file content as bytes from Azure Blob Storage
        
        Args:
            blob_name: Blob name (key) of the file
            
        Returns:
            File content as bytes
        """
        try:
            blob_client = self.blob_service_client.get_blob_client(
                container=self.container_name,
                blob=blob_name
            )
            
            return blob_client.download_blob().readall()
        except ResourceNotFoundError:
            raise FileNotFoundError(f"Blob not found: {blob_name}")
        except AzureError as e:
            logger.error(f"Failed to get file from Azure Blob Storage: {e}")
            raise IOError(f"Failed to get document from Azure Blob Storage: {e}")
    
    def blob_exists(self, blob_name: str) -> bool:
        """
        Check if a blob exists
        
        Args:
            blob_name: Blob name (key) to check
            
        Returns:
            True if blob exists, False otherwise
        """
        try:
            blob_client = self.blob_service_client.get_blob_client(
                container=self.container_name,
                blob=blob_name
            )
            blob_client.get_blob_properties()
            return True
        except ResourceNotFoundError:
            return False
        except AzureError:
            return False
    
    def list_blobs(self, prefix: str = "") -> list:
        """
        List blobs with a given prefix
        
        Args:
            prefix: Prefix to filter blobs
            
        Returns:
            List of blob names
        """
        try:
            blobs = []
            for blob in self.container_client.list_blobs(name_starts_with=prefix):
                blobs.append(blob.name)
            return blobs
        except AzureError as e:
            logger.error(f"Failed to list blobs: {e}")
            return []

