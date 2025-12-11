/**
 * SharePoint search component with live suggestions
 * Shows results as user types with "Service Name | OWNER" format
 */

import { useState, useEffect, useRef } from 'react';
import {
  TextField,
  Box,
  List,
  ListItem,
  ListItemButton,
  ListItemText,
  Typography,
  CircularProgress,
  Paper,
} from '@mui/material';
import { Search as SearchIcon } from '@mui/icons-material';
import sharepointApi, { SearchResult } from '../services/sharepointApi';

interface SharePointSearchProps {
  query: string;
  onChange: (query: string) => void;
  onSelect: (result: SearchResult) => void;
  docType?: 'SERVICE DESC' | 'Pricing Doc';
  gcloudVersion?: '14' | '15';
  placeholder?: string;
  label?: string;
}

export default function SharePointSearch({
  query,
  onChange,
  onSelect,
  docType,
  gcloudVersion = '14',
  placeholder = 'Start typing service name...',
  label = 'Search Service',
}: SharePointSearchProps) {
  const [results, setResults] = useState<SearchResult[]>([]);
  const [loading, setLoading] = useState(false);
  const [showResults, setShowResults] = useState(false);
  const searchTimeoutRef = useRef<number | null>(null);
  const containerRef = useRef<HTMLDivElement>(null);

  // Debounced search
  useEffect(() => {
    // Clear previous timeout
    if (searchTimeoutRef.current) {
      window.clearTimeout(searchTimeoutRef.current);
    }

    // Don't search if query is too short
    if (query.trim().length < 2) {
      setResults([]);
      setShowResults(false);
      return;
    }

    // Set loading state
    setLoading(true);
    setShowResults(true);

    // Debounce search
    searchTimeoutRef.current = window.setTimeout(async () => {
      try {
        const searchResults = await sharepointApi.searchDocuments({
          query: query.trim(),
          doc_type: docType,
          gcloud_version: gcloudVersion,
          search_all_versions: true, // Search both GCloud 14 and 15
        });
        setResults(searchResults);
      } catch (error) {
        console.error('Search error:', error);
        setResults([]);
      } finally {
        setLoading(false);
      }
    }, 300); // 300ms debounce

    // Cleanup
    return () => {
      if (searchTimeoutRef.current) {
        window.clearTimeout(searchTimeoutRef.current);
      }
    };
  }, [query, docType, gcloudVersion]);

  // Close results when clicking outside
  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (containerRef.current && !containerRef.current.contains(event.target as Node)) {
        setShowResults(false);
      }
    };

    document.addEventListener('mousedown', handleClickOutside);
    return () => {
      document.removeEventListener('mousedown', handleClickOutside);
    };
  }, []);

  const handleSelect = (result: SearchResult) => {
    onSelect(result);
    setShowResults(false);
  };

  return (
    <Box ref={containerRef} sx={{ position: 'relative', width: '100%' }}>
      <TextField
        fullWidth
        label={label}
        value={query}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        InputProps={{
          startAdornment: <SearchIcon sx={{ mr: 1, color: 'text.secondary' }} />,
        }}
        onFocus={() => query.trim().length >= 2 && setShowResults(true)}
      />

      {showResults && query.trim().length >= 2 && (
        <Paper
          elevation={4}
          sx={{
            position: 'absolute',
            top: '100%',
            left: 0,
            right: 0,
            zIndex: 1000,
            mt: 0.5,
            maxHeight: 300,
            overflow: 'auto',
          }}
        >
          {loading ? (
            <Box display="flex" justifyContent="center" alignItems="center" p={3}>
              <CircularProgress size={24} />
            </Box>
          ) : results.length > 0 ? (
            <List dense>
              {results.map((result, index) => (
                <ListItem key={index} disablePadding>
                  <ListItemButton onClick={() => handleSelect(result)}>
                    <ListItemText
                      primary={result.service_name}
                      secondary={`OWNER: ${result.owner} | LOT ${result.lot} | ${result.doc_type}`}
                      primaryTypographyProps={{
                        fontWeight: 500,
                      }}
                    />
                  </ListItemButton>
                </ListItem>
              ))}
            </List>
          ) : (
            <Box p={3}>
              <Typography variant="body2" color="text.secondary" align="center">
                No results found
              </Typography>
            </Box>
          )}
        </Paper>
      )}
    </Box>
  );
}

