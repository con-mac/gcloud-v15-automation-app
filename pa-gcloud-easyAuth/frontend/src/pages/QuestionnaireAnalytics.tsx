/**
 * Questionnaire Analytics Dashboard
 * Shows visual analytics of questionnaire responses with drill-down functionality
 */

import { useEffect, useState } from 'react';
import {
  Container,
  Typography,
  Box,
  Card,
  CardContent,
  Grid,
  CircularProgress,
  Alert,
  Tabs,
  Tab,
  FormControl,
  InputLabel,
  Select,
  MenuItem,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  Button,
  List,
  ListItem,
  ListItemText,
  Chip,
  Paper,
  IconButton,
  Tooltip as MuiTooltip,
} from '@mui/material';
import {
  Lock as LockIcon,
} from '@mui/icons-material';
import questionnaireApi from '../services/questionnaireApi';
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
import analyticsApi, { AnalyticsSummary, ServiceStatus, DrillDownResponse } from '../services/analyticsApi';

const COLORS = ['#0088FE', '#00C49F', '#FFBB28', '#FF8042', '#8884d8', '#82ca9d', '#ffc658', '#ff7300'];

export default function QuestionnaireAnalytics() {
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [summary, setSummary] = useState<AnalyticsSummary | null>(null);
  const [servicesStatus, setServicesStatus] = useState<ServiceStatus[]>([]);
  const [selectedLot, setSelectedLot] = useState<string>('');
  const [selectedTab, setSelectedTab] = useState(0);
  const [drillDownOpen, setDrillDownOpen] = useState(false);
  const [drillDownData, setDrillDownData] = useState<DrillDownResponse | null>(null);
  const [loadingDrillDown, setLoadingDrillDown] = useState(false);
  const [seeding, setSeeding] = useState(false);

  useEffect(() => {
    loadAnalytics();
  }, [selectedLot]);

  const loadAnalytics = async () => {
    try {
      setLoading(true);
      setError(null);
      
      const [summaryData, servicesData] = await Promise.all([
        analyticsApi.getAnalyticsSummary(selectedLot || undefined),
        analyticsApi.getServicesStatus(selectedLot || undefined),
      ]);
      
      setSummary(summaryData);
      setServicesStatus(servicesData);
    } catch (err: any) {
      console.error('Failed to load analytics:', err);
      setError(err.response?.data?.detail || 'Failed to load analytics. Please try again.');
    } finally {
      setLoading(false);
    }
  };

  const handleDrillDown = async (sectionName: string, questionText: string) => {
    try {
      setLoadingDrillDown(true);
      const data = await analyticsApi.getDrillDown(
        sectionName,
        questionText,
        selectedLot || undefined
      );
      setDrillDownData(data);
      setDrillDownOpen(true);
    } catch (err: any) {
      console.error('Failed to load drill-down:', err);
      alert(`Failed to load drill-down: ${err.response?.data?.detail || err.message}`);
    } finally {
      setLoadingDrillDown(false);
    }
  };

  const handleLockService = async (service: ServiceStatus) => {
    if (!confirm(`Are you sure you want to lock the questionnaire for "${service.service_name}"? Once locked, it cannot be edited.`)) {
      return;
    }

    try {
      await questionnaireApi.lockQuestionnaire(service.service_name, service.lot, service.gcloud_version);
      alert(`Questionnaire for "${service.service_name}" has been locked successfully.`);
      // Reload analytics to reflect the change
      await loadAnalytics();
    } catch (err: any) {
      console.error('Failed to lock questionnaire:', err);
      alert(`Failed to lock questionnaire: ${err.response?.data?.detail || err.message}`);
    }
  };

  const handleSeedData = async () => {
    if (!confirm('This will create 5 sample questionnaire responses for testing. Continue?')) {
      return;
    }

    try {
      setSeeding(true);
      setError(null);
      const result = await analyticsApi.seedQuestionnaireData();
      
      if (result.success) {
        alert(`Successfully seeded ${result.succeeded} questionnaire responses!\n\nServices created:\n${result.results.map(r => `- ${r.service_name} (LOT ${r.lot}): ${r.status}`).join('\n')}`);
        // Reload analytics to show new data
        await loadAnalytics();
      } else {
        setError(`Seeding completed with errors: ${result.failed} failed`);
      }
    } catch (err: any) {
      console.error('Failed to seed data:', err);
      setError(err.response?.data?.detail || 'Failed to seed questionnaire data');
    } finally {
      setSeeding(false);
    }
  };

  if (loading) {
    return (
      <Box display="flex" justifyContent="center" alignItems="center" minHeight="80vh">
        <CircularProgress />
      </Box>
    );
  }

  if (error) {
    return (
      <Container maxWidth="xl" sx={{ py: 4 }}>
        <Alert severity="error">{error}</Alert>
      </Container>
    );
  }

  if (!summary) {
    return (
      <Container maxWidth="xl" sx={{ py: 4 }}>
        <Alert severity="info">No analytics data available.</Alert>
      </Container>
    );
  }

  return (
    <Container maxWidth="xl" sx={{ py: 4 }}>
      <Box mb={4} display="flex" justifyContent="space-between" alignItems="center">
        <Box>
          <Typography variant="h4" gutterBottom sx={{ fontWeight: 700 }}>
            Questionnaire Analytics
          </Typography>
          <Typography variant="body1" color="text.secondary">
            Visual analytics of questionnaire responses with drill-down functionality
          </Typography>
        </Box>
        <Box display="flex" gap={2} alignItems="center">
          <FormControl sx={{ minWidth: 200 }}>
            <InputLabel>Filter by LOT</InputLabel>
            <Select
              value={selectedLot}
              label="Filter by LOT"
              onChange={(e) => setSelectedLot(e.target.value)}
            >
              <MenuItem value="">All LOTs</MenuItem>
              <MenuItem value="2a">LOT 2a</MenuItem>
              <MenuItem value="2b">LOT 2b</MenuItem>
              <MenuItem value="3">LOT 3</MenuItem>
            </Select>
          </FormControl>
          <Button
            variant="outlined"
            color="secondary"
            onClick={handleSeedData}
            disabled={seeding}
            startIcon={seeding ? <CircularProgress size={20} /> : undefined}
          >
            {seeding ? 'Seeding...' : 'Seed Test Data'}
          </Button>
        </Box>
      </Box>

      {/* Summary Cards */}
      <Grid container spacing={3} sx={{ mb: 4 }}>
        <Grid item xs={12} sm={6} md={3}>
          <Card>
            <CardContent>
              <Typography variant="h4" gutterBottom>
                {summary.total_services}
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
                {summary.services_with_responses}
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
                {summary.services_without_responses}
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
              <Typography variant="h4" gutterBottom color="info.main">
                {summary.services_locked}
              </Typography>
              <Typography variant="body2" color="text.secondary">
                Completed & Locked
              </Typography>
            </CardContent>
          </Card>
        </Grid>
      </Grid>

      {/* LOT Breakdown Chart */}
      {Object.keys(summary.lot_breakdown).length > 0 && (
        <Card sx={{ mb: 4 }}>
          <CardContent>
            <Typography variant="h5" gutterBottom>
              Services by LOT
            </Typography>
            <ResponsiveContainer width="100%" height={300}>
              <BarChart data={Object.entries(summary.lot_breakdown).map(([lot, count]) => ({ lot, count }))}>
                <CartesianGrid strokeDasharray="3 3" />
                <XAxis dataKey="lot" />
                <YAxis />
                <Tooltip />
                <Legend />
                <Bar dataKey="count" fill="#8884d8" />
              </BarChart>
            </ResponsiveContainer>
          </CardContent>
        </Card>
      )}

      {/* Tabs for Overview and Services */}
      <Card>
        <Tabs value={selectedTab} onChange={(_, newValue) => setSelectedTab(newValue)}>
          <Tab label="Question Analytics" />
          <Tab label="Services Status" />
        </Tabs>

        {/* Question Analytics Tab */}
        {selectedTab === 0 && (
          <CardContent>
            {summary.sections.length === 0 ? (
              <Alert severity="info">No questionnaire data available.</Alert>
            ) : (
              summary.sections.map((section) => (
                <Box key={section.section_name} sx={{ mb: 4 }}>
                  <Typography variant="h6" gutterBottom sx={{ mt: 2 }}>
                    {section.section_name}
                  </Typography>
                  <Typography variant="body2" color="text.secondary" gutterBottom>
                    {section.completed_services} services completed • {section.total_questions} questions
                  </Typography>

                  {section.questions.map((question, qIdx) => {
                    // Prepare chart data
                    const chartData = Object.entries(question.answer_counts).map(([answer, count]) => ({
                      answer: answer.length > 30 ? answer.substring(0, 30) + '...' : answer,
                      count,
                      fullAnswer: answer,
                    }));

                    if (chartData.length === 0) {
                      return (
                        <Paper key={qIdx} sx={{ p: 2, mb: 2 }}>
                          <Typography variant="body2" color="text.secondary">
                            {question.question_text} - No responses yet
                          </Typography>
                        </Paper>
                      );
                    }

                    return (
                      <Card key={qIdx} sx={{ mb: 2 }}>
                        <CardContent>
                          <Box display="flex" justifyContent="space-between" alignItems="center" mb={2}>
                            <Typography variant="subtitle1" fontWeight="bold">
                              {question.question_text}
                            </Typography>
                            <Chip
                              label={question.question_type}
                              size="small"
                              color="primary"
                              variant="outlined"
                            />
                          </Box>
                          <Typography variant="body2" color="text.secondary" gutterBottom>
                            Total responses: {question.total_responses}
                          </Typography>

                          <Box sx={{ mt: 2 }}>
                            {chartData.length <= 5 ? (
                              // Pie chart for small number of options
                              <ResponsiveContainer width="100%" height={300}>
                                <PieChart>
                                  <Pie
                                    data={chartData}
                                    dataKey="count"
                                    nameKey="answer"
                                    cx="50%"
                                    cy="50%"
                                    outerRadius={100}
                                    label={(entry: any) => `${entry.answer}: ${entry.count}`}
                                  >
                                    {chartData.map((_, index) => (
                                      <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} />
                                    ))}
                                  </Pie>
                                  <Tooltip />
                                </PieChart>
                              </ResponsiveContainer>
                            ) : (
                              // Bar chart for many options
                              <ResponsiveContainer width="100%" height={300}>
                                <BarChart data={chartData}>
                                  <CartesianGrid strokeDasharray="3 3" />
                                  <XAxis dataKey="answer" angle={-45} textAnchor="end" height={100} />
                                  <YAxis />
                                  <Tooltip />
                                  <Bar dataKey="count" fill="#8884d8" />
                                </BarChart>
                              </ResponsiveContainer>
                            )}
                          </Box>

                          <Button
                            variant="outlined"
                            size="small"
                            onClick={() => handleDrillDown(section.section_name, question.question_text)}
                            sx={{ mt: 2 }}
                          >
                            Drill Down
                          </Button>
                        </CardContent>
                      </Card>
                    );
                  })}
                </Box>
              ))
            )}
          </CardContent>
        )}

        {/* Services Status Tab */}
        {selectedTab === 1 && (
          <CardContent>
            <Grid container spacing={2}>
              <Grid item xs={12} md={6}>
                <Typography variant="h6" gutterBottom>
                  Services with Responses ({servicesStatus.filter(s => s.has_responses).length})
                </Typography>
                <List>
                  {servicesStatus
                    .filter(s => s.has_responses)
                    .map((service) => (
                      <ListItem 
                        key={service.service_name}
                        secondaryAction={
                          !service.is_locked ? (
                            <MuiTooltip title="Lock Questionnaire">
                              <IconButton
                                edge="end"
                                onClick={() => handleLockService(service)}
                                color="warning"
                              >
                                <LockIcon />
                              </IconButton>
                            </MuiTooltip>
                          ) : (
                            <MuiTooltip title="Questionnaire is locked">
                              <LockIcon color="success" />
                            </MuiTooltip>
                          )
                        }
                      >
                        <ListItemText
                          primary={service.service_name}
                          secondary={
                            <Box>
                              <Chip label={`LOT ${service.lot}`} size="small" sx={{ mr: 1 }} />
                              <Chip
                                label={service.is_locked ? 'Locked' : service.is_draft ? 'Draft' : 'Completed'}
                                size="small"
                                color={service.is_locked ? 'success' : service.is_draft ? 'warning' : 'info'}
                                sx={{ mr: 1 }}
                              />
                              <Typography variant="caption" color="text.secondary">
                                {service.completion_percentage.toFixed(0)}% complete
                              </Typography>
                            </Box>
                          }
                        />
                      </ListItem>
                    ))}
                </List>
              </Grid>
              <Grid item xs={12} md={6}>
                <Typography variant="h6" gutterBottom color="warning.main">
                  Services Not Started ({servicesStatus.filter(s => !s.has_responses).length})
                </Typography>
                <List>
                  {servicesStatus
                    .filter(s => !s.has_responses)
                    .map((service) => (
                      <ListItem key={service.service_name}>
                        <ListItemText
                          primary={service.service_name}
                          secondary={
                            <Chip label={`LOT ${service.lot}`} size="small" />
                          }
                        />
                      </ListItem>
                    ))}
                </List>
              </Grid>
            </Grid>
          </CardContent>
        )}
      </Card>

      {/* Drill-Down Dialog */}
      <Dialog
        open={drillDownOpen}
        onClose={() => setDrillDownOpen(false)}
        maxWidth="md"
        fullWidth
      >
        <DialogTitle>
          {drillDownData?.section_name} - {drillDownData?.question_text}
        </DialogTitle>
        <DialogContent>
          {loadingDrillDown ? (
            <Box display="flex" justifyContent="center" p={4}>
              <CircularProgress />
            </Box>
          ) : drillDownData ? (
            <Box>
              <Typography variant="body2" color="text.secondary" gutterBottom>
                Total services: {drillDownData.total_services}
              </Typography>
              {Object.entries(drillDownData.breakdown).map(([answer, services]) => (
                <Box key={answer} sx={{ mb: 3 }}>
                  <Typography variant="subtitle1" fontWeight="bold" gutterBottom>
                    {answer} ({services.length} services)
                  </Typography>
                  <List dense>
                    {services.map((service, idx) => (
                      <ListItem key={idx}>
                        <ListItemText
                          primary={service.service_name}
                          secondary={`LOT ${service.lot}`}
                        />
                      </ListItem>
                    ))}
                  </List>
                </Box>
              ))}
            </Box>
          ) : null}
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setDrillDownOpen(false)}>Close</Button>
        </DialogActions>
      </Dialog>
    </Container>
  );
}

