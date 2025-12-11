/**
 * Proposal Flow Questionnaire
 * Handles Update vs Create workflow with SharePoint integration
 */

import { useState, useEffect } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import {
  Container,
  Box,
  Card,
  CardContent,
  Typography,
  Button,
  Radio,
  RadioGroup,
  FormControlLabel,
  FormControl,
  FormLabel,
  TextField,
  Alert,
  Stepper,
  Step,
  StepLabel,
  CircularProgress,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogContentText,
  DialogActions,
} from '@mui/material';
import {
  ArrowBack,
  ArrowForward,
  Update,
  Add,
  Description,
  AttachMoney,
  Dashboard,
} from '@mui/icons-material';
import SharePointSearch from '../components/SharePointSearch';
import sharepointApi, { SearchResult } from '../services/sharepointApi';
import { useAuth } from '../contexts/EasyAuthContext';

type FlowType = 'update' | 'create' | null;
type DocType = 'SERVICE DESC' | 'Pricing Doc' | null;
type LotType = '2' | '2a' | '2b' | '3' | null;

export default function ProposalFlow() {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const { user } = useAuth();
  const [activeStep, setActiveStep] = useState(0);
  const [flowType, setFlowType] = useState<FlowType>(null);
  const [docType, setDocType] = useState<DocType>(null);
  const [selectedResult, setSelectedResult] = useState<SearchResult | null>(null);
  const [searchQuery, setSearchQuery] = useState('');
  const [createData, setCreateData] = useState({
    service: '',
    owner: '',
    sponsor: '',
    lot: null as LotType,
  });
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [changeMetadataDialogOpen, setChangeMetadataDialogOpen] = useState(false);
  const [pendingUpdateContent, setPendingUpdateContent] = useState<any>(null);

  // Check for URL parameter to skip step 1 (coming from dashboard)
  useEffect(() => {
    const type = searchParams.get('type');
    if (type === 'create') {
      // Skip step 0 (Select Flow Type) and go directly to step 1 (Enter Proposal Details)
      setFlowType('create');
      setActiveStep(1);
      
      // Check if we have existing content to load (from change metadata flow)
      const existingContent = sessionStorage.getItem('existingProposalContent');
      if (existingContent) {
        try {
          const contentData = JSON.parse(existingContent);
          // Pre-populate createData with existing metadata
          setCreateData({
            service: contentData.metadata?.service_name || '',
            owner: contentData.metadata?.owner || '',
            sponsor: contentData.metadata?.sponsor || '',
            lot: contentData.metadata?.lot || null,
          });
        } catch (e) {
          console.error('Error parsing existing content:', e);
        }
      }
    }
  }, [searchParams]);

  const steps = [
    'Select Flow Type',
    flowType === 'update' ? 'Search & Select Document' : 'Enter Proposal Details',
    'Confirm & Proceed',
  ];

  const handleNext = () => {
    setError('');
    if (activeStep === 0) {
      if (!flowType) {
        setError('Please select a flow type');
        return;
      }
    } else if (activeStep === 1) {
      if (flowType === 'update') {
        if (!selectedResult) {
          setError('Please select a document');
          return;
        }
      } else {
        if (!createData.service || !createData.owner || !createData.sponsor || !createData.lot) {
          setError('Please fill in all fields');
          return;
        }
      }
    } else if (activeStep === 2) {
      handleProceed();
      return;
    }
    setActiveStep((prev) => prev + 1);
  };

  const handleBack = () => {
    setActiveStep((prev) => prev - 1);
    setError('');
  };

  const handleSelectResult = (result: SearchResult) => {
    setSelectedResult(result);
    setSearchQuery(result.service_name);
    setError('');
  };

  // No email formatting needed - use Entra ID user profile directly

  const handleProceed = async () => {
    setLoading(true);
    setError('');

    try {
      if (flowType === 'update' && selectedResult) {
        // Check if owner matches logged-in user (use Entra ID user profile)
        const userName = user?.name || '';
        const proposalOwner = selectedResult.owner || '';
        
        // Load document content first
        try {
          // Use docType from state if selectedResult doesn't have it
          const docTypeToUse = (selectedResult.doc_type || docType) as 'SERVICE DESC' | 'Pricing Doc';
          const lotToUse = (selectedResult.lot || '3') as '2a' | '2b' | '3';
          const gcloudVersionToUse = (selectedResult.gcloud_version || '14') as '14' | '15';
          
          console.log('Loading document:', {
            service_name: selectedResult.service_name,
            doc_type: docTypeToUse,
            lot: lotToUse,
            gcloud_version: gcloudVersionToUse
          });
          
          const documentContent = await sharepointApi.getDocumentContent(
            selectedResult.service_name,
            docTypeToUse,
            lotToUse,
            gcloudVersionToUse
          );
          
          // Check if owner matches logged-in user (case-insensitive)
          if (userName.toLowerCase() !== proposalOwner.toLowerCase()) {
            // Owner doesn't match - ask if they want to change metadata
            setPendingUpdateContent({
              content: documentContent,
              metadata: {
                service_name: selectedResult.service_name,
                owner: selectedResult.owner,
                sponsor: selectedResult.sponsor,
                lot: lotToUse,
                doc_type: docTypeToUse,
                gcloud_version: gcloudVersionToUse,
                folder_path: selectedResult.folder_path || '',
              }
            });
            setChangeMetadataDialogOpen(true);
            setLoading(false);
            return;
          }
          
          // Owner matches - proceed with normal update flow
          // Store document content and metadata for the form
          const updateMetadata = {
            service_name: selectedResult.service_name,
            owner: selectedResult.owner,
            sponsor: selectedResult.sponsor,
            lot: lotToUse,
            doc_type: docTypeToUse,
            gcloud_version: gcloudVersionToUse,
            folder_path: selectedResult.folder_path || '',
          };
          
          // Store document content with version to invalidate old cache
          const cacheVersion = Date.now();
          sessionStorage.setItem('updateDocument', JSON.stringify({
            ...updateMetadata,
            content: documentContent,
            _cacheVersion: cacheVersion, // Version to detect stale cache
            _timestamp: Date.now(), // Timestamp for cache invalidation
          }));
          
          // Also store update metadata separately for document generation
          sessionStorage.setItem('updateMetadata', JSON.stringify(updateMetadata));
          
          navigate(`/proposals/create/service-description`);
        } catch (err: any) {
          let errorMessage = 'Failed to load document';
          if (err.response?.data?.detail) {
            const detail = err.response.data.detail;
            errorMessage += `: ${typeof detail === 'string' ? detail : JSON.stringify(detail)}`;
          } else if (err.message) {
            errorMessage += `: ${err.message}`;
          } else if (err.response?.data?.message) {
            errorMessage += `: ${err.response.data.message}`;
          }
          console.error('Error loading document:', err);
          setError(errorMessage);
          setLoading(false);
          return;
        }
      } else if (flowType === 'create') {
        // Get user name for owner and last_edited_by (use Entra ID user profile)
        const userName = user?.name || '';
        
        // Create folder and metadata
        await sharepointApi.createFolder({
          service_name: createData.service,
          lot: createData.lot!,
          gcloud_version: '15',
        });

        // Use SSO user's display name as owner (from Entra ID)
        await sharepointApi.createMetadata({
          service_name: createData.service,
          owner: userName, // Use SSO user's Entra ID display name
          sponsor: createData.sponsor,
          lot: createData.lot!,
          gcloud_version: '15',
          last_edited_by: userName,
        });
        
        // Update createData to use SSO user's name as owner
        createData.owner = userName;

        // Check if we have existing content to load (from change metadata flow)
        const existingContent = sessionStorage.getItem('existingProposalContent');
        if (existingContent) {
          // Load existing content into updateDocument for the form
          const contentData = JSON.parse(existingContent);
          sessionStorage.setItem('updateDocument', JSON.stringify({
            ...contentData.metadata,
            content: contentData.content,
            _timestamp: Date.now(),
          }));
          sessionStorage.removeItem('existingProposalContent');
        } else {
          // Clear any previous proposal data for security
          sessionStorage.removeItem('updateDocument');
          sessionStorage.removeItem('updateMetadata');
        }
        
        // Store creation data for document generation
        sessionStorage.setItem('newProposal', JSON.stringify(createData));

        // Redirect to service description form
        navigate(`/proposals/create/service-description`);
      }
    } catch (err: any) {
      setError(err.response?.data?.detail || 'An error occurred. Please try again.');
      setLoading(false);
    }
  };

  const renderStepContent = () => {
    switch (activeStep) {
      case 0:
        return (
          <Box>
            <Alert severity="info" sx={{ mb: 3 }}>
              <Typography variant="body2" component="div">
                <strong>Workflow Steps:</strong>
                <ol style={{ margin: '8px 0', paddingLeft: '20px' }}>
                  <li>Create New or Update existing proposal</li>
                  <li>Complete Service Description document</li>
                  <li>Generate documents (Word & PDF)</li>
                  <li>Complete G-Cloud Capabilities Questionnaire</li>
                </ol>
              </Typography>
            </Alert>
            <FormControl component="fieldset" fullWidth>
              <FormLabel component="legend" sx={{ mb: 2, fontWeight: 600 }}>
                Are you updating or creating new?
              </FormLabel>
              <RadioGroup
                value={flowType || ''}
                onChange={(e) => {
                  setFlowType(e.target.value as FlowType);
                  setError('');
                }}
              >
                <FormControlLabel
                  value="update"
                  control={<Radio />}
                  label={
                    <Box display="flex" alignItems="center" gap={1}>
                      <Update />
                      <Typography>Updating existing proposal</Typography>
                    </Box>
                  }
                />
                <FormControlLabel
                  value="create"
                  control={<Radio />}
                  label={
                    <Box display="flex" alignItems="center" gap={1}>
                      <Add />
                      <Typography>Creating new proposal</Typography>
                    </Box>
                  }
                />
              </RadioGroup>
            </FormControl>
          </Box>
        );

      case 1:
        if (flowType === 'update') {
          return (
            <Box>
              <FormControl fullWidth sx={{ mb: 2 }}>
                <FormLabel component="legend" sx={{ mb: 2, fontWeight: 600 }}>
                  Are you updating a Service Description or Pricing Document?
                </FormLabel>
                <RadioGroup
                  value={docType || ''}
                  onChange={(e) => {
                    setDocType(e.target.value as DocType);
                    setError('');
                  }}
                >
                  <FormControlLabel
                    value="SERVICE DESC"
                    control={<Radio />}
                    label={
                      <Box display="flex" alignItems="center" gap={1}>
                        <Description />
                        <Typography>Service Description</Typography>
                      </Box>
                    }
                  />
                  <FormControlLabel
                    value="Pricing Doc"
                    control={<Radio />}
                    label={
                      <Box display="flex" alignItems="center" gap={1}>
                        <AttachMoney />
                        <Typography>Pricing Document</Typography>
                      </Box>
                    }
                  />
                </RadioGroup>
              </FormControl>

              {docType && (
                <Box>
                  <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
                    Enter the name of the service you are updating:
                  </Typography>
                  <SharePointSearch
                    query={searchQuery}
                    onChange={setSearchQuery}
                    onSelect={handleSelectResult}
                    docType={docType}
                    gcloudVersion="14"
                    placeholder="Type service name (e.g., Test Title, Agile Test Title)"
                    label="Search Service"
                  />
                  {selectedResult && (
                    <Alert severity="success" sx={{ mt: 2 }}>
                      Selected: {selectedResult.service_name} | OWNER: {selectedResult.owner}
                    </Alert>
                  )}
                </Box>
              )}
            </Box>
          );
        } else {
          return (
            <Box>
              <Typography variant="body2" color="text.secondary" sx={{ mb: 3 }}>
                Enter the proposal details:
              </Typography>
              <TextField
                fullWidth
                label="SERVICE"
                value={createData.service}
                onChange={(e) => setCreateData({ ...createData, service: e.target.value })}
                placeholder="e.g., Test Title"
                sx={{ mb: 2 }}
                required
                helperText="Service name (will be used for folder name)"
              />
              <TextField
                fullWidth
                label="OWNER"
                value={createData.owner}
                onChange={(e) => setCreateData({ ...createData, owner: e.target.value })}
                placeholder="First name Last name"
                sx={{ mb: 2 }}
                required
                helperText="Owner name (First name Last name)"
              />
              <TextField
                fullWidth
                label="SPONSOR"
                value={createData.sponsor}
                onChange={(e) => setCreateData({ ...createData, sponsor: e.target.value })}
                placeholder="First name Last name"
                sx={{ mb: 2 }}
                required
                helperText="Sponsor name (First name Last name)"
              />
              <FormControl fullWidth>
                <FormLabel component="legend" sx={{ mb: 1, fontWeight: 600 }}>
                  Which LOT is this proposal for?
                </FormLabel>
                <RadioGroup
                  value={createData.lot || ''}
                  onChange={(e) => setCreateData({ ...createData, lot: e.target.value as LotType })}
                >
                  <FormControlLabel value="2a" control={<Radio />} label="Cloud Support Services LOT 2a (IaaS and PaaS)" />
                  <FormControlLabel value="2b" control={<Radio />} label="Cloud Support Services LOT 2b (SaaS)" />
                  <FormControlLabel value="3" control={<Radio />} label="Cloud Support Services LOT 3" />
                </RadioGroup>
              </FormControl>
            </Box>
          );
        }

      case 2:
        return (
          <Box>
            <Typography variant="h6" gutterBottom>
              Confirm Details
            </Typography>
            {flowType === 'update' && selectedResult ? (
              <Box>
                <Typography variant="body1" paragraph>
                  <strong>Flow Type:</strong> Update Existing
                </Typography>
                <Typography variant="body1" paragraph>
                  <strong>Document Type:</strong> {selectedResult.doc_type}
                </Typography>
                <Typography variant="body1" paragraph>
                  <strong>Service Name:</strong> {selectedResult.service_name}
                </Typography>
                <Typography variant="body1" paragraph>
                  <strong>Owner:</strong> {selectedResult.owner}
                </Typography>
                <Typography variant="body1" paragraph>
                  <strong>LOT:</strong> {selectedResult.lot}
                </Typography>
              </Box>
            ) : (
              <Box>
                <Typography variant="body1" paragraph>
                  <strong>Flow Type:</strong> Create New
                </Typography>
                <Typography variant="body1" paragraph>
                  <strong>Service:</strong> {createData.service}
                </Typography>
                <Typography variant="body1" paragraph>
                  <strong>Owner:</strong> {createData.owner}
                </Typography>
                <Typography variant="body1" paragraph>
                  <strong>Sponsor:</strong> {createData.sponsor}
                </Typography>
                <Typography variant="body1" paragraph>
                  <strong>LOT:</strong> {createData.lot}
                </Typography>
                <Typography variant="body1" paragraph>
                  <strong>GCloud Version:</strong> 15 (New Proposal)
                </Typography>
              </Box>
            )}
          </Box>
        );

      default:
        return null;
    }
  };

  return (
    <Container maxWidth="md" sx={{ mt: 4, mb: 4 }}>
      <Card>
        <CardContent sx={{ p: 4 }}>
          <Box display="flex" alignItems="center" gap={2} mb={4}>
            <Button startIcon={<ArrowBack />} onClick={() => navigate('/proposals')}>
              Back
            </Button>
            <Typography variant="h5" component="h1" sx={{ flex: 1 }}>
              Proposal Workflow
            </Typography>
            <Button
              variant="outlined"
              startIcon={<Dashboard />}
              onClick={() => navigate('/proposals')}
            >
              Visit your dashboard
            </Button>
          </Box>

          <Stepper activeStep={activeStep} sx={{ mb: 4 }}>
            {steps.map((label) => (
              <Step key={label}>
                <StepLabel>{label}</StepLabel>
              </Step>
            ))}
          </Stepper>

          {error && (
            <Alert severity="error" sx={{ mb: 3 }}>
              {error}
            </Alert>
          )}

          <Box sx={{ mb: 4, minHeight: 300 }}>{renderStepContent()}</Box>

          <Box display="flex" justifyContent="space-between">
            <Button
              disabled={activeStep === 0 || loading}
              onClick={handleBack}
              startIcon={<ArrowBack />}
            >
              Back
            </Button>
            <Button
              variant="contained"
              onClick={handleNext}
              disabled={loading}
              endIcon={loading ? <CircularProgress size={20} /> : <ArrowForward />}
            >
              {activeStep === steps.length - 1 ? 'Proceed' : 'Next'}
            </Button>
          </Box>
        </CardContent>
      </Card>

      {/* Change Metadata Dialog */}
      <Dialog
        open={changeMetadataDialogOpen}
        onClose={() => setChangeMetadataDialogOpen(false)}
        aria-labelledby="change-metadata-dialog-title"
        aria-describedby="change-metadata-dialog-description"
      >
        <DialogTitle id="change-metadata-dialog-title">
          Change Proposal Metadata?
        </DialogTitle>
        <DialogContent>
          <DialogContentText id="change-metadata-dialog-description">
            This proposal belongs to another owner ({pendingUpdateContent?.metadata?.owner}). 
            Would you like to change the SERVICE, OWNER, or SPONSOR? 
            This will create a new proposal with the existing content, and you can update the metadata.
          </DialogContentText>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => {
            // User chose to continue as update - proceed with normal update flow
            if (pendingUpdateContent) {
              const updateMetadata = pendingUpdateContent.metadata;
              sessionStorage.setItem('updateDocument', JSON.stringify({
                ...updateMetadata,
                content: pendingUpdateContent.content,
                _timestamp: Date.now(),
              }));
              sessionStorage.setItem('updateMetadata', JSON.stringify(updateMetadata));
              setChangeMetadataDialogOpen(false);
              navigate('/proposals/create/service-description');
            }
          }} color="secondary">
            No, Continue as Update
          </Button>
          <Button 
            onClick={() => {
              // Store existing content for create flow
              sessionStorage.setItem('existingProposalContent', JSON.stringify(pendingUpdateContent));
              setChangeMetadataDialogOpen(false);
              // Navigate to create flow with existing content
              navigate('/proposals/flow?type=create');
            }} 
            color="primary" 
            variant="contained" 
            autoFocus
          >
            Yes, Change Metadata
          </Button>
        </DialogActions>
      </Dialog>
    </Container>
  );
}

