import { Toaster } from "@/components/ui/toaster";
import { Toaster as Sonner } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter, Routes, Route, Navigate } from "react-router-dom";
import { AuthProvider, useAuth } from "@/contexts/AuthContext";
import Login from "./pages/Login";
import Dashboard from "./pages/Dashboard";
import NotFound from "./pages/NotFound";
import { supabaseConfigurationError } from "@/lib/env";

const queryClient = new QueryClient();

const ProtectedRoute = ({ children }: { children: React.ReactNode }) => {
  const { isAuthenticated, loading } = useAuth();
  if (loading) return null;
  return isAuthenticated ? <>{children}</> : <Navigate to="/login" replace />;
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
