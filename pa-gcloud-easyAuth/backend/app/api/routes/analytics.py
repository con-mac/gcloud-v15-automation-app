"""
Analytics API routes for questionnaire responses
Provides aggregated analytics and drill-down functionality for admin dashboard
"""

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel
from typing import List, Dict, Any, Optional
import logging
import json
import os
from pathlib import Path
from collections import defaultdict, Counter
from datetime import datetime

from app.services.questionnaire_parser import QuestionnaireParser

logger = logging.getLogger(__name__)

router = APIRouter()

# Seed data functions (inline to avoid import issues)
SAMPLE_SERVICES = [
    {
        "service_name": "Cloud Infrastructure Services",
        "lot": "3",
        "gcloud_version": "15",
        "completion_status": "completed",
        "is_locked": True,
    },
    {
        "service_name": "Data Analytics Platform",
        "lot": "2a",
        "gcloud_version": "15",
        "completion_status": "completed",
        "is_locked": True,
    },
    {
        "service_name": "Customer Relationship Management",
        "lot": "2b",
        "gcloud_version": "15",
        "completion_status": "draft",
        "is_locked": False,
    },
    {
        "service_name": "Security Monitoring Service",
        "lot": "3",
        "gcloud_version": "15",
        "completion_status": "completed",
        "is_locked": False,
    },
    {
        "service_name": "Business Intelligence Tool",
        "lot": "2a",
        "gcloud_version": "15",
        "completion_status": "draft",
        "is_locked": False,
    },
]

def _generate_sample_answers(parser: QuestionnaireParser, lot: str, service_name: str) -> List[Dict[str, Any]]:
    """Generate sample answers for a questionnaire"""
    sections = parser.parse_questions_for_lot(lot)
    answers = []
    
    for section_name, questions in sections.items():
        for question in questions:
            question_text = question.get('question_text', '')
            question_type = question.get('question_type', 'text')
            answer_options = question.get('answer_options', [])
            
            answer_value = None
            
            if question_type == 'text' or question_type == 'Text field':
                if 'service name' in question_text.lower() or 'service called' in question_text.lower():
                    answer_value = service_name
                elif 'service type' in question_text.lower():
                    answer_value = "Cloud Support Service"
                else:
                    answer_value = f"Sample answer for {question_text[:30]}"
            elif question_type == 'textarea' or question_type == 'Textarea':
                answer_value = f"This is a sample detailed response for the question: {question_text[:50]}. It provides comprehensive information about the service capabilities and features."
            elif question_type == 'radio' or question_type == 'Radio buttons':
                if answer_options:
                    answer_value = answer_options[0]
                else:
                    answer_value = "Yes"
            elif question_type == 'checkbox' or question_type == 'Grouped checkboxes':
                if answer_options:
                    answer_value = answer_options[:min(3, len(answer_options))]
                else:
                    answer_value = ["Option 1", "Option 2"]
            elif question_type == 'list' or question_type == 'List of text fields':
                if 'systems requirements' in question_text.lower():
                    answer_value = [
                        "Windows 10 or later",
                        "Minimum 4GB RAM",
                        "Internet connection required",
                        "Modern web browser",
                        "Active directory integration"
                    ]
                else:
                    answer_value = [
                        "Sample requirement item one",
                        "Sample requirement item two",
                        "Sample requirement item three"
                    ]
            
            if answer_value is not None:
                answers.append({
                    "question_text": question_text,
                    "question_type": question_type,
                    "answer": answer_value,
                    "section_name": section_name
                })
    
    return answers

# Initialize parser
_parser = None

def get_parser():
    """Get or create questionnaire parser instance"""
    global _parser
    if _parser is None:
        try:
            _parser = QuestionnaireParser()
        except Exception as e:
            logger.warning(f"Failed to initialize questionnaire parser: {e}")
            _parser = None
    return _parser


class QuestionAnalytics(BaseModel):
    """Analytics for a single question"""
    question_text: str
    question_type: str
    section_name: str
    answer_counts: Dict[str, int]  # answer_value -> count
    total_responses: int
    services_by_answer: Dict[str, List[str]]  # answer_value -> list of service names


class SectionAnalytics(BaseModel):
    """Analytics for a section"""
    section_name: str
    questions: List[QuestionAnalytics]
    total_questions: int
    completed_services: int


