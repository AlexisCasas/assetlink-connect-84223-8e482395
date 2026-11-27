import { useCallback, useEffect, useState } from 'react';
import { RefreshCw, ShieldCheck, UserPlus, XCircle } from 'lucide-react';
import { toast } from 'sonner';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';

type QueryResult = { data: unknown; error: { message: string } | null };
interface AccessQuery extends PromiseLike<QueryResult> {
  select(columns?: string): AccessQuery;
  insert(values: Record<string, unknown>): AccessQuery;
  update(values: Record<string, unknown>): AccessQuery;
  eq(column: string, value: string | boolean): AccessQuery;
  order(column: string, options?: { ascending?: boolean }): AccessQuery;
}
const accessDb = supabase as unknown as { from: (table: string) => AccessQuery };

type Member = { user_id: string; role: string; is_active: boolean };
type Grant = {
  id: string;
  user_id: string;
  capability: string;
  granted_at: string;
  granted_by: string;
  revoked_at: string | null;
  revoked_by: string | null;
  revocation_reason: string | null;
};

const activeCapabilities = [
  { value: 'market_cost.read', label: 'Consultar costos y proveedores' },
  { value: 'market_cost.manage', label: 'Registrar y mantener costos' },
  { value: 'market_cost.validate', label: 'Validar costos' },
  { value: 'pricing_rules.manage', label: 'Administrar reglas y tipo de cambio' },
] as const;
const reservedCapabilities = ['commercial_price.read', 'commercial_price.propose', 'commercial_price.approve'] as const;
const dateLabel = (value: string) => new Intl.DateTimeFormat('es-PE', { dateStyle: 'medium', timeZone: 'UTC' }).format(new Date(value));

