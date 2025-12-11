"""Middleware package for Easy Auth"""

from .easy_auth import get_easy_auth_user, require_auth, get_user_email, is_admin

__all__ = ["get_easy_auth_user", "require_auth", "get_user_email", "is_admin"]

