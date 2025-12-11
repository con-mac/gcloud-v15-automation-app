/**
 * Core TypeScript type definitions
 */

export enum UserRole {
  VIEWER = 'viewer',
  EDITOR = 'editor',
  REVIEWER = 'reviewer',
  ADMIN = 'admin',
}

export enum ProposalStatus {
  DRAFT = 'draft',
  IN_REVIEW = 'in_review',
  READY_FOR_SUBMISSION = 'ready_for_submission',
  SUBMITTED = 'submitted',
  APPROVED = 'approved',
  REJECTED = 'rejected',
}

export enum SectionType {
  SERVICE_NAME = 'service_name',
  SERVICE_SUMMARY = 'service_summary',
  SERVICE_FEATURES = 'service_features',
  SERVICE_BENEFITS = 'service_benefits',
  PRICING = 'pricing',
  PRICING_DETAILS = 'pricing_details',
  TERMS_CONDITIONS = 'terms_conditions',
  USER_SUPPORT = 'user_support',
  ONBOARDING = 'onboarding',
  OFFBOARDING = 'offboarding',
  DATA_MANAGEMENT = 'data_management',
  DATA_SECURITY = 'data_security',
  DATA_BACKUP = 'data_backup',
  SERVICE_AVAILABILITY = 'service_availability',
  IDENTITY_AUTHENTICATION = 'identity_authentication',
  AUDIT_LOGGING = 'audit_logging',
  SECURITY_GOVERNANCE = 'security_governance',
  VULNERABILITY_MANAGEMENT = 'vulnerability_management',
  PROTECTIVE_MONITORING = 'protective_monitoring',
  INCIDENT_MANAGEMENT = 'incident_management',
  CUSTOM = 'custom',
}

export enum ValidationStatus {
  NOT_STARTED = 'not_started',
  INVALID = 'invalid',
  WARNING = 'warning',
  VALID = 'valid',
}

export interface User {
  id: string;
  azure_ad_id: string;
  email: string;
  full_name: string;
  role: UserRole;
  is_active: boolean;
  last_login?: string;
  created_at: string;
  updated_at: string;
}

export interface Proposal {
  id: string;
  title: string;
  framework_version: string;
  status: ProposalStatus;
  deadline?: string;
  completion_percentage: number;
  created_by: string;
  last_modified_by?: string;
  original_document_url?: string;
  created_at: string;
  updated_at: string;
  section_count?: number;
  completed_sections?: number;
}

export interface Section {
  id: string;
  proposal_id: string;
  section_type: SectionType;
  title: string;
  order: number;
  content?: string;
  word_count: number;
  validation_status: ValidationStatus;
  validation_errors?: string;
  is_mandatory: boolean;
  last_modified_by?: string;
  locked_by?: string;
  locked_at?: string;
  created_at: string;
  updated_at: string;
  is_locked?: boolean;
  locked_by_name?: string;
}

export interface ValidationRule {
  id: string;
  section_type: SectionType;
  rule_type: string;
  name: string;
  description?: string;
  parameters?: Record<string, any>;
  error_message: string;
  severity: 'error' | 'warning';
  is_active: boolean;
  framework_version?: string;
}

export interface ValidationResult {
  section_id: string;
  section_title: string;
  is_valid: boolean;
  errors: string[];
  warnings: string[];
  word_count: number;
  word_count_min?: number;
  word_count_max?: number;
}

export interface ChangeHistory {
  id: string;
  section_id: string;
  user_id: string;
  change_type: 'create' | 'update' | 'delete' | 'rollback';
  old_content?: string;
  new_content?: string;
  ip_address?: string;
  user_agent?: string;
  comment?: string;
  created_at: string;
}

export interface Notification {
  id: string;
  proposal_id?: string;
  user_id: string;
  notification_type: string;
  title: string;
  message: string;
  sent_at?: string;
  read_at?: string;
  is_sent: boolean;
  is_read: boolean;
  email_sent: boolean;
  email_sent_at?: string;
  created_at: string;
}

export interface ApiResponse<T> {
  data?: T;
  error?: string;
  message?: string;
}

export interface PaginatedResponse<T> {
  items: T[];
  total: number;
  page: number;
  page_size: number;
  pages: number;
}

