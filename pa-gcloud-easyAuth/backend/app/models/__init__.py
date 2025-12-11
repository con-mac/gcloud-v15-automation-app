"""Database models"""

# Lazy imports for Lambda compatibility (models use SQLAlchemy which isn't needed for document generation)
# Import only when actually needed
import os
_use_s3 = os.environ.get("USE_S3", "false").lower() == "true"

if not _use_s3:
    # Only try to import models if not in Lambda
    try:
        from app.models.base import Base
        from app.models.user import User
        from app.models.proposal import Proposal
        from app.models.section import Section
        from app.models.validation_rule import ValidationRule
        from app.models.change_history import ChangeHistory
        from app.models.notification import Notification
    except ImportError:
        # Models not available
        Base = None
        User = None
        Proposal = None
        Section = None
        ValidationRule = None
        ChangeHistory = None
        Notification = None
else:
    # In Lambda, don't even try to import models (they trigger SQLAlchemy/psycopg2 imports)
    Base = None
    User = None
    Proposal = None
    Section = None
    ValidationRule = None
    ChangeHistory = None
    Notification = None

__all__ = [
    "Base",
    "User",
    "Proposal",
    "Section",
    "ValidationRule",
    "ChangeHistory",
    "Notification",
]

