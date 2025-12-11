"""
Questionnaire models for G-Cloud Capabilities Questionnaire
"""

import os
from typing import Optional, Dict, Any
import json

# Check if we're in Lambda (USE_S3 environment variable)
_use_s3 = os.environ.get("USE_S3", "false").lower() == "true"

if not _use_s3:
    try:
        import importlib
        sqlalchemy_module = importlib.import_module("sqlalchemy")
        postgresql_dialect = importlib.import_module("sqlalchemy.dialects.postgresql")
        orm_module = importlib.import_module("sqlalchemy.orm")
        models_base = importlib.import_module("app.models.base")
        
        Column = getattr(sqlalchemy_module, "Column", None)
        String = getattr(sqlalchemy_module, "String", None)
        Text = getattr(sqlalchemy_module, "Text", None)
        Boolean = getattr(sqlalchemy_module, "Boolean", None)
        DateTime = getattr(sqlalchemy_module, "DateTime", None)
        ForeignKey = getattr(sqlalchemy_module, "ForeignKey", None)
        UUID = getattr(postgresql_dialect, "UUID", None)
        JSON = getattr(postgresql_dialect, "JSON", None)
        relationship = getattr(orm_module, "relationship", None)
        Base = getattr(models_base, "Base", None)
        SQLALCHEMY_AVAILABLE = True
    except (ImportError, AttributeError, ModuleNotFoundError):
        SQLALCHEMY_AVAILABLE = False
        Base = None
else:
    SQLALCHEMY_AVAILABLE = False
    Base = None

if SQLALCHEMY_AVAILABLE and Base is not None:
    class QuestionnaireResponse(Base):
        """Questionnaire response model for G-Cloud Capabilities Questionnaire"""
        
        __tablename__ = "questionnaire_responses"
        
        # Identification
        id = Column(UUID(as_uuid=True), primary_key=True, default=lambda: __import__('uuid').uuid4())
        service_name = Column(String(500), nullable=False, index=True)
        lot = Column(String(10), nullable=False)  # "2a", "2b", "3"
        gcloud_version = Column(String(10), nullable=False, default="15")
        
        # Question details
        section_name = Column(String(200), nullable=False)
        question_text = Column(Text, nullable=False)
        question_type = Column(String(50), nullable=False)  # "radio", "checkbox", "text", "textarea", "list"
        
        # Answer (stored as JSON for flexibility)
        answer = Column(JSON, nullable=True)  # Can be string, list, or dict depending on question type
        
        # State
        is_draft = Column(Boolean, default=True, nullable=False)
        is_locked = Column(Boolean, default=False, nullable=False)
        
        # Metadata
        created_at = Column(DateTime, nullable=False, default=lambda: __import__('datetime').datetime.utcnow())
        updated_at = Column(DateTime, nullable=False, default=lambda: __import__('datetime').datetime.utcnow(), onupdate=lambda: __import__('datetime').datetime.utcnow())
        
        # Composite index for efficient queries
        __table_args__ = (
            {'extend_existing': True},
        )
        
        def to_dict(self) -> Dict[str, Any]:
            """Convert to dictionary"""
            return {
                'id': str(self.id),
                'service_name': self.service_name,
                'lot': self.lot,
                'gcloud_version': self.gcloud_version,
                'section_name': self.section_name,
                'question_text': self.question_text,
                'question_type': self.question_type,
                'answer': self.answer,
                'is_draft': self.is_draft,
                'is_locked': self.is_locked,
                'created_at': self.created_at.isoformat() if self.created_at else None,
                'updated_at': self.updated_at.isoformat() if self.updated_at else None,
            }
else:
    # Fallback for environments without SQLAlchemy
    class QuestionnaireResponse:
        """Questionnaire response model (fallback)"""
        pass

