"""Section schemas"""

from datetime import datetime
from typing import Optional, List
from uuid import UUID

from pydantic import BaseModel, Field

# Import from constants module (no database dependency)
from app.models.constants import SectionType, ValidationStatus


class SectionBase(BaseModel):
    """Base section schema"""

    section_type: SectionType
    title: str = Field(..., min_length=1, max_length=500)
    order: int = Field(..., ge=0)
    content: Optional[str] = None
    is_mandatory: bool = False


class SectionCreate(SectionBase):
    """Schema for creating a section"""

    proposal_id: UUID


class SectionUpdate(BaseModel):
    """Schema for updating a section"""

    title: Optional[str] = Field(None, min_length=1, max_length=500)
    content: Optional[str] = None
    order: Optional[int] = Field(None, ge=0)


class SectionInDB(SectionBase):
    """Schema for section in database"""

    id: UUID
    proposal_id: UUID
    word_count: int
    validation_status: ValidationStatus
    validation_errors: Optional[str]
    last_modified_by: Optional[UUID]
    locked_by: Optional[UUID]
    locked_at: Optional[datetime]
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class SectionResponse(SectionInDB):
    """Schema for section API response"""

    is_locked: bool = False
    locked_by_name: Optional[str] = None


class SectionValidationResult(BaseModel):
    """Schema for section validation result"""

    section_id: UUID
    section_title: str
    is_valid: bool
    errors: List[str] = []
    warnings: List[str] = []
    word_count: int
    word_count_min: Optional[int] = None
    word_count_max: Optional[int] = None

