import { useAuth } from '@/contexts/AuthContext';

export const useCurrentMembership = () => {
  const { currentMembership } = useAuth();

  return { currentMembership };
};
