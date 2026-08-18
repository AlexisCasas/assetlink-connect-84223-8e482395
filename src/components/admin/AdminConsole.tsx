import { useEffect, useState } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import type {
  Organization,
  OrganizationMemberRole,
  OrganizationType,
} from '@/types/organization';

type Member = {
  id: string;
  user_id: string;
  email: string | null;
  name: string | null;
  role: OrganizationMemberRole;
  is_active: boolean;
  joined_at: string;
};

const roles: OrganizationMemberRole[] = [
  'owner',
  'admin',
  'manager',
  'requester',
  'quote_manager',
  'technician',
  'operator',
  'viewer',
];

const organizationTypes: OrganizationType[] = [
  'client_company',
  'provider_company',
  'facility_manager',
  'subcontractor_company',
];

export function AdminConsole() {
  const { memberships, organizations } = useAuth();
  const isPlatformAdmin = memberships.some(
    (membership) =>
      membership.isActive &&
      ['owner', 'admin'].includes(membership.role) &&
      organizations.some(
        (organization) =>
          organization.id === membership.organizationId &&
          organization.organizationType === 'platform_admin',
      ),
  );

  const [items, setItems] = useState<Organization[]>([]);
  const [selected, setSelected] = useState<Organization | null>(null);
  const [members, setMembers] = useState<Member[]>([]);
  const [organizationName, setOrganizationName] = useState('');
  const [memberEmail, setMemberEmail] = useState('');
  const [memberName, setMemberName] = useState('');
  const [temporaryPassword, setTemporaryPassword] = useState('');
  const [organizationType, setOrganizationType] =
    useState<OrganizationType>('client_company');
  const [memberRole, setMemberRole] = useState<OrganizationMemberRole>('viewer');
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState('');

  const invoke = async (functionName: string, body: unknown) => {
    const { data, error } = await supabase.functions.invoke(functionName, { body });
    if (error) throw error;
    return data;
  };

  const loadOrganizations = async () => {
    setLoading(true);
    try {
      const { data, error } = await supabase
        .from('organizations')
        .select('*')
        .order('created_at');

      if (error) throw error;

      setItems(
        (data ?? []).map((organization) => ({
          id: organization.id,
          name: organization.name,
          legalName: organization.legal_name,
          organizationType: organization.organization_type,
          taxId: organization.tax_id,
          status: organization.status,
          settings: organization.settings,
          createdBy: organization.created_by,
          createdAt: organization.created_at,
          updatedAt: organization.updated_at,
        })),
      );
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'No se pudieron cargar organizaciones.');
    } finally {
      setLoading(false);
    }
  };

  const loadMembers = async (organization: Organization) => {
    setSelected(organization);
    setLoading(true);
    try {
      const data = await invoke('admin-list-organization-members', {
        organization_id: organization.id,
      });
      setMembers(data.members ?? []);
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'No se pudieron cargar miembros.');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    if (isPlatformAdmin) void loadOrganizations();
  }, [isPlatformAdmin]);

  const updateMembership = async (member: Member, changes: object) => {
    const activeOwners = members.filter(
      (item) => item.role === 'owner' && item.is_active,
    );
    const removesLastOwner =
      member.role === 'owner' &&
      member.is_active &&
      activeOwners.length === 1 &&
      ((changes as { role?: OrganizationMemberRole }).role !== 'owner' ||
        (changes as { is_active?: boolean }).is_active === false);

    if (removesLastOwner) {
      setMessage('No puedes modificar el último owner activo.');
      return;
    }

    setSaving(true);
    try {
      await invoke('admin-update-organization-member', {
        membership_id: member.id,
        ...changes,
      });
      if (selected) await loadMembers(selected);
      setMessage('Membresía actualizada.');
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'No se pudo actualizar la membresía.');
    } finally {
      setSaving(false);
    }
  };

  const createMember = async () => {
    if (!selected) return;

    if (temporaryPassword && temporaryPassword.length < 8) {
      setMessage('La contraseña temporal debe tener al menos 8 caracteres.');
      return;
    }

    setSaving(true);
    try {
      await invoke('admin-create-user-and-add-member', {
        organization_id: selected.id,
        email: memberEmail,
        name: memberName,
        role: memberRole,
        ...(temporaryPassword ? { temporary_password: temporaryPassword } : {}),
      });

      setMemberEmail('');
      setMemberName('');
      setTemporaryPassword('');
      await loadMembers(selected);
      setMessage(
        temporaryPassword
          ? 'Usuario creado/actualizado. Ya puede iniciar sesión con la contraseña temporal.'
          : 'Usuario creado. Debe definir contraseña mediante recuperación/invitación.',
      );
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'No se pudo crear el usuario.');
    } finally {
      setSaving(false);
    }
  };

  if (!isPlatformAdmin) {
    return (
      <Card>
        <CardContent className="p-8 text-center">Acceso denegado.</CardContent>
      </Card>
    );
  }

  return (
    <div className="space-y-5 p-6">
      <Card>
        <CardHeader>
          <CardTitle>Administración</CardTitle>
        </CardHeader>
        <CardContent className="flex flex-wrap gap-2">
          <Input
            value={organizationName}
            onChange={(event) => setOrganizationName(event.target.value)}
            placeholder="Nombre"
          />
          <Select
            value={organizationType}
            onValueChange={(value) => setOrganizationType(value as OrganizationType)}
          >
            <SelectTrigger className="w-52">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {organizationTypes.map((type) => (
                <SelectItem key={type} value={type}>
                  {type}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
          <Button
            disabled={saving || !organizationName.trim()}
            onClick={async () => {
              setSaving(true);
              try {
                await invoke('admin-create-organization', {
                  name: organizationName,
                  organization_type: organizationType,
                });
                setOrganizationName('');
                await loadOrganizations();
                setMessage('Organización creada.');
              } catch (error) {
                setMessage(error instanceof Error ? error.message : 'No se pudo crear la organización.');
              } finally {
                setSaving(false);
              }
            }}
          >
            Crear
          </Button>
        </CardContent>
      </Card>

      {message && <p className="text-sm">{message}</p>}

      {loading ? (
        <p>Cargando…</p>
      ) : (
        items.map((organization) => (
          <Button
            key={organization.id}
            variant="outline"
            onClick={() => void loadMembers(organization)}
          >
            {organization.name} · {organization.organizationType}
          </Button>
        ))
      )}

      {selected && (
        <Card>
          <CardHeader>
            <CardTitle>Miembros · {selected.name}</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            {members.map((member) => (
              <div key={member.id} className="flex flex-wrap gap-2 border-b pb-2 text-sm">
                <span>
                  {member.name || '—'} · {member.email || '—'} · {member.user_id.slice(0, 8)} ·{' '}
                  {new Date(member.joined_at).toLocaleDateString()}
                </span>
                <Select
                  value={member.role}
                  onValueChange={(value) => void updateMembership(member, { role: value })}
                >
                  <SelectTrigger className="w-36">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {roles.map((role) => (
                      <SelectItem key={role} value={role}>
                        {role}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
                <Button
                  size="sm"
                  disabled={saving}
                  onClick={() => void updateMembership(member, { is_active: !member.is_active })}
                >
                  {member.is_active ? 'Desactivar' : 'Activar'}
                </Button>
              </div>
            ))}

            <div className="grid gap-3 md:grid-cols-2">
              <div className="space-y-2">
                <Label htmlFor="member-email">Correo electrónico</Label>
                <Input
                  id="member-email"
                  value={memberEmail}
                  onChange={(event) => setMemberEmail(event.target.value)}
                  placeholder="email@empresa.com"
                  type="email"
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="member-name">Nombre</Label>
                <Input
                  id="member-name"
                  value={memberName}
                  onChange={(event) => setMemberName(event.target.value)}
                  placeholder="Nombre opcional"
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="temporary-password">Contraseña temporal</Label>
                <Input
                  id="temporary-password"
                  value={temporaryPassword}
                  onChange={(event) => setTemporaryPassword(event.target.value)}
                  placeholder="Mínimo 8 caracteres"
                  type="password"
                  autoComplete="new-password"
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="member-role">Rol</Label>
                <Select
                  value={memberRole}
                  onValueChange={(value) => setMemberRole(value as OrganizationMemberRole)}
                >
                  <SelectTrigger id="member-role">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {roles.map((role) => (
                      <SelectItem key={role} value={role}>
                        {role}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
            </div>
            <Button
              disabled={
                saving ||
                !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(memberEmail) ||
                (temporaryPassword.length > 0 && temporaryPassword.length < 8)
              }
              onClick={() => void createMember()}
            >
              Crear usuario
            </Button>
          </CardContent>
        </Card>
      )}
    </div>
  );
}
