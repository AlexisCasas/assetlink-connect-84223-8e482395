import { useCallback, useMemo } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import type { OrganizationMemberRole } from '@/types/organization';

export const usePermissions = () => {
  const { currentMembership } = useAuth();

  const hasRole = useCallback((roles: OrganizationMemberRole[]) => (
    currentMembership ? roles.includes(currentMembership.role) : false
  ), [currentMembership]);

  return useMemo(() => ({
    hasRole,
    isOwnerOrAdmin: hasRole(['owner', 'admin']),
    canManageMembers: hasRole(['owner', 'admin']),
    canManageOrganization: hasRole(['owner', 'admin']),
  }), [hasRole]);
};
