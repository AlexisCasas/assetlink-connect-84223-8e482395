import { Toaster } from "@/components/ui/toaster";
import { Toaster as Sonner } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import { Button } from "@/components/ui/button";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter, Routes, Route, Navigate, useLocation } from "react-router-dom";
import { AuthProvider, useAuth } from "@/contexts/AuthContext";
import Login from "./pages/Login";
import Dashboard from "./pages/Dashboard";
import NotFound from "./pages/NotFound";
import { supabaseConfigurationError } from "@/lib/env";

const queryClient = new QueryClient();

const NoOrganizationScreen = () => {
  const { logout } = useAuth();
  return (
    <main className="flex min-h-screen items-center justify-center bg-background p-6">
      <section className="w-full max-w-lg rounded-lg border bg-card p-6 text-center shadow-sm">
        <h1 className="text-xl font-semibold">Sin acceso asignado</h1>
        <p className="mt-2 text-sm text-muted-foreground">
          Tu cuenta aún no está asociada a una organización. Solicita al administrador que te asigne acceso.
        </p>
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
    return <Navigate to="/login" replace state={{ from: { pathname: location.pathname, hash: location.hash } }} />;
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
