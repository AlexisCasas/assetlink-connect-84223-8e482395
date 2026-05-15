import { createContext, useContext, useState, useEffect, ReactNode } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { lovable } from '@/integrations/lovable';
import type { Session } from '@supabase/supabase-js';

export type UserRole = 'cliente' | 'proveedor' | 'team_member';

interface User {
  id: string;
  email: string;
  role: UserRole;
  name?: string;
  providerId?: string;
}

interface AuthContextType {
  user: User | null;
  loading: boolean;
  login: (email: string, password: string, role: UserRole) => Promise<boolean>;
  register: (email: string, password: string, name: string, role: UserRole) => Promise<boolean>;
  loginWithGoogle: () => Promise<void>;
  logout: () => void;
  isAuthenticated: boolean;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

const DEMO_PASSWORD = 'demo-password-2024';

const DEMO_ACCOUNTS: Record<string, { role: UserRole; name: string; providerId?: string }> = {
  'cliente@test.com': { role: 'cliente', name: 'Cliente Demo' },
  'proveedor@test.com': { role: 'proveedor', name: 'Proveedor Demo', providerId: 'provider-1' },
  'equipo@test.com': { role: 'team_member', name: 'Juan Pérez', providerId: 'provider-1' },
};

async function loadProfile(session: Session): Promise<User | null> {
  const uid = session.user.id;
  const email = session.user.email ?? '';

  // Fetch profile + role
  const [{ data: profile }, { data: roles }] = await Promise.all([
    supabase.from('profiles').select('name, provider_id').eq('id', uid).maybeSingle(),
    supabase.from('user_roles').select('role').eq('user_id', uid),
  ]);

  let role: UserRole = (roles?.[0]?.role as UserRole) ?? 'cliente';

  // Demo overrides (so the seeded mockup works regardless)
  const demo = DEMO_ACCOUNTS[email];
  if (demo) role = demo.role;

  return {
    id: uid,
    email,
    role,
    name: profile?.name ?? session.user.user_metadata?.name ?? email.split('@')[0],
    providerId: profile?.provider_id ?? demo?.providerId,
  };
}

export const AuthProvider = ({ children }: { children: ReactNode }) => {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    // Listener FIRST
    const { data: sub } = supabase.auth.onAuthStateChange((_event, session) => {
      if (!session) {
        setUser(null);
        return;
      }
      // Defer Supabase calls to avoid deadlock inside the callback
      setTimeout(() => {
        loadProfile(session).then(setUser);
      }, 0);
    });

    supabase.auth.getSession().then(({ data: { session } }) => {
      if (session) {
        loadProfile(session).then((u) => {
          setUser(u);
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
    const demo = DEMO_ACCOUNTS[email];
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
  };

  return (
    <AuthContext.Provider
      value={{
        user,
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
