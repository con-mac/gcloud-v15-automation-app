"""Sections API routes"""

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional, List

# Lazy import for Lambda compatibility
try:
    from app.services.database import db_service
except ImportError:
    db_service = None

router = APIRouter()


class UpdateSectionRequest(BaseModel):
    """Request to update section content"""
    content: str
    user_id: str = "fe3d34b2-3538-4550-89b8-0fc96eee953a"  # Test user ID


class ValidationResult(BaseModel):
    """Validation result"""
    section_id: str
    is_valid: bool
    word_count: int
    min_words: Optional[int] = None
    max_words: Optional[int] = None
    errors: List[str]
    warnings: List[str]


@router.put("/{section_id}")
async def update_section(section_id: str, request: UpdateSectionRequest):
    """Update section content"""
    try:
        section = db_service.update_section_content(
            section_id=section_id,
            content=request.content,
            user_id=request.user_id
        )
        
        # Validate after update
        validation = db_service.validate_section(section_id)
        
        return {
            "section": section,
            "validation": validation
        }
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/{section_id}/validate", response_model=ValidationResult)
async def validate_section(section_id: str):
    """Validate a section"""
    try:
        validation = db_service.validate_section(section_id)
        return validation
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/rules/{section_type}")
async def get_validation_rules(section_type: str):
    """Get validation rules for a section type"""
    try:
        rules = db_service.get_validation_rules(section_type)
        return {"section_type": section_type, "rules": rules}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

