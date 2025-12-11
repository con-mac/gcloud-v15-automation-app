/**
 * API service for backend communication with Easy Auth
 * Easy Auth handles authentication via cookies, so no tokens needed
 */

import axios, { AxiosInstance, AxiosError } from 'axios';
import { toast } from 'react-toastify';

// Support both VITE_API_BASE_URL (for AWS) and VITE_API_URL (for Docker)
const API_BASE_URL = (window as any).__ENV__?.VITE_API_BASE_URL || 
                     (window as any).__ENV__?.VITE_API_URL || 
                     import.meta.env.VITE_API_BASE_URL || 
                     import.meta.env.VITE_API_URL || 
                     'http://localhost:8000';
const API_VERSION = import.meta.env.VITE_API_VERSION || 'v1';

class ApiService {
  private client: AxiosInstance;

  constructor() {
    // Check if API_BASE_URL already includes /api/v1 (Azure Function App)
    // If it does, use it as-is; otherwise add /api/v1 prefix
    let baseURL: string;
    if (API_BASE_URL.includes('/api/v1')) {
      baseURL = API_BASE_URL;
    } else {
      baseURL = `${API_BASE_URL}/api/${API_VERSION}`;
    }
    
    this.client = axios.create({
      baseURL: baseURL,
      timeout: 30000,
      headers: {
        'Content-Type': 'application/json',
      },
      withCredentials: true, // CRITICAL: Include cookies for Easy Auth
    });

    this.setupInterceptors();
  }

  private setupInterceptors() {
    // Request interceptor
    this.client.interceptors.request.use(
      (config) => {
        // Easy Auth handles authentication via cookies automatically
        // No need to add Authorization header or function keys
        
        // Add user email from Easy Auth context (if available)
        // This is optional - backend can also read from Easy Auth headers
        const userEmail = sessionStorage.getItem('user_email');
        const userName = sessionStorage.getItem('user_name');
        if (userEmail) {
          config.headers['X-User-Email'] = userEmail;
        }
        if (userName) {
          config.headers['X-User-Name'] = userName;
        }

        // Add correlation ID for request tracking
        config.headers['X-Correlation-ID'] = crypto.randomUUID();

        return config;
      },
      (error) => {
        return Promise.reject(error);
      }
    );

    // Response interceptor
    this.client.interceptors.response.use(
      (response) => {
        return response;
      },
      (error: AxiosError) => {
        this.handleError(error);
        return Promise.reject(error);
      }
    );
  }

  private handleError(error: AxiosError) {
    if (!error.response) {
      // Network error
      toast.error('Network error: Unable to connect to the server');
      return;
    }

    const status = error.response.status;
    const data = error.response.data as any;

    switch (status) {
      case 401:
        // Unauthorized - redirect to Easy Auth login
        toast.error('Authentication required. Redirecting to login...');
        // Get API base URL for Easy Auth login
        const apiBaseUrl = API_BASE_URL;
        const currentPath = window.location.pathname;
        const loginUrl = `${apiBaseUrl}/.auth/login/aad?post_login_redirect_url=${encodeURIComponent(window.location.origin + currentPath)}`;
        setTimeout(() => {
          window.location.href = loginUrl;
        }, 1000);
        break;
      case 403:
        toast.error(data?.detail || 'Access forbidden');
        break;
      case 404:
        toast.error(data?.detail || 'Resource not found');
        break;
      case 500:
        toast.error(data?.detail || 'Server error occurred');
        break;
      default:
        toast.error(data?.detail || `Error: ${status}`);
    }
  }

  // Proposals API
  async getProposals(ownerEmail?: string) {
    const params = ownerEmail ? { owner_email: ownerEmail } : {};
    const response = await this.client.get('/proposals/', { params });
    return response.data;
  }

  async getProposal(id: string) {
    const response = await this.client.get(`/proposals/${id}`);
    return response.data;
  }

  async createProposal(data: any) {
    const response = await this.client.post('/proposals/', data);
    return response.data;
  }

  async updateProposal(id: string, data: any) {
    const response = await this.client.put(`/proposals/${id}`, data);
    return response.data;
  }

  async deleteProposal(id: string) {
    const response = await this.client.delete(`/proposals/${id}`);
    return response.data;
  }

  // Admin API
  async getAllProposals() {
    const response = await this.client.get('/proposals/admin/all');
    return response.data;
  }

  // Health check
  async healthCheck() {
    const response = await this.client.get('/health');
    return response.data;
  }

  // Generic HTTP methods (expose axios client methods for other services)
  async get<T = any>(url: string, config?: any): Promise<T> {
    const response = await this.client.get<T>(url, config);
    return response.data;
  }

  async post<T = any>(url: string, data?: any, config?: any): Promise<T> {
    const response = await this.client.post<T>(url, data, config);
    return response.data;
  }

  async put<T = any>(url: string, data?: any, config?: any): Promise<T> {
    const response = await this.client.put<T>(url, data, config);
    return response.data;
  }

  async delete<T = any>(url: string, config?: any): Promise<T> {
    const response = await this.client.delete<T>(url, config);
    return response.data;
  }

  async patch<T = any>(url: string, data?: any, config?: any): Promise<T> {
    const response = await this.client.patch<T>(url, data, config);
    return response.data;
  }
}

export const apiService = new ApiService();
export default apiService;
