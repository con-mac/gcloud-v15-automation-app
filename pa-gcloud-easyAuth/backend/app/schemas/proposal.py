"""Proposal schemas"""

from datetime import datetime
from typing import Optional, List
from uuid import UUID

from pydantic import BaseModel, Field

# Import from constants (no database dependency)
from app.models.constants import ProposalStatus


class ProposalBase(BaseModel):
    """Base proposal schema"""

    title: str = Field(..., min_length=1, max_length=500)
    framework_version: str = Field(..., min_length=1, max_length=50)
    deadline: Optional[datetime] = None


class ProposalCreate(ProposalBase):
    """Schema for creating a proposal"""

    pass


class ProposalUpdate(BaseModel):
    """Schema for updating a proposal"""

    title: Optional[str] = Field(None, min_length=1, max_length=500)
    framework_version: Optional[str] = Field(None, min_length=1, max_length=50)
    status: Optional[ProposalStatus] = None
    deadline: Optional[datetime] = None


class ProposalInDB(ProposalBase):
    """Schema for proposal in database"""

    id: UUID
    status: ProposalStatus
    completion_percentage: float
    created_by: UUID
    last_modified_by: Optional[UUID]
    original_document_url: Optional[str]
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class ProposalResponse(ProposalInDB):
    """Schema for proposal API response"""

    section_count: Optional[int] = 0
    completed_sections: Optional[int] = 0


class ProposalListResponse(BaseModel):
    """Schema for proposal list response"""

    proposals: List[ProposalResponse]
    total: int
    page: int
    page_size: int

