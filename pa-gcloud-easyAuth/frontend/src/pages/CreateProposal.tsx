/**
 * Template Selection Page - PA Consulting Style
 * Choose between Service Description and Pricing Document templates
 */

import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Container, Box, Typography, Grid, Card, CardContent, CardActions,
  Button, Chip, CircularProgress,
} from '@mui/material';
import {
  Description as DescriptionIcon,
  AttachMoney as MoneyIcon,
  ArrowForward as ArrowIcon,
} from '@mui/icons-material';
import apiService from '../services/api';

export default function CreateProposal() {
  const [templates, setTemplates] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const navigate = useNavigate();

  useEffect(() => {
    loadTemplates();
  }, []);

  const loadTemplates = async () => {
    try {
      const response: any = await apiService.get('/templates');
      setTemplates(response.templates || []);
    } catch (error) {
      console.error('Failed to load templates:', error);
    } finally {
      setLoading(false);
    }
  };

  const handleSelectTemplate = (templateId: string) => {
    if (templateId === 'service-description') {
      // Clear any previous update data for security (but keep newProposal if it exists)
      sessionStorage.removeItem('updateDocument');
      sessionStorage.removeItem('updateMetadata');
      // Don't clear newProposal here - it might be set from ProposalFlow
      // Only clear it when explicitly starting a new proposal
      
      navigate('/proposals/create/service-description');
    } else if (templateId === 'pricing-document') {
      // Coming soon
      alert('Pricing Document template coming soon!');
    }
  };

  const getTemplateIcon = (id: string) => {
    switch (id) {
      case 'service-description':
        return <DescriptionIcon sx={{ fontSize: 60, color: 'primary.main' }} />;
      case 'pricing-document':
        return <MoneyIcon sx={{ fontSize: 60, color: 'primary.main' }} />;
      default:
        return null;
    }
  };

  if (loading) {
    return (
      <Box display="flex" justifyContent="center" alignItems="center" minHeight="80vh">
        <CircularProgress />
      </Box>
    );
  }

  return (
    <Container maxWidth="lg" sx={{ py: 6 }}>
      <Box mb={6}>
        <Typography variant="h2" gutterBottom sx={{ fontWeight: 700 }}>
          Create New Proposal
        </Typography>
        <Typography variant="body1" color="text.secondary">
          Select a template to begin creating your G-Cloud proposal
        </Typography>
      </Box>

      <Grid container spacing={4}>
        {templates.map((template) => (
          <Grid item xs={12} md={6} key={template.id}>
            <Card
              sx={{
                height: '100%',
                display: 'flex',
                flexDirection: 'column',
                position: 'relative',
                opacity: template.status === 'Coming soon' ? 0.7 : 1,
              }}
            >
              <CardContent sx={{ flexGrow: 1, textAlign: 'center', py: 4 }}>
                <Box mb={3}>
                  {getTemplateIcon(template.id)}
                </Box>

                <Typography variant="h4" gutterBottom sx={{ fontWeight: 600 }}>
                  {template.name}
                </Typography>

                <Typography variant="body1" color="text.secondary" paragraph>
                  {template.description}
                </Typography>

                {template.status && (
                  <Chip 
                    label={template.status} 
                    color="warning" 
                    size="small"
                    sx={{ mt: 2 }}
                  />
                )}

                {template.sections && (
                  <Box mt={3} textAlign="left">
                    <Typography variant="subtitle2" gutterBottom sx={{ fontWeight: 600 }}>
                      Required Sections:
                    </Typography>
                    {template.sections.map((section: any, idx: number) => (
                      <Typography key={idx} variant="body2" color="text.secondary" sx={{ ml: 2 }}>
                        • {section.label}
                      </Typography>
                    ))}
                  </Box>
                )}

                {template.validation && (
                  <Box mt={2} textAlign="left">
                    <Typography variant="caption" color="text.secondary" display="block" sx={{ fontStyle: 'italic' }}>
                      Validation: {template.validation.description || Object.values(template.validation).join(', ')}
                    </Typography>
                  </Box>
                )}
              </CardContent>

              <CardActions sx={{ p: 3, pt: 0 }}>
                <Button
                  fullWidth
                  variant="contained"
                  size="large"
                  endIcon={<ArrowIcon />}
                  onClick={() => handleSelectTemplate(template.id)}
                  disabled={template.status === 'Coming soon'}
                >
                  {template.status === 'Coming soon' ? 'Coming Soon' : 'Start Creating'}
                </Button>
              </CardActions>
            </Card>
          </Grid>
        ))}
      </Grid>
    </Container>
  );
}

