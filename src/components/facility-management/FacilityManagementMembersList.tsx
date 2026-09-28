import { Badge } from '@/components/ui/badge';
import { ORGANIZATION_ROLE_LABELS } from '@/lib/organizationRoles';
import type { FacilityManagementMember } from '@/types/facilityManagement';

/** Equipo asignado, solo lectura (vista del cliente). */
export function FacilityManagementMembersList({ members, loading }: { members: FacilityManagementMember[]; loading: boolean }) {
  if (loading) return <p className="text-sm text-muted-foreground">Cargando equipo…</p>;
  if (members.length === 0) return <p className="text-sm text-muted-foreground">El Facility Manager todavía no asignó personas a esta relación.</p>;
  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm">
        <thead className="border-b text-left text-muted-foreground">
          <tr><th className="p-2">Nombre</th><th className="p-2">Email</th><th className="p-2">Rol en el FM</th><th className="p-2">Estado</th></tr>
        </thead>
        <tbody>
          {members.map((member) => (
            <tr key={member.organizationMemberId} className="border-b last:border-0">
              <td className="p-2">{member.name || '—'}</td>
              <td className="p-2">{member.email}</td>
              <td className="p-2">{ORGANIZATION_ROLE_LABELS[member.role]}</td>
              <td className="p-2">
                <Badge variant={member.membershipIsActive ? 'default' : 'outline'}>{member.membershipIsActive ? 'Activo' : 'Inactivo'}</Badge>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
