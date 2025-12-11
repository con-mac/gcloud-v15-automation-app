/**
 * PA Consulting-inspired Material-UI theme
 * Based on https://www.paconsulting.com/ design language
 */

import { createTheme } from '@mui/material/styles';

const theme = createTheme({
  palette: {
    primary: {
      main: '#003DA5',      // PA Consulting deep blue
      light: '#0066CC',     // Brighter blue for accents
      dark: '#002870',      // Darker shade for hover states
      contrastText: '#ffffff',
    },
    secondary: {
      main: '#0066CC',
      light: '#3399FF',
      dark: '#004C99',
      contrastText: '#ffffff',
    },
    success: {
      main: '#28A745',
      light: '#5CB85C',
      dark: '#1E7E34',
    },
    warning: {
      main: '#FFC107',
      light: '#FFD54F',
      dark: '#FFA000',
    },
    error: {
      main: '#DC3545',
      light: '#E57373',
      dark: '#C82333',
    },
    background: {
      default: '#F5F7FA',   // Light professional grey
      paper: '#FFFFFF',
    },
    text: {
      primary: '#333333',
      secondary: '#666666',
    },
    divider: '#E0E0E0',
  },
  typography: {
    fontFamily: [
      '-apple-system',
      'BlinkMacSystemFont',
      '"Segoe UI"',
      'Roboto',
      '"Helvetica Neue"',
      'Arial',
      'sans-serif',
    ].join(','),
    h1: {
      fontSize: '2.75rem',
      fontWeight: 700,
      lineHeight: 1.2,
      letterSpacing: '-0.02em',
      color: '#333333',
    },
    h2: {
      fontSize: '2.25rem',
      fontWeight: 700,
      lineHeight: 1.3,
      letterSpacing: '-0.01em',
      color: '#333333',
    },
    h3: {
      fontSize: '1.875rem',
      fontWeight: 600,
      lineHeight: 1.4,
      color: '#333333',
    },
    h4: {
      fontSize: '1.5rem',
      fontWeight: 600,
      lineHeight: 1.4,
      color: '#333333',
    },
    h5: {
      fontSize: '1.25rem',
      fontWeight: 600,
      lineHeight: 1.5,
      color: '#333333',
    },
    h6: {
      fontSize: '1rem',
      fontWeight: 600,
      lineHeight: 1.5,
      color: '#333333',
    },
    body1: {
      fontSize: '1rem',
      lineHeight: 1.6,
      color: '#333333',
    },
    body2: {
      fontSize: '0.875rem',
      lineHeight: 1.6,
      color: '#666666',
    },
  },
  shape: {
    borderRadius: 8,
  },
  shadows: [
    'none',
    '0 2px 4px rgba(0,0,0,0.08)',
    '0 4px 8px rgba(0,0,0,0.10)',
    '0 8px 16px rgba(0,0,0,0.12)',
    '0 12px 24px rgba(0,0,0,0.14)',
    '0 16px 32px rgba(0,0,0,0.16)',
    '0 20px 40px rgba(0,0,0,0.18)',
    '0 24px 48px rgba(0,0,0,0.20)',
    '0 2px 4px rgba(0,0,0,0.08)',
    '0 2px 4px rgba(0,0,0,0.08)',
    '0 2px 4px rgba(0,0,0,0.08)',
    '0 2px 4px rgba(0,0,0,0.08)',
    '0 2px 4px rgba(0,0,0,0.08)',
    '0 2px 4px rgba(0,0,0,0.08)',
    '0 2px 4px rgba(0,0,0,0.08)',
    '0 2px 4px rgba(0,0,0,0.08)',
    '0 2px 4px rgba(0,0,0,0.08)',
    '0 2px 4px rgba(0,0,0,0.08)',
    '0 2px 4px rgba(0,0,0,0.08)',
    '0 2px 4px rgba(0,0,0,0.08)',
    '0 2px 4px rgba(0,0,0,0.08)',
    '0 2px 4px rgba(0,0,0,0.08)',
    '0 2px 4px rgba(0,0,0,0.08)',
    '0 2px 4px rgba(0,0,0,0.08)',
    '0 2px 4px rgba(0,0,0,0.08)',
  ],
  components: {
    MuiButton: {
      styleOverrides: {
        root: {
          textTransform: 'none',
          borderRadius: 6,
          fontWeight: 600,
          padding: '10px 24px',
          boxShadow: 'none',
          '&:hover': {
            boxShadow: '0 4px 12px rgba(0,61,165,0.2)',
          },
        },
        contained: {
          '&:hover': {
            boxShadow: '0 4px 12px rgba(0,61,165,0.3)',
          },
        },
      },
    },
    MuiCard: {
      styleOverrides: {
        root: {
          borderRadius: 12,
          boxShadow: '0 2px 8px rgba(0,0,0,0.08)',
          transition: 'box-shadow 0.3s ease-in-out, transform 0.3s ease-in-out',
          '&:hover': {
            boxShadow: '0 8px 24px rgba(0,0,0,0.12)',
            transform: 'translateY(-2px)',
          },
        },
      },
    },
    MuiTextField: {
      defaultProps: {
        variant: 'outlined',
      },
      styleOverrides: {
        root: {
          '& .MuiOutlinedInput-root': {
            '&:hover fieldset': {
              borderColor: '#0066CC',
            },
          },
        },
      },
    },
    MuiChip: {
      styleOverrides: {
        root: {
          fontWeight: 500,
          borderRadius: 6,
        },
      },
    },
    MuiLinearProgress: {
      styleOverrides: {
        root: {
          borderRadius: 4,
          height: 8,
        },
      },
    },
  },
});

export default theme;

