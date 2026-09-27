import { useMemo, useState } from 'react';
import { Mail, UserX, UserCheck, Ban, Plus } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { useOrganizationAccess } from '@/hooks/useOrganizationAccess';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { useToast } from '@/hooks/use-toast';
import { ORGANIZATION_ROLE_LABELS } from '@/lib/organizationRoles';
import { INVITATION_STATUS_LABELS, isInvitationActionable } from '@/lib/invitations';
import type { OrganizationMemberRole } from '@/types/organization';
import { InviteUserDialog } from './InviteUserDialog';

const ALL_ROLES: OrganizationMemberRole[] = ['owner', 'admin', 'manager', 'requester', 'quote_manager', 'technician', 'operator', 'viewer'];

const formatDateTime = (value: string | null) => value ? new Date(value).toLocaleString() : '—';

/** Administración de usuarios de la organización activa. Solo owner/admin
 * (gate aplicado por el llamante — Sidebar/Dashboard, ver #users). Toda
 * regla de jerarquía (qué rol puede asignarse, quién puede modificar a
 * quién, protección del último owner) se re-valida server-side en
 * update_organization_member/can_manage_organization_role — esta vista solo
 * evita ofrecer una acción que el servidor rechazaría de todas formas. */
export function OrganizationUsersView() {
  const { currentOrganization, currentMembership, user } = useAuth();
  const { toast } = useToast();
  const organizationId = currentOrganization?.id ?? null;
  const { rows, loading, error, inviteUser, resendInvitation, revokeInvitation, updateMember } = useOrganizationAccess(organizationId);
  const [inviteOpen, setInviteOpen] = useState(false);
  const [busyId, setBusyId] = useState<string | null>(null);

  const isOwner = currentMembership?.role === 'owner';
  // An admin never sees 'owner' as an assignable/selectable role — matches
  // can_manage_organization_role's own rule exactly.
  const assignableRoles = useMemo(() => (isOwner ? ALL_ROLES : ALL_ROLES.filter((role) => role !== 'owner')), [isOwner]);

  const members = rows.filter((row) => row.kind === 'member');
  const invitations = rows.filter((row) => row.kind === 'invitation');

  const runAction = async (id: string, action: () => Promise<void>, successMessage: string) => {
    setBusyId(id);
    try {
      await action();
      toast({ title: successMessage });
    } catch (actionError) {
      toast({
        title: 'No se pudo completar la acción',
        description: actionError instanceof Error ? actionError.message : 'Ocurrió un error inesperado.',
        variant: 'destructive',
      });
    } finally {
      setBusyId(null);
    }
  };

  if (!organizationId) return null;

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-xl font-semibold">Usuarios</h2>
          <p className="text-sm text-muted-foreground">Miembros e invitaciones de {currentOrganization?.name}.</p>
        </div>
        <Button onClick={() => setInviteOpen(true)}><Plus className="mr-2 h-4 w-4" />Invitar usuario</Button>
      </div>

      {error && <p role="status" className="rounded-md border border-destructive/40 bg-destructive/5 p-3 text-sm text-destructive">{error}</p>}

      <Card>
        <CardHeader><CardTitle className="text-base">Miembros</CardTitle></CardHeader>
        <CardContent>
          {loading ? <p className="py-6 text-center text-sm text-muted-foreground">Cargando…</p> : members.length === 0 ? (
            <p className="py-6 text-center text-sm text-muted-foreground">Sin miembros.</p>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="border-b text-left text-muted-foreground">
                  <tr><th className="p-2">Nombre</th><th className="p-2">Email</th><th className="p-2">Rol</th><th className="p-2">Estado</th><th className="p-2">Ingreso</th><th className="p-2 text-right">Acciones</th></tr>
                </thead>
                <tbody>
                  {members.map((member) => {
                    const isSelf = member.user_id === user?.id;
                    // Mirrors can_manage_organization_role: caller must be
                    // able to manage the member's CURRENT role, and an admin
                    // (not owner, not platform admin) never touches itself.
                    const canManage = isOwner || member.role !== 'owner';
                    const disableSelf = isSelf && !isOwner;
                    return (
                      <tr key={member.id} className="border-b last:border-0">
                        <td className="p-2">{member.name || '—'}</td>
                        <td className="p-2">{member.email}</td>
                        <td className="p-2">
                          <Select
                            value={member.role}
                            onValueChange={(value) => void runAction(member.id, () => updateMember(member.id, { role: value as OrganizationMemberRole }), 'Rol actualizado')}
                            disabled={!canManage || disableSelf || busyId === member.id}
                          >
                            <SelectTrigger className="w-40"><SelectValue /></SelectTrigger>
                            <SelectContent>
                              {assignableRoles.map((role) => <SelectItem key={role} value={role}>{ORGANIZATION_ROLE_LABELS[role]}</SelectItem>)}
                            </SelectContent>
                          </Select>
                        </td>
                        <td className="p-2"><Badge variant={member.is_active ? 'default' : 'outline'}>{member.is_active ? 'Activo' : 'Inactivo'}</Badge></td>
                        <td className="p-2">{formatDateTime(member.joined_at)}</td>
                        <td className="p-2 text-right">
                          <Button
                            size="sm" variant="outline"
                            disabled={!canManage || disableSelf || busyId === member.id}
                            onClick={() => void runAction(member.id, () => updateMember(member.id, { isActive: !member.is_active }), member.is_active ? 'Miembro desactivado' : 'Miembro activado')}
                          >
                            {member.is_active ? <UserX className="mr-1 h-4 w-4" /> : <UserCheck className="mr-1 h-4 w-4" />}
                            {member.is_active ? 'Desactivar' : 'Activar'}
                          </Button>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader><CardTitle className="text-base">Invitaciones</CardTitle></CardHeader>
        <CardContent>
          {loading ? <p className="py-6 text-center text-sm text-muted-foreground">Cargando…</p> : invitations.length === 0 ? (
            <p className="py-6 text-center text-sm text-muted-foreground">Sin invitaciones.</p>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="border-b text-left text-muted-foreground">
                  <tr><th className="p-2">Email</th><th className="p-2">Nombre</th><th className="p-2">Rol</th><th className="p-2">Estado</th><th className="p-2">Enviada</th><th className="p-2">Vence</th><th className="p-2 text-right">Acciones</th></tr>
                </thead>
                <tbody>
                  {invitations.map((invitation) => {
                    const actionable = isInvitationActionable(invitation.effective_status);
                    return (
                      <tr key={invitation.id} className="border-b last:border-0">
                        <td className="p-2">{invitation.email}</td>
                        <td className="p-2">{invitation.invited_name || '—'}</td>
                        <td className="p-2">{ORGANIZATION_ROLE_LABELS[invitation.role]}</td>
                        <td className="p-2">
                          <Badge variant={invitation.effective_status === 'pending' ? 'default' : 'outline'}>
                            {INVITATION_STATUS_LABELS[invitation.effective_status]}
                          </Badge>
                        </td>
                        <td className="p-2">{invitation.last_sent_at ? formatDateTime(invitation.last_sent_at) : 'No enviada'}</td>
                        <td className="p-2">{formatDateTime(invitation.expires_at)}</td>
                        <td className="p-2 text-right space-x-2">
                          <Button
                            size="sm" variant="outline" disabled={!actionable || busyId === invitation.id}
                            onClick={() => void runAction(invitation.id, async () => { await resendInvitation(invitation.id); }, 'Invitación reenviada')}
                          >
                            <Mail className="mr-1 h-4 w-4" />Reenviar
                          </Button>
                          <Button
                            size="sm" variant="destructive" disabled={!actionable || busyId === invitation.id}
                            onClick={() => void runAction(invitation.id, () => revokeInvitation(invitation.id), 'Invitación cancelada')}
                          >
                            <Ban className="mr-1 h-4 w-4" />Cancelar
                          </Button>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
        </CardContent>
      </Card>

      <InviteUserDialog open={inviteOpen} onOpenChange={setInviteOpen} assignableRoles={assignableRoles} onInvite={inviteUser} />
    </div>
  );
}
