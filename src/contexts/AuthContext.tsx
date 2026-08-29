import { createContext, useContext, useState, useEffect, useRef, ReactNode } from 'react';
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

  // Single-flight cache for the organization_members + organizations load:
  // keyed by userId, so that a SIGNED_IN event arriving through the auth
  // listener and an explicit login() call for the same sign-in share one
  // in-flight query instead of firing it twice (and, on bootstrap, the
  // same protection covers any other overlapping caller). Cleared as soon
  // as the query settles — never a permanent cache of a resolved promise.
  const organizationLoadRef = useRef(new Map<string, ReturnType<typeof loadOrganizations>>());

  const loadOrganizationsSingleFlight = (userId: string) => {
    const inFlight = organizationLoadRef.current.get(userId);
    if (inFlight) {
      if (import.meta.env.DEV) console.debug('[auth] reuse in-flight organizations load', userId);
      return inFlight;
    }
    if (import.meta.env.DEV) console.debug('[auth] start organizations load', userId);
    const promise = loadOrganizations(userId).finally(() => {
      organizationLoadRef.current.delete(userId);
    });
    organizationLoadRef.current.set(userId, promise);
    return promise;
  };

  // Bumped on every sign-out so a hydration already in flight for a user
  // who has since signed out can detect it was superseded and must not
  // repopulate the context (hydrate User A -> logout -> User A's load
  // resolves late -> discarded, never re-applied).
  const sessionGenerationRef = useRef(0);

  // The single central hydration path: bootstrap (INITIAL_SESSION),
  // subsequent sign-ins (SIGNED_IN) and login() all call this instead of
  // each running their own loadOrganizations + setAuthState. Returns
  // whether the resulting state was actually applied (false only when a
  // sign-out raced ahead of this call while it was pending).
  const hydrateSession = async (session: Parameters<typeof loadProfile>[0]): Promise<boolean> => {
    const myGeneration = sessionGenerationRef.current;
    if (import.meta.env.DEV) console.debug('[auth] hydrate start', session.user.id);
    const organizationData = await loadOrganizationsSingleFlight(session.user.id);
    if (sessionGenerationRef.current !== myGeneration) {
      if (import.meta.env.DEV) console.debug('[auth] hydrate discarded (stale, signed out meanwhile)', session.user.id);
      return false;
    }
    setAuthState(loadProfile(session), organizationData);
    if (import.meta.env.DEV) console.debug('[auth] hydrate applied', session.user.id);
    return true;
  };

  const clearAuthState = () => {
    sessionGenerationRef.current += 1;
    setUser(null);
    setProfile(null);
    setOrganizations([]);
    setMemberships([]);
    setCurrentOrganizationState(null);
    setLoading(false);
    if (typeof window !== 'undefined') window.localStorage.removeItem(CURRENT_ORGANIZATION_STORAGE_KEY);
  };

  useEffect(() => {
    // Listener FIRST — required both for onAuthStateChange to reliably
    // deliver INITIAL_SESSION and so no event fired during client
    // initialization is missed.
    const { data: sub } = supabase.auth.onAuthStateChange((event, session) => {
      if (import.meta.env.DEV) console.debug('[auth] event', event, session ? 'session' : 'no-session');

      if (event === 'SIGNED_OUT' || !session) {
        clearAuthState();
        return;
      }

      // A refreshed access token does not change organization_members,
      // organizations, or currentOrganization — re-running hydration for
      // it would only add contention around the session lock for no
      // observable benefit. The Supabase client already persists the
      // refreshed token on its own; nothing here depends on the raw
      // session/tokens, so there is nothing to update.
      if (event === 'TOKEN_REFRESHED') return;

      // INITIAL_SESSION (bootstrap) and SIGNED_IN (including the one
      // login() itself triggers) both flow through the same central,
      // single-flight hydration. Deferred out of the callback per
      // supabase-js guidance: never call back into the Supabase client
      // synchronously from inside onAuthStateChange.
      setTimeout(() => {
        void hydrateSession(session).finally(() => setLoading(false));
      }, 0);
    });

    return () => sub.subscription.unsubscribe();
  }, []);

  const login = async (email: string, password: string, role: UserRole): Promise<boolean> => {
    const demo = isDemoAuthEnabled ? DEMO_ACCOUNTS[email] : undefined;
    const pwd = demo ? DEMO_PASSWORD : password;
    const targetRole = demo?.role ?? role;
    const targetName = demo?.name ?? email.split('@')[0];

    let result = await supabase.auth.signInWithPassword({ email, password: pwd });

    // For demo accounts, auto-create on first use
    if (result.error && demo) {
      const { error: signUpErr } = await supabase.auth.signUp({
        email,
        password: pwd,
        options: { data: { name: targetName, role: targetRole } },
      });
      if (signUpErr) return false;
      result = await supabase.auth.signInWithPassword({ email, password: pwd });
    }

    if (result.error || !result.data.session) return false;

    // Do not wait only for onAuthStateChange: Login navigates immediately after
    // this promise resolves, so the protected route must already know the user.
    // Goes through the same central hydrateSession() as the SIGNED_IN event the
    // auth listener will also receive for this same sign-in — the single-flight
    // load means whichever caller resolves second just reuses the other's
    // in-flight query instead of issuing a second one. Returns false (instead
    // of true) in the rare case a sign-out raced in and the hydration was
    // discarded, so the caller never navigates with a stale/empty context.
    return hydrateSession(result.data.session);
  };

  const loginWithGoogle = async () => {
    await lovable.auth.signInWithOAuth('google', {
      redirect_uri: window.location.origin,
    });
  };

  const logout = async () => {
    await supabase.auth.signOut();
    // The SIGNED_OUT event from the listener will also call this, but
    // clearing here too means the UI updates immediately without waiting
    // for that event to round-trip — clearAuthState() is idempotent.
    clearAuthState();
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
