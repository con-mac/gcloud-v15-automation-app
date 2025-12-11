/**
 * SharePoint API service for document management
 */

import apiService from './api';

export interface SearchRequest {
  query: string;
  doc_type?: 'SERVICE DESC' | 'Pricing Doc';
  gcloud_version?: '14' | '15';
  search_all_versions?: boolean; // Search both GCloud 14 and 15
}

export interface SearchResult {
  service_name: string;
  owner: string;
  sponsor: string;
  folder_path: string;
  doc_type: string;
  lot: string;
  gcloud_version: string;
}

export interface MetadataResponse {
  service: string;
  owner: string;
  sponsor: string;
}

export interface CreateFolderRequest {
  service_name: string;
  lot: '2' | '2a' | '2b' | '3';
  gcloud_version?: '14' | '15';
}

export interface CreateMetadataRequest {
  service_name: string;
  owner: string;
  sponsor: string;
  lot: '2' | '2a' | '2b' | '3';
  gcloud_version?: '14' | '15';
  last_edited_by?: string;
}

class SharePointApiService {
  /**
   * Search documents in SharePoint
   */
  async searchDocuments(request: SearchRequest): Promise<SearchResult[]> {
    try {
      const response = await apiService.post<SearchResult[]>('/sharepoint/search', request);
      return response;
    } catch (error: any) {
      console.error('Error searching documents:', error);
      throw error;
    }
  }

  /**
   * Get metadata for a service
   */
  async getMetadata(
    serviceName: string,
    lot: '2' | '2a' | '2b' | '3',
    gcloudVersion: '14' | '15' = '14'
  ): Promise<MetadataResponse> {
    try {
      const response = await apiService.get<MetadataResponse>(
        `/sharepoint/metadata/${encodeURIComponent(serviceName)}`,
        { lot, gcloud_version: gcloudVersion }
      );
      return response;
    } catch (error: any) {
      console.error('Error getting metadata:', error);
      throw error;
    }
  }

  /**
   * Get document info
   */
  async getDocument(
    serviceName: string,
    docType: 'SERVICE DESC' | 'Pricing Doc',
    lot: '2' | '2a' | '2b' | '3',
    gcloudVersion: '14' | '15' = '14'
  ): Promise<{ service_name: string; doc_type: string; lot: string; gcloud_version: string; file_path: string; exists: boolean }> {
    try {
      const response = await apiService.get<{ service_name: string; doc_type: string; lot: string; gcloud_version: string; file_path: string; exists: boolean }>(
        `/sharepoint/document/${encodeURIComponent(serviceName)}`,
        { doc_type: docType, lot, gcloud_version: gcloudVersion }
      );
      return response;
    } catch (error: any) {
      console.error('Error getting document:', error);
      throw error;
    }
  }

  /**
   * Create folder structure
   */
  async createFolder(request: CreateFolderRequest): Promise<{ success: boolean; folder_path: string; service_name: string; lot: string; gcloud_version: string }> {
    try {
      const response = await apiService.post<{ success: boolean; folder_path: string; service_name: string; lot: string; gcloud_version: string }>('/sharepoint/create-folder', request);
      return response;
    } catch (error: any) {
      console.error('Error creating folder:', error);
      throw error;
    }
  }

  /**
   * Create metadata file
   */
  async createMetadata(request: CreateMetadataRequest): Promise<{ success: boolean; folder_path: string; service_name: string; owner: string; sponsor: string }> {
    try {
      const response = await apiService.post<{ success: boolean; folder_path: string; service_name: string; owner: string; sponsor: string }>('/sharepoint/create-metadata', request);
      return response;
    } catch (error: any) {
      console.error('Error creating metadata:', error);
      throw error;
    }
  }

  /**
   * Get document content (parsed from Word document)
   */
  async getDocumentContent(
    serviceName: string,
    docType: 'SERVICE DESC' | 'Pricing Doc',
    lot: '2' | '2a' | '2b' | '3',
    gcloudVersion: '14' | '15' = '14'
  ): Promise<{ title: string; description: string; features: string[]; benefits: string[]; service_definition: Array<{ subtitle: string; content: string }> }> {
    try {
      const response = await apiService.get<{ title: string; description: string; features: string[]; benefits: string[]; service_definition: Array<{ subtitle: string; content: string }> }>(
        `/sharepoint/document-content/${encodeURIComponent(serviceName)}`,
        { doc_type: docType, lot, gcloud_version: gcloudVersion }
      );
      return response;
    } catch (error: any) {
      console.error('Error getting document content:', error);
      throw error;
    }
  }
}

const sharepointApi = new SharePointApiService();
export default sharepointApi;

