"""Change history model"""

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

class ChangeType(str, enum.Enum):
    """Types of changes"""

    CREATE = "create"
    UPDATE = "update"
    DELETE = "delete"
    ROLLBACK = "rollback"

if SQLALCHEMY_AVAILABLE and Base is not None:
    class ChangeHistory(Base):
        """Change history for audit trail"""

        __tablename__ = "change_history"

        # References
        section_id = Column(UUID(as_uuid=True), ForeignKey("sections.id"), nullable=False)
        user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)

        # Change details
        change_type = Column(SQLEnum(ChangeType), nullable=False)
        old_content = Column(Text, nullable=True)
        new_content = Column(Text, nullable=True)

        # Relationships
        section = relationship("Section", back_populates="change_history")

        def __repr__(self) -> str:
            return f"<ChangeHistory {self.change_type} on section {self.section_id}>"
else:
    # Dummy ChangeHistory class for Lambda
    class ChangeHistory:
        pass
