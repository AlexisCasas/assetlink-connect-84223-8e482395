import { useEffect, useMemo, useState } from 'react';
import { Archive, Building2, Eye, EyeOff, Plus, Search, Users } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { OrganizationProfile } from '@/components/organization/OrganizationProfile';
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from '@/components/ui/alert-dialog';
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import type { Organization, OrganizationMemberRole, OrganizationType } from '@/types/organization';
import { ORGANIZATION_ROLE_LABELS } from '@/lib/organizationRoles';

type Member = { id: string; user_id: string; email: string | null; name: string | null; role: OrganizationMemberRole; is_active: boolean; joined_at: string };
const roles: OrganizationMemberRole[] = ['owner', 'admin', 'manager', 'requester', 'quote_manager', 'technician', 'operator', 'viewer'];
const organizationTypes: OrganizationType[] = ['client_company', 'provider_company', 'facility_manager', 'subcontractor_company'];
const typeLabels: Record<OrganizationType, string> = { client_company: 'Cliente', provider_company: 'Proveedor', facility_manager: 'Facility manager', subcontractor_company: 'Subcontratista', platform_admin: 'Administrador plataforma' };
const toSettingsRecord = (value: unknown): Record<string, unknown> =>
  value && typeof value === 'object' && !Array.isArray(value) ? (value as Record<string, unknown>) : {};

