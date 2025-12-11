"""Validation utilities"""

import re
from typing import List, Dict, Any


def count_words(text: str) -> int:
    """
    Count words in text.
    
    Splits by whitespace and filters out empty strings.
    Excludes common markdown/formatting characters.
    """
    if not text:
        return 0
    
    # Remove common markdown/formatting
    text = re.sub(r'[#*_\-`]', '', text)
    
    # Split and count
    words = text.split()
    return len([w for w in words if w.strip()])


def validate_word_count(content: str, min_words: int = None, max_words: int = None) -> Dict[str, Any]:
    """
    Validate word count against min/max requirements.
    
    Returns dict with:
    - is_valid: bool
    - word_count: int
    - errors: List[str]
    - warnings: List[str]
    """
    word_count = count_words(content)
    errors = []
    warnings = []
    is_valid = True
    
    if min_words and word_count < min_words:
        errors.append(f"Content has {word_count} words but requires at least {min_words} words")
        is_valid = False
    
    if max_words and word_count > max_words:
        errors.append(f"Content has {word_count} words but must not exceed {max_words} words")
        is_valid = False
    
    # Warnings for content approaching limits
    if min_words and word_count < min_words * 1.1 and word_count >= min_words:
        warnings.append(f"Content is close to minimum word count ({word_count}/{min_words})")
    
    if max_words and word_count > max_words * 0.9 and word_count <= max_words:
        warnings.append(f"Content is approaching maximum word count ({word_count}/{max_words})")
    
    return {
        "is_valid": is_valid,
        "word_count": word_count,
        "errors": errors,
        "warnings": warnings,
        "min_words": min_words,
        "max_words": max_words,
    }


def validate_section(section_content: str, section_type: str, validation_rules: List[Dict]) -> Dict[str, Any]:
    """
    Validate a section against all applicable rules.
    
    Args:
        section_content: The section text content
        section_type: Type of section (e.g., 'service_summary')
        validation_rules: List of validation rules from database
        
    Returns:
        Validation result dict
    """
    all_errors = []
    all_warnings = []
    is_valid = True
    word_count = count_words(section_content)
    
    min_words = None
    max_words = None
    
    # Apply each rule
    for rule in validation_rules:
        if rule['section_type'] != section_type or not rule['is_active']:
            continue
            
        rule_type = rule['rule_type']
        parameters = rule.get('parameters', {})
        
        if rule_type == 'word_count_min':
            min_words = parameters.get('min_words')
            if min_words and word_count < min_words:
                all_errors.append(rule['error_message'])
                is_valid = False
                
        elif rule_type == 'word_count_max':
            max_words = parameters.get('max_words')
            if max_words and word_count > max_words:
                all_errors.append(rule['error_message'])
                is_valid = False
    
    return {
        "is_valid": is_valid,
        "word_count": word_count,
        "min_words": min_words,
        "max_words": max_words,
        "errors": all_errors,
        "warnings": all_warnings,
    }

