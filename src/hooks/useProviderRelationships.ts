import { useCallback, useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import type { OrganizationRelationshipStatus } from '@/types/organization';
import type { ProviderDirectoryEntry } from '@/types/providerRelationship';

/** Backs the "Proveedores Homologados" screen entirely through
 * get_provider_relationship_directory / set_provider_relationship_status
 * (provider_company / subcontractor_company only since Fase 1 · Punto 9B;
 * facility managers use useFacilityManagement) —
 * scoped by currentOrganization.id, never by user.email or client_email
 * (the legacy client_approved_providers/client_specialties key). */
export function useProviderRelationships() {
  const { currentOrganization } = useAuth();
  const [directory, setDirectory] = useState<ProviderDirectoryEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const loadDirectory = useCallback(async () => {
    if (!currentOrganization) {
      setDirectory([]);
      setLoading(false);
      return;
    }

    setLoading(true);
    setError(null);
    try {
      const { data, error: rpcError } = await supabase.rpc('get_provider_relationship_directory', {
        p_client_organization_id: currentOrganization.id,
      });
      if (rpcError) throw rpcError;

      setDirectory((data ?? []).map((row) => ({
        organizationId: row.organization_id,
        organizationName: row.organization_name,
        organizationType: row.organization_type,
        relationshipId: row.relationship_id,
        relationshipType: row.relationship_type,
        relationshipStatus: row.relationship_status,
        specialties: row.specialties ?? [],
      })));
    } catch (err) {
      setError(err instanceof Error ? err.message : 'No se pudo cargar el directorio de proveedores.');
    } finally {
      setLoading(false);
    }
  }, [currentOrganization]);

  const setStatus = useCallback(async (targetOrganizationId: string, status: OrganizationRelationshipStatus) => {
    if (!currentOrganization) {
      throw new Error('Selecciona una organización activa antes de gestionar proveedores.');
    }

    const { error: rpcError } = await supabase.rpc('set_provider_relationship_status', {
      p_client_organization_id: currentOrganization.id,
      p_target_organization_id: targetOrganizationId,
      p_status: status,
    });
    if (rpcError) throw rpcError;

    await loadDirectory();
  }, [currentOrganization, loadDirectory]);

  useEffect(() => {
    void loadDirectory();
  }, [loadDirectory]);

  return {
    directory,
    loading,
    error,
    loadDirectory,
    setStatus,
    refresh: loadDirectory,
  };
}
