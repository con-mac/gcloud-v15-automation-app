"""Base database model"""

import uuid
from datetime import datetime
from typing import Any

# Lazy import for Lambda compatibility (SQLAlchemy not needed for document generation)
# Check if we're in Lambda (USE_S3 environment variable)
import os
_use_s3 = os.environ.get("USE_S3", "false").lower() == "true"

# Always set defaults first
SQLALCHEMY_AVAILABLE = False
Column = None
DateTime = None
UUID = None
as_declarative = lambda: lambda x: x  # Dummy decorator
declared_attr = lambda x: x  # Dummy decorator

if not _use_s3:
    # Only try to import SQLAlchemy if not in Lambda
    # Use importlib to avoid parsing-time import issues
    try:
        import importlib
        sqlalchemy_module = importlib.import_module("sqlalchemy")
        postgresql_dialect = importlib.import_module("sqlalchemy.dialects.postgresql")
        declarative_module = importlib.import_module("sqlalchemy.ext.declarative")
        
        Column = getattr(sqlalchemy_module, "Column", None)
        DateTime = getattr(sqlalchemy_module, "DateTime", None)
        UUID = getattr(postgresql_dialect, "UUID", None)
        as_declarative = getattr(declarative_module, "as_declarative", None)
        declared_attr = getattr(declarative_module, "declared_attr", None)
        SQLALCHEMY_AVAILABLE = True
    except (ImportError, AttributeError, ModuleNotFoundError):
        pass  # Already set to defaults above


if SQLALCHEMY_AVAILABLE:
    @as_declarative()
    class Base:
        """Base class for all database models"""

        id: Any
        __name__: str
        __allow_unmapped__ = True  # Allow legacy annotations

        # Generate __tablename__ automatically
        @declared_attr
        def __tablename__(cls) -> str:
            return cls.__name__.lower()

        # Common columns for all models
        id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4, index=True)
        created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
        updated_at = Column(
            DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
        )
else:
    # Fallback for Lambda (models not used)
    class Base:
        """Base class for all database models (dummy for Lambda)"""
        pass

