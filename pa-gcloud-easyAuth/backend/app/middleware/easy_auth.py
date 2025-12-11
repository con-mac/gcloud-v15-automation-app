"""
Easy Auth Middleware for Azure App Service
Reads user information from X-MS-CLIENT-PRINCIPAL header set by Easy Auth
"""

import base64
import json
import logging
from typing import Optional, Dict, Any
from fastapi import Request, HTTPException, status

logger = logging.getLogger(__name__)


def get_easy_auth_user(request: Request) -> Optional[Dict[str, Any]]:
    """
    Extract user information from Easy Auth headers
    
    Easy Auth sets X-MS-CLIENT-PRINCIPAL header with base64-encoded JSON
    containing user information from Microsoft Identity Provider
    """
    principal_header = request.headers.get("X-MS-CLIENT-PRINCIPAL")
    
    if not principal_header:
        return None
    
    try:
        # Decode base64 header
        decoded = base64.b64decode(principal_header).decode('utf-8')
        principal = json.loads(decoded)
        
        # Extract user information
        user_info = {
            "auth_typ": principal.get("auth_typ", ""),
            "name_typ": principal.get("name_typ", ""),
            "role_typ": principal.get("role_typ", ""),
            "claims": principal.get("claims", [])
        }
        
        # Extract email and name from claims
        email = None
        name = None
        roles = []
        
        for claim in user_info["claims"]:
            claim_type = claim.get("typ", "")
            claim_value = claim.get("val", "")
            
            if claim_type == "preferred_username" or claim_type == "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress":
                email = claim_value
            elif claim_type == "name" or claim_type == "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name":
                name = claim_value
            elif claim_type == "roles" or "role" in claim_type.lower():
                roles.append(claim_value)
        
        user_info["email"] = email
        user_info["name"] = name or email
        user_info["roles"] = roles
        
        logger.info(f"Easy Auth user: {email} ({name})")
        return user_info
        
    except Exception as e:
        logger.error(f"Error parsing Easy Auth header: {e}")
        return None


def require_auth(request: Request) -> Dict[str, Any]:
    """
    Require authentication - raise 401 if user not authenticated
    """
    user = get_easy_auth_user(request)
    
    if not user or not user.get("email"):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication required"
        )
    
    return user


def get_user_email(request: Request) -> Optional[str]:
    """Get user email from Easy Auth header"""
    user = get_easy_auth_user(request)
    return user.get("email") if user else None


def is_admin(request: Request, admin_group_id: Optional[str] = None) -> bool:
    """
    Check if user is admin
    Can check by role or by group membership (if admin_group_id provided)
    """
    user = get_easy_auth_user(request)
    
    if not user:
        return False
    
    # Check roles
    roles = user.get("roles", [])
    if any("admin" in role.lower() for role in roles):
        return True
    
    # Check group membership if admin_group_id provided
    if admin_group_id:
        # Easy Auth includes group claims in the principal
        claims = user.get("claims", [])
        for claim in claims:
            if claim.get("typ") == "groups" and claim.get("val") == admin_group_id:
                return True
    
    return False

