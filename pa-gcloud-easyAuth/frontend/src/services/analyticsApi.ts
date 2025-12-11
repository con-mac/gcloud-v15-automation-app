import apiService from './api';

export interface QuestionAnalytics {
  question_text: string;
  question_type: string;
  section_name: string;
  answer_counts: { [key: string]: number };
  total_responses: number;
  services_by_answer: { [key: string]: string[] };
}

export interface SectionAnalytics {
  section_name: string;
  questions: QuestionAnalytics[];
  total_questions: number;
  completed_services: number;
}

export interface ServiceStatus {
  service_name: string;
  lot: string;
  gcloud_version: string;
  has_responses: boolean;
  is_draft: boolean;
  is_locked: boolean;
  completion_percentage: number;
  last_updated?: string;
}

export interface AnalyticsSummary {
  total_services: number;
  services_with_responses: number;
  services_without_responses: number;
  services_locked: number;
  services_draft: number;
  lot_breakdown: { [key: string]: number };
  sections: SectionAnalytics[];
}

export interface DrillDownResponse {
  section_name: string;
  question_text: string;
  breakdown: { [answer: string]: Array<{ service_name: string; lot: string }> };
  total_services: number;
}

class AnalyticsApiService {
  async getAnalyticsSummary(lot?: string, gcloudVersion: string = '15'): Promise<AnalyticsSummary> {
    const params = new URLSearchParams();
    if (lot) params.append('lot', lot);
    params.append('gcloud_version', gcloudVersion);
    
    const response = await apiService.get<AnalyticsSummary>(`/analytics/summary?${params.toString()}`);
    return response;
  }

  async getServicesStatus(lot?: string, gcloudVersion: string = '15'): Promise<ServiceStatus[]> {
    const params = new URLSearchParams();
    if (lot) params.append('lot', lot);
    params.append('gcloud_version', gcloudVersion);
    
    const response = await apiService.get<ServiceStatus[]>(`/analytics/services?${params.toString()}`);
    return response;
  }

  async getDrillDown(
    sectionName: string,
    questionText: string,
    lot?: string,
    gcloudVersion: string = '15'
  ): Promise<DrillDownResponse> {
    const params = new URLSearchParams();
    if (lot) params.append('lot', lot);
    params.append('gcloud_version', gcloudVersion);
    
    const encodedSection = encodeURIComponent(sectionName);
    const encodedQuestion = encodeURIComponent(questionText);
    
    const response = await apiService.get<DrillDownResponse>(
      `/analytics/drill-down/${encodedSection}/${encodedQuestion}?${params.toString()}`
    );
    return response;
  }

  async seedQuestionnaireData(): Promise<{
    success: boolean;
    message: string;
    results: Array<{
      service_name: string;
      lot: string;
      status: string;
      answers_count?: number;
      is_locked?: boolean;
      error?: string;
    }>;
    total: number;
    succeeded: number;
    failed: number;
  }> {
    const response = await apiService.post<{
      success: boolean;
      message: string;
      results: any[];
      total: number;
      succeeded: number;
      failed: number;
    }>('/analytics/seed-questionnaire-data', {});
    return response;
  }
}

const analyticsApi = new AnalyticsApiService();
export default analyticsApi;

