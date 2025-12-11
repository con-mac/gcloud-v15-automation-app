"""API routes"""

import os
import logging
from fastapi import APIRouter

logger = logging.getLogger(__name__)

# Lazy imports for Lambda compatibility (templates doesn't need database)
# Only import templates router - proposals/sections need database and will fail
# Check if we're in Lambda environment (USE_S3 is set)
_use_s3 = os.environ.get("USE_S3", "false").lower() == "true"

# Always import templates (needed for document generation)
from app.api.routes import templates

# Import SharePoint routes (mock service, no database needed)
try:
    from app.api.routes import sharepoint
except (ImportError, AttributeError, ModuleNotFoundError):
    sharepoint = None

# Import proposals router (uses SharePoint service, not database)
# Proposals router works with both local and S3 storage
try:
    from app.api.routes import proposals
    logger.info("Proposals router imported successfully")
except (ImportError, AttributeError, ModuleNotFoundError) as e:
    logger.warning(f"Failed to import proposals router: {e}")
    proposals = None
except Exception as e:
    logger.error(f"Unexpected error importing proposals router: {e}", exc_info=True)
    proposals = None

# Import questionnaire router (uses file storage, not database)
try:
    from app.api.routes import questionnaire
except (ImportError, AttributeError, ModuleNotFoundError):
    questionnaire = None

# Import analytics router (uses file storage, not database)
try:
    from app.api.routes import analytics
except (ImportError, AttributeError, ModuleNotFoundError):
    analytics = None

# Only import database-dependent routes if not in Lambda
if not _use_s3:
    try:
        from app.api.routes import sections
    except (ImportError, AttributeError, ModuleNotFoundError):
        sections = None
else:
    # In Lambda, don't import database-dependent routes
    sections = None

api_router = APIRouter()

# Include route modules (only templates is needed for document generation)
routes_included = []
if templates:
    api_router.include_router(templates.router, prefix="/templates", tags=["Templates"])
    routes_included.append("templates")
    logger.info("Templates router included")
if sharepoint:
    api_router.include_router(sharepoint.router, prefix="/sharepoint", tags=["SharePoint"])
    routes_included.append("sharepoint")
    logger.info("SharePoint router included")
if proposals:
    api_router.include_router(proposals.router, prefix="/proposals", tags=["Proposals"])
    routes_included.append("proposals")
    logger.info("Proposals router included")
else:
    logger.warning("Proposals router NOT included (import failed or None)")
if questionnaire:
    api_router.include_router(questionnaire.router, prefix="/questionnaire", tags=["Questionnaire"])
    routes_included.append("questionnaire")
    logger.info("Questionnaire router included")
if analytics:
    api_router.include_router(analytics.router, prefix="/analytics", tags=["Analytics"])
    routes_included.append("analytics")
    logger.info("Analytics router included")
if sections:
    api_router.include_router(sections.router, prefix="/sections", tags=["Sections"])
    routes_included.append("sections")
    logger.info("Sections router included")

logger.info(f"API router initialized with {len(api_router.routes)} total routes")
logger.info(f"Routes included: {', '.join(routes_included) if routes_included else 'none'}")


@api_router.get("/")
async def api_root():
    """API root endpoint"""
    return {
        "message": "G-Cloud Proposal Automation API",
        "version": "1.0.0",
        "endpoints": {
            "docs": "/docs",
            "health": "/health",
            "proposals": "/api/v1/proposals",
            "sections": "/api/v1/sections",
        },
    }

