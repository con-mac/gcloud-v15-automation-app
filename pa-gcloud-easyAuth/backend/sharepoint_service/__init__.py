"""
SharePoint service for PA deployment
Uses SharePoint Online via Microsoft Graph API
"""

# Export SharePoint Online functions
from sharepoint_service.sharepoint_online import (
    fuzzy_match,
    read_metadata_file,
    search_documents,
    get_document_path,
    create_folder,
    create_metadata_file,
    list_all_folders,
    upload_file_to_sharepoint,
    download_file_from_sharepoint,
    file_exists_in_sharepoint,
    get_file_properties,
)

__all__ = [
    'fuzzy_match',
    'read_metadata_file',
    'search_documents',
    'get_document_path',
    'create_folder',
    'create_metadata_file',
    'list_all_folders',
    'upload_file_to_sharepoint',
    'download_file_from_sharepoint',
    'file_exists_in_sharepoint',
    'get_file_properties',
]

