"""Notification model"""

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
        Text = getattr(sqlalchemy_module, "Text", None)
        Boolean = getattr(sqlalchemy_module, "Boolean", None)
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

import enum

class NotificationType(str, enum.Enum):
    """Notification types"""

    DEADLINE_30_DAYS = "deadline_30_days"
    DEADLINE_14_DAYS = "deadline_14_days"
    DEADLINE_7_DAYS = "deadline_7_days"
    DEADLINE_3_DAYS = "deadline_3_days"
    DEADLINE_1_DAY = "deadline_1_day"
    DEADLINE_PASSED = "deadline_passed"
    VALIDATION_FAILED = "validation_failed"
    PROPOSAL_SUBMITTED = "proposal_submitted"
    PROPOSAL_APPROVED = "proposal_approved"
    PROPOSAL_REJECTED = "proposal_rejected"
    SECTION_LOCKED = "section_locked"
    SECTION_UNLOCKED = "section_unlocked"
    COMMENT_ADDED = "comment_added"
    CUSTOM = "custom"

if SQLALCHEMY_AVAILABLE and Base is not None:
    class Notification(Base):
        """Notification model for user notifications"""

        __tablename__ = "notifications"

        # References
        user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
        proposal_id = Column(UUID(as_uuid=True), ForeignKey("proposals.id"), nullable=True)

        # Notification details
        notification_type = Column(SQLEnum(NotificationType), nullable=False)
        title = Column(String(255), nullable=False)
        message = Column(Text, nullable=False)
        is_read = Column(Boolean, default=False, nullable=False)
        read_at = Column(DateTime, nullable=True)

        def __repr__(self) -> str:
            return f"<Notification {self.title} for user {self.user_id}>"
else:
    # Dummy Notification class for Lambda
    class Notification:
        pass
