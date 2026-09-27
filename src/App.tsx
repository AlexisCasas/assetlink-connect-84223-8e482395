import { useEffect, useState } from "react";
import { Toaster } from "@/components/ui/toaster";
import { Toaster as Sonner } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import { Button } from "@/components/ui/button";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter, Routes, Route, Navigate, useLocation, Link } from "react-router-dom";
import { AuthProvider, useAuth } from "@/contexts/AuthContext";
import { supabase } from "@/integrations/supabase/client";
import { ORGANIZATION_ROLE_LABELS } from "@/lib/organizationRoles";
import Login from "./pages/Login";
import Dashboard from "./pages/Dashboard";
import NotFound from "./pages/NotFound";
import AcceptInvitation from "./pages/AcceptInvitation";
import { supabaseConfigurationError } from "@/lib/env";

const queryClient = new QueryClient();

interface MyPendingInvitationRow {
  invitation_id: string;
  organization_name: string;
  role: keyof typeof ORGANIZATION_ROLE_LABELS;
}

// A user created by admin-create-user-and-add-member or by accepting an
// earlier invitation may reach this screen with a valid session but zero
// memberships (deactivated, or a brand-new invited account that hasn't
// accepted yet). Surfacing get_my_pending_invitations() here — rather than
// only relying on the emailed link — means the flow never dead-ends just
// because the user is already signed in and lands on "/" first.
const NoOrganizationScreen = () => {
  const { logout } = useAuth();
  const [invitations, setInvitations] = useState<MyPendingInvitationRow[] | null>(null);

  useEffect(() => {
    let cancelled = false;
    void supabase.rpc('get_my_pending_invitations').then(({ data }) => {
      if (!cancelled) setInvitations((data as MyPendingInvitationRow[] | null) ?? []);
    });
    return () => { cancelled = true; };
  }, []);

  return (
    <main className="flex min-h-screen items-center justify-center bg-background p-6">
      <section className="w-full max-w-lg rounded-lg border bg-card p-6 text-center shadow-sm">
        <h1 className="text-xl font-semibold">Sin acceso asignado</h1>
        <p className="mt-2 text-sm text-muted-foreground">
          Tu cuenta aún no está asociada a una organización. Solicita al administrador que te asigne acceso.
        </p>
        {invitations && invitations.length > 0 && (
          <div className="mt-6 space-y-3 text-left">
            {invitations.map((invitation) => (
              <div key={invitation.invitation_id} className="rounded-md border bg-muted/40 p-3">
                <p className="text-sm font-medium">Tienes una invitación pendiente</p>
                <p className="text-sm text-muted-foreground">
                  {invitation.organization_name} · {ORGANIZATION_ROLE_LABELS[invitation.role] ?? invitation.role}
                </p>
                <Button asChild size="sm" className="mt-2">
                  <Link to={`/invitations/accept?invitation=${invitation.invitation_id}`}>Revisar invitación</Link>
                </Button>
              </div>
            ))}
          </div>
        )}
        <Button className="mt-6" variant="outline" onClick={logout}>
          Cerrar sesión
        </Button>
      </section>
    </main>
  );
};

const ProtectedRoute = ({ children }: { children: React.ReactNode }) => {
  const { isAuthenticated, loading, organizations } = useAuth();
  const location = useLocation();
  if (loading) return null;
  if (!isAuthenticated) {
    // Carries only this app's own current pathname/hash (never search, never
    // anything from another origin) so Login.tsx can resume the original
    // deep link — a scanned asset QR included — after signing in. This is
    // NOT itself trusted as a safe navigation target: Login.tsx re-validates
    // it against a strict allowlist (resolveSafeLoginReturnTarget) before
    // ever navigating with it.
    return <Navigate to="/login" replace state={{ from: { pathname: location.pathname, search: location.search, hash: location.hash } }} />;
  }
  if (organizations.length === 0) return <NoOrganizationScreen />;
  return <>{children}</>;
};

const EnvironmentConfigurationError = () => (
  <main className="flex min-h-screen items-center justify-center bg-background p-6">
    <section className="w-full max-w-lg rounded-lg border bg-card p-6 text-center shadow-sm">
      <h1 className="text-xl font-semibold">Configuración pendiente</h1>
      <p className="mt-2 text-sm text-muted-foreground">
        {supabaseConfigurationError}
      </p>
      <p className="mt-4 text-sm text-muted-foreground">
        Configura las variables públicas de Supabase y vuelve a desplegar. No agregues secretos de backend al frontend.
      </p>
    </section>
  </main>
);

const App = () => supabaseConfigurationError ? <EnvironmentConfigurationError /> : (
  <QueryClientProvider client={queryClient}>
    <AuthProvider>
      <TooltipProvider>
        <Toaster />
        <Sonner />
        <BrowserRouter>
          <Routes>
            <Route path="/login" element={<Login />} />
            {/* Deliberately OUTSIDE ProtectedRoute: a brand-new invited user
                has a valid session but zero memberships, so ProtectedRoute's
                NoOrganizationScreen would otherwise dead-end them before
                they ever reach the one action (accepting) that gives them
                an organization at all. Works with or without a session —
                AcceptInvitation itself redirects to /login (preserving this
                same path via resolveSafeLoginReturnTarget) when signed out. */}
            <Route path="/invitations/accept" element={<AcceptInvitation />} />
            <Route path="/" element={<ProtectedRoute><Dashboard /></ProtectedRoute>} />
            {/* ADD ALL CUSTOM ROUTES ABOVE THE CATCH-ALL "*" ROUTE */}
            <Route path="*" element={<NotFound />} />
          </Routes>
        </BrowserRouter>
      </TooltipProvider>
    </AuthProvider>
  </QueryClientProvider>
);

export default App;
