/**
 * G-Cloud Capabilities Questionnaire Page
 * Displays questionnaire with pagination by section
 */

import { useState, useEffect } from 'react';
import { useParams } from 'react-router-dom';
import {
  Container,
  Box,
  Typography,
  Button,
  Paper,
  FormControl,
  FormLabel,
  RadioGroup,
  FormControlLabel,
  Radio,
  Checkbox,
  TextField,
  FormGroup,
  CircularProgress,
  Alert,
  Chip,
} from '@mui/material';
import {
  ArrowBack as ArrowBackIcon,
  ArrowForward as ArrowForwardIcon,
  Save as SaveIcon,
  Lock as LockIcon,
} from '@mui/icons-material';
import questionnaireApi, { Question, QuestionnaireData, QuestionAnswer } from '../services/questionnaireApi';

export default function QuestionnairePage() {
  const { serviceName, lot } = useParams<{ serviceName: string; lot: string }>();
  
  const [loading, setLoading] = useState(true);
  const [questionnaireData, setQuestionnaireData] = useState<QuestionnaireData | null>(null);
  const [currentSectionIndex, setCurrentSectionIndex] = useState(0);
  const [answers, setAnswers] = useState<Record<string, any>>({});
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [successMessage, setSuccessMessage] = useState<string | null>(null);
  const [listValidationErrors, setListValidationErrors] = useState<Record<string, string>>({});

  useEffect(() => {
    if (lot && serviceName) {
      loadQuestionnaire();
    }
  }, [lot, serviceName]);

  const loadQuestionnaire = async () => {
    try {
      setLoading(true);
      setError(null);
      
      const data = await questionnaireApi.getQuestions(lot!, serviceName, '15');
      setQuestionnaireData(data);
      
      // Load saved answers if available
      if (data.saved_answers) {
        setAnswers(data.saved_answers);
      }
      
      // Pre-fill service name if available
      if (serviceName) {
        for (const sectionName of data.section_order) {
          const questions = data.sections[sectionName] || [];
          for (const question of questions) {
            if (question.prefilled_answer) {
              setAnswers(prev => ({
                ...prev,
                [question.question_text]: question.prefilled_answer,
              }));
            }
          }
        }
      }
    } catch (err: any) {
      setError(err.response?.data?.detail || 'Failed to load questionnaire');
    } finally {
      setLoading(false);
    }
  };

  // Helper functions for list validation
  const stripNumberPrefix = (text: string): string => {
    return text.replace(/^\s*\d+\.?\s*/, '').trim();
  };

  const countWords = (text: string): number => {
    return text.trim().split(/\s+/).filter(word => word.length > 0).length;
  };

  const validateListItems = (items: string[], questionText: string): boolean => {
    const validItems = items.filter(item => item.trim().length > 0);
    
    if (validItems.length > 10) {
      setListValidationErrors(prev => ({
        ...prev,
        [questionText]: `Maximum 10 items allowed (currently ${validItems.length})`
      }));
      return false;
    }
    
    // Check each item is max 10 words
    for (const item of validItems) {
      const strippedItem = stripNumberPrefix(item);
      const words = countWords(strippedItem);
      if (words > 10) {
        setListValidationErrors(prev => ({
          ...prev,
          [questionText]: `Each item must be max 10 words (found ${words} words in one item)`
        }));
        return false;
      }
    }
    
    // Clear error if valid
    setListValidationErrors(prev => {
      const newErrors = { ...prev };
      delete newErrors[questionText];
      return newErrors;
    });
    return true;
  };

  const handleAnswerChange = (questionText: string, answer: any) => {
    setAnswers(prev => ({
      ...prev,
      [questionText]: answer,
    }));
  };

  const handleSaveDraft = async () => {
    if (!questionnaireData) return;
    
    try {
      setSaving(true);
      setError(null);
      setSuccessMessage(null);
      
      // Convert answers to QuestionAnswer format
      const questionAnswers: QuestionAnswer[] = [];
      for (const sectionName of questionnaireData.section_order) {
        const questions = questionnaireData.sections[sectionName] || [];
        for (const question of questions) {
          if (answers[question.question_text] !== undefined) {
            questionAnswers.push({
              question_text: question.question_text,
              question_type: question.question_type,
              answer: answers[question.question_text],
              section_name: sectionName,
            });
          }
        }
      }
      
      await questionnaireApi.saveResponses({
        service_name: questionnaireData.service_name,
        lot: questionnaireData.lot,
        gcloud_version: questionnaireData.gcloud_version,
        answers: questionAnswers,
        is_draft: true,
        is_locked: false,
      });
      
      setSuccessMessage('Draft saved successfully!');
      setTimeout(() => setSuccessMessage(null), 3000);
    } catch (err: any) {
      setError(err.response?.data?.detail || 'Failed to save draft');
    } finally {
      setSaving(false);
    }
  };


  const handleNext = () => {
    if (questionnaireData && currentSectionIndex < questionnaireData.section_order.length - 1) {
      setCurrentSectionIndex(prev => prev + 1);
    }
  };

  const handlePrevious = () => {
    if (currentSectionIndex > 0) {
      setCurrentSectionIndex(prev => prev - 1);
    }
  };

  const handleSectionClick = (index: number) => {
    setCurrentSectionIndex(index);
  };

  const renderQuestion = (question: Question) => {
    const currentAnswer = answers[question.question_text];
    
    switch (question.question_type) {
      case 'radio':
        return (
          <FormControl key={question.question_text} fullWidth sx={{ mb: 3 }}>
            <FormLabel component="legend" sx={{ mb: 1, fontWeight: 600 }}>
              {question.question_text}
            </FormLabel>
            {question.question_hint && (
              <Typography variant="caption" color="text.secondary" sx={{ mb: 1, display: 'block' }}>
                {question.question_hint}
              </Typography>
            )}
            {question.question_advice && (
              <Typography variant="body2" color="text.secondary" sx={{ mb: 1, fontStyle: 'italic' }}>
                {question.question_advice}
              </Typography>
            )}
            <RadioGroup
              value={currentAnswer || ''}
              onChange={(e) => handleAnswerChange(question.question_text, e.target.value)}
            >
              {question.answer_options?.map((option, idx) => (
                <FormControlLabel
                  key={idx}
                  value={option}
                  control={<Radio />}
                  label={option}
                />
              ))}
            </RadioGroup>
          </FormControl>
        );
      
      case 'checkbox':
        return (
          <FormControl key={question.question_text} fullWidth component="fieldset" sx={{ mb: 3 }}>
            <FormLabel component="legend" sx={{ mb: 1, fontWeight: 600 }}>
              {question.question_text}
            </FormLabel>
            {question.question_hint && (
              <Typography variant="caption" color="text.secondary" sx={{ mb: 1, display: 'block' }}>
                {question.question_hint}
              </Typography>
            )}
            {question.question_advice && (
              <Typography variant="body2" color="text.secondary" sx={{ mb: 1, fontStyle: 'italic' }}>
                {question.question_advice}
              </Typography>
            )}
            <FormGroup>
              {question.answer_options?.map((option, idx) => (
                <FormControlLabel
                  key={idx}
                  control={
                    <Checkbox
                      checked={(currentAnswer || []).includes(option)}
                      onChange={(e) => {
                        const current = (currentAnswer || []) as string[];
                        if (e.target.checked) {
                          handleAnswerChange(question.question_text, [...current, option]);
                        } else {
                          handleAnswerChange(question.question_text, current.filter(v => v !== option));
                        }
                      }}
                    />
                  }
                  label={option}
                />
              ))}
            </FormGroup>
          </FormControl>
        );
      
      case 'textarea':
        return (
          <TextField
            key={question.question_text}
            fullWidth
            multiline
            rows={4}
            label={question.question_text}
            value={currentAnswer || ''}
            onChange={(e) => handleAnswerChange(question.question_text, e.target.value)}
            helperText={question.question_hint || question.question_advice}
            sx={{ mb: 3 }}
          />
        );
      
      case 'list':
        // List of text fields (like features/benefits)
        const listItems = currentAnswer || [''];
        const validItems = listItems.filter((item: string) => item.trim().length > 0);
        const maxItems = 10;
        const validationError = listValidationErrors[question.question_text];
        
        return (
          <Box key={question.question_text} sx={{ mb: 3 }}>
            <FormLabel component="legend" sx={{ mb: 1, fontWeight: 600, display: 'block' }}>
              {question.question_text}
            </FormLabel>
            {question.question_hint && (
              <Typography variant="caption" color="text.secondary" sx={{ mb: 1, display: 'block' }}>
                {question.question_hint}
              </Typography>
            )}
            {question.question_advice && (
              <Typography variant="body2" color="text.secondary" sx={{ mb: 1, fontStyle: 'italic' }}>
                {question.question_advice}
              </Typography>
            )}
            {validationError && (
              <Alert severity="error" sx={{ mb: 1 }}>
                {validationError}
              </Alert>
            )}
            <Typography variant="caption" color="text.secondary" sx={{ mb: 1, display: 'block' }}>
              {validItems.length}/{maxItems} items (max 10 words per item)
            </Typography>
            {listItems.map((item: string, idx: number) => {
              const strippedItem = stripNumberPrefix(item);
              const wordCount = countWords(strippedItem);
              const hasError = wordCount > 10;
              
              return (
                <TextField
                  key={idx}
                  fullWidth
                  value={item}
                  onChange={(e) => {
                    const newList = [...listItems];
                    newList[idx] = e.target.value;
                    handleAnswerChange(question.question_text, newList);
                    // Validate on change
                    validateListItems(newList, question.question_text);
                  }}
                  error={hasError}
                  helperText={hasError ? `${wordCount} words (max 10)` : wordCount > 0 ? `${wordCount} words` : ''}
                  sx={{ mb: 1 }}
                  placeholder={`Item ${idx + 1}`}
                />
              );
            })}
            <Button
              size="small"
              onClick={() => {
                if (validItems.length < maxItems) {
                  handleAnswerChange(question.question_text, [...listItems, '']);
                }
              }}
              disabled={validItems.length >= maxItems}
              sx={{ mt: 1 }}
            >
              Add Item {validItems.length >= maxItems ? `(Max ${maxItems} items)` : ''}
            </Button>
          </Box>
        );
      
      case 'text':
      default:
        return (
          <TextField
            key={question.question_text}
            fullWidth
            label={question.question_text}
            value={currentAnswer || ''}
            onChange={(e) => handleAnswerChange(question.question_text, e.target.value)}
            helperText={question.question_hint || question.question_advice}
            sx={{ mb: 3 }}
          />
        );
    }
  };

  if (loading) {
    return (
      <Container maxWidth="lg" sx={{ py: 4 }}>
        <Box display="flex" justifyContent="center" alignItems="center" minHeight="400px">
          <CircularProgress />
        </Box>
      </Container>
    );
  }

  if (!questionnaireData) {
    return (
      <Container maxWidth="lg" sx={{ py: 4 }}>
        <Alert severity="error">Failed to load questionnaire</Alert>
      </Container>
    );
  }

  const currentSectionName = questionnaireData.section_order[currentSectionIndex];
  const currentQuestions = questionnaireData.sections[currentSectionName] || [];
  const totalSections = questionnaireData.section_order.length;

  return (
    <Container maxWidth="lg" sx={{ py: 4 }}>
      <Box sx={{ mb: 4 }}>
        <Typography variant="h4" gutterBottom>
          G-Cloud Capabilities Questionnaire
        </Typography>
        <Typography variant="body1" color="text.secondary" gutterBottom>
          Service: {questionnaireData.service_name} | LOT: {questionnaireData.lot} | G-Cloud {questionnaireData.gcloud_version}
        </Typography>
        {questionnaireData.is_locked && (
          <Chip
            icon={<LockIcon />}
            label="Locked"
            color="warning"
            sx={{ mt: 1 }}
          />
        )}
      </Box>

      {error && (
        <Alert severity="error" sx={{ mb: 2 }} onClose={() => setError(null)}>
          {error}
        </Alert>
      )}

      {successMessage && (
        <Alert severity="success" sx={{ mb: 2 }} onClose={() => setSuccessMessage(null)}>
          {successMessage}
        </Alert>
      )}

      {/* Section Navigation - Compact Chip List */}
      <Paper sx={{ p: 2, mb: 3 }}>
        <Typography variant="subtitle2" color="text.secondary" sx={{ mb: 1 }}>
          Sections ({currentSectionIndex + 1} of {totalSections})
        </Typography>
        <Box
          sx={{
            display: 'flex',
            gap: 1,
            overflowX: 'auto',
            pb: 1,
            '&::-webkit-scrollbar': {
              height: '8px',
            },
            '&::-webkit-scrollbar-track': {
              backgroundColor: 'rgba(0,0,0,0.1)',
              borderRadius: '4px',
            },
            '&::-webkit-scrollbar-thumb': {
              backgroundColor: 'rgba(0,0,0,0.3)',
              borderRadius: '4px',
            },
          }}
        >
          {questionnaireData.section_order.map((sectionName, index) => (
            <Chip
              key={sectionName}
              label={sectionName}
              onClick={() => handleSectionClick(index)}
              color={index === currentSectionIndex ? 'primary' : 'default'}
              variant={index === currentSectionIndex ? 'filled' : 'outlined'}
              sx={{
                cursor: 'pointer',
                whiteSpace: 'nowrap',
                flexShrink: 0,
                '&:hover': {
                  backgroundColor: index === currentSectionIndex ? undefined : 'action.hover',
                },
              }}
            />
          ))}
        </Box>
      </Paper>

      {/* Current Section */}
      <Paper sx={{ p: 4, mb: 3 }}>
        <Typography variant="h5" gutterBottom>
          {currentSectionName}
        </Typography>
        <Typography variant="body2" color="text.secondary" sx={{ mb: 3 }}>
          Section {currentSectionIndex + 1} of {totalSections}
        </Typography>

        {currentQuestions.map((question) => renderQuestion(question))}
      </Paper>

      {/* Navigation */}
      <Box display="flex" justifyContent="space-between" alignItems="center">
        <Button
          startIcon={<ArrowBackIcon />}
          onClick={handlePrevious}
          disabled={currentSectionIndex === 0 || questionnaireData.is_locked}
        >
          Previous
        </Button>

        <Button
          startIcon={<SaveIcon />}
          onClick={handleSaveDraft}
          disabled={saving || questionnaireData.is_locked}
        >
          {saving ? <CircularProgress size={24} /> : 'Save Draft'}
        </Button>

        <Button
          endIcon={<ArrowForwardIcon />}
          onClick={handleNext}
          disabled={currentSectionIndex === totalSections - 1 || questionnaireData.is_locked}
          variant="contained"
        >
          Next
        </Button>
      </Box>
    </Container>
  );
}

