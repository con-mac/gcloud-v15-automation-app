"""Constants and enums that don't require database models"""

import enum


class SectionType(str, enum.Enum):
    """G-Cloud section types"""

    SERVICE_NAME = "service_name"
    SERVICE_SUMMARY = "service_summary"
    SERVICE_FEATURES = "service_features"
    SERVICE_BENEFITS = "service_benefits"
    PRICING = "pricing"
    PRICING_DETAILS = "pricing_details"
    TERMS_CONDITIONS = "terms_conditions"
    USER_SUPPORT = "user_support"
    ONBOARDING = "onboarding"
    OFFBOARDING = "offboarding"
    DATA_MANAGEMENT = "data_management"
    DATA_SECURITY = "data_security"
    DATA_BACKUP = "data_backup"
    SERVICE_AVAILABILITY = "service_availability"
    IDENTITY_AUTHENTICATION = "identity_authentication"
    AUDIT_LOGGING = "audit_logging"
    SECURITY_GOVERNANCE = "security_governance"
    VULNERABILITY_MANAGEMENT = "vulnerability_management"
    PROTECTIVE_MONITORING = "protective_monitoring"
    INCIDENT_MANAGEMENT = "incident_management"
    CUSTOM = "custom"


class ValidationStatus(str, enum.Enum):
    """Validation status for sections"""

    NOT_STARTED = "not_started"
    INVALID = "invalid"
    WARNING = "warning"
    VALID = "valid"


class ProposalStatus(str, enum.Enum):
    """Proposal status types"""

    DRAFT = "draft"
    IN_REVIEW = "in_review"
    READY_FOR_SUBMISSION = "ready_for_submission"
    SUBMITTED = "submitted"
    APPROVED = "approved"
    REJECTED = "rejected"


class UserRole(str, enum.Enum):
    """User role types"""

    VIEWER = "viewer"
    EDITOR = "editor"
    REVIEWER = "reviewer"
    ADMIN = "admin"
