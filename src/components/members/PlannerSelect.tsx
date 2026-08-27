import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { useOrganizationPlanners } from '@/hooks/useOrganizationPlanners';

interface PlannerSelectProps {
  organizationId: string | null | undefined;
  /** Selected organization_members.id, or null when unassigned. */
  value: string | null;
  onChange: (memberId: string | null) => void;
  disabled?: boolean;
  /** Shown instead of the default "no planners yet" copy when the list is empty. */
  emptyMessage?: string;
}

/**
 * Picks an active owner/admin/manager ("Planner / Gestor") from the given
 * organization only — same shape as TechnicianSelect, backed by
 * useOrganizationPlanners/get_assignable_planners instead.
 */
export function PlannerSelect({ organizationId, value, onChange, disabled, emptyMessage }: PlannerSelectProps) {
  const { planners, loading, error } = useOrganizationPlanners(organizationId);

  return (
    <div className="space-y-1">
      <Select
        value={value ?? 'none'}
        onValueChange={(next) => onChange(next === 'none' ? null : next)}
        disabled={disabled || loading || !organizationId}
      >
        <SelectTrigger>
          <SelectValue placeholder={loading ? 'Cargando planners…' : 'Selecciona un planner'} />
        </SelectTrigger>
        <SelectContent>
          <SelectItem value="none">Sin asignar</SelectItem>
          {planners.map((planner) => (
            <SelectItem key={planner.memberId} value={planner.memberId}>
              {planner.name}{planner.email ? ` (${planner.email})` : ''}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
      {!loading && !error && organizationId && planners.length === 0 && (
        <p className="text-xs text-muted-foreground">
          {emptyMessage ?? 'Esta organización todavía no tiene planners activos (owner/admin/manager).'}
        </p>
      )}
      {error && (
        emptyMessage
          ? <p className="text-xs text-muted-foreground">{emptyMessage}</p>
          : <p className="text-xs text-destructive">{error}</p>
      )}
    </div>
  );
}
