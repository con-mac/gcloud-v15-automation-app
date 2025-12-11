/**
 * Proposal Editor - PA Consulting Style
 * Real-time validation with visual feedback
 */

import { useEffect, useState, useCallback } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import {
  Container, Box, Typography, Paper, TextField, LinearProgress,
  Alert, Chip, List, ListItem, ListItemButton, ListItemText,
  CircularProgress, IconButton,
} from '@mui/material';
import {
  CheckCircle, Warning, Error, ArrowBack,
} from '@mui/icons-material';
import { debounce } from 'lodash';
import { proposalsService } from '../services/proposals';

interface Section {
  id: string;
  section_type: string;
  title: string;
  content: string;
  word_count: number;
  validation_status: string;
  is_mandatory: boolean;
}

export default function ProposalEditor() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const [proposal, setProposal] = useState<any>(null);
  const [activeSection, setActiveSection] = useState<Section | null>(null);
  const [content, setContent] = useState('');
  const [validation, setValidation] = useState<any>(null);
  const [saving, setSaving] = useState(false);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (id) {
      loadProposal(id);
    }
  }, [id]);

  const loadProposal = async (proposalId: string) => {
    try {
      const data = await proposalsService.getProposalById(proposalId);
      setProposal(data);
      if (data.sections && data.sections.length > 0) {
        setActiveSection(data.sections[0]);
        setContent(data.sections[0].content || '');
      }
    } catch (error) {
      console.error('Failed to load proposal:', error);
    } finally {
      setLoading(false);
    }
  };

  const saveContent = useCallback(
    debounce(async (sectionId: string, newContent: string) => {
      setSaving(true);
      try {
        const result = await proposalsService.updateSection(sectionId, newContent);
        setValidation(result.validation);
        // Update section in proposal
        if (proposal) {
          const updatedSections = proposal.sections.map((s: Section) =>
            s.id === sectionId ? { ...s, ...result.section } : s
          );
          setProposal({ ...proposal, sections: updatedSections });
        }
      } catch (error) {
        console.error('Failed to save:', error);
      } finally {
        setSaving(false);
      }
    }, 1000),
    [proposal]
  );

  const handleContentChange = (newContent: string) => {
    setContent(newContent);
    if (activeSection) {
      saveContent(activeSection.id, newContent);
    }
  };

  const handleSectionClick = (section: Section) => {
    setActiveSection(section);
    setContent(section.content || '');
    setValidation(null);
  };

  const getWordCount = (text: string) => {
    return text.trim().split(/\s+/).filter(Boolean).length;
  };

  const getValidationColor = () => {
    if (!validation) return 'default';
    if (validation.is_valid) return 'success';
    return 'error';
  };

  const getValidationIcon = (section: Section) => {
    if (section.validation_status === 'valid') return <CheckCircle color="success" fontSize="small" />;
    if (section.validation_status === 'warning') return <Warning color="warning" fontSize="small" />;
    return <Error color="error" fontSize="small" />;
  };

  if (loading) {
    return (
      <Box display="flex" justifyContent="center" alignItems="center" minHeight="80vh">
        <CircularProgress />
      </Box>
    );
  }

  if (!proposal) {
    return (
      <Container>
        <Alert severity="error">Proposal not found</Alert>
      </Container>
    );
  }

  const currentWordCount = getWordCount(content);
  const wordCountPercentage = validation
    ? Math.min((currentWordCount / (validation.max_words || currentWordCount)) * 100, 100)
    : 0;

  return (
    <Box sx={{ display: 'flex', minHeight: '100vh', bgcolor: 'background.default' }}>
      {/* Sidebar - Sections Navigation */}
      <Paper
        sx={{
          width: 280,
          flexShrink: 0,
          borderRight: 1,
          borderColor: 'divider',
          overflowY: 'auto',
        }}
        elevation={0}
        square
      >
        <Box p={2} borderBottom={1} borderColor="divider">
          <IconButton onClick={() => navigate('/proposals')} sx={{ mb: 1 }}>
            <ArrowBack />
          </IconButton>
          <Typography variant="h6" noWrap>
            {proposal.title}
          </Typography>
          <Typography variant="caption" color="text.secondary">
            {proposal.framework_version}
          </Typography>
        </Box>

        <List>
          {proposal.sections?.map((section: Section) => (
            <ListItem key={section.id} disablePadding>
              <ListItemButton
                selected={activeSection?.id === section.id}
                onClick={() => handleSectionClick(section)}
              >
                <ListItemText
                  primary={
                    <Box display="flex" alignItems="center" gap={1}>
                      {getValidationIcon(section)}
                      <Typography variant="body2">{section.title}</Typography>
                    </Box>
                  }
                  secondary={`${section.word_count} words`}
                />
              </ListItemButton>
            </ListItem>
          ))}
        </List>
      </Paper>

      {/* Main Content Area */}
      <Box flexGrow={1} display="flex" flexDirection="column">
        {activeSection && (
          <>
            {/* Header */}
            <Box p={3} borderBottom={1} borderColor="divider" bgcolor="background.paper">
              <Box display="flex" justifyContent="space-between" alignItems="center">
                <Box>
                  <Typography variant="h4">{activeSection.title}</Typography>
                  <Typography variant="body2" color="text.secondary" mt={0.5}>
                    {activeSection.section_type.replace(/_/g, ' ')}
                  </Typography>
                </Box>
                <Box display="flex" gap={2} alignItems="center">
                  {saving && <CircularProgress size={20} />}
                  <Chip
                    icon={validation?.is_valid ? <CheckCircle /> : <Error />}
                    label={validation?.is_valid ? 'Valid' : 'Invalid'}
                    color={getValidationColor() as any}
                  />
                </Box>
              </Box>

              {/* Word Count Indicator */}
              {validation && (
                <Box mt={2}>
                  <Box display="flex" justifyContent="space-between" mb={0.5}>
                    <Typography variant="caption" color="text.secondary">
                      Word Count: {currentWordCount} / {validation.max_words}
                      {validation.min_words && ` (min: ${validation.min_words})`}
                    </Typography>
                    <Typography
                      variant="caption"
                      fontWeight="bold"
                      color={validation.is_valid ? 'success.main' : 'error.main'}
                    >
                      {validation.is_valid ? 'Within limits' : 'Out of range'}
                    </Typography>
                  </Box>
                  <LinearProgress
                    variant="determinate"
                    value={wordCountPercentage}
                    color={validation.is_valid ? 'success' : 'error'}
                    sx={{ height: 8, borderRadius: 4 }}
                  />
                </Box>
              )}

              {/* Validation Errors */}
              {validation?.errors && validation.errors.length > 0 && (
                <Box mt={2}>
                  {validation.errors.map((error: string, index: number) => (
                    <Alert key={index} severity="error" sx={{ mt: 1 }}>
                      {error}
                    </Alert>
                  ))}
                </Box>
              )}
            </Box>

            {/* Editor */}
            <Box p={3} flexGrow={1} overflow="auto">
              <TextField
                fullWidth
                multiline
                rows={20}
                value={content}
                onChange={(e) => handleContentChange(e.target.value)}
                placeholder={`Enter ${activeSection.title.toLowerCase()} content...`}
                variant="outlined"
                sx={{
                  '& .MuiOutlinedInput-root': {
                    fontFamily: 'monospace',
                    fontSize: '0.95rem',
                    lineHeight: 1.8,
                  },
                }}
              />
            </Box>
          </>
        )}
      </Box>
    </Box>
  );
}

