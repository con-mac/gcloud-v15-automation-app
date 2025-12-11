"""User schemas"""

from datetime import datetime
from typing import Optional
from uuid import UUID

from pydantic import BaseModel, EmailStr, Field

# Import from constants (no database dependency)
from app.models.constants import UserRole


class UserBase(BaseModel):
    """Base user schema"""

    email: EmailStr
    full_name: str = Field(..., min_length=1, max_length=255)
    role: UserRole = UserRole.EDITOR


class UserCreate(UserBase):
    """Schema for creating a user"""

    azure_ad_id: str = Field(..., min_length=1, max_length=255)


class UserUpdate(BaseModel):
    """Schema for updating a user"""

    full_name: Optional[str] = Field(None, min_length=1, max_length=255)
    role: Optional[UserRole] = None
    is_active: Optional[bool] = None


class UserInDB(UserBase):
    """Schema for user in database"""

    id: UUID
    azure_ad_id: str
    is_active: bool
    last_login: Optional[datetime]
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class UserResponse(UserInDB):
    """Schema for user API response"""

    pass

