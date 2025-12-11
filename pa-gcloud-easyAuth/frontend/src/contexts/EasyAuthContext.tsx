/**
 * Authentication Context using Azure App Service Easy Auth
 * Handles authentication via Easy Auth endpoints
 */

import React, { createContext, useContext, useEffect, useState, ReactNode } from 'react';

interface User {
  email: string;
  name: string;
  isAdmin: boolean;
}

interface AuthContextType {
  user: User | null;
  isLoading: boolean;
  isAuthenticated: boolean;
  login: () => void;
  logout: () => void;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export const useAuth = () => {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error('useAuth must be used within EasyAuthProvider');
  }
  return context;
};

interface EasyAuthProviderProps {
  children: ReactNode;
}

export const EasyAuthProvider: React.FC<EasyAuthProviderProps> = ({ children }) => {
  const [user, setUser] = useState<User | null>(null);
  const [isLoading, setIsLoading] = useState(true);

  // Get API base URL for Easy Auth endpoints
  const getApiBaseUrl = (): string => {
    const runtimeConfig = (window as any).__ENV__;
    return runtimeConfig?.VITE_API_BASE_URL || 
           runtimeConfig?.VITE_API_URL || 
           import.meta.env.VITE_API_BASE_URL || 
           import.meta.env.VITE_API_URL || 
           'http://localhost:8000';
  };

  // Check if user is authenticated by calling Easy Auth endpoint
  const checkAuth = async (): Promise<void> => {
    try {
      const apiBaseUrl = getApiBaseUrl();
      // Easy Auth provides /.auth/me endpoint
      // Since we're calling from frontend, we need to call the Function App's Easy Auth endpoint
      const response = await fetch(`${apiBaseUrl}/.auth/me`, {
        method: 'GET',
        credentials: 'include', // Include cookies for Easy Auth
      });

      if (response.ok) {
        const authData = await response.json();
        
        if (authData.clientPrincipal) {
          // Extract user info from Easy Auth response
          const claims = authData.clientPrincipal.claims || [];
          let email = '';
          let name = '';
          const roles: string[] = [];

          claims.forEach((claim: any) => {
            const typ = claim.typ || claim.type;
            const val = claim.val || claim.value;

            if (typ === 'preferred_username' || typ === 'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress') {
              email = val;
            }
            if (typ === 'name' || typ === 'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name') {
              name = val;
            }
            if (typ === 'roles' || typ?.includes('role')) {
              roles.push(val);
            }
          });

          // Check admin status
          const runtimeConfig = (window as any).__ENV__;
          const adminGroupId = runtimeConfig?.VITE_AZURE_AD_ADMIN_GROUP_ID || import.meta.env.VITE_AZURE_AD_ADMIN_GROUP_ID;
          
          // Check if user has admin role or is in admin group
          const isAdmin = roles.some(role => role.toLowerCase().includes('admin')) ||
                         (adminGroupId && claims.some((claim: any) => 
                           (claim.typ === 'groups' || claim.type === 'groups') && 
                           (claim.val === adminGroupId || claim.value === adminGroupId)
                         ));

          setUser({
            email: email || 'unknown@example.com',
            name: name || email || 'Unknown User',
            isAdmin: isAdmin || false,
          });
        } else {
          setUser(null);
        }
      } else {
        setUser(null);
      }
    } catch (error) {
      console.error('Error checking Easy Auth status:', error);
      setUser(null);
    } finally {
      setIsLoading(false);
    }
  };

  // Login: Redirect to Easy Auth login endpoint
  const login = (): void => {
    const apiBaseUrl = getApiBaseUrl();
    const currentPath = window.location.pathname;
    const webAppUrl = window.location.origin + currentPath;
    // Easy Auth login endpoint - redirect back to Web App after login
    // The Function App's Easy Auth must have the Web App URL in allowedExternalRedirectUrls
    const loginUrl = `${apiBaseUrl}/.auth/login/aad?post_login_redirect_url=${encodeURIComponent(webAppUrl)}`;
    window.location.href = loginUrl;
  };

  // Logout: Redirect to Easy Auth logout endpoint
  const logout = (): void => {
    const apiBaseUrl = getApiBaseUrl();
    const logoutUrl = `${apiBaseUrl}/.auth/logout?post_logout_redirect_uri=${encodeURIComponent(window.location.origin)}`;
    window.location.href = logoutUrl;
  };

  // Check auth on mount and when API base URL changes
  useEffect(() => {
    checkAuth();
  }, []);

  const value: AuthContextType = {
    user,
    isLoading,
    isAuthenticated: !!user,
    login,
    logout,
  };

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
};

