"""Validation rule model"""

# Lazy import for Lambda compatibility
import os
_use_s3 = os.environ.get("USE_S3", "false").lower() == "true"

SQLALCHEMY_AVAILABLE = False
Base = None
Column = None
String = None
Text = None
Boolean = None
SQLEnum = None
JSON = None

if not _use_s3:
    # Only try to import SQLAlchemy if not in Lambda
    # Use importlib to avoid parsing-time import issues
    try:
        import importlib
        sqlalchemy_module = importlib.import_module("sqlalchemy")
        models_base = importlib.import_module("app.models.base")
        
        Column = getattr(sqlalchemy_module, "Column", None)
        String = getattr(sqlalchemy_module, "String", None)
        Text = getattr(sqlalchemy_module, "Text", None)
        Boolean = getattr(sqlalchemy_module, "Boolean", None)
        SQLEnum = getattr(sqlalchemy_module, "Enum", None)
        JSON = getattr(sqlalchemy_module, "JSON", None)
        Base = getattr(models_base, "Base", None)
        SQLALCHEMY_AVAILABLE = True
    except (ImportError, AttributeError, ModuleNotFoundError):
        pass  # Already set to defaults above

# Import from constants (no database dependency)
from app.models.constants import SectionType

if SQLALCHEMY_AVAILABLE and Base is not None:
    class ValidationRule(Base):
        """Validation rule for proposal sections"""

        __tablename__ = "validation_rules"

        # Rule identification
        section_type = Column(SQLEnum(SectionType), nullable=False, index=True)
        rule_type = Column(String(100), nullable=False)  # e.g., "word_count_min", "word_count_max"
        name = Column(String(500), nullable=False)
        is_active = Column(Boolean, default=True, nullable=False)

        # Rule parameters
        parameters = Column(JSON, nullable=True)  # JSON dict with rule-specific parameters
        error_message = Column(Text, nullable=True)
        severity = Column(String(20), default="error", nullable=False)  # "error" or "warning"

        def __repr__(self) -> str:
            return f"<ValidationRule {self.name} ({self.rule_type})>"
else:
    # Dummy ValidationRule class for Lambda
    class ValidationRule:
        pass