class ServiceStatus(BaseModel):
    """Status of a service's questionnaire"""
    service_name: str
    lot: str
    gcloud_version: str
    has_responses: bool
    is_draft: bool
    is_locked: bool
    completion_percentage: float
    last_updated: Optional[str] = None


class AnalyticsSummary(BaseModel):
    """Summary of all analytics"""
    total_services: int
    services_with_responses: int
    services_without_responses: int
    services_locked: int
    services_draft: int
    lot_breakdown: Dict[str, int]  # lot -> count
    sections: List[SectionAnalytics]


@router.get("/summary", response_model=AnalyticsSummary)
async def get_analytics_summary(
    lot: Optional[str] = Query(None, description="Filter by LOT (2a, 2b, 3)"),
    gcloud_version: str = Query("15", description="G-Cloud version")
):
    """
    Get overall analytics summary for questionnaire responses
    
    Returns:
        Summary with counts and breakdowns
    """
    try:
        # Get all services and their questionnaire status
        services_status = await get_all_services_status(lot, gcloud_version)
        
        # Get all questionnaire responses
        all_responses = await get_all_questionnaire_responses(lot, gcloud_version)
        
        # Aggregate by section and question
        sections_analytics = await aggregate_responses_by_section(all_responses, lot, gcloud_version)
        
        # Calculate summary stats
        total_services = len(services_status)
        services_with_responses = len([s for s in services_status if s.has_responses])
        services_without_responses = total_services - services_with_responses
        services_locked = len([s for s in services_status if s.is_locked])
        services_draft = len([s for s in services_status if s.is_draft and not s.is_locked])
        
        # LOT breakdown
        lot_breakdown = defaultdict(int)
        for service in services_status:
            lot_breakdown[service.lot] += 1
        
        return AnalyticsSummary(
            total_services=total_services,
            services_with_responses=services_with_responses,
            services_without_responses=services_without_responses,
            services_locked=services_locked,
            services_draft=services_draft,
            lot_breakdown=dict(lot_breakdown),
            sections=sections_analytics
        )
    except Exception as e:
        logger.error(f"Error getting analytics summary: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Error getting analytics: {str(e)}")


@router.get("/services", response_model=List[ServiceStatus])
async def get_services_status(
    lot: Optional[str] = Query(None, description="Filter by LOT (2a, 2b, 3)"),
    gcloud_version: str = Query("15", description="G-Cloud version")
):
    """
    Get status of all services regarding questionnaire completion
    
    Returns:
        List of service statuses
    """
    try:
        services = await get_all_services_status(lot, gcloud_version)
        return services
    except Exception as e:
        logger.error(f"Error getting services status: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Error getting services status: {str(e)}")


@router.get("/drill-down/{section_name}/{question_text:path}")
async def get_drill_down(
    section_name: str,
    question_text: str,
    lot: Optional[str] = Query(None, description="Filter by LOT (2a, 2b, 3)"),
    gcloud_version: str = Query("15", description="G-Cloud version")
):
    """
    Get drill-down data for a specific question showing which services answered what
    
    Args:
        section_name: Section name
        question_text: Question text (URL encoded)
        lot: Optional LOT filter
        gcloud_version: G-Cloud version
        
    Returns:
        Detailed breakdown by answer value with service names
    """
    try:
        # Get all responses
        all_responses = await get_all_questionnaire_responses(lot, gcloud_version)
        
        # Find the specific question
        question_responses = {}
        for response in all_responses:
            service_name = response['service_name']
            lot_val = response['lot']
            answers = response.get('answers', [])
            
            for answer in answers:
                if (answer.get('section_name') == section_name and 
                    answer.get('question_text') == question_text):
                    answer_value = answer.get('answer')
                    # Convert answer to string key for grouping
                    if isinstance(answer_value, list):
                        answer_key = ', '.join(str(v) for v in answer_value)
                    else:
                        answer_key = str(answer_value) if answer_value else 'No answer'
                    
                    if answer_key not in question_responses:
                        question_responses[answer_key] = []
                    question_responses[answer_key].append({
                        'service_name': service_name,
                        'lot': lot_val
                    })
        
        return {
            'section_name': section_name,
            'question_text': question_text,
            'breakdown': question_responses,
            'total_services': sum(len(services) for services in question_responses.values())
        }
    except Exception as e:
        logger.error(f"Error getting drill-down: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Error getting drill-down: {str(e)}")


