import { useCallback, useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import type { OrganizationMemberRole } from '@/types/organization';
import {
  toOrganizationAccessRow,
  type OrganizationAccessRow,
  type RawOrganizationAccessRow,
} from '@/lib/invitations';

export interface InviteUserInput {
  email: string;
  invitedName?: string;
  role: OrganizationMemberRole;
}

interface SendInvitationErrorPayload {
  error?: string;
  invitation_id?: string;
}

/** Reads list_organization_access(organization_id) — members + non-accepted
 * invitations in one call, no N+1 — and exposes the write actions
 * (invite/resend/revoke via send-organization-invitation, role/active
 * changes via update_organization_member). Every authorization rule lives
 * server-side; this hook only surfaces whatever error message the RPC/Edge
 * Function returned. */
export function useOrganizationAccess(organizationId: string | null) {
  const [rows, setRows] = useState<OrganizationAccessRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const reload = useCallback(async () => {
    if (!organizationId) { setRows([]); setLoading(false); return; }
    setLoading(true);
    setError(null);
    const { data, error: rpcError } = await supabase.rpc('list_organization_access', { p_organization_id: organizationId });
    if (rpcError) {
      setError(rpcError.message);
      setRows([]);
    } else {
      setRows(((data ?? []) as unknown as RawOrganizationAccessRow[]).map(toOrganizationAccessRow));
    }
    setLoading(false);
  }, [organizationId]);

  useEffect(() => { void reload(); }, [reload]);

  const inviteUser = useCallback(async (input: InviteUserInput) => {
    if (!organizationId) throw new Error('No hay una organización seleccionada');
    const { data, error: invokeError } = await supabase.functions.invoke('send-organization-invitation', {
      body: {
        action: 'create',
        organization_id: organizationId,
        email: input.email,
        role: input.role,
        invited_name: input.invitedName || undefined,
      },
    });
    if (invokeError) {
      const payload = await readFunctionErrorPayload(invokeError);
      throw new Error(payload?.error ?? invokeError.message);
    }
    await reload();
    return data;
  }, [organizationId, reload]);

  const resendInvitation = useCallback(async (invitationId: string) => {
    const { data, error: invokeError } = await supabase.functions.invoke('send-organization-invitation', {
      body: { action: 'resend', invitation_id: invitationId },
    });
    if (invokeError) {
      const payload = await readFunctionErrorPayload(invokeError);
      throw new Error(payload?.error ?? invokeError.message);
    }
    await reload();
    return data;
  }, [reload]);

  const revokeInvitation = useCallback(async (invitationId: string) => {
    const { error: rpcError } = await supabase.rpc('revoke_organization_invitation', { p_invitation_id: invitationId });
    if (rpcError) throw new Error(rpcError.message);
    await reload();
  }, [reload]);

  const updateMember = useCallback(async (membershipId: string, changes: { role?: OrganizationMemberRole; isActive?: boolean }) => {
    const { error: rpcError } = await supabase.rpc('update_organization_member', {
      p_membership_id: membershipId,
      p_role: changes.role ?? null,
      p_is_active: changes.isActive ?? null,
    });
    if (rpcError) throw new Error(rpcError.message);
    await reload();
  }, [reload]);

  return { rows, loading, error, reload, inviteUser, resendInvitation, revokeInvitation, updateMember };
}

/** supabase-js throws a FunctionsHttpError whose `.context` is the raw
 * Response — this reads its JSON body (the {error, invitation_id} shape
 * send-organization-invitation returns) without assuming a specific
 * supabase-js version's error class shape. */
async function readFunctionErrorPayload(error: unknown): Promise<SendInvitationErrorPayload | null> {
  const context = (error as { context?: unknown } | null)?.context;
  if (!context || typeof (context as Response).json !== 'function') return null;
  try {
    return await (context as Response).json() as SendInvitationErrorPayload;
  } catch {
    return null;
  }
}
