import { useEffect, useMemo, useState } from 'react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import type { OrganizationProfileClient, OrganizationProfileForm } from '@/types/organizationProfile';
import type { OrganizationType } from '@/types/organization';
import { isProviderFacingOrganizationType } from '@/types/providerRelationship';

// trim, drop empty entries, and de-dupe case-insensitively (keeping the
// first casing seen) — same normalization on load-time data and on save.
const parseSpecialties = (raw: string): string[] => {
  const seen = new Set<string>();
  const result: string[] = [];
  raw.split(',').forEach((item) => {
    const trimmed = item.trim();
    if (!trimmed) return;
    const key = trimmed.toLowerCase();
    if (seen.has(key)) return;
    seen.add(key);
    result.push(trimmed);
  });
  return result;
};

type OrganizationProfileProps = {
  organizationId?: string;
  readOnly?: boolean;
};

const emptyClient = (): OrganizationProfileClient => ({
  razon_social: '', contact_name: '', email: '', phone: '', annex: '',
});

const defaultProfile = (organization?: { name: string; legal_name: string | null; tax_id: string | null }): OrganizationProfileForm => ({
  commercial_name: organization?.name ?? '',
  legal_name: organization?.legal_name ?? '',
  tax_id: organization?.tax_id ?? '',
  country: 'Perú',
  currency: 'PEN',
  timezone: 'America/Lima',
  contact_email: '',
  phone: '',
  whatsapp: '',
  website: '',
  logo_url: '',
  description: '',
  founded_year: '',
  employee_range: '',
  service_regions: '',
  primary_clients: [],
  presentation_file_url: '',
  certification_status: 'not_requested',
  certification_notes: '',
  specialties: [],
});

