"""User model"""

import os
_use_s3 = os.environ.get("USE_S3", "false").lower() == "true"

if not _use_s3:
    try:
        import importlib
        sqlalchemy_module = importlib.import_module("sqlalchemy")
        orm_module = importlib.import_module("sqlalchemy.orm")
        models_base = importlib.import_module("app.models.base")
        
        Boolean = getattr(sqlalchemy_module, "Boolean", None)
        Column = getattr(sqlalchemy_module, "Column", None)
        String = getattr(sqlalchemy_module, "String", None)
        DateTime = getattr(sqlalchemy_module, "DateTime", None)
        SQLEnum = getattr(sqlalchemy_module, "Enum", None)
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
from app.models.constants import UserRole

if SQLALCHEMY_AVAILABLE and Base is not None:
    class User(Base):
        """User model"""

        __tablename__ = "users"

        # Azure AD integration
        azure_ad_id = Column(String(255), unique=True, nullable=True, index=True)
        email = Column(String(255), unique=True, nullable=False, index=True)
        full_name = Column(String(255), nullable=False)

        # Role and permissions
        role = Column(SQLEnum(UserRole), default=UserRole.VIEWER, nullable=False)
        is_active = Column(Boolean, default=True, nullable=False)

        # Relationships
        created_proposals = relationship("Proposal", back_populates="created_by_user", foreign_keys="Proposal.created_by")

        def __repr__(self) -> str:
            return f"<User {self.email} ({self.role})>"
else:
    # Dummy User class for Lambda
    class User:
        pass
