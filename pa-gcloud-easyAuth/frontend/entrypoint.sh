#!/bin/sh
# Entrypoint script to inject runtime environment variables into the React app

INDEX_HTML="/usr/share/nginx/html/index.html"

# Check if index.html exists
if [ ! -f "$INDEX_HTML" ]; then
  echo "ERROR: index.html not found at $INDEX_HTML"
  echo "Contents of /usr/share/nginx/html:"
  ls -la /usr/share/nginx/html/ || true
  # Don't exit - let nginx start anyway to see what happens
fi

# Read environment variables from Azure App Service
CLIENT_ID="${VITE_AZURE_AD_CLIENT_ID:-}"
TENANT_ID="${VITE_AZURE_AD_TENANT_ID:-}"
REDIRECT_URI="${VITE_AZURE_AD_REDIRECT_URI:-}"
ADMIN_GROUP_ID="${VITE_AZURE_AD_ADMIN_GROUP_ID:-}"
API_BASE_URL="${VITE_API_BASE_URL:-}"
FUNCTION_KEY="${VITE_FUNCTION_KEY:-}"

echo "Injecting environment variables..."
echo "CLIENT_ID: ${CLIENT_ID:0:8}..."
echo "TENANT_ID: ${TENANT_ID:0:8}..."
echo "REDIRECT_URI: $REDIRECT_URI"
echo "API_BASE_URL: $API_BASE_URL"
if [ -n "$FUNCTION_KEY" ]; then
  echo "FUNCTION_KEY: ${FUNCTION_KEY:0:8}..."
fi

# Escape single quotes in values for JavaScript
escape_js() {
  echo "$1" | sed "s/'/\\\'/g"
}

CLIENT_ID_ESC=$(escape_js "$CLIENT_ID")
TENANT_ID_ESC=$(escape_js "$TENANT_ID")
REDIRECT_URI_ESC=$(escape_js "$REDIRECT_URI")
ADMIN_GROUP_ID_ESC=$(escape_js "$ADMIN_GROUP_ID")
API_BASE_URL_ESC=$(escape_js "$API_BASE_URL")
FUNCTION_KEY_ESC=$(escape_js "$FUNCTION_KEY")

# Create JavaScript config object (must be injected before </head>)
CONFIG_JS="window.__ENV__ = {
  VITE_AZURE_AD_CLIENT_ID: '${CLIENT_ID_ESC}',
  VITE_AZURE_AD_TENANT_ID: '${TENANT_ID_ESC}',
  VITE_AZURE_AD_REDIRECT_URI: '${REDIRECT_URI_ESC}',
  VITE_AZURE_AD_ADMIN_GROUP_ID: '${ADMIN_GROUP_ID_ESC}',
  VITE_API_BASE_URL: '${API_BASE_URL_ESC}',
  VITE_FUNCTION_KEY: '${FUNCTION_KEY_ESC}'
};"

# Inject config into index.html before </head> tag (only if file exists)
if [ -f "$INDEX_HTML" ]; then
  if grep -q "</head>" "$INDEX_HTML"; then
    sed -i "s|</head>|<script>${CONFIG_JS}</script></head>|" "$INDEX_HTML" 2>&1 || echo "WARNING: sed failed, continuing anyway"
    if grep -q "window.__ENV__" "$INDEX_HTML"; then
      echo "✓ Environment variables injected successfully"
    else
      echo "✗ WARNING: window.__ENV__ not found after injection, but continuing"
    fi
  else
    echo "✗ WARNING: Could not find </head> tag in index.html, but continuing"
  fi
else
  echo "✗ WARNING: index.html not found, starting nginx without injection"
fi

# Test nginx config (don't exit on failure, just warn)
echo "Testing nginx configuration..."
nginx -t 2>&1 || echo "WARNING: nginx config test failed, but continuing"

# Start nginx
echo "Starting nginx..."
exec nginx -g 'daemon off;'

