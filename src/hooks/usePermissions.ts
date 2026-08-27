import { useCallback, useMemo } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import type { OrganizationMemberRole } from '@/types/organization';
import { canExecuteWork, canPlanWork, isOrganizationAdminRole, isPlannerRole, isTechnicianRole } from '@/lib/organizationRoles';

export const usePermissions = () => {
  const { currentMembership } = useAuth();
  const role = currentMembership?.isActive ? currentMembership.role : null;

  const hasRole = useCallback((roles: OrganizationMemberRole[]) => (
    currentMembership ? roles.includes(currentMembership.role) : false
  ), [currentMembership]);

  return useMemo(() => ({
    hasRole,
    isOwnerOrAdmin: hasRole(['owner', 'admin']),
    canManageMembers: hasRole(['owner', 'admin']),
    canManageOrganization: hasRole(['owner', 'admin']),
    // Functional operation roles (owner/admin = Administrador,
    // manager = Planner/Gestor, technician = Técnico).
    isOrganizationAdmin: !!role && isOrganizationAdminRole(role),
    isPlanner: !!role && isPlannerRole(role),
    isTechnician: !!role && isTechnicianRole(role),
    canPlanWork: canPlanWork(role),
    canExecuteWork: canExecuteWork(role),
  }), [hasRole, role]);
};