@router.post("/seed-questionnaire-data")
async def seed_questionnaire_data():
    """
    Seed sample questionnaire data for testing admin analytics (admin only)
    
    Creates 5 sample questionnaire responses with various completion statuses.
    
    Returns:
        Summary of seeded data
    """
    try:
        # Initialize parser
        parser = QuestionnaireParser()
        
        # Check if we're in Azure
        use_azure = bool(os.environ.get("AZURE_STORAGE_CONNECTION_STRING", ""))
        
        results = []
        
        # Generate and save responses for each service
        for service in SAMPLE_SERVICES:
            try:
                # Generate answers
                answers = _generate_sample_answers(
                    parser,
                    service['lot'],
                    service['service_name']
                )
                
                # Save response using the same logic as questionnaire.py
                response_data = {
                    "service_name": service['service_name'],
                    "lot": service['lot'],
                    "gcloud_version": service['gcloud_version'],
                    "answers": answers,
                    "is_draft": (service['completion_status'] == 'draft'),
                    "is_locked": service['is_locked'],
                    "updated_at": datetime.utcnow().isoformat()
                }
                
                if use_azure:
                    from app.services.azure_blob_service import AzureBlobService
                    azure_blob_service = AzureBlobService()
                    
                    blob_key = f"GCloud {service['gcloud_version']}/PA Services/Cloud Support Services LOT {service['lot']}/{service['service_name']}/questionnaire_responses.json"
                    
                    json_data = json.dumps(response_data, indent=2)
                    import tempfile
                    with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
                        f.write(json_data)
                        temp_path = Path(f.name)
                    
                    try:
                        azure_blob_service.upload_file(temp_path, blob_key)
                    finally:
                        if temp_path.exists():
                            temp_path.unlink()
                else:
                    # Local filesystem
                    from sharepoint_service.mock_sharepoint import MOCK_BASE_PATH
                    
                    response_path = MOCK_BASE_PATH / f"GCloud {service['gcloud_version']}" / "PA Services" / f"Cloud Support Services LOT {service['lot']}" / service['service_name'] / "questionnaire_responses.json"
                    
                    response_path.parent.mkdir(parents=True, exist_ok=True)
                    
                    with open(response_path, 'w', encoding='utf-8') as f:
                        json.dump(response_data, f, indent=2)
                
                results.append({
                    "service_name": service['service_name'],
                    "lot": service['lot'],
                    "status": "success",
                    "answers_count": len(answers),
                    "is_locked": service['is_locked']
                })
            except Exception as e:
                logger.error(f"Failed to seed {service['service_name']}: {e}", exc_info=True)
                results.append({
                    "service_name": service['service_name'],
                    "lot": service['lot'],
                    "status": "error",
                    "error": str(e)
                })
        
        success_count = len([r for r in results if r['status'] == 'success'])
        
        return {
            "success": True,
            "message": f"Seeded {success_count} questionnaire responses",
            "results": results,
            "total": len(SAMPLE_SERVICES),
            "succeeded": success_count,
            "failed": len(results) - success_count
        }
    except Exception as e:
        logger.error(f"Error seeding questionnaire data: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Error seeding data: {str(e)}")


