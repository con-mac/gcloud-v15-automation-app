# Multi-stage build for React application

# Stage 1: Build
FROM node:20-alpine AS builder

WORKDIR /app

# Accept build arguments for SSO and API configuration
ARG VITE_AZURE_AD_TENANT_ID
ARG VITE_AZURE_AD_CLIENT_ID
ARG VITE_AZURE_AD_REDIRECT_URI
ARG VITE_AZURE_AD_ADMIN_GROUP_ID
ARG VITE_API_BASE_URL

# Set as environment variables so Vite can access them during build
ENV VITE_AZURE_AD_TENANT_ID=$VITE_AZURE_AD_TENANT_ID
ENV VITE_AZURE_AD_CLIENT_ID=$VITE_AZURE_AD_CLIENT_ID
ENV VITE_AZURE_AD_REDIRECT_URI=$VITE_AZURE_AD_REDIRECT_URI
ENV VITE_AZURE_AD_ADMIN_GROUP_ID=$VITE_AZURE_AD_ADMIN_GROUP_ID
ENV VITE_API_BASE_URL=$VITE_API_BASE_URL

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm install

# Copy source code
COPY . .

# Build the application (Vite will embed the env vars)
RUN npm run build

# Stage 2: Production
FROM nginx:alpine

# Install sed for entrypoint script
RUN apk add --no-cache sed

# Copy custom nginx config
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copy built assets from builder
COPY --from=builder /app/dist /usr/share/nginx/html

# Expose port
EXPOSE 80

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD wget --quiet --tries=1 --spider http://localhost/ || exit 1

# Start nginx - SSO config is baked into the build via build-time ARG/ENV
# The build-and-push-images.ps1 script passes SSO values as --build-arg
# which get embedded into the Vite build output during npm run build
CMD ["nginx", "-g", "daemon off;"]

