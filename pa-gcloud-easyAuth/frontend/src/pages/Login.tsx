/**
 * Login page with email validation for PA Consulting employees
 * Validates @paconsulting.com domain
 */

import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '../contexts/EasyAuthContext';
import {
  Container,
  Box,
  Card,
  CardContent,
  Button,
  Typography,
  Alert,
} from '@mui/material';
import { Login as LoginIcon } from '@mui/icons-material';

export default function Login() {
  const navigate = useNavigate();
  const { login, isAuthenticated, user } = useAuth();
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  // Redirect if already authenticated - automatically based on security group membership
  useEffect(() => {
    if (isAuthenticated && user) {
      // Access is determined automatically by security group membership
      // Admin group members get admin dashboard, others get standard employee view
      if (user.isAdmin) {
        navigate('/admin/dashboard');
      } else {
        navigate('/proposals');
      }
    }
  }, [isAuthenticated, user, navigate]);

  // Easy Auth handles authentication - just redirect to login endpoint
  const handleSubmit = (e?: React.FormEvent) => {
    if (e) {
      e.preventDefault();
    }
    setError('');
    setLoading(true);

    // Easy Auth login redirects to /.auth/login/aad
    // Navigation will happen automatically via useEffect when user is authenticated
    // based on their security group membership (admin vs employee)
    login();
    // Note: login() redirects immediately, so setLoading(false) won't execute
  };

  // Check if Easy Auth is configured (has API base URL)
  // Easy Auth is configured at the Function App level, so we just need the API URL
  const runtimeConfig = (window as any).__ENV__;
  const apiBaseUrl = runtimeConfig?.VITE_API_BASE_URL || import.meta.env.VITE_API_BASE_URL || '';
  const isSSOConfigured = apiBaseUrl && apiBaseUrl.trim() !== '';

  return (
    <Container maxWidth="sm" sx={{ mt: 8 }}>
      <Card>
        <CardContent sx={{ p: 4 }}>
          <Box display="flex" flexDirection="column" alignItems="center" mb={3}>
            <LoginIcon sx={{ fontSize: 48, color: 'primary.main', mb: 2 }} />
            <Typography variant="h4" component="h1" gutterBottom>
              G-Cloud Proposal System
            </Typography>
          </Box>

          {isSSOConfigured ? (
            // Easy Auth Login (Microsoft 365)
            // Access level (admin vs employee) is automatically determined by security group membership
            <Box>
              <Button
                fullWidth
                variant="contained"
                size="large"
                onClick={handleSubmit}
                disabled={loading}
                startIcon={<LoginIcon />}
                sx={{ mb: 2 }}
              >
                {loading ? 'Signing in...' : 'Sign in with Microsoft 365'}
              </Button>
              {error && (
                <Alert severity="error" sx={{ mb: 2 }}>
                  {error}
                </Alert>
              )}
            </Box>
          ) : (
            // Easy Auth not configured - show error message
            <Alert severity="warning" sx={{ mb: 2 }}>
              Easy Auth is not configured. Please run configure-easy-auth.ps1 to enable Microsoft 365 SSO.
              <br />
              Access level (admin vs employee) is automatically determined by your security group membership.
            </Alert>
          )}

          <Box mt={3}>
            <Typography variant="caption" color="text.secondary" align="center" display="block">
              {isSSOConfigured ? (
                <>
                  Sign in with your Microsoft 365 account (PA Consulting).
                  <br />
                  Your access level (admin dashboard or standard employee view) is automatically determined by your security group membership.
                  <br />
                  Admin group members will see the admin dashboard; all other users will see the standard employee interface.
                </>
              ) : (
                <>
                  Easy Auth is not configured. Please run configure-easy-auth.ps1 to enable Microsoft 365 SSO.
                </>
              )}
            </Typography>
          </Box>
        </CardContent>
      </Card>
    </Container>
  );
}