async def get_all_services_status(
    lot: Optional[str],
    gcloud_version: str
) -> List[ServiceStatus]:
    """
    Get status of all services (with and without questionnaire responses)
    
    Returns:
        List of ServiceStatus objects
    """
    services_status = []
    
    # Check if we're in Azure
    use_azure = bool(os.environ.get("AZURE_STORAGE_CONNECTION_STRING", ""))
    
    if use_azure:
        from app.services.azure_blob_service import AzureBlobService
        azure_blob_service = AzureBlobService()
        
        # Get all service folders
        lots_to_check = [lot] if lot else ["2a", "2b", "3"]
        
        for lot_val in lots_to_check:
            base_prefix = f"GCloud {gcloud_version}/PA Services/Cloud Support Services LOT {lot_val}/"
            blob_list = azure_blob_service.list_blobs(prefix=base_prefix)
            
            # Extract unique service folder names
            service_folders = set()
            for blob_name in blob_list:
                parts = blob_name.split('/')
                if len(parts) >= 4:
                    service_folders.add(parts[3])
            
            # Check each service for questionnaire responses
            for service_name in service_folders:
                response_blob = f"{base_prefix}{service_name}/questionnaire_responses.json"
                
                has_responses = azure_blob_service.blob_exists(response_blob)
                is_draft = True
                is_locked = False
                last_updated = None
                
                if has_responses:
                    try:
                        json_bytes = azure_blob_service.get_file_bytes(response_blob)
                        response_data = json.loads(json_bytes.decode('utf-8'))
                        is_draft = response_data.get('is_draft', True)
                        is_locked = response_data.get('is_locked', False)
                        last_updated = response_data.get('updated_at')
                        
                        # Calculate completion percentage
                        answers = response_data.get('answers', [])
                        parser = get_parser()
                        if parser:
                            questions = parser.parse_questions_for_lot(lot_val)
                            total_questions = sum(len(q_list) for q_list in questions.values())
                            completion_percentage = (len(answers) / total_questions * 100) if total_questions > 0 else 0
                        else:
                            completion_percentage = 100 if not is_draft else 50
                    except Exception as e:
                        logger.warning(f"Failed to parse questionnaire for {service_name}: {e}")
                        completion_percentage = 0
                else:
                    completion_percentage = 0
                
                services_status.append(ServiceStatus(
                    service_name=service_name,
                    lot=lot_val,
                    gcloud_version=gcloud_version,
                    has_responses=has_responses,
                    is_draft=is_draft,
                    is_locked=is_locked,
                    completion_percentage=completion_percentage,
                    last_updated=last_updated
                ))
    else:
        # Local filesystem
        from sharepoint_service.mock_sharepoint import MOCK_BASE_PATH
        
        lots_to_check = [lot] if lot else ["2a", "2b", "3"]
        
        for lot_val in lots_to_check:
            base_path = MOCK_BASE_PATH / f"GCloud {gcloud_version}" / "PA Services" / f"Cloud Support Services LOT {lot_val}"
            
            if not base_path.exists():
                continue
            
            # Get all service folders
            for service_folder in base_path.iterdir():
                if not service_folder.is_dir():
                    continue
                
                service_name = service_folder.name
                response_path = service_folder / "questionnaire_responses.json"
                
                has_responses = response_path.exists()
                is_draft = True
                is_locked = False
                last_updated = None
                
                if has_responses:
                    try:
                        with open(response_path, 'r', encoding='utf-8') as f:
                            response_data = json.load(f)
                        is_draft = response_data.get('is_draft', True)
                        is_locked = response_data.get('is_locked', False)
                        last_updated = response_data.get('updated_at')
                        
                        # Calculate completion percentage
                        answers = response_data.get('answers', [])
                        parser = get_parser()
                        if parser:
                            questions = parser.parse_questions_for_lot(lot_val)
                            total_questions = sum(len(q_list) for q_list in questions.values())
                            completion_percentage = (len(answers) / total_questions * 100) if total_questions > 0 else 0
                        else:
                            completion_percentage = 100 if not is_draft else 50
                    except Exception as e:
                        logger.warning(f"Failed to parse questionnaire for {service_name}: {e}")
                        completion_percentage = 0
                else:
                    completion_percentage = 0
                
                services_status.append(ServiceStatus(
                    service_name=service_name,
                    lot=lot_val,
                    gcloud_version=gcloud_version,
                    has_responses=has_responses,
                    is_draft=is_draft,
                    is_locked=is_locked,
                    completion_percentage=completion_percentage,
                    last_updated=last_updated
                ))
    
    return services_status


