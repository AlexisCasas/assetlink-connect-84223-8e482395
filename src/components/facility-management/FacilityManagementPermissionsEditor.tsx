import { useEffect, useMemo, useState } from 'react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Checkbox } from '@/components/ui/checkbox';
import { Label } from '@/components/ui/label';
import { groupFacilityManagementPermissions } from '@/lib/facilityManagement';
import type { FacilityManagementPermission } from '@/types/facilityManagement';

interface Props {
  value: FacilityManagementPermission[];
  /** Sin onSave la vista es de solo lectura (Facility Manager). */
  onSave?: (permissions: FacilityManagementPermission[]) => Promise<void>;
  disabled?: boolean;
  disabledReason?: string;
}

export function FacilityManagementPermissionsEditor({ value, onSave, disabled, disabledReason }: Props) {
  const [selected, setSelected] = useState<Set<FacilityManagementPermission>>(new Set(value));
  const [saving, setSaving] = useState(false);

  useEffect(() => { setSelected(new Set(value)); }, [value]);

  const readOnly = !onSave;
  const groups = useMemo(() => groupFacilityManagementPermissions(readOnly ? value : undefined), [readOnly, value]);
  const dirty = useMemo(() => selected.size !== value.length || value.some((code) => !selected.has(code)), [selected, value]);

  if (readOnly) {
    if (groups.length === 0) return <p className="text-sm text-muted-foreground">El cliente todavía no delegó permisos.</p>;
    return (
      <div className="grid gap-3 sm:grid-cols-2">
        {groups.map((group) => (
          <div key={group.key} className="rounded-md border p-3">
            <p className="mb-2 text-sm font-medium">{group.label}</p>
            <div className="flex flex-wrap gap-1">
              {group.permissions.map((permission) => <Badge key={permission.code} variant="secondary">{permission.label}</Badge>)}
            </div>
          </div>
        ))}
      </div>
    );
  }

  const toggle = (code: FacilityManagementPermission, checked: boolean) => {
    setSelected((current) => {
      const next = new Set(current);
      if (checked) next.add(code); else next.delete(code);
      return next;
    });
  };

  const save = async () => {
    setSaving(true);
    try {
      await onSave(Array.from(selected));
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="space-y-4">
      {disabled && disabledReason && <p className="text-sm text-muted-foreground">{disabledReason}</p>}
      <div className="grid gap-3 sm:grid-cols-2">
        {groups.map((group) => (
          <fieldset key={group.key} className="rounded-md border p-3" disabled={disabled || saving}>
            <legend className="px-1 text-sm font-medium">{group.label}</legend>
            <div className="space-y-2">
              {group.permissions.map((permission) => {
                const id = `fm-permission-${permission.code}`;
                return (
                  <div key={permission.code} className="flex items-center gap-2">
                    <Checkbox
                      id={id}
                      checked={selected.has(permission.code)}
                      disabled={disabled || saving}
                      onCheckedChange={(checked) => toggle(permission.code, checked === true)}
                    />
                    <Label htmlFor={id} className="text-sm font-normal">{permission.label}</Label>
                  </div>
                );
              })}
            </div>
          </fieldset>
        ))}
      </div>
      <div className="flex justify-end gap-2">
        <Button variant="outline" disabled={!dirty || saving || disabled} onClick={() => setSelected(new Set(value))}>Descartar</Button>
        <Button disabled={!dirty || saving || disabled} onClick={() => void save()}>{saving ? 'Guardando…' : 'Guardar permisos'}</Button>
      </div>
    </div>
  );
}
