"""Database service layer"""

import os
from typing import List, Dict, Any, Optional
import json

# Optional import for Lambda (not needed for document generation)
# Check if we're in Lambda (USE_S3 environment variable)
_use_s3 = os.environ.get("USE_S3", "false").lower() == "true"

psycopg2 = None
if not _use_s3:
    # Only try to import psycopg2 if not in Lambda
    # Use importlib to avoid parse-time import errors
    try:
        import importlib
        psycopg2 = importlib.import_module("psycopg2")
    except (ImportError, ModuleNotFoundError):
        psycopg2 = None


class DatabaseService:
    """Service for database operations"""
    
    def __init__(self):
        db_url = os.getenv('DATABASE_URL', 'postgresql://postgres:postgres@postgres:5432/gcloud_db')
        self.db_url = db_url.replace('postgresql+asyncpg://', 'postgresql://')
    
    def get_connection(self):
        """Get database connection"""
        if psycopg2 is None:
            raise ImportError("psycopg2 is not installed. Database features are unavailable.")
        return psycopg2.connect(self.db_url)
    
    def get_all_proposals(self) -> List[Dict[str, Any]]:
        """Get all proposals with basic info"""
        conn = self.get_connection()
        cur = conn.cursor()
        
        try:
            cur.execute("""
                SELECT p.id, p.title, p.framework_version, p.status, p.deadline, 
                       p.completion_percentage, p.created_at, p.updated_at,
                       u.full_name as created_by_name,
                       COUNT(s.id) as section_count,
                       COUNT(CASE WHEN s.validation_status = 'valid' THEN 1 END) as valid_sections
                FROM proposals p
                LEFT JOIN users u ON p.created_by = u.id
                LEFT JOIN sections s ON p.id = s.proposal_id
                GROUP BY p.id, u.full_name
                ORDER BY p.created_at DESC
            """)
            
            columns = [desc[0] for desc in cur.description]
            results = []
            
            for row in cur.fetchall():
                results.append(dict(zip(columns, row)))
            
            return results
        finally:
            cur.close()
            conn.close()
    
    def get_proposal_by_id(self, proposal_id: str) -> Optional[Dict[str, Any]]:
        """Get proposal with all sections"""
        conn = self.get_connection()
        cur = conn.cursor()
        
        try:
            # Get proposal
            cur.execute("""
                SELECT p.*, u.full_name as created_by_name
                FROM proposals p
                LEFT JOIN users u ON p.created_by = u.id
                WHERE p.id = %s
            """, (proposal_id,))
            
            row = cur.fetchone()
            if not row:
                return None
            
            columns = [desc[0] for desc in cur.description]
            proposal = dict(zip(columns, row))
            
            # Get sections
            cur.execute("""
                SELECT s.*, u.full_name as last_modified_by_name
                FROM sections s
                LEFT JOIN users u ON s.last_modified_by = u.id
                WHERE s.proposal_id = %s
                ORDER BY s."order"
            """, (proposal_id,))
            
            columns = [desc[0] for desc in cur.description]
            sections = []
            
            for row in cur.fetchall():
                sections.append(dict(zip(columns, row)))
            
            proposal['sections'] = sections
            return proposal
        finally:
            cur.close()
            conn.close()
    
    def update_section_content(self, section_id: str, content: str, user_id: str) -> Dict[str, Any]:
        """Update section content and recalculate word count"""
        from app.utils.validation import count_words
        
        conn = self.get_connection()
        cur = conn.cursor()
        
        try:
            word_count = count_words(content)
            
            cur.execute("""
                UPDATE sections
                SET content = %s, word_count = %s, last_modified_by = %s, updated_at = CURRENT_TIMESTAMP
                WHERE id = %s
                RETURNING id, section_type, title, content, word_count, validation_status
            """, (content, word_count, user_id, section_id))
            
            row = cur.fetchone()
            if not row:
                raise ValueError(f"Section {section_id} not found")
            
            columns = [desc[0] for desc in cur.description]
            section = dict(zip(columns, row))
            
            conn.commit()
            return section
        finally:
            cur.close()
            conn.close()
    
    def validate_section(self, section_id: str) -> Dict[str, Any]:
        """Validate a section against rules"""
        conn = self.get_connection()
        cur = conn.cursor()
        
        try:
            # Get section
            cur.execute("""
                SELECT id, section_type, content, word_count
                FROM sections
                WHERE id = %s
            """, (section_id,))
            
            section = cur.fetchone()
            if not section:
                raise ValueError(f"Section {section_id} not found")
            
            section_id, section_type, content, word_count = section
            
            # Get validation rules
            cur.execute("""
                SELECT rule_type, parameters, error_message
                FROM validation_rules
                WHERE section_type = %s AND is_active = TRUE
            """, (section_type,))
            
            rules = cur.fetchall()
            
            errors = []
            warnings = []
            min_words = None
            max_words = None
            
            for rule in rules:
                rule_type, parameters, error_msg = rule
                
                if rule_type == 'word_count_min':
                    min_words = parameters.get('min_words')
                    if min_words and word_count < min_words:
                        errors.append(error_msg)
                
                elif rule_type == 'word_count_max':
                    max_words = parameters.get('max_words')
                    if max_words and word_count > max_words:
                        errors.append(error_msg)
            
            # Update section validation status
            if errors:
                status = 'invalid'
            else:
                status = 'valid'
            
            cur.execute("""
                UPDATE sections
                SET validation_status = %s, validation_errors = %s
                WHERE id = %s
            """, (status, json.dumps(errors) if errors else None, section_id))
            
            conn.commit()
            
            return {
                "section_id": str(section_id),
                "is_valid": len(errors) == 0,
                "word_count": word_count,
                "min_words": min_words,
                "max_words": max_words,
                "errors": errors,
                "warnings": warnings
            }
        finally:
            cur.close()
            conn.close()
    
    def get_validation_rules(self, section_type: str) -> List[Dict[str, Any]]:
        """Get validation rules for a section type"""
        conn = self.get_connection()
        cur = conn.cursor()
        
        try:
            cur.execute("""
                SELECT id, rule_type, name, parameters, error_message, severity
                FROM validation_rules
                WHERE section_type = %s AND is_active = TRUE
            """, (section_type,))
            
            columns = [desc[0] for desc in cur.description]
            results = []
            
            for row in cur.fetchall():
                results.append(dict(zip(columns, row)))
            
            return results
        finally:
            cur.close()
            conn.close()


# Global instance (lazy initialization for Lambda compatibility)
_db_service_instance = None

def get_db_service():
    """Get or create database service instance (lazy for Lambda)"""
    global _db_service_instance
    if _db_service_instance is None:
        try:
            _db_service_instance = DatabaseService()
        except (ImportError, AttributeError):
            # psycopg2 not available (Lambda environment)
            _db_service_instance = None
    return _db_service_instance

# For backwards compatibility - use a class to simulate lazy access
class _LazyDBService:
    def __getattr__(self, name):
        service = get_db_service()
        if service is None:
            raise AttributeError("Database service is not available (psycopg2 not installed)")
        return getattr(service, name)

db_service = _LazyDBService()

