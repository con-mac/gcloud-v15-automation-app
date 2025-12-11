"""Application configuration"""

from typing import List, Union, Optional
from pydantic_settings import BaseSettings, SettingsConfigDict
from pydantic import Field, field_validator


class Settings(BaseSettings):
    """Application settings loaded from environment variables"""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
        validate_default=False,  # Don't validate defaults, allow empty strings
    )

    # Application
    APP_NAME: str = "G-Cloud Automation System"
    APP_VERSION: str = "1.0.0"
    ENVIRONMENT: str = "development"
    DEBUG: bool = True
    SECRET_KEY: str = Field(default="min-32-char-secret-key-for-development-only-use", min_length=32, validate_default=False)

    # Database (optional for Lambda - not needed for document generation)
    DATABASE_URL: str = ""
    DATABASE_POOL_SIZE: int = 20
    DATABASE_MAX_OVERFLOW: int = 10

    # Redis (optional for Lambda)
    REDIS_URL: str = "redis://localhost:6379/0"
    REDIS_CACHE_TTL: int = 3600

    # Azure Active Directory (optional for Lambda)
    AZURE_AD_TENANT_ID: str = ""
    AZURE_AD_CLIENT_ID: str = ""
    AZURE_AD_CLIENT_SECRET: str = ""
    AZURE_AD_AUTHORITY: str = "https://login.microsoftonline.com/"

    # Azure Storage (optional for Lambda - using S3 instead)
    AZURE_STORAGE_CONNECTION_STRING: str = ""
    AZURE_STORAGE_CONTAINER_NAME: str = "gcloud-documents"

    # Azure Key Vault
    AZURE_KEY_VAULT_URL: str = ""

    # Microsoft Graph API
    GRAPH_API_ENDPOINT: str = "https://graph.microsoft.com/v1.0"
    GRAPH_API_SCOPE: str = "https://graph.microsoft.com/.default"

    # SharePoint
    SHAREPOINT_SITE_ID: str = ""
    SHAREPOINT_DRIVE_ID: str = ""

    # Email
    SENDGRID_API_KEY: str = ""
    FROM_EMAIL: str = "notifications@your-organisation.com"

    # CORS - can be set via environment variable as comma-separated string
    # Default includes localhost for development and common production URL
    CORS_ORIGINS: Union[List[str], str] = Field(
        default=[
            "http://localhost:3000",
            "http://localhost:5173",
            "http://localhost:5174",
            "http://localhost:5175",
            "http://localhost:5176",
            "http://127.0.0.1:3000",
            "http://127.0.0.1:5173",
            "http://127.0.0.1:5174",
            "http://127.0.0.1:5175",
            "http://127.0.0.1:5176",
            # Production frontend URL (Azure App Service) - will be overridden by env var if set
            "https://pa-gcloud15-web.azurewebsites.net",
        ],
        validate_default=False
    )

    @field_validator("CORS_ORIGINS", mode="before")
    @classmethod
    def parse_cors_origins(cls, v):
        if isinstance(v, str):
            return [origin.strip() for origin in v.split(",") if origin.strip()]
        return v

    # JWT
    JWT_ALGORITHM: str = "RS256"
    JWT_ACCESS_TOKEN_EXPIRE_MINUTES: int = 60
    JWT_REFRESH_TOKEN_EXPIRE_DAYS: int = 7

    # Celery
    CELERY_BROKER_URL: str = "redis://localhost:6379/1"
    CELERY_RESULT_BACKEND: str = "redis://localhost:6379/2"

    # Monitoring
    APPLICATIONINSIGHTS_CONNECTION_STRING: str = ""

    # Logging
    LOG_LEVEL: str = "INFO"
    LOG_FORMAT: str = "json"

    # Validation constraints
    MIN_PASSWORD_LENGTH: int = 8
    MAX_PROPOSAL_SIZE_MB: int = 50
    MAX_DOCUMENT_SIZE_MB: int = 50
    DEFAULT_PAGE_SIZE: int = 20
    MAX_PAGE_SIZE: int = 100

    @property
    def database_url_sync(self) -> str:
        """Get synchronous database URL for Alembic"""
        if not self.DATABASE_URL:
            return ""
        return str(self.DATABASE_URL).replace("+asyncpg", "")


# Create settings instance
# Handle validation errors gracefully for Lambda environment
try:
    settings = Settings()
except Exception as e:
    # If validation fails, create settings with explicit values
    import os
    _env = os.environ.copy()
    _env.setdefault("DATABASE_URL", "")
    _env.setdefault("AZURE_AD_TENANT_ID", "")
    _env.setdefault("AZURE_AD_CLIENT_ID", "")
    _env.setdefault("AZURE_AD_CLIENT_SECRET", "")
    _env.setdefault("AZURE_STORAGE_CONNECTION_STRING", "")
    _env.setdefault("SECRET_KEY", "min-32-char-secret-key-for-development-only-use")
    
    # Temporarily set env vars
    for k, v in _env.items():
        if k not in os.environ:
            os.environ[k] = v
    
    settings = Settings()