export function AdminConsole() {
  const { memberships, organizations } = useAuth();
  const isPlatformAdmin = memberships.some((membership) => membership.isActive && ['owner', 'admin'].includes(membership.role) && organizations.some((organization) => organization.id === membership.organizationId && organization.organizationType === 'platform_admin'));
  const [items, setItems] = useState<Organization[]>([]);
  const [selectedOrganization, setSelectedOrganization] = useState<Organization | null>(null);
  const [isMembersDialogOpen, setIsMembersDialogOpen] = useState(false);
  const [profileOrganization, setProfileOrganization] = useState<Organization | null>(null);
  const [archiveTarget, setArchiveTarget] = useState<Organization | null>(null);
  const [newOrganizationOpen, setNewOrganizationOpen] = useState(false);
  const [members, setMembers] = useState<Member[]>([]);
  const [search, setSearch] = useState('');
  const [typeFilter, setTypeFilter] = useState('all');
  const [statusFilter, setStatusFilter] = useState('all');
  const [showArchived, setShowArchived] = useState(false);
  const [currentPage, setCurrentPage] = useState(1);
  const [pageSize, setPageSize] = useState(5);
  const [organizationName, setOrganizationName] = useState('');
  const [organizationType, setOrganizationType] = useState<OrganizationType>('client_company');
  const [memberEmail, setMemberEmail] = useState('');
  const [memberName, setMemberName] = useState('');
  const [temporaryPassword, setTemporaryPassword] = useState('');
  const [memberRole, setMemberRole] = useState<OrganizationMemberRole>('viewer');
  const [loadingOrganizations, setLoadingOrganizations] = useState(false);
  const [loadingMembers, setLoadingMembers] = useState(false);
  const [saving, setSaving] = useState(false);
  const [savingMember, setSavingMember] = useState(false);
  const [message, setMessage] = useState('');

  const invoke = async (functionName: string, body: unknown) => { const { data, error } = await supabase.functions.invoke(functionName, { body }); if (error) throw error; return data; };
  const loadOrganizations = async () => { setLoadingOrganizations(true); try { const { data, error } = await supabase.from('organizations').select('*').order('created_at', { ascending: false }); if (error) throw error; setItems((data ?? []).map((organization) => ({ id: organization.id, name: organization.name, legalName: organization.legal_name, organizationType: organization.organization_type, taxId: organization.tax_id, status: organization.status as Organization['status'], settings: toSettingsRecord(organization.settings), createdBy: organization.created_by, createdAt: organization.created_at, updatedAt: organization.updated_at }))); } catch (error) { setMessage(error instanceof Error ? error.message : 'No se pudieron cargar organizaciones.'); } finally { setLoadingOrganizations(false); } };
  const loadMembers = async (organization: Organization) => { setSelectedOrganization(organization); setLoadingMembers(true); try { const data = await invoke('admin-list-organization-members', { organization_id: organization.id }); setMembers(data.members ?? []); } catch (error) { setMessage(error instanceof Error ? error.message : 'No se pudieron cargar miembros.'); } finally { setLoadingMembers(false); } };
  const openMembersDialog = (organization: Organization) => { setIsMembersDialogOpen(true); void loadMembers(organization); };
  useEffect(() => { if (isPlatformAdmin) void loadOrganizations(); }, [isPlatformAdmin]);

  const filteredItems = useMemo(() => items.filter((organization) => { const haystack = `${organization.name} ${organization.legalName ?? ''} ${organization.taxId ?? ''} ${typeLabels[organization.organizationType]}`.toLowerCase(); return (!search || haystack.includes(search.toLowerCase())) && (typeFilter === 'all' || organization.organizationType === typeFilter) && (statusFilter === 'all' || organization.status === statusFilter) && (showArchived || organization.status !== 'archived'); }), [items, search, statusFilter, typeFilter, showArchived]);
  const summary = useMemo(() => ({ total: items.length, clients: items.filter((item) => item.organizationType === 'client_company').length, providers: items.filter((item) => ['provider_company', 'facility_manager', 'subcontractor_company'].includes(item.organizationType)).length, platform: items.filter((item) => item.organizationType === 'platform_admin').length, archived: items.filter((item) => item.status === 'archived').length }), [items]);
  const hiddenArchivedCount = showArchived ? 0 : summary.archived;

  const totalPages = Math.max(1, Math.ceil(filteredItems.length / pageSize));
  const paginatedItems = useMemo(() => filteredItems.slice((currentPage - 1) * pageSize, currentPage * pageSize), [filteredItems, currentPage, pageSize]);
  const paginationStart = filteredItems.length === 0 ? 0 : (currentPage - 1) * pageSize + 1;
  const paginationEnd = Math.min(currentPage * pageSize, filteredItems.length);
  useEffect(() => { setCurrentPage(1); }, [search, typeFilter, statusFilter, showArchived, pageSize]);
  useEffect(() => { if (currentPage > totalPages) setCurrentPage(totalPages); }, [totalPages, currentPage]);

  const handleStatusFilterChange = (value: string) => { setStatusFilter(value); if (value === 'archived') setShowArchived(true); };
  const toggleShowArchived = () => setShowArchived((current) => { const next = !current; if (!next && statusFilter === 'archived') setStatusFilter('all'); return next; });

  const createOrganization = async () => { setSaving(true); try { await invoke('admin-create-organization', { name: organizationName, organization_type: organizationType }); setOrganizationName(''); setNewOrganizationOpen(false); await loadOrganizations(); setMessage('Organización creada correctamente.'); } catch (error) { setMessage(error instanceof Error ? error.message : 'No se pudo crear la organización.'); } finally { setSaving(false); } };
  const archiveOrganization = async () => { if (!archiveTarget) return; setSaving(true); try { await invoke('admin-archive-organization', { organization_id: archiveTarget.id }); setArchiveTarget(null); if (selectedOrganization?.id === archiveTarget.id) { setSelectedOrganization(null); setMembers([]); setIsMembersDialogOpen(false); } await loadOrganizations(); setMessage('Organización archivada correctamente.'); } catch (error) { setMessage(error instanceof Error ? error.message : 'No se pudo archivar la organización.'); } finally { setSaving(false); } };
  const updateMembership = async (member: Member, changes: object) => { if (!selectedOrganization) return; setSavingMember(true); try { await invoke('admin-update-organization-member', { membership_id: member.id, ...changes }); await loadMembers(selectedOrganization); setMessage('Membresía actualizada.'); } catch (error) { setMessage(error instanceof Error ? error.message : 'No se pudo actualizar la membresía.'); } finally { setSavingMember(false); } };
  const createMember = async () => { if (!selectedOrganization) return; if (temporaryPassword && temporaryPassword.length < 8) return setMessage('La contraseña temporal debe tener al menos 8 caracteres.'); setSavingMember(true); try { await invoke('admin-create-user-and-add-member', { organization_id: selectedOrganization.id, email: memberEmail, name: memberName, role: memberRole, ...(temporaryPassword ? { temporary_password: temporaryPassword } : {}) }); setMemberEmail(''); setMemberName(''); setTemporaryPassword(''); await loadMembers(selectedOrganization); setMessage('Usuario creado o actualizado correctamente.'); } catch (error) { setMessage(error instanceof Error ? error.message : 'No se pudo crear el usuario.'); } finally { setSavingMember(false); } };

  if (!isPlatformAdmin) return <Card><CardContent className="p-8 text-center">Acceso denegado.</CardContent></Card>;
  if (profileOrganization) return <div><div className="p-6 pb-0"><Button variant="outline" onClick={() => setProfileOrganization(null)}>Volver a Administración</Button></div><OrganizationProfile organizationId={profileOrganization.id} readOnly={profileOrganization.status === 'archived'} /></div>;

  return <div className="space-y-6 p-6">
    <header className="flex flex-wrap items-end justify-between gap-4"><div><h1 className="text-3xl font-semibold tracking-tight">Administración</h1><p className="mt-1 text-muted-foreground">Gestiona organizaciones, usuarios y perfiles empresariales.</p></div><Button onClick={() => setNewOrganizationOpen(true)}><Plus className="mr-2 h-4 w-4" />Nueva organización</Button></header>
    <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-5">{[['Total organizaciones', summary.total, Building2], ['Clientes', summary.clients, Building2], ['Proveedores', summary.providers, Users], ['Administradores plataforma', summary.platform, Users], ['Archivadas', summary.archived, Archive]].map(([label, value, Icon]) => <Card key={label as string}><CardContent className="flex items-center justify-between gap-2 p-3"><div className="min-w-0"><p className="truncate text-xs text-muted-foreground">{label as string}</p><p className="text-lg font-semibold">{value as number}</p></div>{typeof Icon === 'function' && <Icon className="h-4 w-4 shrink-0 text-muted-foreground" />}</CardContent></Card>)}</div>
    <Card><CardContent className="flex flex-wrap gap-3 p-4"><div className="relative min-w-64 flex-1"><Search className="absolute left-3 top-3 h-4 w-4 text-muted-foreground" /><Input className="pl-9" value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Buscar por nombre, razón social o RUC" /></div><Select value={typeFilter} onValueChange={setTypeFilter}><SelectTrigger className="w-52"><SelectValue placeholder="Tipo" /></SelectTrigger><SelectContent><SelectItem value="all">Todos los tipos</SelectItem>{([...organizationTypes, 'platform_admin'] as OrganizationType[]).map((type) => <SelectItem key={type} value={type}>{typeLabels[type]}</SelectItem>)}</SelectContent></Select><Select value={statusFilter} onValueChange={handleStatusFilterChange}><SelectTrigger className="w-40"><SelectValue placeholder="Estado" /></SelectTrigger><SelectContent><SelectItem value="all">Todos los estados</SelectItem><SelectItem value="active">Activa</SelectItem><SelectItem value="suspended">Suspendida</SelectItem><SelectItem value="archived">Archivada</SelectItem></SelectContent></Select></CardContent></Card>
    {message && <p role="status" className="rounded-md border bg-muted p-3 text-sm">{message}</p>}
    <Card><CardHeader className="flex flex-row flex-wrap items-center justify-between gap-3 space-y-0"><CardTitle>Organizaciones</CardTitle><div className="flex flex-wrap items-center gap-3">{hiddenArchivedCount > 0 && <span className="text-sm text-muted-foreground">{hiddenArchivedCount} organización{hiddenArchivedCount === 1 ? '' : 'es'} archivada{hiddenArchivedCount === 1 ? '' : 's'} oculta{hiddenArchivedCount === 1 ? '' : 's'}</span>}<Button size="sm" variant="outline" onClick={toggleShowArchived}>{showArchived ? <EyeOff className="mr-1 h-4 w-4" /> : <Eye className="mr-1 h-4 w-4" />}{showArchived ? 'Ocultar archivadas' : 'Ver archivadas'}</Button></div></CardHeader><CardContent>{loadingOrganizations ? <p className="py-8 text-center text-muted-foreground">Cargando organizaciones…</p> : filteredItems.length === 0 ? <div className="py-12 text-center"><Building2 className="mx-auto mb-3 h-8 w-8 text-muted-foreground" /><p className="font-medium">No hay organizaciones para mostrar.</p><p className="text-sm text-muted-foreground">Ajusta los filtros o crea una organización nueva.</p></div> : <><div className="overflow-x-auto"><table className="w-full text-sm"><thead className="border-b text-left text-muted-foreground"><tr><th className="p-3">Organización</th><th className="p-3">Tipo</th><th className="p-3">Estado</th><th className="p-3">RUC</th><th className="p-3">Creada</th><th className="p-3 text-right">Acciones</th></tr></thead><tbody>{paginatedItems.map((organization) => <tr key={organization.id} className="border-b last:border-0"><td className="p-3"><p className="font-medium">{organization.name}</p>{organization.legalName && <p className="text-xs text-muted-foreground">{organization.legalName}</p>}</td><td className="p-3"><Badge variant="secondary">{typeLabels[organization.organizationType]}</Badge></td><td className="p-3"><Badge variant={organization.status === 'archived' ? 'outline' : 'default'}>{organization.status === 'archived' ? 'Archivada' : organization.status === 'suspended' ? 'Suspendida' : 'Activa'}</Badge></td><td className="p-3">{organization.taxId ?? '—'}</td><td className="p-3">{new Date(organization.createdAt).toLocaleDateString()}</td><td className="p-3"><div className="flex justify-end gap-2"><Button size="sm" variant="outline" disabled={organization.status === 'archived'} onClick={() => openMembersDialog(organization)}><Users className="mr-1 h-4 w-4" />Miembros</Button><Button size="sm" variant="outline" onClick={() => setProfileOrganization(organization)}><Eye className="mr-1 h-4 w-4" />Perfil</Button>{organization.organizationType !== 'platform_admin' && <Button size="sm" variant="destructive" disabled={organization.status === 'archived'} onClick={() => setArchiveTarget(organization)}><Archive className="mr-1 h-4 w-4" />Archivar</Button>}</div></td></tr>)}</tbody></table></div><div className="mt-4 flex flex-wrap items-center justify-between gap-3 border-t border-onefacility-border pt-4 text-sm text-muted-foreground"><span>Mostrando {paginationStart}-{paginationEnd} de {filteredItems.length} organizaciones</span><div className="flex flex-wrap items-center gap-3"><div className="flex items-center gap-2"><span>Por página</span><Select value={String(pageSize)} onValueChange={(value) => setPageSize(Number(value))}><SelectTrigger className="w-20"><SelectValue /></SelectTrigger><SelectContent><SelectItem value="5">5</SelectItem><SelectItem value="10">10</SelectItem><SelectItem value="20">20</SelectItem></SelectContent></Select></div><div className="flex items-center gap-2"><Button size="sm" variant="outline" disabled={currentPage <= 1} onClick={() => setCurrentPage((page) => page - 1)}>Anterior</Button><Button size="sm" variant="outline" disabled={currentPage >= totalPages} onClick={() => setCurrentPage((page) => page + 1)}>Siguiente</Button></div></div></div></>}</CardContent></Card>
    <Dialog open={isMembersDialogOpen} onOpenChange={(open) => { setIsMembersDialogOpen(open); if (!open) { setSelectedOrganization(null); setMembers([]); } }}>
      <DialogContent className="max-w-4xl max-h-[85vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{selectedOrganization?.name ?? 'Miembros'}</DialogTitle>
          <DialogDescription>Gestiona los miembros actuales y crea nuevos usuarios para esta organización.</DialogDescription>
        </DialogHeader>
        {selectedOrganization && <div className="space-y-5">
          <div className="flex flex-wrap items-center justify-between gap-3 rounded-md border border-onefacility-border bg-onefacility-surface p-4 text-sm">
            <div className="flex flex-wrap gap-4">
              <span><strong>Tipo:</strong> {typeLabels[selectedOrganization.organizationType]}</span>
              <span><strong>RUC:</strong> {selectedOrganization.taxId ?? '—'}</span>
              <span><strong>Estado:</strong> {selectedOrganization.status === 'archived' ? 'Archivada' : selectedOrganization.status === 'suspended' ? 'Suspendida' : 'Activa'}</span>
            </div>
            <Button size="sm" variant="outline" onClick={() => setProfileOrganization(selectedOrganization)}>Ver perfil</Button>
          </div>

          {message && <p role="status" className="rounded-md border bg-muted p-3 text-sm">{message}</p>}

          <div className="space-y-2">
            <h3 className="text-sm font-semibold text-onefacility-navy">Miembros actuales</h3>
            {loadingMembers ? (
              <p className="py-8 text-center text-muted-foreground">Cargando miembros…</p>
            ) : members.length === 0 ? (
              <div className="rounded-md border border-dashed py-10 text-center text-muted-foreground">
                <Users className="mx-auto mb-2 h-6 w-6" />
                <p className="font-medium">Esta organización todavía no tiene miembros.</p>
                <p className="text-sm">Crea el primer usuario con el formulario de abajo.</p>
              </div>
            ) : (
              <div className="space-y-2">
                {members.map((member) => <div key={member.id} className="flex flex-wrap items-center justify-between gap-2 rounded border p-3 text-sm"><span>{member.name || '—'} · {member.email || '—'} · {member.is_active ? 'Activo' : 'Inactivo'}</span><div className="flex gap-2"><Select value={member.role} onValueChange={(value) => void updateMembership(member, { role: value })}><SelectTrigger className="w-36"><SelectValue /></SelectTrigger><SelectContent>{roles.map((role) => <SelectItem key={role} value={role}>{ORGANIZATION_ROLE_LABELS[role]}</SelectItem>)}</SelectContent></Select><Button size="sm" variant="outline" disabled={savingMember} onClick={() => void updateMembership(member, { is_active: !member.is_active })}>{member.is_active ? 'Desactivar' : 'Activar'}</Button></div></div>)}
              </div>
            )}
          </div>

          {/* Legacy/staging-only (Fase 1 · Punto 6B): admin-create-user-and-add-member
              activates a membership immediately, with no acceptance step,
              and is meant for staging/demo data where invitation emails
              can't be delivered to fictitious addresses — never for
              production, where "Invitar usuario" (Usuarios, #users) is the
              productive flow. Hidden outright in production builds. */}
          {import.meta.env.VITE_APP_ENV !== 'production' && (
            <Card>
              <CardHeader><CardTitle className="text-base">Crear usuario (solo staging/demo)</CardTitle></CardHeader>
              <CardContent className="grid gap-3 md:grid-cols-2">
                <div><Label>Correo electrónico</Label><Input value={memberEmail} onChange={(event) => setMemberEmail(event.target.value)} placeholder="email@empresa.com" /></div>
                <div><Label>Nombre</Label><Input value={memberName} onChange={(event) => setMemberName(event.target.value)} placeholder="Nombre opcional" /></div>
                <div><Label>Contraseña temporal</Label><Input type="password" value={temporaryPassword} onChange={(event) => setTemporaryPassword(event.target.value)} placeholder="Mínimo 8 caracteres" /></div>
                <div><Label>Rol</Label><Select value={memberRole} onValueChange={(value) => setMemberRole(value as OrganizationMemberRole)}><SelectTrigger><SelectValue /></SelectTrigger><SelectContent>{roles.map((role) => <SelectItem key={role} value={role}>{ORGANIZATION_ROLE_LABELS[role]}</SelectItem>)}</SelectContent></Select></div>
                <Button className="md:col-span-2" disabled={savingMember || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(memberEmail) || (temporaryPassword.length > 0 && temporaryPassword.length < 8)} onClick={() => void createMember()}>{savingMember ? 'Creando…' : 'Crear usuario'}</Button>
              </CardContent>
            </Card>
          )}
        </div>}
      </DialogContent>
    </Dialog>
    <Dialog open={newOrganizationOpen} onOpenChange={setNewOrganizationOpen}><DialogContent><DialogHeader><DialogTitle>Nueva organización</DialogTitle><DialogDescription>Crea una organización tenant-aware para administrar sus miembros y perfil.</DialogDescription></DialogHeader><div className="space-y-4"><div><Label>Nombre</Label><Input value={organizationName} onChange={(event) => setOrganizationName(event.target.value)} /></div><div><Label>Tipo</Label><Select value={organizationType} onValueChange={(value) => setOrganizationType(value as OrganizationType)}><SelectTrigger><SelectValue /></SelectTrigger><SelectContent>{organizationTypes.map((type) => <SelectItem key={type} value={type}>{typeLabels[type]}</SelectItem>)}</SelectContent></Select></div><Button className="w-full" disabled={saving || !organizationName.trim()} onClick={() => void createOrganization()}>Crear organización</Button></div></DialogContent></Dialog>
    <AlertDialog open={!!archiveTarget} onOpenChange={(open) => !open && setArchiveTarget(null)}><AlertDialogContent><AlertDialogHeader><AlertDialogTitle>Eliminar organización</AlertDialogTitle><AlertDialogDescription>Esta acción archivará la organización y conservará su historial. Los usuarios ya no deberían operar sobre ella.</AlertDialogDescription></AlertDialogHeader><AlertDialogFooter><AlertDialogCancel disabled={saving}>Cancelar</AlertDialogCancel><AlertDialogAction disabled={saving} onClick={(event) => { event.preventDefault(); void archiveOrganization(); }}>{saving ? 'Archivando…' : 'Archivar organización'}</AlertDialogAction></AlertDialogFooter></AlertDialogContent></AlertDialog>
  </div>;
}
