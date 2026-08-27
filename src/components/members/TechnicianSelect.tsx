import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { useOrganizationTechnicians } from '@/hooks/useOrganizationTechnicians';

interface TechnicianSelectProps {
  organizationId: string | null | undefined;
  /** Selected organization_members.id, or null when unassigned. */
  value: string | null;
  onChange: (memberId: string | null) => void;
  disabled?: boolean;
}

/**
 * Picks an active technician from the given organization only
 * (useOrganizationTechnicians -> get_assignable_technicians RPC already
 * scopes this server-side; nothing here can leak another tenant's members).
 */
export function TechnicianSelect({ organizationId, value, onChange, disabled }: TechnicianSelectProps) {
  const { technicians, loading, error } = useOrganizationTechnicians(organizationId);

  return (
    <div className="space-y-1">
      <Select
        value={value ?? 'none'}
        onValueChange={(next) => onChange(next === 'none' ? null : next)}
        disabled={disabled || loading || !organizationId}
      >
        <SelectTrigger>
          <SelectValue placeholder={loading ? 'Cargando técnicos…' : 'Selecciona un técnico'} />
        </SelectTrigger>
        <SelectContent>
          <SelectItem value="none">Sin asignar</SelectItem>
          {technicians.map((technician) => (
            <SelectItem key={technician.memberId} value={technician.memberId}>
              {technician.name}{technician.email ? ` (${technician.email})` : ''}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
      {!loading && !error && organizationId && technicians.length === 0 && (
        <p className="text-xs text-muted-foreground">
          Esta organización todavía no tiene técnicos activos. Créalos desde Administración.
        </p>
      )}
      {error && <p className="text-xs text-destructive">{error}</p>}
    </div>
  );
}