export function PricingAccessPanel({ onChanged }: { onChanged?: () => Promise<void> | void }) {
  const { currentOrganization, currentMembership, user } = useAuth();
  const organizationId = currentOrganization?.id ?? '';
  const isAdmin = !!currentMembership?.isActive
    && currentMembership.organizationId === organizationId
    && ['owner', 'admin'].includes(currentMembership.role);
  const [members, setMembers] = useState<Member[]>([]);
  const [grants, setGrants] = useState<Grant[]>([]);
  const [selectedUserId, setSelectedUserId] = useState('');
  const [selectedCapability, setSelectedCapability] = useState<string>(activeCapabilities[0].value);
  const [revocationReason, setRevocationReason] = useState('');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  const load = useCallback(async () => {
    if (!organizationId || !isAdmin) { setLoading(false); return; }
    setLoading(true);
    try {
      const [memberResult, grantResult] = await Promise.all([
        accessDb.from('organization_members').select('user_id,role,is_active')
          .eq('organization_id', organizationId).eq('is_active', true).order('role'),
        accessDb.from('provider_pricing_access_grants')
          .select('id,user_id,capability,granted_at,granted_by,revoked_at,revoked_by,revocation_reason')
          .eq('organization_id', organizationId).order('granted_at', { ascending: false }),
      ]);
      for (const result of [memberResult, grantResult]) {
        if (result.error) throw new Error(result.error.message);
      }
      const loadedMembers = (memberResult.data ?? []) as Member[];
      setMembers(loadedMembers);
      setGrants((grantResult.data ?? []) as Grant[]);
      setSelectedUserId((current) => current || loadedMembers[0]?.user_id || '');
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'No se pudieron cargar los permisos.');
    } finally {
      setLoading(false);
    }
  }, [organizationId, isAdmin]);

  useEffect(() => { void load(); }, [load]);

  const grant = async () => {
    if (!isAdmin || !organizationId || !user?.id || !selectedUserId || !selectedCapability) return;
    setSaving(true);
    try {
      const { data, error } = await accessDb.from('provider_pricing_access_grants').insert({
        organization_id: organizationId,
        user_id: selectedUserId,
        capability: selectedCapability,
        granted_by: user.id,
      }).select('id');
      if (error) throw new Error(error.message);
      if (!Array.isArray(data) || data.length !== 1) throw new Error('No se confirmó la asignación. Actualiza la lista.');
      toast.success('Permiso asignado.');
      await load();
      await onChanged?.();
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'No se pudo asignar el permiso.');
    } finally {
      setSaving(false);
    }
  };

  const revoke = async (row: Grant) => {
    if (!isAdmin || !organizationId || !user?.id) return;
    setSaving(true);
    try {
      const { data, error } = await accessDb.from('provider_pricing_access_grants').update({
        revoked_at: new Date().toISOString(),
        revoked_by: user.id,
        revocation_reason: revocationReason.trim() || null,
      }).eq('id', row.id).eq('organization_id', organizationId).select('id');
      if (error) throw new Error(error.message);
      if (!Array.isArray(data) || data.length !== 1) throw new Error('El permiso ya fue revocado o no tienes autorización.');
      toast.success('Permiso revocado. El cambio se aplica inmediatamente en RLS.');
      setRevocationReason('');
      await load();
      await onChanged?.();
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'No se pudo revocar el permiso.');
    } finally {
      setSaving(false);
    }
  };

  if (!isAdmin) {
    return <Card><CardContent className="p-6 text-sm text-muted-foreground">Solo owner o admin pueden administrar los permisos de costos.</CardContent></Card>;
  }

  const activeGrants = grants.filter((row) => !row.revoked_at);
  const selectedMember = members.find((member) => member.user_id === selectedUserId);

  return (
    <div className="space-y-5">
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2 text-base"><ShieldCheck className="h-5 w-5" />Permisos comerciales por usuario</CardTitle>
          <CardDescription>Asigna capacidades individuales. Supabase RLS vuelve a validar cada lectura y escritura; ocultar una pestaña no sustituye el permiso de base de datos.</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="grid gap-3 md:grid-cols-[minmax(0,1fr)_minmax(0,1fr)_auto]">
            <div className="space-y-1.5">
              <label className="text-sm font-medium" htmlFor="pricing-member">Miembro activo</label>
              <select id="pricing-member" className="h-10 w-full rounded-md border bg-background px-3 text-sm" value={selectedUserId} onChange={(event) => setSelectedUserId(event.target.value)}>
                {members.map((member) => <option key={member.user_id} value={member.user_id}>{member.role} · {member.user_id}</option>)}
              </select>
            </div>
            <div className="space-y-1.5">
              <label className="text-sm font-medium" htmlFor="pricing-capability">Capacidad</label>
              <select id="pricing-capability" className="h-10 w-full rounded-md border bg-background px-3 text-sm" value={selectedCapability} onChange={(event) => setSelectedCapability(event.target.value)}>
                {activeCapabilities.map((capability) => <option key={capability.value} value={capability.value}>{capability.label}</option>)}
              </select>
            </div>
            <div className="flex items-end"><Button onClick={() => void grant()} disabled={saving || loading || !selectedUserId}><UserPlus className="mr-2 h-4 w-4" />Asignar</Button></div>
          </div>
          {selectedMember && <p className="text-xs text-muted-foreground">Usuario seleccionado: {selectedMember.user_id} · rol de organización: {selectedMember.role}. Esta vista utiliza el ID de usuario; no expone correos de otros miembros.</p>}
          <div className="rounded-md border p-3">
            <p className="text-sm font-medium">Capacidades reservadas para R2-E2.5</p>
            <div className="mt-2 flex flex-wrap gap-2">{reservedCapabilities.map((capability) => <Badge key={capability} variant="outline">{capability}</Badge>)}</div>
            <p className="mt-1 text-xs text-muted-foreground">Todavía no habilitan lectura ni aprobación de precios de venta ROMAX.</p>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="flex flex-row items-center justify-between space-y-0">
          <div><CardTitle className="text-base">Asignaciones y auditoría</CardTitle><CardDescription>Las revocaciones se conservan; no se eliminan registros históricos.</CardDescription></div>
          <Button size="sm" variant="outline" onClick={() => void load()} disabled={loading}><RefreshCw className="mr-2 h-4 w-4" />Actualizar</Button>
        </CardHeader>
        <CardContent>
          {loading ? <p className="py-6 text-center text-sm text-muted-foreground">Cargando permisos…</p> : grants.length === 0 ? (
            <p className="py-6 text-center text-sm text-muted-foreground">Todavía no hay capacidades asignadas.</p>
          ) : (
            <div className="space-y-2">
              {grants.map((row) => {
                const member = members.find((candidate) => candidate.user_id === row.user_id);
                return (
                  <div key={row.id} className="flex flex-wrap items-center justify-between gap-3 rounded-md border p-3">
                    <div className="min-w-0">
                      <p className="font-medium">{row.capability}</p>
                      <p className="break-all text-xs text-muted-foreground">{row.user_id}{member ? ' · ' + member.role : ' · miembro no activo'}</p>
                      <p className="text-xs text-muted-foreground">Asignado: {dateLabel(row.granted_at)} · Por: {row.granted_by}</p>
                      {row.revoked_at && <p className="text-xs text-muted-foreground">Revocado: {dateLabel(row.revoked_at)} · Por: {row.revoked_by}{row.revocation_reason ? ' · ' + row.revocation_reason : ''}</p>}
                    </div>
                    {row.revoked_at ? <Badge variant="secondary">Revocado</Badge> : (
                      <div className="flex flex-wrap items-center gap-2">
                        <input aria-label="Motivo opcional de revocación" className="h-9 w-48 rounded-md border bg-background px-2 text-xs" value={revocationReason} onChange={(event) => setRevocationReason(event.target.value)} placeholder="Motivo opcional" />
                        <Button size="sm" variant="destructive" onClick={() => void revoke(row)} disabled={saving}><XCircle className="mr-1.5 h-4 w-4" />Revocar</Button>
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          )}
          <p className="mt-3 text-xs text-muted-foreground">{activeGrants.length} permisos activos de {grants.length} registros de auditoría.</p>
        </CardContent>
      </Card>
    </div>
  );
}
