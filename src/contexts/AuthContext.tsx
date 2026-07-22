import { createContext, useContext, useState, useEffect, ReactNode } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { lovable } from '@/integrations/lovable';
import type { Organization, OrganizationMember, OrganizationMemberRole } from '@/types/organization';

export type UserRole = 'cliente' | 'proveedor' | 'team_member';

export interface User {
  id: string;
  email: string;
  role: UserRole;
  name?: string;
  providerId?: string;
}

export interface Profile {
  id: string;
  email: string;
  name: string | null;
  providerId: string | null;
}

interface AuthContextType {
  user: User | null;
  profile: Profile | null;
  organizations: Organization[];
  memberships: OrganizationMember[];
  currentOrganization: Organization | null;
  currentMembership: OrganizationMember | null;
  setCurrentOrganization: (organizationId: string | null) => void;
  loading: boolean;
  login: (email: string, password: string, role: UserRole) => Promise<boolean>;
  register: (email: string, password: string, name: string, role: UserRole) => Promise<boolean>;
  loginWithGoogle: () => Promise<void>;
  logout: () => void;
  isAuthenticated: boolean;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

const DEMO_PASSWORD = 'demo-password-2024';
const CURRENT_ORGANIZATION_STORAGE_KEY = 'onefacility.currentOrganizationId';

const DEMO_ACCOUNTS: Record<string, { role: UserRole; name: string }> = {
  'cliente@test.com': { role: 'cliente', name: 'Cliente Demo' },
  'proveedor@test.com': { role: 'proveedor', name: 'Proveedor Demo' },
  'equipo@test.com': { role: 'team_member', name: 'Juan Pérez' },
};

const isDemoAuthEnabled = import.meta.env.DEV && import.meta.env.VITE_ENABLE_DEMO_SEED === 'true';

const toLegacyUserRole = (organization: Organization | null): UserRole => {
  switch (organization?.organizationType) {
    case 'provider_company':
    case 'facility_manager':
    case 'subcontractor_company':
      return 'proveedor';
    case 'platform_admin':
      return 'team_member';
    default:
      return 'cliente';
  }
};

function loadProfile(session: { user: { id: string; email?: string; user_metadata?: { name?: unknown } } }): User {
  const email = session.user.email ?? '';
  const metadataName = session.user.user_metadata?.name;

  return {
    id: session.user.id,
    email,
    // Compatibility value only. Product permissions are organization based.
    role: 'cliente',
    name: typeof metadataName === 'string' && metadataName.trim()
      ? metadataName
      : email.split('@')[0],
  };
}

interface OrganizationRow {
  id: string;
  name: string;
  legal_name: string | null;
  organization_type: Organization['organizationType'];
  tax_id: string | null;
  status: Organization['status'];
  settings: Record<string, unknown> | null;
  created_by: string | null;
  created_at: string;
  updated_at: string;
}

interface MembershipRow {
  id: string;
  organization_id: string;
  user_id: string;
  role: OrganizationMemberRole;
  is_active: boolean;
  invited_by: string | null;
  joined_at: string;
  updated_at: string;
  organizations: OrganizationRow | null;
}

interface OrganizationMembershipQuery {
  select: (columns: string) => OrganizationMembershipQuery;
  eq: (column: string, value: string | boolean) => OrganizationMembershipQuery;
  then: PromiseLike<{ data: MembershipRow[] | null; error: unknown }>['then'];
}

const toOrganization = (organization: OrganizationRow): Organization => ({
  id: organization.id,
  name: organization.name,
  legalName: organization.legal_name ?? null,
  organizationType: organization.organization_type,
  taxId: organization.tax_id ?? null,
  status: organization.status,
  settings: organization.settings ?? {},
  createdBy: organization.created_by ?? null,
  createdAt: organization.created_at,
  updatedAt: organization.updated_at,
});

const toMembership = (membership: MembershipRow): OrganizationMember => ({
  id: membership.id,
  organizationId: membership.organization_id,
  userId: membership.user_id,
  role: membership.role as OrganizationMemberRole,
  isActive: membership.is_active,
  invitedBy: membership.invited_by ?? null,
  joinedAt: membership.joined_at,
  updatedAt: membership.updated_at,
});

async function loadOrganizations(userId: string) {
  // Keep the current mockup usable until its generated database types are refreshed.
  const database = supabase as unknown as { from: (table: string) => OrganizationMembershipQuery };
  const { data, error } = await database
    .from('organization_members')
    .select('id, organization_id, user_id, role, is_active, invited_by, joined_at, updated_at, organizations(*)')
    .eq('user_id', userId)
    .eq('is_active', true);

  if (error || !data) return { organizations: [] as Organization[], memberships: [] as OrganizationMember[] };

  return {
    organizations: data
      .map((membership) => membership.organizations)
      .filter((organization): organization is OrganizationRow => organization !== null)
      .map(toOrganization),
    memberships: data.map(toMembership),
  };
}

const getPreferredOrganization = (organizations: Organization[], currentOrganizationId?: string) => {
  if (typeof window === 'undefined') return organizations[0] ?? null;

  const savedOrganizationId = window.localStorage.getItem(CURRENT_ORGANIZATION_STORAGE_KEY);
  const savedOrganization = organizations.find((organization) => organization.id === savedOrganizationId);

  if (savedOrganization) return savedOrganization;
  if (savedOrganizationId) window.localStorage.removeItem(CURRENT_ORGANIZATION_STORAGE_KEY);

  return organizations.find((organization) => organization.id === currentOrganizationId)
    ?? organizations[0]
    ?? null;
};

export const AuthProvider = ({ children }: { children: ReactNode }) => {
  const [user, setUser] = useState<User | null>(null);
  const [profile, setProfile] = useState<Profile | null>(null);
  const [organizations, setOrganizations] = useState<Organization[]>([]);
  const [memberships, setMemberships] = useState<OrganizationMember[]>([]);
  const [currentOrganization, setCurrentOrganizationState] = useState<Organization | null>(null);
  const [loading, setLoading] = useState(true);

  const setAuthState = (nextUser: User | null, organizationData: { organizations: Organization[]; memberships: OrganizationMember[] }) => {
    const nextOrganization = getPreferredOrganization(organizationData.organizations, currentOrganization?.id);
    const organizationUser = nextUser
      ? { ...nextUser, role: toLegacyUserRole(nextOrganization) }
      : null;

    setUser(organizationUser);
    setProfile(organizationUser ? {
      id: organizationUser.id,
      email: organizationUser.email,
      name: organizationUser.name ?? null,
      providerId: null,
    } : null);
    setOrganizations(organizationData.organizations);
    setMemberships(organizationData.memberships);
    setCurrentOrganizationState(nextOrganization);
    if (typeof window !== 'undefined') {
      if (nextOrganization) window.localStorage.setItem(CURRENT_ORGANIZATION_STORAGE_KEY, nextOrganization.id);
      else window.localStorage.removeItem(CURRENT_ORGANIZATION_STORAGE_KEY);
    }
  };

  useEffect(() => {
    // Listener FIRST
    const { data: sub } = supabase.auth.onAuthStateChange((_event, session) => {
      if (!session) {
        setUser(null);
        setProfile(null);
        setOrganizations([]);
        setMemberships([]);
        setCurrentOrganizationState(null);
        return;
      }
      // Defer Supabase calls to avoid deadlock inside the callback
      setTimeout(() => {
        loadOrganizations(session.user.id)
          .then((organizationData) => setAuthState(loadProfile(session), organizationData));
      }, 0);
    });

    supabase.auth.getSession().then(({ data: { session } }) => {
      if (session) {
        loadOrganizations(session.user.id).then((organizationData) => {
          setAuthState(loadProfile(session), organizationData);
          setLoading(false);
        });
      } else {
        setLoading(false);
      }
    });

    return () => sub.subscription.unsubscribe();
  }, []);

  const register = async (email: string, password: string, name: string, role: UserRole): Promise<boolean> => {
    const { error } = await supabase.auth.signUp({
      email,
      password,
      options: {
        emailRedirectTo: `${window.location.origin}/`,
        data: { name, role },
      },
    });
    return !error;
  };

  const login = async (email: string, password: string, role: UserRole): Promise<boolean> => {
    const demo = isDemoAuthEnabled ? DEMO_ACCOUNTS[email] : undefined;
    const pwd = demo ? DEMO_PASSWORD : password;
    const targetRole = demo?.role ?? role;
    const targetName = demo?.name ?? email.split('@')[0];

    let { error } = await supabase.auth.signInWithPassword({ email, password: pwd });

    // For demo accounts, auto-create on first use
    if (error && demo) {
      const { error: signUpErr } = await supabase.auth.signUp({
        email,
        password: pwd,
        options: { data: { name: targetName, role: targetRole } },
      });
      if (signUpErr) return false;
      const retry = await supabase.auth.signInWithPassword({ email, password: pwd });
      error = retry.error;
    }
    return !error;
  };

  const loginWithGoogle = async () => {
    await lovable.auth.signInWithOAuth('google', {
      redirect_uri: window.location.origin,
    });
  };

  const logout = async () => {
    await supabase.auth.signOut();
    setUser(null);
    setProfile(null);
    setOrganizations([]);
    setMemberships([]);
    setCurrentOrganizationState(null);
    if (typeof window !== 'undefined') window.localStorage.removeItem(CURRENT_ORGANIZATION_STORAGE_KEY);
  };

  const setCurrentOrganization = (organizationId: string | null) => {
    if (!organizationId) {
      setCurrentOrganizationState(null);
      setUser((current) => current ? { ...current, role: 'cliente' } : null);
      if (typeof window !== 'undefined') window.localStorage.removeItem(CURRENT_ORGANIZATION_STORAGE_KEY);
      return;
    }
    const organization = organizations.find((candidate) => candidate.id === organizationId);
    if (organization) {
      setCurrentOrganizationState(organization);
      setUser((current) => current ? { ...current, role: toLegacyUserRole(organization) } : null);
      if (typeof window !== 'undefined') window.localStorage.setItem(CURRENT_ORGANIZATION_STORAGE_KEY, organization.id);
    }
  };

  const currentMembership = currentOrganization
    ? memberships.find((membership) => membership.organizationId === currentOrganization.id) ?? null
    : null;

  return (
    <AuthContext.Provider
      value={{
        user,
        profile,
        organizations,
        memberships,
        currentOrganization,
        currentMembership,
        setCurrentOrganization,
        loading,
        login,
        register,
        loginWithGoogle,
        logout,
        isAuthenticated: !!user,
      }}
    >
      {children}
    </AuthContext.Provider>
  );
};

export const useAuth = () => {
  const context = useContext(AuthContext);
  if (!context) throw new Error('useAuth must be used within AuthProvider');
  return context;
};