export function OrganizationProfile({ organizationId, readOnly = false }: OrganizationProfileProps) {
  const { user, currentOrganization, memberships, organizations } = useAuth();
  const targetOrganizationId = organizationId ?? currentOrganization?.id;
  const [form, setForm] = useState<OrganizationProfileForm>(defaultProfile());
  const [organizationType, setOrganizationType] = useState<OrganizationType | null>(null);
  // Raw comma-separated text the user types; parsed into form.specialties
  // (trim / drop empty / de-dupe) on blur and again right before save, so
  // an unfinished trailing "," never gets lost mid-edit.
  const [specialtiesInput, setSpecialtiesInput] = useState('');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState('');

  const isPlatformAdmin = useMemo(() => memberships.some((membership) =>
    membership.isActive &&
    ['owner', 'admin'].includes(membership.role) &&
    organizations.some((organization) =>
      organization.id === membership.organizationId && organization.organizationType === 'platform_admin',
    ),
  ), [memberships, organizations]);
  const isOrganizationAdmin = memberships.some((membership) =>
    membership.isActive &&
    membership.organizationId === targetOrganizationId &&
    ['owner', 'admin'].includes(membership.role),
  );
  const canEdit = !readOnly && !!user && (isPlatformAdmin || isOrganizationAdmin);
  const isProviderFacing = !!organizationType && isProviderFacingOrganizationType(organizationType);
  const specialtiesPreview = useMemo(() => parseSpecialties(specialtiesInput), [specialtiesInput]);

  useEffect(() => {
    const load = async () => {
      if (!targetOrganizationId) {
        setLoading(false);
        return;
      }

      setLoading(true);
      setMessage('');
      try {
        const [{ data: organization, error: organizationError }, { data: profile, error: profileError }] = await Promise.all([
          supabase.from('organizations').select('id, name, legal_name, tax_id, organization_type').eq('id', targetOrganizationId).maybeSingle(),
          supabase.from('organization_profiles').select('*').eq('organization_id', targetOrganizationId).maybeSingle(),
        ]);
        if (organizationError) throw organizationError;
        if (profileError) throw profileError;
        if (!organization) {
          setMessage('No tienes acceso a esta organización.');
          return;
        }

        setOrganizationType(organization.organization_type);
        const specialties = profile?.specialties ?? [];
        setSpecialtiesInput(specialties.join(', '));
        setForm(profile ? {
          commercial_name: profile.commercial_name ?? organization.name,
          legal_name: profile.legal_name ?? organization.legal_name ?? '',
          tax_id: profile.tax_id ?? organization.tax_id ?? '',
          country: profile.country,
          currency: profile.currency,
          timezone: profile.timezone,
          contact_email: profile.contact_email ?? '',
          phone: profile.phone ?? '',
          whatsapp: profile.whatsapp ?? '',
          website: profile.website ?? '',
          logo_url: profile.logo_url ?? '',
          description: profile.description ?? '',
          founded_year: profile.founded_year?.toString() ?? '',
          employee_range: profile.employee_range ?? '',
          service_regions: profile.service_regions ?? '',
          primary_clients: Array.isArray(profile.primary_clients) ? profile.primary_clients as unknown as OrganizationProfileClient[] : [],
          presentation_file_url: profile.presentation_file_url ?? '',
          certification_status: profile.certification_status,
          certification_notes: profile.certification_notes ?? '',
          specialties,
        } : defaultProfile(organization));
      } catch (error) {
        setMessage(error instanceof Error ? error.message : 'No se pudo cargar el perfil.');
      } finally {
        setLoading(false);
      }
    };
    void load();
  }, [targetOrganizationId]);

  const setField = <K extends keyof OrganizationProfileForm>(key: K, value: OrganizationProfileForm[K]) => {
    setForm((current) => ({ ...current, [key]: value }));
  };

  const save = async () => {
    if (!targetOrganizationId || !user || !canEdit) return;
    const foundedYear = form.founded_year ? Number(form.founded_year) : null;
    if (form.founded_year && (!Number.isInteger(foundedYear) || foundedYear < 1800 || foundedYear > new Date().getFullYear() + 1)) {
      setMessage('El año de constitución no es válido.');
      return;
    }

    setSaving(true);
    setMessage('');
    try {
      const { error: profileError } = await supabase.from('organization_profiles').upsert({
        organization_id: targetOrganizationId,
        commercial_name: form.commercial_name || null,
        legal_name: form.legal_name || null,
        tax_id: form.tax_id || null,
        country: form.country,
        currency: form.currency,
        timezone: form.timezone,
        contact_email: form.contact_email || null,
        phone: form.phone || null,
        whatsapp: form.whatsapp || null,
        website: form.website || null,
        logo_url: form.logo_url || null,
        description: form.description || null,
        founded_year: foundedYear,
        employee_range: form.employee_range || null,
        service_regions: form.service_regions || null,
        primary_clients: form.primary_clients,
        presentation_file_url: form.presentation_file_url || null,
        specialties: isProviderFacing ? parseSpecialties(specialtiesInput) : form.specialties,
        certification_status: form.certification_status,
        certification_notes: form.certification_notes || null,
        updated_by_user_id: user.id,
      }, { onConflict: 'organization_id' });
      if (profileError) throw profileError;

      // Existing organization RLS lets only that organization's owner/admin update
      // the transition columns. Platform admins still persist the business profile.
      if (isOrganizationAdmin) {
        const { error: organizationError } = await supabase.from('organizations').update({
          name: form.commercial_name || 'Sin nombre comercial',
          legal_name: form.legal_name || null,
          tax_id: form.tax_id || null,
        }).eq('id', targetOrganizationId);
        if (organizationError) throw organizationError;
      }
      setMessage('Perfil de organización guardado correctamente.');
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'No se pudo guardar el perfil.');
    } finally {
      setSaving(false);
    }
  };

  if (!targetOrganizationId) return <Card><CardContent className="p-6">Sin organización asignada.</CardContent></Card>;
  if (loading) return <Card><CardContent className="p-6">Cargando perfil…</CardContent></Card>;

  const disabled = !canEdit || saving;
  const input = (label: string, key: keyof OrganizationProfileForm, type = 'text') => (
    <div className="space-y-2"><Label>{label}</Label><Input type={type} value={String(form[key] ?? '')} disabled={disabled} onChange={(event) => setField(key, event.target.value as never)} /></div>
  );
  const updateClient = (index: number, key: keyof OrganizationProfileClient, value: string) => setField('primary_clients', form.primary_clients.map((client, clientIndex) => clientIndex === index ? { ...client, [key]: value } : client));

  const tabTriggerClass = 'data-[state=active]:bg-onefacility-blue data-[state=active]:text-white data-[state=active]:shadow-soft';

  return <div className="space-y-6 p-6">
    <div className="flex flex-wrap items-center justify-between gap-3"><div><h1 className="text-2xl font-semibold text-onefacility-navy">Perfil organización</h1><p className="text-sm text-muted-foreground">Información empresarial de la organización activa.</p></div>{!canEdit && <Badge variant="secondary">Solo lectura</Badge>}</div>
    {message && <p className="text-sm text-muted-foreground">{message}</p>}

    <Tabs defaultValue="contact" className="space-y-4">
      <div className="-mx-1 overflow-x-auto px-1">
        <TabsList className="inline-flex w-max gap-1 rounded-lg border border-onefacility-border bg-onefacility-surface p-1">
          <TabsTrigger value="contact" className={tabTriggerClass}>Datos de contacto</TabsTrigger>
          <TabsTrigger value="company" className={tabTriggerClass}>Empresa</TabsTrigger>
          <TabsTrigger value="commercial" className={tabTriggerClass}>Información comercial</TabsTrigger>
          <TabsTrigger value="clients" className={tabTriggerClass}>Clientes</TabsTrigger>
          <TabsTrigger value="documents" className={tabTriggerClass}>Documentos</TabsTrigger>
        </TabsList>
      </div>

      <TabsContent value="contact">
        <Card><CardHeader><CardTitle>Mi información / Datos de contacto</CardTitle></CardHeader><CardContent className="grid gap-4 md:grid-cols-2">{input('Nombre comercial', 'commercial_name')}{input('Razón social', 'legal_name')}{input('RUC / Código tributario', 'tax_id')}{input('Correo de contacto', 'contact_email', 'email')}{input('Teléfono', 'phone')}{input('WhatsApp', 'whatsapp')}{input('Website', 'website', 'url')}</CardContent></Card>
      </TabsContent>

      <TabsContent value="company">
        <Card><CardHeader><CardTitle>Empresa</CardTitle></CardHeader><CardContent className="grid gap-4 md:grid-cols-2">{input('Logo URL', 'logo_url', 'url')}{form.logo_url && <img src={form.logo_url} alt="Logo de la organización" className="h-20 max-w-48 rounded border object-contain" />}{input('País', 'country')}{input('Moneda', 'currency')}{input('Zona horaria', 'timezone')}</CardContent></Card>
      </TabsContent>

      <TabsContent value="commercial">
        <Card><CardHeader><CardTitle>Información comercial</CardTitle></CardHeader><CardContent className="grid gap-4 md:grid-cols-2">{input('Año de constitución', 'founded_year', 'number')}{input('Número de empleados', 'employee_range')}{input('Zona / Región de cobertura', 'service_regions')}
          {isProviderFacing && (
            <div className="space-y-2 md:col-span-2">
              <Label htmlFor="specialties">Especialidades</Label>
              <Input
                id="specialties"
                value={specialtiesInput}
                disabled={disabled}
                placeholder="Ej: HVAC, Electricidad, Plomería"
                onChange={(event) => setSpecialtiesInput(event.target.value)}
                onBlur={() => setSpecialtiesInput(parseSpecialties(specialtiesInput).join(', '))}
              />
              <p className="text-xs text-muted-foreground">Separadas por coma. Visibles para los clientes que te homologuen.</p>
              {specialtiesPreview.length > 0 && (
                <div className="flex flex-wrap gap-1 pt-1">
                  {specialtiesPreview.map((specialty) => <Badge key={specialty} variant="outline">{specialty}</Badge>)}
                </div>
              )}
            </div>
          )}
          <div className="space-y-2 md:col-span-2"><Label>Descripción empresarial</Label><Textarea value={form.description} disabled={disabled} onChange={(event) => setField('description', event.target.value)} /></div></CardContent></Card>
      </TabsContent>

      <TabsContent value="clients">
        <Card><CardHeader><CardTitle>Principales clientes</CardTitle></CardHeader><CardContent className="space-y-3">{form.primary_clients.map((client, index) => <div key={`${client.razon_social}-${index}`} className="grid gap-2 rounded border p-3 md:grid-cols-3">{(['razon_social','contact_name','email','phone','annex'] as const).map((key) => <Input key={key} disabled={disabled} placeholder={key === 'razon_social' ? 'Razón social' : key} value={client[key]} onChange={(event) => updateClient(index, key, event.target.value)} />)}{canEdit && <Button variant="outline" onClick={() => setField('primary_clients', form.primary_clients.filter((_, clientIndex) => clientIndex !== index))}>Eliminar</Button>}</div>)}{canEdit && <Button variant="outline" onClick={() => setField('primary_clients', [...form.primary_clients, emptyClient()])}>Agregar cliente</Button>}</CardContent></Card>
      </TabsContent>

      <TabsContent value="documents">
        <Card><CardHeader><CardTitle>Carta de presentación / Certificación</CardTitle></CardHeader><CardContent className="grid gap-4 md:grid-cols-2">{input('URL carta de presentación', 'presentation_file_url', 'url')}<div className="space-y-2"><Label>Estado de certificación</Label><Input value={form.certification_status} disabled={disabled} onChange={(event) => setField('certification_status', event.target.value)} /></div><div className="space-y-2 md:col-span-2"><Label>Notas de certificación</Label><Textarea value={form.certification_notes} disabled={disabled} onChange={(event) => setField('certification_notes', event.target.value)} /></div><p className="text-sm text-muted-foreground md:col-span-2">La carga de documentos de certificación quedará pendiente para la integración con Storage/R2.</p></CardContent></Card>
      </TabsContent>
    </Tabs>

    {canEdit && <div className="flex justify-end border-t border-onefacility-border pt-4"><Button onClick={() => void save()} disabled={saving}>{saving ? 'Guardando…' : 'Guardar perfil'}</Button></div>}
  </div>;
}