async def get_all_questionnaire_responses(
    lot: Optional[str],
    gcloud_version: str
) -> List[Dict[str, Any]]:
    """
    Load all questionnaire responses from storage
    
    Returns:
        List of response dictionaries
    """
    all_responses = []
    
    # Check if we're in Azure
    use_azure = bool(os.environ.get("AZURE_STORAGE_CONNECTION_STRING", ""))
    
    if use_azure:
        from app.services.azure_blob_service import AzureBlobService
        azure_blob_service = AzureBlobService()
        
        lots_to_check = [lot] if lot else ["2a", "2b", "3"]
        
        for lot_val in lots_to_check:
            base_prefix = f"GCloud {gcloud_version}/PA Services/Cloud Support Services LOT {lot_val}/"
            blob_list = azure_blob_service.list_blobs(prefix=base_prefix)
            
            # Find all questionnaire_responses.json files
            for blob_name in blob_list:
                if blob_name.endswith('questionnaire_responses.json'):
                    try:
                        json_bytes = azure_blob_service.get_file_bytes(blob_name)
                        response_data = json.loads(json_bytes.decode('utf-8'))
                        
                        # Extract service name from blob path
                        parts = blob_name.split('/')
                        service_name = parts[3] if len(parts) > 3 else 'Unknown'
                        
                        response_data['service_name'] = service_name
                        response_data['lot'] = lot_val
                        all_responses.append(response_data)
                    except Exception as e:
                        logger.warning(f"Failed to load questionnaire from {blob_name}: {e}")
    else:
        # Local filesystem
        from sharepoint_service.mock_sharepoint import MOCK_BASE_PATH
        
        lots_to_check = [lot] if lot else ["2a", "2b", "3"]
        
        for lot_val in lots_to_check:
            base_path = MOCK_BASE_PATH / f"GCloud {gcloud_version}" / "PA Services" / f"Cloud Support Services LOT {lot_val}"
            
            if not base_path.exists():
                continue
            
            for service_folder in base_path.iterdir():
                if not service_folder.is_dir():
                    continue
                
                response_path = service_folder / "questionnaire_responses.json"
                
                if response_path.exists():
                    try:
                        with open(response_path, 'r', encoding='utf-8') as f:
                            response_data = json.load(f)
                        
                        response_data['service_name'] = service_folder.name
                        response_data['lot'] = lot_val
                        all_responses.append(response_data)
                    except Exception as e:
                        logger.warning(f"Failed to load questionnaire from {response_path}: {e}")
    
    return all_responses


async def aggregate_responses_by_section(
    all_responses: List[Dict[str, Any]],
    lot: Optional[str],
    gcloud_version: str
) -> List[SectionAnalytics]:
    """
    Aggregate responses by section and question
    
    Returns:
        List of SectionAnalytics
    """
    # Get question structure from parser
    parser = get_parser()
    if not parser:
        return []
    
    # Get sections for the LOT (or all LOTs)
    lots_to_check = [lot] if lot else ["2a", "2b", "3"]
    
    sections_analytics = []
    
    for lot_val in lots_to_check:
        questions_by_section = parser.parse_questions_for_lot(lot_val)
        section_order = parser.get_sections_for_lot(lot_val)
        
        # Filter responses for this LOT
        lot_responses = [r for r in all_responses if r.get('lot') == lot_val]
        
        # Aggregate by section
        for section_name in section_order:
            questions = questions_by_section.get(section_name, [])
            question_analytics = []
            
            for question in questions:
                question_text = question.get('question_text', '')
                question_type = question.get('question_type', '')
                
                # Count answers for this question
                answer_counts = Counter()
                services_by_answer = defaultdict(list)
                
                for response in lot_responses:
                    service_name = response['service_name']
                    answers = response.get('answers', [])
                    
                    # Find matching answer
                    for answer in answers:
                        if answer.get('question_text') == question_text:
                            answer_value = answer.get('answer')
                            
                            # Convert to string key
                            if isinstance(answer_value, list):
                                answer_key = ', '.join(str(v) for v in answer_value)
                            else:
                                answer_key = str(answer_value) if answer_value else 'No answer'
                            
                            answer_counts[answer_key] += 1
                            services_by_answer[answer_key].append(service_name)
                            break
                
                question_analytics.append(QuestionAnalytics(
                    question_text=question_text,
                    question_type=question_type,
                    section_name=section_name,
                    answer_counts=dict(answer_counts),
                    total_responses=sum(answer_counts.values()),
                    services_by_answer={k: list(set(v)) for k, v in services_by_answer.items()}  # Deduplicate
                ))
            
            # Count completed services for this section
            completed_services = set()
            for response in lot_responses:
                answers = response.get('answers', [])
                section_answers = [a for a in answers if a.get('section_name') == section_name]
                if section_answers:
                    completed_services.add(response['service_name'])
            
            sections_analytics.append(SectionAnalytics(
                section_name=section_name,
                questions=question_analytics,
                total_questions=len(question_analytics),
                completed_services=len(completed_services)
            ))
    
    return sections_analytics

