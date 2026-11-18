import { useCallback, useEffect, useMemo, useState } from 'react';
import { BriefcaseBusiness, Plus, RefreshCw, Search, Paperclip } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { useToast } from '@/hooks/use-toast';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';

type Opportunity = {
  id: string;
  status: string;
  classification: string;
  classification_confidence: number | null;
  classification_reason: string | null;
  commercial_client_id: string | null;
  commercial_site_id: string | null;
  commercial_contact_id: string | null;
  match_status: string;
  subject: string | null;
  sender_email: string | null;
  received_at: string | null;
  snippet: string | null;
  source_system: string;
  source_message_id: string | null;
  source_thread_id: string | null;
  created_at: string;
};

type Client = { id: string; business_name: string };
type Site = { id: string; commercial_client_id: string; site_name: string };
type Contact = { id: string; commercial_client_id: string; commercial_site_id: string | null; full_name: string; email: string | null };

const statusLabels: Record<string, string> = {
  new: 'Nueva',
  reviewing: 'En revisión',
  ready_for_analysis: 'Lista para análisis',
  in_analysis: 'En análisis',
  quoted: 'Cotizada',
  discarded: 'Descartada',
};

const classificationLabels: Record<string, string> = {
  quote_request: 'Solicitud de cotización',
  follow_up: 'Seguimiento',
  information_only: 'Solo información',
  other: 'Otro',
  unknown: 'Sin clasificar',
};

const matchLabels: Record<string, string> = {
  unmatched: 'Sin vincular',
  suggested: 'Coincidencia sugerida',
  confirmed: 'Vinculada',
  ambiguous: 'Requiere revisión',
};

const emptyForm = {
  subject: '',
  sender_email: '',
  received_at: '',
  snippet: '',
  classification: 'quote_request',
  commercial_client_id: '',
  commercial_site_id: '',
  commercial_contact_id: '',
};

const db = supabase as any;

