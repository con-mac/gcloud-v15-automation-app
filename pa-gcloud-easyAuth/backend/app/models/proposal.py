"""Proposal model"""

import os
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
        Float = getattr(sqlalchemy_module, "Float", None)
        DateTime = getattr(sqlalchemy_module, "DateTime", None)
        SQLEnum = getattr(sqlalchemy_module, "Enum", None)
        ForeignKey = getattr(sqlalchemy_module, "ForeignKey", None)
        UUID = getattr(postgresql_dialect, "UUID", None)
        relationship = getattr(orm_module, "relationship", None)
        Base = getattr(models_base, "Base", None)
        SQLALCHEMY_AVAILABLE = True
    except (ImportError, AttributeError, ModuleNotFoundError):
        SQLALCHEMY_AVAILABLE = False
        Base = None
else:
    SQLALCHEMY_AVAILABLE = False
    Base = None

# Import from constants (no database dependency)
from app.models.constants import ProposalStatus

if SQLALCHEMY_AVAILABLE and Base is not None:
    class Proposal(Base):
        """Proposal model for G-Cloud proposals"""

        __tablename__ = "proposals"

        # Basic information
        title = Column(String(500), nullable=False)
        framework_version = Column(String(50), nullable=False)  # e.g., "G-Cloud 14"
        status = Column(SQLEnum(ProposalStatus), default=ProposalStatus.DRAFT, nullable=False)
        deadline = Column(DateTime, nullable=True)

        # Progress tracking
        completion_percentage = Column(Float, default=0.0, nullable=False)

        # Ownership
        created_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)

        # Relationships
        created_by_user = relationship("User", back_populates="created_proposals", foreign_keys=[created_by])
        sections = relationship("Section", back_populates="proposal", cascade="all, delete-orphan", order_by="Section.order")

        def __repr__(self) -> str:
            return f"<Proposal {self.title} ({self.framework_version})>"
else:
    # Dummy Proposal class for Lambda
    class Proposal:
        pass
