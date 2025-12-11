"""
Main FastAPI application for PA deployment with Easy Auth
Uses SharePoint Online instead of Azure Blob Storage
Easy Auth handles authentication at platform level
"""

from fastapi import FastAPI, Request, Depends
from fastapi.middleware.cors import CORSMiddleware
import os
import logging

from app.api import api_router
from app.middleware.easy_auth import get_easy_auth_user, get_user_email

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="G-Cloud 15 Automation API (PA Deployment - Easy Auth)",
    description="API for G-Cloud proposal automation using SharePoint with Easy Auth",
    version="1.0.0"
)

# CORS configuration
cors_origins_str = os.environ.get("CORS_ORIGINS", "http://localhost:3000,http://localhost:5173")
cors_origins = [origin.strip() for origin in cors_origins_str.split(",") if origin.strip()]
logger.info(f"CORS origins configured: {cors_origins}")

# Add explicit OPTIONS handler for preflight requests
@app.options("/{full_path:path}")
async def options_handler(full_path: str, request: Request):
    """Handle OPTIONS preflight requests"""
    origin = request.headers.get("Origin", "*")
    if origin not in cors_origins and cors_origins:
        origin = cors_origins[0]
    
    headers = {
        "Access-Control-Allow-Origin": origin,
        "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, PATCH, OPTIONS",
        "Access-Control-Allow-Headers": request.headers.get('Access-Control-Request-Headers', '*'),
        "Access-Control-Allow-Credentials": "true",
        "Access-Control-Max-Age": "86400"
    }
    from fastapi.responses import Response
    return Response(status_code=200, headers=headers)

app.add_middleware(
    CORSMiddleware,
    allow_origins=cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["*"],
)

# Dependency to get current user from Easy Auth
async def get_current_user(request: Request):
    """Dependency to get current user from Easy Auth headers"""
    user = get_easy_auth_user(request)
    if not user:
        from fastapi import HTTPException, status
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Not authenticated"
        )
    return user

# Include API routes
app.include_router(api_router, prefix="/api/v1")

@app.get("/")
async def root():
    """Health check endpoint"""
    return {
        "status": "ok",
        "service": "G-Cloud 15 Automation API",
        "deployment": "PA Environment - Easy Auth",
        "storage": "SharePoint Online",
        "auth": "Easy Auth (Microsoft Identity Provider)"
    }

@app.get("/health")
async def health():
    """Health check endpoint"""
    return {"status": "healthy"}

@app.get("/auth/me")
async def get_auth_info(request: Request):
    """Get current user info from Easy Auth"""
    user = get_easy_auth_user(request)
    if user:
        return {
            "authenticated": True,
            "email": user.get("email"),
            "name": user.get("name"),
            "roles": user.get("roles", [])
        }
    return {"authenticated": False}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