const OpportunitiesView = () => {
  const { currentOrganization, currentMembership } = useAuth();
  const { toast } = useToast();
  const organizationId = currentOrganization?.id ?? '';
  const authorized = currentOrganization?.organizationType === 'provider_company'
    && currentMembership?.isActive
    && currentMembership.organizationId === organizationId
    && ['owner', 'admin', 'manager', 'quote_manager'].includes(currentMembership.role);

  const [opportunities, setOpportunities] = useState<Opportunity[]>([]);
  const [clients, setClients] = useState<Client[]>([]);
  const [sites, setSites] = useState<Site[]>([]);
  const [contacts, setContacts] = useState<Contact[]>([]);
  const [form, setForm] = useState(emptyForm);
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState('all');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  const loadData = useCallback(async () => {
    if (!organizationId || !authorized) return;
    setLoading(true);
    try {
      const [opportunitiesResult, clientsResult, sitesResult, contactsResult] = await Promise.all([
        db.from('romax_opportunities').select('*').eq('organization_id', organizationId).order('received_at', { ascending: false, nullsFirst: false }).order('created_at', { ascending: false }),
        db.from('commercial_clients').select('id,business_name').eq('organization_id', organizationId).eq('is_active', true).order('business_name'),
        db.from('commercial_client_sites').select('id,commercial_client_id,site_name').eq('organization_id', organizationId).eq('is_active', true).order('site_name'),
        db.from('commercial_client_contacts').select('id,commercial_client_id,commercial_site_id,full_name,email').eq('organization_id', organizationId).eq('is_active', true).order('full_name'),
      ]);
      for (const result of [opportunitiesResult, clientsResult, sitesResult, contactsResult]) {
        if (result.error) throw new Error(result.error.message);
      }
      setOpportunities((opportunitiesResult.data ?? []) as Opportunity[]);
      setClients((clientsResult.data ?? []) as Client[]);
      setSites((sitesResult.data ?? []) as Site[]);
      setContacts((contactsResult.data ?? []) as Contact[]);
    } catch (error) {
      toast({ title: 'No se pudo cargar oportunidades', description: error instanceof Error ? error.message : 'Error inesperado.', variant: 'destructive' });
    } finally {
      setLoading(false);
    }
  }, [organizationId, authorized, toast]);

  useEffect(() => { void loadData(); }, [loadData]);

  const filteredSites = useMemo(
    () => sites.filter((site) => !form.commercial_client_id || site.commercial_client_id === form.commercial_client_id),
    [sites, form.commercial_client_id],
  );

  const filteredContacts = useMemo(
    () => contacts.filter((contact) => {
      if (form.commercial_client_id && contact.commercial_client_id !== form.commercial_client_id) return false;
      if (form.commercial_site_id && contact.commercial_site_id && contact.commercial_site_id !== form.commercial_site_id) return false;
      return true;
    }),
    [contacts, form.commercial_client_id, form.commercial_site_id],
  );

  const clientName = (id: string | null) => clients.find((client) => client.id === id)?.business_name ?? 'Sin cliente';
  const siteName = (id: string | null) => sites.find((site) => site.id === id)?.site_name ?? 'Sin sede';
  const contactName = (id: string | null) => contacts.find((contact) => contact.id === id)?.full_name ?? 'Sin contacto';

  const visibleOpportunities = useMemo(() => opportunities.filter((opportunity) => {
    if (statusFilter !== 'all' && opportunity.status !== statusFilter) return false;
    if (!search.trim()) return true;
    const text = [
      opportunity.subject,
      opportunity.sender_email,
      opportunity.snippet,
      clientName(opportunity.commercial_client_id),
      siteName(opportunity.commercial_site_id),
    ].filter(Boolean).join(' ').toLowerCase();
    return text.includes(search.trim().toLowerCase());
  }), [opportunities, statusFilter, search, clients, sites]);

  const resetForm = () => setForm(emptyForm);

  const createOpportunity = async (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!authorized || !organizationId) return;
    setSaving(true);
    try {
      const payload = {
        organization_id: organizationId,
        status: 'new',
        classification: form.classification,
        commercial_client_id: form.commercial_client_id || null,
        commercial_site_id: form.commercial_site_id || null,
        commercial_contact_id: form.commercial_contact_id || null,
        match_status: form.commercial_client_id ? 'confirmed' : 'unmatched',
        subject: form.subject.trim() || null,
        sender_email: form.sender_email.trim() || null,
        received_at: form.received_at ? new Date(form.received_at).toISOString() : null,
        snippet: form.snippet.trim() || null,
        source_system: 'manual',
      };
      const { error } = await db.from('romax_opportunities').insert(payload);
      if (error) throw new Error(error.message);
      toast({ title: 'Oportunidad registrada', description: 'La solicitud quedó disponible para revisión.' });
      resetForm();
      await loadData();
    } catch (error) {
      toast({ title: 'No se pudo registrar la oportunidad', description: error instanceof Error ? error.message : 'Error inesperado.', variant: 'destructive' });
    } finally {
      setSaving(false);
    }
  };

  if (!authorized) {
    return (
      <div className="flex min-h-[60vh] items-center justify-center p-6">
        <Card className="max-w-lg"><CardContent className="p-8 text-center">
          <h2 className="font-semibold">Acceso restringido</h2>
          <p className="mt-2 text-sm text-muted-foreground">La bandeja de oportunidades está disponible para usuarios autorizados de organizaciones proveedoras.</p>
        </CardContent></Card>
      </div>
    );
  }

  return (
    <div className="space-y-6 p-6">
      <header className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <div className="flex items-center gap-2">
            <BriefcaseBusiness className="h-6 w-6" />
            <h1 className="text-2xl font-semibold tracking-tight">Oportunidades</h1>
          </div>
          <p className="mt-1 text-sm text-muted-foreground">Bandeja de solicitudes que alimentará el análisis y el cotizador de ROMAX.</p>
        </div>
        <Button variant="outline" onClick={() => void loadData()} disabled={loading}>
          <RefreshCw className="mr-2 h-4 w-4" />Actualizar
        </Button>
      </header>

      <div className="grid gap-3 sm:grid-cols-3">
        <Card><CardContent className="p-4"><p className="text-sm text-muted-foreground">Nuevas</p><p className="text-2xl font-semibold">{opportunities.filter((row) => row.status === 'new').length}</p></CardContent></Card>
        <Card><CardContent className="p-4"><p className="text-sm text-muted-foreground">En análisis</p><p className="text-2xl font-semibold">{opportunities.filter((row) => row.status === 'in_analysis').length}</p></CardContent></Card>
        <Card><CardContent className="p-4"><p className="text-sm text-muted-foreground">Cotizadas</p><p className="text-2xl font-semibold">{opportunities.filter((row) => row.status === 'quoted').length}</p></CardContent></Card>
      </div>

      <div className="flex flex-wrap items-center gap-3">
        <div className="relative min-w-56 flex-1">
          <Search className="absolute left-3 top-3 h-4 w-4 text-muted-foreground" />
          <Input value={search} onChange={(event) => setSearch(event.target.value)} className="pl-9" placeholder="Buscar asunto, remitente o cliente..." />
        </div>
        <select className="h-10 rounded-md border bg-background px-3 text-sm" value={statusFilter} onChange={(event) => setStatusFilter(event.target.value)}>
          <option value="all">Todos los estados</option>
          {Object.entries(statusLabels).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
        </select>
      </div>

      <div className="grid gap-5 xl:grid-cols-[minmax(0,1fr)_380px]">
        <div className="space-y-3">
          {loading ? (
            <div className="py-12 text-center text-sm text-muted-foreground">Cargando oportunidades…</div>
          ) : visibleOpportunities.length === 0 ? (
            <Card><CardContent className="p-8 text-center">
              <BriefcaseBusiness className="mx-auto mb-2 h-7 w-7 text-muted-foreground" />
              <p className="font-medium">Todavía no hay oportunidades.</p>
              <p className="mt-1 text-sm text-muted-foreground">Mientras se define el buzón de Gmail, puedes registrar una solicitud manual para probar el flujo.</p>
            </CardContent></Card>
          ) : visibleOpportunities.map((opportunity) => (
            <Card key={opportunity.id}>
              <CardContent className="space-y-3 p-4">
                <div className="flex flex-wrap items-start justify-between gap-3">
                  <div className="min-w-0">
                    <div className="flex flex-wrap items-center gap-2">
                      <p className="font-medium">{opportunity.subject || 'Solicitud sin asunto'}</p>
                      <Badge>{statusLabels[opportunity.status] ?? opportunity.status}</Badge>
                      <Badge variant="outline">{classificationLabels[opportunity.classification] ?? opportunity.classification}</Badge>
                    </div>
                    <p className="mt-1 text-sm text-muted-foreground">
                      {clientName(opportunity.commercial_client_id)} · {siteName(opportunity.commercial_site_id)} · {contactName(opportunity.commercial_contact_id)}
                    </p>
                  </div>
                  <Badge variant="secondary">{matchLabels[opportunity.match_status] ?? opportunity.match_status}</Badge>
                </div>
                <div className="grid gap-2 text-sm sm:grid-cols-2">
                  <p><span className="text-muted-foreground">Origen:</span> {opportunity.source_system === 'gmail' ? 'Gmail' : 'Manual'}</p>
                  <p><span className="text-muted-foreground">Remitente:</span> {opportunity.sender_email || 'No informado'}</p>
                  <p><span className="text-muted-foreground">Recibido:</span> {opportunity.received_at ? new Date(opportunity.received_at).toLocaleString('es-PE') : 'No informado'}</p>
                  <p><span className="text-muted-foreground">Adjuntos:</span> <span className="inline-flex items-center gap-1"><Paperclip className="h-3.5 w-3.5" />Se mostrarán aquí al conectar Gmail.</span></p>
                </div>
                {opportunity.snippet && <p className="rounded-md bg-muted/50 p-3 text-sm">{opportunity.snippet}</p>}
              </CardContent>
            </Card>
          ))}
        </div>

        <Card className="h-fit">
          <CardHeader>
            <CardTitle className="text-base">Nueva oportunidad</CardTitle>
            <CardDescription>Entrada manual temporal para probar R3 mientras se define el buzón de Gmail.</CardDescription>
          </CardHeader>
          <CardContent>
            <form className="space-y-3" onSubmit={createOpportunity}>
              <div className="space-y-1.5"><Label htmlFor="opportunity-subject">Asunto</Label><Input id="opportunity-subject" value={form.subject} onChange={(event) => setForm({ ...form, subject: event.target.value })} maxLength={300} /></div>
              <div className="space-y-1.5"><Label htmlFor="opportunity-sender">Remitente</Label><Input id="opportunity-sender" type="email" value={form.sender_email} onChange={(event) => setForm({ ...form, sender_email: event.target.value })} maxLength={320} /></div>
              <div className="space-y-1.5"><Label htmlFor="opportunity-received">Fecha de recepción</Label><Input id="opportunity-received" type="datetime-local" value={form.received_at} onChange={(event) => setForm({ ...form, received_at: event.target.value })} /></div>
              <div className="space-y-1.5"><Label htmlFor="opportunity-classification">Clasificación</Label><select id="opportunity-classification" className="h-10 w-full rounded-md border bg-background px-3 text-sm" value={form.classification} onChange={(event) => setForm({ ...form, classification: event.target.value })}>{Object.entries(classificationLabels).map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select></div>
              <div className="space-y-1.5"><Label htmlFor="opportunity-client">Cliente</Label><select id="opportunity-client" className="h-10 w-full rounded-md border bg-background px-3 text-sm" value={form.commercial_client_id} onChange={(event) => setForm({ ...form, commercial_client_id: event.target.value, commercial_site_id: '', commercial_contact_id: '' })}><option value="">Sin vincular</option>{clients.map((client) => <option key={client.id} value={client.id}>{client.business_name}</option>)}</select></div>
              <div className="space-y-1.5"><Label htmlFor="opportunity-site">Sede</Label><select id="opportunity-site" className="h-10 w-full rounded-md border bg-background px-3 text-sm" value={form.commercial_site_id} onChange={(event) => setForm({ ...form, commercial_site_id: event.target.value, commercial_contact_id: '' })} disabled={!form.commercial_client_id}><option value="">Sin vincular</option>{filteredSites.map((site) => <option key={site.id} value={site.id}>{site.site_name}</option>)}</select></div>
              <div className="space-y-1.5"><Label htmlFor="opportunity-contact">Contacto</Label><select id="opportunity-contact" className="h-10 w-full rounded-md border bg-background px-3 text-sm" value={form.commercial_contact_id} onChange={(event) => setForm({ ...form, commercial_contact_id: event.target.value })} disabled={!form.commercial_client_id}><option value="">Sin vincular</option>{filteredContacts.map((contact) => <option key={contact.id} value={contact.id}>{contact.full_name}{contact.email ? ` · ${contact.email}` : ''}</option>)}</select></div>
              <div className="space-y-1.5"><Label htmlFor="opportunity-snippet">Resumen / contenido inicial</Label><Textarea id="opportunity-snippet" value={form.snippet} onChange={(event) => setForm({ ...form, snippet: event.target.value })} rows={5} placeholder="Pega aquí temporalmente el resumen de la solicitud." /></div>
              <Button type="submit" className="w-full" disabled={saving}><Plus className="mr-2 h-4 w-4" />{saving ? 'Registrando…' : 'Registrar oportunidad'}</Button>
            </form>
          </CardContent>
        </Card>
      </div>
    </div>
  );
};

export default OpportunitiesView;
