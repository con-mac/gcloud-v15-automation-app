/**
 * Admin Dashboard
 * Shows all proposals with metrics, read-only view, download, and message owner functionality
 */

import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Container,
  Typography,
  Box,
  Card,
  CardContent,
  Grid,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Paper,
  Chip,
  Button,
  CircularProgress,
  Alert,
  IconButton,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  TextField,
} from '@mui/material';
import {
  Visibility as ViewIcon,
  Download as DownloadIcon,
  Email as EmailIcon,
  CheckCircle as CheckIcon,
  Warning as WarningIcon,
  Error as ErrorIcon,
} from '@mui/icons-material';
import { proposalsService } from '../services/proposals';
import sharepointApi from '../services/sharepointApi';
import analyticsApi, { AnalyticsSummary } from '../services/analyticsApi';
import {
  BarChart,
  Bar,
  PieChart,
  Pie,
  Cell,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
  ResponsiveContainer,
} from 'recharts';

export default function AdminDashboard() {
  const navigate = useNavigate();
  const [proposals, setProposals] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [selectedProposal, setSelectedProposal] = useState<any>(null);
  const [viewDialogOpen, setViewDialogOpen] = useState(false);
  const [messageDialogOpen, setMessageDialogOpen] = useState(false);
  const [messageSubject, setMessageSubject] = useState('');
  const [messageBody, setMessageBody] = useState('');
  const [loadingDocument, setLoadingDocument] = useState(false);
  const [documentContent, setDocumentContent] = useState<any>(null);
  const [analyticsSummary, setAnalyticsSummary] = useState<AnalyticsSummary | null>(null);
  const [loadingAnalytics, setLoadingAnalytics] = useState(false);
  const [analyticsError, setAnalyticsError] = useState<string | null>(null);
  const [activeSectionIndex, setActiveSectionIndex] = useState<number | null>(null);

  useEffect(() => {
    loadProposals();
    loadAnalytics();
  }, []);

  const loadAnalytics = async () => {
    try {
      setLoadingAnalytics(true);
      setAnalyticsError(null);
      const summary = await analyticsApi.getAnalyticsSummary();
      setAnalyticsSummary(summary);
    } catch (err: any) {
      console.error('Failed to load analytics:', err);
      setAnalyticsError(err.response?.data?.detail || 'Failed to load analytics.');
    } finally {
      setLoadingAnalytics(false);
    }
  };

  // Drill-down functionality available for future enhancement
  // Currently charts navigate to full analytics page for detailed view

  const loadProposals = async () => {
    try {
      setLoading(true);
      const data = await proposalsService.getAllProposalsAdmin();
      setProposals(data);
      setError(null);
    } catch (error: any) {
      console.error('Failed to load proposals:', error);
      setError(error.message || 'Failed to load proposals. Please try again.');
    } finally {
      setLoading(false);
    }
  };

  const handleViewProposal = async (proposal: any) => {
    try {
      setLoadingDocument(true);
      setSelectedProposal(proposal);
      
      // Load document content
      const content = await sharepointApi.getDocumentContent(
        proposal.title,
        'SERVICE DESC',
        proposal.lot as '2' | '3',
        proposal.gcloud_version as '14' | '15'
      );
      
      setDocumentContent(content);
      setViewDialogOpen(true);
    } catch (error: any) {
      console.error('Failed to load proposal:', error);
      alert(`Failed to load proposal: ${error.response?.data?.detail || error.message}`);
    } finally {
      setLoadingDocument(false);
    }
  };

  const handleDownloadWord = async (proposal: any) => {
    try {
      const filename = `PA GC${proposal.gcloud_version} SERVICE DESC ${proposal.title}.docx`;
      const url = `/api/v1/templates/service-description/download/${encodeURIComponent(filename)}`;
      const fullUrl = `${import.meta.env.VITE_API_BASE_URL || 'http://localhost:8000'}${url}`;
      
      // Create a temporary link and click it
      const link = document.createElement('a');
      link.href = fullUrl;
      link.download = filename;
      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);
    } catch (error: any) {
      console.error('Failed to download Word document:', error);
      alert(`Failed to download Word document: ${error.message}`);
    }
  };

  const handleDownloadPDF = async (proposal: any) => {
    try {
      const filename = `PA GC${proposal.gcloud_version} SERVICE DESC ${proposal.title}.pdf`;
      const url = `/api/v1/templates/service-description/download/${encodeURIComponent(filename)}`;
      const fullUrl = `${import.meta.env.VITE_API_BASE_URL || 'http://localhost:8000'}${url}`;
      
      // Create a temporary link and click it
      const link = document.createElement('a');
      link.href = fullUrl;
      link.download = filename;
      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);
    } catch (error: any) {
      console.error('Failed to download PDF:', error);
      alert(`Failed to download PDF: ${error.message}`);
    }
  };

  const handleMessageOwner = (proposal: any) => {
    setSelectedProposal(proposal);
    setMessageSubject(`Regarding your G-Cloud ${proposal.gcloud_version} proposal: ${proposal.title}`);
    setMessageBody('');
    setMessageDialogOpen(true);
  };

  const handleSendMessage = () => {
    if (!selectedProposal || !messageBody.trim()) {
      alert('Please enter a message');
      return;
    }
    
    // Create mailto link
    const ownerEmail = `${selectedProposal.owner.replace(' ', '.')}@paconsulting.com`;
    const subject = encodeURIComponent(messageSubject);
    const body = encodeURIComponent(messageBody);
    const mailtoLink = `mailto:${ownerEmail}?subject=${subject}&body=${body}`;
    
    window.location.href = mailtoLink;
    setMessageDialogOpen(false);
    setMessageSubject('');
    setMessageBody('');
  };

  const formatDate = (dateString: string | null) => {
    if (!dateString) return 'N/A';
    try {
      const date = new Date(dateString);
      return date.toLocaleDateString('en-GB', {
        year: 'numeric',
        month: 'short',
        day: 'numeric',
        hour: '2-digit',
        minute: '2-digit',
      });
    } catch {
      return 'N/A';
    }
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'complete':
        return 'success';
      case 'incomplete':
        return 'warning';
      case 'draft':
        return 'error';
      default:
        return 'default';
    }
  };

  const getStatusIcon = (status: string): React.ReactElement | undefined => {
    switch (status) {
      case 'complete':
        return <CheckIcon color="success" />;
      case 'incomplete':
        return <WarningIcon color="warning" />;
      case 'draft':
        return <ErrorIcon color="error" />;
      default:
        return undefined;
    }
  };

  // Calculate metrics
  const totalProposals = proposals.length;
  const completedProposals = proposals.filter(p => p.status === 'complete').length;
  const incompleteProposals = proposals.filter(p => p.status === 'incomplete' || p.status === 'draft').length;
  const completionRate = totalProposals > 0 ? (completedProposals / totalProposals) * 100 : 0;

  if (loading) {
    return (
      <Box display="flex" justifyContent="center" alignItems="center" minHeight="80vh">
        <CircularProgress />
      </Box>
    );
  }

  return (
    <Container maxWidth="xl" sx={{ py: 4 }}>
      <Box mb={4} display="flex" justifyContent="space-between" alignItems="center">
        <Box>
          <Typography variant="h3" gutterBottom sx={{ fontWeight: 700 }}>
            Admin Dashboard
          </Typography>
          <Typography variant="body1" color="text.secondary">
            Manage and monitor all G-Cloud proposals
          </Typography>
        </Box>
        <Box display="flex" gap={2}>
          <Button
            variant="contained"
            onClick={() => navigate('/admin/analytics')}
          >
            Questionnaire Analytics
          </Button>
          <Button
            variant="outlined"
            onClick={() => navigate('/login')}
          >
            Switch to Employee View
          </Button>
        </Box>
      </Box>

      {error && (
        <Alert severity="error" sx={{ mb: 3 }}>
          {error}
        </Alert>
      )}

      {/* Metrics Cards */}
      <Grid container spacing={3} sx={{ mb: 4 }}>
        <Grid item xs={12} sm={6} md={3}>
          <Card>
            <CardContent>
              <Typography variant="h4" gutterBottom>
                {totalProposals}
              </Typography>
              <Typography variant="body2" color="text.secondary">
                Total Proposals
              </Typography>
            </CardContent>
          </Card>
        </Grid>
        <Grid item xs={12} sm={6} md={3}>
          <Card>
            <CardContent>
              <Typography variant="h4" gutterBottom color="success.main">
                {completedProposals}
              </Typography>
              <Typography variant="body2" color="text.secondary">
                Completed
              </Typography>
            </CardContent>
          </Card>
        </Grid>
        <Grid item xs={12} sm={6} md={3}>
          <Card>
            <CardContent>
              <Typography variant="h4" gutterBottom color="warning.main">
                {incompleteProposals}
              </Typography>
              <Typography variant="body2" color="text.secondary">
                Incomplete
              </Typography>
            </CardContent>
          </Card>
        </Grid>
        <Grid item xs={12} sm={6} md={3}>
          <Card>
            <CardContent>
              <Typography variant="h4" gutterBottom>
                {completionRate.toFixed(1)}%
              </Typography>
              <Typography variant="body2" color="text.secondary">
                Completion Rate
              </Typography>
            </CardContent>
          </Card>
        </Grid>
      </Grid>

      {/* Analytics Widgets */}
      {analyticsSummary && (
        <Grid container spacing={3} sx={{ mb: 4 }}>
          <Grid item xs={12}>
            <Typography variant="h5" gutterBottom>
              Questionnaire Analytics
            </Typography>
          </Grid>
          
          {/* Summary Cards */}
          <Grid item xs={12} sm={6} md={3}>
            <Card>
              <CardContent>
                <Typography variant="h4" gutterBottom>
                  {analyticsSummary.total_services}
                </Typography>
                <Typography variant="body2" color="text.secondary">
                  Total Services
                </Typography>
              </CardContent>
            </Card>
          </Grid>
          <Grid item xs={12} sm={6} md={3}>
            <Card>
              <CardContent>
                <Typography variant="h4" gutterBottom color="success.main">
                  {analyticsSummary.services_with_responses}
                </Typography>
                <Typography variant="body2" color="text.secondary">
                  With Responses
                </Typography>
              </CardContent>
            </Card>
          </Grid>
          <Grid item xs={12} sm={6} md={3}>
            <Card>
              <CardContent>
                <Typography variant="h4" gutterBottom color="warning.main">
                  {analyticsSummary.services_without_responses}
                </Typography>
                <Typography variant="body2" color="text.secondary">
                  Not Started
                </Typography>
              </CardContent>
            </Card>
          </Grid>
          <Grid item xs={12} sm={6} md={3}>
            <Card>
              <CardContent>
                <Typography variant="h4" gutterBottom color="error.main">
                  {analyticsSummary.services_locked}
                </Typography>
                <Typography variant="body2" color="text.secondary">
                  Locked
                </Typography>
              </CardContent>
            </Card>
          </Grid>

          {/* LOT Breakdown Chart */}
          {analyticsSummary.lot_breakdown && Object.keys(analyticsSummary.lot_breakdown).length > 0 && (
            <Grid item xs={12} md={6}>
              <Card>
                <CardContent>
                  <Typography variant="h6" gutterBottom>
                    LOT Breakdown
                  </Typography>
                  <ResponsiveContainer width="100%" height={300}>
                    <BarChart data={Object.entries(analyticsSummary.lot_breakdown).map(([lot, count]) => ({ lot, count }))}>
                      <CartesianGrid strokeDasharray="3 3" />
                      <XAxis dataKey="lot" />
                      <YAxis />
                      <Tooltip 
                        contentStyle={{
                          backgroundColor: 'rgba(255, 255, 255, 0.95)',
                          border: '1px solid #ccc',
                          borderRadius: '4px',
                          padding: '8px',
                        }}
                      />
                      <Legend />
                      <Bar dataKey="count" fill="#0088FE" onClick={(data: any) => {
                        // Navigate to analytics page filtered by LOT
                        if (data && data.lot) {
                          navigate(`/admin/analytics?lot=${data.lot}`);
                        }
                      }} style={{ cursor: 'pointer' }} />
                    </BarChart>
                  </ResponsiveContainer>
                </CardContent>
              </Card>
            </Grid>
          )}

          {/* Service Categories Chart */}
          {analyticsSummary.sections && analyticsSummary.sections.length > 0 && (
            <Grid item xs={12} md={6}>
              <Card>
                <CardContent>
                  <Typography variant="h6" gutterBottom>
                    Service Categories
                  </Typography>
                  <ResponsiveContainer width="100%" height={400}>
                    <PieChart>
                      <Pie
                        data={analyticsSummary.sections.map((section) => ({
                          name: section.section_name,
                          value: section.completed_services || 0,
                        }))}
                        cx="50%"
                        cy="50%"
                        outerRadius={120}
                        fill="#8884d8"
                        dataKey="value"
                        onMouseEnter={(_: any, index: number) => {
                          setActiveSectionIndex(index);
                        }}
                        onMouseLeave={() => {
                          setActiveSectionIndex(null);
                        }}
                      >
                        {analyticsSummary.sections.map((_, index) => {
                          const isActive = activeSectionIndex === index;
                          const baseColor = ['#0088FE', '#00C49F', '#FFBB28', '#FF8042', '#8884d8', '#82ca9d', '#ffc658', '#ff7300'][index % 8];
                          return (
                            <Cell 
                              key={`cell-${index}`} 
                              fill={baseColor}
                              style={{
                                opacity: activeSectionIndex !== null && !isActive ? 0.5 : 1,
                                transition: 'opacity 0.3s ease',
                                cursor: 'pointer',
                              }}
                            />
                          );
                        })}
                      </Pie>
                      <Tooltip 
                        contentStyle={{
                          backgroundColor: 'rgba(255, 255, 255, 0.95)',
                          border: '1px solid #ccc',
                          borderRadius: '4px',
                          padding: '8px',
                        }}
                        formatter={(value: any, name: any) => [
                          `${value} services`,
                          name
                        ]}
                      />
                    </PieChart>
                  </ResponsiveContainer>
                </CardContent>
              </Card>
            </Grid>
          )}
        </Grid>
      )}

      {analyticsError && (
        <Alert severity="warning" sx={{ mb: 3 }}>
          Analytics: {analyticsError}
        </Alert>
      )}

      {loadingAnalytics && (
        <Box display="flex" justifyContent="center" p={2}>
          <CircularProgress size={24} />
        </Box>
      )}

      {/* Proposals Table */}
      <Card>
        <CardContent>
          <Typography variant="h5" gutterBottom sx={{ mb: 3 }}>
            All Proposals
          </Typography>
          <TableContainer component={Paper} variant="outlined">
            <Table>
              <TableHead>
                <TableRow>
                  <TableCell><strong>Service Name</strong></TableCell>
                  <TableCell><strong>Owner</strong></TableCell>
                  <TableCell><strong>Status</strong></TableCell>
                  <TableCell><strong>G-Cloud</strong></TableCell>
                  <TableCell><strong>LOT</strong></TableCell>
                  <TableCell><strong>Completion</strong></TableCell>
                  <TableCell><strong>Last Updated</strong></TableCell>
                  <TableCell><strong>Documents</strong></TableCell>
                  <TableCell><strong>Actions</strong></TableCell>
                </TableRow>
              </TableHead>
              <TableBody>
                {proposals.map((proposal) => (
                  <TableRow key={proposal.id}>
                    <TableCell>{proposal.title}</TableCell>
                    <TableCell>{proposal.owner}</TableCell>
                    <TableCell>
                      <Chip
                        label={proposal.status === 'complete' ? 'Complete' : proposal.status === 'incomplete' ? 'Incomplete' : 'Draft'}
                        color={getStatusColor(proposal.status) as any}
                        size="small"
                        icon={getStatusIcon(proposal.status) || undefined}
                      />
                    </TableCell>
                    <TableCell>G-Cloud {proposal.gcloud_version}</TableCell>
                    <TableCell>LOT {proposal.lot}</TableCell>
                    <TableCell>{Math.round(proposal.completion_percentage || 0)}%</TableCell>
                    <TableCell>{formatDate(proposal.last_update || proposal.updated_at)}</TableCell>
                    <TableCell>
                      {proposal.service_desc_exists ? '✓' : '✗'} Service Desc{' '}
                      {proposal.pricing_doc_exists ? '✓' : '✗'} Pricing
                    </TableCell>
                    <TableCell>
                      <Box display="flex" gap={1}>
                        <IconButton
                          size="small"
                          color="primary"
                          onClick={() => handleViewProposal(proposal)}
                          disabled={loadingDocument}
                          title="View Proposal"
                        >
                          <ViewIcon fontSize="small" />
                        </IconButton>
                        <IconButton
                          size="small"
                          color="primary"
                          onClick={() => handleDownloadWord(proposal)}
                          title="Download Word Document"
                        >
                          <DownloadIcon fontSize="small" />
                        </IconButton>
                        <IconButton
                          size="small"
                          color="primary"
                          onClick={() => handleDownloadPDF(proposal)}
                          title="Download PDF"
                        >
                          <DownloadIcon fontSize="small" />
                        </IconButton>
                        <IconButton
                          size="small"
                          color="primary"
                          onClick={() => handleMessageOwner(proposal)}
                          title="Message Owner"
                        >
                          <EmailIcon fontSize="small" />
                        </IconButton>
                      </Box>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </TableContainer>
        </CardContent>
      </Card>

      {/* View Proposal Dialog */}
      <Dialog
        open={viewDialogOpen}
        onClose={() => setViewDialogOpen(false)}
        maxWidth="md"
        fullWidth
      >
        <DialogTitle>
          View Proposal: {selectedProposal?.title}
        </DialogTitle>
        <DialogContent>
          {loadingDocument ? (
            <Box display="flex" justifyContent="center" p={4}>
              <CircularProgress />
            </Box>
          ) : documentContent ? (
            <Box>
              <Typography variant="h6" gutterBottom>Title</Typography>
              <Typography variant="body1" paragraph>{documentContent.title}</Typography>
              
              <Typography variant="h6" gutterBottom>Description</Typography>
              <Typography variant="body1" paragraph>{documentContent.description}</Typography>
              
              {documentContent.features && documentContent.features.length > 0 && (
                <>
                  <Typography variant="h6" gutterBottom>Features</Typography>
                  <ul>
                    {documentContent.features.map((feature: string, index: number) => (
                      <li key={index}>{feature}</li>
                    ))}
                  </ul>
                </>
              )}
              
              {documentContent.benefits && documentContent.benefits.length > 0 && (
                <>
                  <Typography variant="h6" gutterBottom>Benefits</Typography>
                  <ul>
                    {documentContent.benefits.map((benefit: string, index: number) => (
                      <li key={index}>{benefit}</li>
                    ))}
                  </ul>
                </>
              )}
              
              {documentContent.service_definition && documentContent.service_definition.length > 0 && (
                <>
                  <Typography variant="h6" gutterBottom>Service Definition</Typography>
                  {documentContent.service_definition.map((section: any, index: number) => (
                    <Box key={index} mb={2}>
                      <Typography variant="subtitle1" fontWeight="bold">{section.subtitle}</Typography>
                      <div dangerouslySetInnerHTML={{ __html: section.content }} />
                    </Box>
                  ))}
                </>
              )}
            </Box>
          ) : (
            <Typography>No content available</Typography>
          )}
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setViewDialogOpen(false)}>Close</Button>
        </DialogActions>
      </Dialog>

      {/* Message Owner Dialog */}
      <Dialog
        open={messageDialogOpen}
        onClose={() => setMessageDialogOpen(false)}
        maxWidth="sm"
        fullWidth
      >
        <DialogTitle>
          Message Owner: {selectedProposal?.owner}
        </DialogTitle>
        <DialogContent>
          <TextField
            fullWidth
            label="Subject"
            value={messageSubject}
            onChange={(e) => setMessageSubject(e.target.value)}
            margin="normal"
          />
          <TextField
            fullWidth
            label="Message"
            value={messageBody}
            onChange={(e) => setMessageBody(e.target.value)}
            margin="normal"
            multiline
            rows={6}
            required
          />
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setMessageDialogOpen(false)}>Cancel</Button>
          <Button onClick={handleSendMessage} variant="contained" color="primary">
            Send Email
          </Button>
        </DialogActions>
      </Dialog>

    </Container>
  );
}

