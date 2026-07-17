import { useAuth } from '@/contexts/AuthContext';

export const useCurrentOrganization = () => {
  const { currentOrganization, setCurrentOrganization } = useAuth();

  return { currentOrganization, setCurrentOrganization };
};
