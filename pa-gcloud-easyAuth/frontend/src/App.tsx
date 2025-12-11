import { Routes, Route, Navigate } from 'react-router-dom';
import { useAuth } from './contexts/EasyAuthContext';
import Login from './pages/Login';
import ProposalFlow from './pages/ProposalFlow';
import ProposalsList from './pages/ProposalsList';
import ProposalEditor from './pages/ProposalEditor';
import CreateProposal from './pages/CreateProposal';
import ServiceDescriptionForm from './pages/ServiceDescriptionForm';
import QuestionnairePage from './pages/QuestionnairePage';
import AdminDashboard from './pages/AdminDashboard';
import QuestionnaireAnalytics from './pages/QuestionnaireAnalytics';

// Protected route wrapper
const ProtectedRoute = ({ children }: { children: React.ReactElement }) => {
  const { isAuthenticated, isLoading } = useAuth();
  
  if (isLoading) {
    return <div>Loading...</div>; // Or a proper loading component
  }
  
  return isAuthenticated ? children : <Navigate to="/login" replace />;
};

// Admin-only route wrapper
const AdminRoute = ({ children }: { children: React.ReactElement }) => {
  const { isAuthenticated, isLoading, user } = useAuth();
  
  if (isLoading) {
    return <div>Loading...</div>;
  }
  
  if (!isAuthenticated) {
    return <Navigate to="/login" replace />;
  }
  
  if (!user?.isAdmin) {
    return <Navigate to="/proposals" replace />;
  }
  
  return children;
};

function App() {
  return (
    <Routes>
      <Route path="/login" element={<Login />} />
      <Route path="/" element={<Navigate to="/login" replace />} />
      <Route
        path="/proposals/flow"
        element={
          <ProtectedRoute>
            <ProposalFlow />
          </ProtectedRoute>
        }
      />
      <Route
        path="/proposals"
        element={
          <ProtectedRoute>
            <ProposalsList />
          </ProtectedRoute>
        }
      />
      <Route
        path="/proposals/create"
        element={
          <ProtectedRoute>
            <CreateProposal />
          </ProtectedRoute>
        }
      />
      <Route
        path="/proposals/create/service-description"
        element={
          <ProtectedRoute>
            <ServiceDescriptionForm />
          </ProtectedRoute>
        }
      />
      <Route
        path="/proposals/:id"
        element={
          <ProtectedRoute>
            <ProposalEditor />
          </ProtectedRoute>
        }
      />
      <Route
        path="/questionnaire/:serviceName/:lot"
        element={
          <ProtectedRoute>
            <QuestionnairePage />
          </ProtectedRoute>
        }
      />
      <Route
        path="/admin/dashboard"
        element={
          <AdminRoute>
            <AdminDashboard />
          </AdminRoute>
        }
      />
      <Route
        path="/admin/analytics"
        element={
          <AdminRoute>
            <QuestionnaireAnalytics />
          </AdminRoute>
        }
      />
      <Route path="*" element={<Navigate to="/login" replace />} />
    </Routes>
  );
}

export default App;

