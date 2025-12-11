/**
 * Questionnaire API service
 */

import apiService from './api';

export interface Question {
  question_text: string;
  question_type: 'radio' | 'checkbox' | 'text' | 'textarea' | 'list';
  question_advice?: string;
  question_hint?: string;
  answer_options?: string[];
  prefilled_answer?: string;
  row_index?: number;
}

export interface QuestionnaireData {
  service_name: string;
  lot: string;
  gcloud_version: string;
  sections: Record<string, Question[]>;
  section_order: string[];
  saved_answers?: Record<string, any>;
  is_draft: boolean;
  is_locked: boolean;
}

export interface QuestionAnswer {
  question_text: string;
  question_type: string;
  answer: any;
  section_name: string;
}

export interface SaveResponseRequest {
  service_name: string;
  lot: string;
  gcloud_version: string;
  answers: QuestionAnswer[];
  is_draft: boolean;
  is_locked: boolean;
}

class QuestionnaireApiService {
  /**
   * Get questions for a LOT
   */
  async getQuestions(
    lot: string,
    serviceName?: string,
    gcloudVersion: string = '15'
  ): Promise<QuestionnaireData> {
    try {
      const params: any = { gcloud_version: gcloudVersion };
      if (serviceName) {
        params.service_name = serviceName;
      }
      const response = await apiService.get<QuestionnaireData>(
        `/questionnaire/questions/${lot}`,
        params
      );
      return response;
    } catch (error: any) {
      console.error('Error getting questions:', error);
      throw error;
    }
  }

  /**
   * Save questionnaire responses
   */
  async saveResponses(request: SaveResponseRequest): Promise<{ success: boolean; message: string }> {
    try {
      const response = await apiService.post<{ success: boolean; message: string }>(
        '/questionnaire/responses',
        request
      );
      return response;
    } catch (error: any) {
      console.error('Error saving responses:', error);
      throw error;
    }
  }

  /**
   * Get saved questionnaire responses
   */
  async getResponses(
    serviceName: string,
    lot: string,
    gcloudVersion: string = '15'
  ): Promise<{
    service_name: string;
    lot: string;
    gcloud_version: string;
    answers: Record<string, any>;
    is_draft: boolean;
    is_locked: boolean;
  }> {
    try {
      const response = await apiService.get<{
        service_name: string;
        lot: string;
        gcloud_version: string;
        answers: Record<string, any>;
        is_draft: boolean;
        is_locked: boolean;
      }>(`/questionnaire/responses/${encodeURIComponent(serviceName)}`, {
        lot,
        gcloud_version: gcloudVersion,
      });
      return response;
    } catch (error: any) {
      console.error('Error getting responses:', error);
      throw error;
    }
  }

  /**
   * Lock a questionnaire (admin only)
   */
  async lockQuestionnaire(
    serviceName: string,
    lot: string,
    gcloudVersion: string = '15'
  ): Promise<{ success: boolean; message: string; is_locked: boolean }> {
    try {
      const params = new URLSearchParams({
        lot,
        gcloud_version: gcloudVersion,
      });
      const response = await apiService.post<{ success: boolean; message: string; is_locked: boolean }>(
        `/questionnaire/responses/${encodeURIComponent(serviceName)}/lock?${params.toString()}`,
        {}
      );
      return response;
    } catch (error: any) {
      console.error('Error locking questionnaire:', error);
      throw error;
    }
  }
}

const questionnaireApi = new QuestionnaireApiService();
export default questionnaireApi;

