"""
Azure Functions entry point for PA deployment
Uses SharePoint instead of Azure Blob Storage
"""

import azure.functions as func
import sys
import os
import logging

# Add backend to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from app.main import app

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Create Azure Functions handler
def main(req: func.HttpRequest, context: func.Context) -> func.HttpResponse:
    """Azure Functions HTTP trigger handler"""
    
    # CRITICAL: Handle OPTIONS preflight requests FIRST (before authLevel check)
    if req.method == 'OPTIONS':
        logger.info("Handling OPTIONS preflight request")
        # Get origin from request headers
        origin = req.headers.get('Origin', '')
        # Get allowed origins from environment variable
        cors_origins_str = os.environ.get("CORS_ORIGINS", "http://localhost:3000,http://localhost:5173")
        cors_origins = [o.strip() for o in cors_origins_str.split(",") if o.strip()]
        
        # Determine allowed origin
        allowed_origin = "*"
        if origin and origin in cors_origins:
            allowed_origin = origin
        elif cors_origins:
            allowed_origin = cors_origins[0]  # Fallback to first configured origin
        
        headers = {
            "Access-Control-Allow-Origin": allowed_origin,
            "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, PATCH, OPTIONS",
            "Access-Control-Allow-Headers": req.headers.get('Access-Control-Request-Headers', '*'),
            "Access-Control-Allow-Credentials": "true",
            "Access-Control-Max-Age": "86400"
        }
        logger.info(f"OPTIONS response headers: {headers}")
        return func.HttpResponse(
            status_code=200,
            headers=headers
        )
    
    # Handle all other requests through FastAPI
    response = func.WsgiMiddleware(app.wsgi_app).handle(req, context)
    
    # Add CORS headers to all responses
    origin = req.headers.get('Origin', '')
    cors_origins_str = os.environ.get("CORS_ORIGINS", "http://localhost:3000,http://localhost:5173")
    cors_origins = [o.strip() for o in cors_origins_str.split(",") if o.strip()]
    allowed_origin = "*"
    if origin and origin in cors_origins:
        allowed_origin = origin
    elif cors_origins:
        allowed_origin = cors_origins[0]
    
    response.headers["Access-Control-Allow-Origin"] = allowed_origin
    response.headers["Access-Control-Allow-Credentials"] = "true"
    response.headers["Access-Control-Expose-Headers"] = "*"
    
    return response

