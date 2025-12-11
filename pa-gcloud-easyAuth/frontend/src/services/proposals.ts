/**
 * Proposals API service
 */

import apiService from './api';

export const proposalsService = {
  async getAllProposals(ownerEmail?: string): Promise<any[]> {
    const params = ownerEmail ? { owner_email: ownerEmail } : undefined;
    return apiService.get<any[]>('/proposals/', params);
  },

  async getProposalById(id: string): Promise<any> {
    return apiService.get(`/proposals/${id}`);
  },

  async updateSection(sectionId: string, content: string): Promise<any> {
    return apiService.put(`/sections/${sectionId}`, {
      content,
      user_id: 'fe3d34b2-3538-4550-89b8-0fc96eee953a', // Test user
    });
  },

  async validateSection(sectionId: string): Promise<any> {
    return apiService.post(`/sections/${sectionId}/validate`, {});
  },

  async deleteProposal(serviceName: string, lot: string, gcloudVersion: string): Promise<void> {
    return apiService.delete(`/proposals/${encodeURIComponent(serviceName)}`, {
      lot,
      gcloud_version: gcloudVersion,
    });
  },

  async getAllProposalsAdmin(): Promise<any[]> {
    return apiService.get<any[]>('/proposals/admin/all');
  },
};

