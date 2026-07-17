import { useAuth } from '@/contexts/AuthContext';

export const useUserOrganizations = () => {
  const { organizations, memberships, loading } = useAuth();

  return { organizations, memberships, loading };
};
