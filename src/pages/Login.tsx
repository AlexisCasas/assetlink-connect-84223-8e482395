import { useState } from 'react';
import { ArrowRight, CheckCircle2, Loader2 } from 'lucide-react';
import { useLocation, useNavigate } from 'react-router-dom';
import { useAuth, UserRole } from '@/contexts/AuthContext';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { useToast } from '@/hooks/use-toast';
import { resolveSafeLoginReturnTarget } from '@/lib/entityNavigation';

const Login = () => {
  const isDemoUiEnabled = import.meta.env.DEV && import.meta.env.VITE_ENABLE_DEMO_SEED === 'true';
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const { login } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();
  const { toast } = useToast();

  // Where to go after a successful sign-in: the original deep link
  // ProtectedRoute stashed (e.g. a scanned asset QR that required a login
  // first), re-validated against a strict allowlist so this can never become
  // an open redirect — an external origin, "//host", "javascript:", or an
  // unrecognized view all fall back to a bare "/". Works the same whether
  // the user already had a session (ProtectedRoute never redirected here) or
  // just signed in on this form.
  //
  // NOTE: this relies on react-router's `location.state`, which does NOT
  // survive a real cross-origin redirect. If Google OAuth (loginWithGoogle
  // in AuthContext) is ever wired up on this page, its round trip through
  // Lovable's own auth domain would lose this state — that flow would need
  // to persist the return target itself (e.g. sessionStorage) before
  // starting the redirect, not react-router state.
  const returnTarget = resolveSafeLoginReturnTarget((location.state as { from?: unknown } | null)?.from)
    ?? { pathname: '/' as const, hash: '' };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setSubmitting(true);
    try {
      // The authenticated user's tenant and permissions are resolved from
      // organization_members after sign-in. This legacy argument remains
      // only for the existing AuthContext compatibility contract.
      const ok = await login(email, password, 'cliente');
      if (ok) {
        toast({ title: 'Inicio de sesión exitoso' });
        navigate(returnTarget, { replace: true });
      } else {
        toast({
          title: 'Error',
          description: 'No pudimos iniciar sesión. Verifica tu correo, contraseña o solicita acceso al administrador.',
          variant: 'destructive',
        });
      }
    } finally {
      setSubmitting(false);
    }
  };

  const handleDemo = async (demoEmail: string, role: UserRole) => {
    setSubmitting(true);
    const ok = await login(demoEmail, 'ignored', role);
    setSubmitting(false);
    if (ok) {
      toast({ title: 'Acceso demo' });
      navigate(returnTarget, { replace: true });
    } else {
      toast({ title: 'Error', description: 'No se pudo iniciar sesión demo', variant: 'destructive' });
    }
  };

  return (
    <main className="min-h-screen bg-onefacility-background lg:grid lg:grid-cols-[minmax(0,1.05fr)_minmax(520px,0.95fr)]">
      <section className="relative hidden min-h-screen overflow-hidden bg-onefacility-navy px-12 py-14 text-white lg:flex lg:flex-col lg:justify-between xl:px-20">
        <div className="absolute -right-40 top-1/2 h-[620px] w-[620px] -translate-y-1/2 rounded-full border border-white/10" />
        <div className="absolute -right-24 top-1/2 h-[440px] w-[440px] -translate-y-1/2 rounded-full border border-white/10" />
        <img src="/brand/isotipo-primary.png" alt="" aria-hidden="true" className="absolute -bottom-20 -right-16 w-[520px] brightness-0 invert opacity-[0.07]" />

        <div className="relative z-10 inline-flex w-fit items-center rounded-2xl bg-white px-5 py-3 shadow-panel">
          <img src="/brand/logo-primary.png" alt="OneFacility" className="h-10 w-auto" />
        </div>

        <div className="relative z-10 max-w-xl space-y-7">
          <div className="h-1 w-16 rounded-full bg-onefacility-blue" />
          <h1 className="text-4xl font-bold leading-tight xl:text-5xl">
            Gestión integral de solicitudes, proveedores y órdenes de trabajo.
          </h1>
          <p className="max-w-lg text-lg leading-8 text-white/68">
            Centraliza operaciones, cotizaciones y trazabilidad en una sola plataforma.
          </p>
          <div className="grid gap-3 pt-3 text-sm text-white/78 sm:grid-cols-2">
            {['Operación multiempresa', 'Trazabilidad centralizada', 'Cotizaciones organizadas', 'Órdenes bajo control'].map((benefit) => (
              <div key={benefit} className="flex items-center gap-2">
                <CheckCircle2 className="h-4 w-4 text-sky-300" />
                <span>{benefit}</span>
              </div>
            ))}
          </div>
        </div>

        <p className="relative z-10 text-xs tracking-wide text-white/42">ONEFACILITY · OPERACIONES CONECTADAS</p>
      </section>

      <section className="flex min-h-screen items-center justify-center px-5 py-10 sm:px-10 lg:px-14 xl:px-20">
        <div className="w-full max-w-[480px]">
          <div className="mb-8 flex justify-center lg:hidden">
            <img src="/brand/logo-primary.png" alt="OneFacility" className="h-12 w-auto" />
          </div>
          <Card className="overflow-hidden border-onefacility-border/90 bg-white shadow-panel">
            <div className="h-1.5 bg-gradient-to-r from-onefacility-navy via-onefacility-blue to-onefacility-brown" />
            <CardHeader className="space-y-2 px-7 pb-5 pt-8 sm:px-9">
              <img src="/brand/wordmark-primary.png" alt="OneFacility" className="mb-5 hidden h-10 w-auto self-start lg:block" />
              <CardTitle className="text-2xl font-bold text-onefacility-navy">Bienvenido nuevamente</CardTitle>
              <CardDescription className="text-[15px]">
                Ingresa tus credenciales para acceder a tu espacio de trabajo.
              </CardDescription>
            </CardHeader>
            <CardContent className="px-7 pb-8 sm:px-9">
              <form onSubmit={handleSubmit} className="space-y-4">
                <div className="space-y-2"><Label htmlFor="email">Email</Label><Input className="h-11 bg-white" id="email" type="email" placeholder="tu@email.com" value={email} onChange={(event) => setEmail(event.target.value)} required /></div>
                <div className="space-y-2"><Label htmlFor="password">Contraseña</Label><Input className="h-11 bg-white" id="password" type="password" placeholder="••••••••" value={password} onChange={(event) => setPassword(event.target.value)} required minLength={6} /></div>
                <Button type="submit" className="h-11 w-full shadow-soft" disabled={submitting}>
                  {submitting ? <Loader2 className="h-4 w-4 animate-spin" /> : <ArrowRight className="h-4 w-4" />}
                  {submitting ? 'Procesando…' : 'Iniciar sesión'}
                </Button>
              </form>

              <p className="mt-5 text-center text-sm text-muted-foreground">
                ¿Necesitas acceso? Solicítalo al administrador de tu organización.
              </p>

              {isDemoUiEnabled && <div className="mt-6 space-y-2 rounded-lg bg-muted p-4"><h3 className="text-center text-sm font-semibold">Cuentas Demo (un clic)</h3><Button variant="secondary" size="sm" className="w-full" disabled={submitting} onClick={() => handleDemo('cliente@test.com', 'cliente')}>Entrar como Cliente</Button><Button variant="secondary" size="sm" className="w-full" disabled={submitting} onClick={() => handleDemo('proveedor@test.com', 'proveedor')}>Entrar como Proveedor</Button><Button variant="secondary" size="sm" className="w-full" disabled={submitting} onClick={() => handleDemo('equipo@test.com', 'team_member')}>Entrar como Equipo</Button></div>}
            </CardContent>
          </Card>
          <p className="mt-6 text-center text-xs text-muted-foreground">Acceso seguro a la plataforma OneFacility</p>
        </div>
      </section>
    </main>
  );
};

export default Login;
