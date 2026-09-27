import type { OrganizationMemberRole } from '@/types/organization';

/** Mirrors organization_invitation_status plus the client-side-only
 * "expired" the DB computes on the fly (status='pending' AND expires_at <=
 * now()) — never persisted as a separate enum value, see
 * accept_organization_invitation/list_organization_access. */
export type InvitationEffectiveStatus = 'pending' | 'expired' | 'accepted' | 'revoked';

export const INVITATION_STATUS_LABELS: Record<InvitationEffectiveStatus, string> = {
  pending: 'Pendiente',
  expired: 'Vencida',
  accepted: 'Aceptada',
  revoked: 'Revocada',
};

/** A row from list_organization_access(organization_id): either an active
 * organization member or a non-accepted invitation. Two shapes exist only
 * to avoid a wide "everything nullable" interface at every call site. */
export interface OrganizationAccessMemberRow {
  kind: 'member';
  id: string;
  user_id: string;
  name: string;
  email: string;
  role: OrganizationMemberRole;
  is_active: boolean;
  joined_at: string;
}

export interface OrganizationAccessInvitationRow {
  kind: 'invitation';
  id: string;
  email: string;
  role: OrganizationMemberRole;
  invited_name: string | null;
  effective_status: InvitationEffectiveStatus;
  created_at: string;
  expires_at: string;
  accepted_at: string | null;
  revoked_at: string | null;
  last_sent_at: string | null;
  send_count: number;
}

export type OrganizationAccessRow = OrganizationAccessMemberRow | OrganizationAccessInvitationRow;

/** Raw row shape as list_organization_access(uuid) actually returns it
 * (one flat table, nulls for whichever variant doesn't apply) — narrowed
 * into OrganizationAccessRow by useOrganizationAccess. */
export interface RawOrganizationAccessRow {
  kind: 'member' | 'invitation';
  id: string;
  user_id: string | null;
  name: string | null;
  email: string | null;
  role: OrganizationMemberRole;
  is_active: boolean | null;
  joined_at: string | null;
  invited_name: string | null;
  effective_status: InvitationEffectiveStatus | null;
  created_at: string | null;
  expires_at: string | null;
  accepted_at: string | null;
  revoked_at: string | null;
  last_sent_at: string | null;
  send_count: number | null;
}

export const toOrganizationAccessRow = (raw: RawOrganizationAccessRow): OrganizationAccessRow => (
  raw.kind === 'member'
    ? {
      kind: 'member',
      id: raw.id,
      user_id: raw.user_id ?? '',
      name: raw.name ?? '',
      email: raw.email ?? '',
      role: raw.role,
      is_active: raw.is_active ?? false,
      joined_at: raw.joined_at ?? '',
    }
    : {
      kind: 'invitation',
      id: raw.id,
      email: raw.email ?? '',
      role: raw.role,
      invited_name: raw.invited_name,
      effective_status: raw.effective_status ?? 'pending',
      created_at: raw.created_at ?? '',
      expires_at: raw.expires_at ?? '',
      accepted_at: raw.accepted_at,
      revoked_at: raw.revoked_at,
      last_sent_at: raw.last_sent_at,
      send_count: raw.send_count ?? 0,
    }
);

/** Only pending/expired invitations can be resent or cancelled — matches
 * resend_organization_invitation/revoke_organization_invitation's own
 * server-side check exactly, so the UI never offers an action the RPC
 * would reject anyway. */
export const isInvitationActionable = (status: InvitationEffectiveStatus): boolean =>
  status === 'pending' || status === 'expired';
