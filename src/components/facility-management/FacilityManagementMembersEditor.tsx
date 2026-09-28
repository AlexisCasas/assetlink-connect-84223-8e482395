import { useEffect, useMemo, useState } from 'react';
import { toast } from 'sonner';
import { Button } from '@/components/ui/button';
import { Checkbox } from '@/components/ui/checkbox';
import { Label } from '@/components/ui/label';
import { useAuth } from '@/contexts/AuthContext';
import { useOrganizationAccess } from '@/hooks/useOrganizationAccess';
import { ORGANIZATION_ROLE_LABELS } from '@/lib/organizationRoles';
import type { OrganizationAccessMemberRow } from '@/lib/invitations';
import type { FacilityManagementMember } from '@/types/facilityManagement';

interface Props {
  assigned: FacilityManagementMember[];
  loading: boolean;
  editable: boolean;
  onSave: (membershipIds: string[]) => Promise<void>;
}

/** Asignación del equipo del FM a una relación. El roster sale del mismo
 * mecanismo que la pantalla Usuarios (list_organization_access, solo
 * owner/admin de la organización activa = el propio FM). Se envía
 * organization_members.id, nunca user_id. */
export function FacilityManagementMembersEditor({ assigned, loading, editable, onSave }: Props) {
  const { currentOrganization } = useAuth();
  const { rows, loading: rosterLoading, error: rosterError } = useOrganizationAccess(currentOrganization?.id ?? null);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [saving, setSaving] = useState(false);

  const assignedActiveIds = useMemo(
    () => assigned.filter((member) => member.membershipIsActive).map((member) => member.organizationMemberId),
    [assigned],
  );
  useEffect(() => { setSelected(new Set(assignedActiveIds)); }, [assignedActiveIds]);

  const roster = useMemo(
    () => rows.filter((row): row is OrganizationAccessMemberRow => row.kind === 'member' && row.is_active),
    [rows],
  );
  const inactiveAssigned = assigned.filter((member) => !member.membershipIsActive);
  const dirty = inactiveAssigned.length > 0 || selected.size !== assignedActiveIds.length || assignedActiveIds.some((id) => !selected.has(id));

  const save = async () => {
    setSaving(true);
    try {
      await onSave(Array.from(selected));
      toast.success('Equipo asignado actualizado');
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'No se pudo actualizar el equipo');
    } finally {
      setSaving(false);
    }
  };

  if (loading || rosterLoading) return <p className="text-sm text-muted-foreground">Cargando equipo…</p>;
  if (rosterError) return <p role="status" className="text-sm text-destructive">{rosterError}</p>;

  return (
    <div className="space-y-3">
      {!editable && <p className="text-sm text-muted-foreground">La relación está finalizada: no se puede asignar equipo.</p>}
      {roster.length === 0 ? <p className="text-sm text-muted-foreground">Tu organización no tiene miembros activos.</p> : (
        <div className="space-y-2">
          {roster.map((member) => {
            const id = `fm-member-${member.id}`;
            return (
              <div key={member.id} className="flex items-center gap-2">
                <Checkbox
                  id={id}
                  checked={selected.has(member.id)}
                  disabled={!editable || saving}
                  onCheckedChange={(checked) => setSelected((current) => {
                    const next = new Set(current);
                    if (checked === true) next.add(member.id); else next.delete(member.id);
                    return next;
                  })}
                />
                <Label htmlFor={id} className="text-sm font-normal">
                  {member.name || member.email} <span className="text-muted-foreground">· {member.email} · {ORGANIZATION_ROLE_LABELS[member.role]}</span>
                </Label>
              </div>
            );
          })}
        </div>
      )}
      {inactiveAssigned.length > 0 && (
        <p className="text-sm text-muted-foreground">
          Asignados con membresía inactiva (sin acceso; se quitarán al guardar): {inactiveAssigned.map((member) => member.name || member.email).join(', ')}
        </p>
      )}
      <div className="flex justify-end">
        <Button disabled={!editable || !dirty || saving} onClick={() => void save()}>{saving ? 'Guardando…' : 'Guardar equipo'}</Button>
      </div>
    </div>
  );
}
