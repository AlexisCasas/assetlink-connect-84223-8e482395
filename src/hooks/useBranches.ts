import { useCallback, useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import type { ClientBranch } from '@/types/request';
import type { OrganizationMemberRole } from '@/types/organization';

type BranchInput = Pick<ClientBranch, 'name' | 'city' | 'site' | 'address'>;

const managerRoles: OrganizationMemberRole[] = ['owner', 'admin', 'manager'];

export const useBranches = (
  organizationId: string | undefined,
  role: OrganizationMemberRole | undefined,
) => {
  const [branches, setBranches] = useState<ClientBranch[]>([]);
  const [loading, setLoading] = useState(Boolean(organizationId));
  const [error, setError] = useState<string | null>(null);
  const canManageBranches = Boolean(role && managerRoles.includes(role));

  const loadBranches = useCallback(async () => {
    if (!organizationId) {
      setBranches([]);
      setLoading(false);
      setError(null);
      return;
    }

    setLoading(true);
    setError(null);
    const { data, error: queryError } = await supabase
      .from('client_branches')
      .select('id, name, city, site, address, is_active')
      .eq('organization_id', organizationId)
      .order('name');

    if (queryError) {
      setBranches([]);
      setError(queryError.message);
    } else {
      setBranches((data ?? []).map((branch) => ({
        id: branch.id,
        name: branch.name,
        city: branch.city,
        site: branch.site,
        address: branch.address,
        isActive: branch.is_active,
      })));
    }
    setLoading(false);
  }, [organizationId]);

  const createBranch = async (input: BranchInput) => {
    if (!organizationId || !canManageBranches) return { error: 'No tienes permisos para crear sucursales' };

    const { error: insertError } = await supabase.from('client_branches').insert({
      organization_id: organizationId,
      // Legacy compatibility only. Authorization and tenant scoping use organization_id.
      client_email: '',
      name: input.name,
      city: input.city,
      site: input.site,
      address: input.address || null,
      is_active: true,
    });
    if (!insertError) await loadBranches();
    return { error: insertError?.message };
  };

  const updateBranch = async (id: string, input: BranchInput) => {
    if (!organizationId || !canManageBranches) return { error: 'No tienes permisos para editar sucursales' };

    const { error: updateError } = await supabase
      .from('client_branches')
      .update({ name: input.name, city: input.city, site: input.site, address: input.address || null })
      .eq('id', id)
      .eq('organization_id', organizationId);
    if (!updateError) await loadBranches();
    return { error: updateError?.message };
  };

  const setBranchActive = async (id: string, isActive: boolean) => {
    if (!organizationId || !canManageBranches) return { error: 'No tienes permisos para actualizar sucursales' };

    const { error: updateError } = await supabase
      .from('client_branches')
      .update({ is_active: isActive })
      .eq('id', id)
      .eq('organization_id', organizationId);
    if (!updateError) await loadBranches();
    return { error: updateError?.message };
  };

  useEffect(() => {
    void loadBranches();
  }, [loadBranches]);

  return { branches, loading, error, canManageBranches, createBranch, updateBranch, setBranchActive, reloadBranches: loadBranches };
};
