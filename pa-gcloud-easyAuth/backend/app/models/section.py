"""Section model"""

# Lazy import for Lambda compatibility
import os
_use_s3 = os.environ.get("USE_S3", "false").lower() == "true"

SQLALCHEMY_AVAILABLE = False
Base = None
Column = None
String = None
Text = None
Integer = None
Boolean = None
SQLEnum = None
ForeignKey = None
DateTime = None
UUID = None
relationship = None

if not _use_s3:
    # Only try to import SQLAlchemy if not in Lambda
    # Use importlib to avoid parsing-time import issues
    try:
        import importlib
        sqlalchemy_module = importlib.import_module("sqlalchemy")
        postgresql_dialect = importlib.import_module("sqlalchemy.dialects.postgresql")
        orm_module = importlib.import_module("sqlalchemy.orm")
        models_base = importlib.import_module("app.models.base")
        
        Column = getattr(sqlalchemy_module, "Column", None)
        String = getattr(sqlalchemy_module, "String", None)
        Text = getattr(sqlalchemy_module, "Text", None)
        Integer = getattr(sqlalchemy_module, "Integer", None)
        Boolean = getattr(sqlalchemy_module, "Boolean", None)
        SQLEnum = getattr(sqlalchemy_module, "Enum", None)
        ForeignKey = getattr(sqlalchemy_module, "ForeignKey", None)
        DateTime = getattr(sqlalchemy_module, "DateTime", None)
        UUID = getattr(postgresql_dialect, "UUID", None)
        relationship = getattr(orm_module, "relationship", None)
        Base = getattr(models_base, "Base", None)
        SQLALCHEMY_AVAILABLE = True
    except (ImportError, AttributeError, ModuleNotFoundError):
        pass  # Already set to defaults above

# Import from constants (no database dependency)
from app.models.constants import SectionType, ValidationStatus as ValidationStatusEnum

# Re-export for backwards compatibility (if SQLAlchemy available)
ValidationStatus = ValidationStatusEnum

if SQLALCHEMY_AVAILABLE and Base is not None:
    class Section(Base):
        """Section model for proposal sections"""

        __tablename__ = "sections"

        # Section identification
        proposal_id = Column(UUID(as_uuid=True), ForeignKey("proposals.id"), nullable=False)
        section_type = Column(SQLEnum(SectionType), nullable=False)
        title = Column(String(500), nullable=False)
        order = Column(Integer, nullable=False)  # Display order within proposal

        # Content
        content = Column(Text, nullable=True)
        word_count = Column(Integer, default=0, nullable=False)

        # Validation
        validation_status = Column(
            SQLEnum(ValidationStatusEnum), default=ValidationStatusEnum.NOT_STARTED, nullable=False
        )
        is_mandatory = Column(Boolean, default=False, nullable=False)
        validation_errors = Column(Text, nullable=True)  # JSON string of errors

        # Metadata
        last_modified_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
        locked_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
        locked_at = Column(DateTime, nullable=True)

        # Relationships
        proposal = relationship("Proposal", back_populates="sections")
        change_history = relationship("ChangeHistory", back_populates="section", cascade="all, delete-orphan")
        validation_rules = relationship(
            "ValidationRule",
            primaryjoin="Section.section_type == ValidationRule.section_type",
            foreign_keys="ValidationRule.section_type",
            viewonly=True,
        )

        def __repr__(self) -> str:
            return f"<Section {self.title} ({self.section_type})>"
else:
    # Dummy Section class for Lambda (models not used)
    class Section:
        pass
