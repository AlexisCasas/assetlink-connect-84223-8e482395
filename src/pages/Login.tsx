import { useState } from 'react';
import { ArrowRight, CheckCircle2, Loader2 } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { useAuth, UserRole } from '@/contexts/AuthContext';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { useToast } from '@/hooks/use-toast';

const Login = () => {
  const isDemoUiEnabled = import.meta.env.DEV && import.meta.env.VITE_ENABLE_DEMO_SEED === 'true';
  const [isLogin, setIsLogin] = useState(true);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [name, setName] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const { login, register, loginWithGoogle } = useAuth();
  const navigate = useNavigate();
  const { toast } = useToast();

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setSubmitting(true);
    try {
      if (isLogin) {
        // The authenticated user's tenant and permissions are resolved from
        // organization_members after sign-in. This legacy argument remains
        // only for the existing AuthContext compatibility contract.
        const ok = await login(email, password, 'cliente');
        if (ok) {
          toast({ title: 'Inicio de sesión exitoso' });
          navigate('/', { replace: true });
        } else {
          toast({ title: 'Error', description: 'Credenciales incorrectas', variant: 'destructive' });
        }
      } else {
        if (!name) {
          toast({ title: 'Error', description: 'Ingresa tu nombre', variant: 'destructive' });
          return;
        }
        const ok = await register(email, password, name, 'cliente');
        if (ok) {
          toast({ title: 'Registro exitoso', description: 'Iniciando sesión...' });
          await login(email, password, 'cliente');
          navigate('/', { replace: true });
        } else {
          toast({ title: 'Error', description: 'No se pudo registrar (¿usuario existente?)', variant: 'destructive' });
        }
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
      navigate('/', { replace: true });
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
              <CardTitle className="text-2xl font-bold text-onefacility-navy">
                {isLogin ? 'Bienvenido nuevamente' : 'Crea tu cuenta'}
              </CardTitle>
              <CardDescription className="text-[15px]">
                {isLogin ? 'Ingresa tus credenciales para acceder a tu espacio de trabajo.' : 'Completa tus datos para comenzar.'}
              </CardDescription>
            </CardHeader>
            <CardContent className="px-7 pb-8 sm:px-9">
              <form onSubmit={handleSubmit} className="space-y-4">
                {!isLogin && <div className="space-y-2"><Label htmlFor="name">Nombre</Label><Input className="h-11 bg-white" id="name" type="text" placeholder="Tu nombre" value={name} onChange={(event) => setName(event.target.value)} required /></div>}
                <div className="space-y-2"><Label htmlFor="email">Email</Label><Input className="h-11 bg-white" id="email" type="email" placeholder="tu@email.com" value={email} onChange={(event) => setEmail(event.target.value)} required /></div>
                <div className="space-y-2"><Label htmlFor="password">Contraseña</Label><Input className="h-11 bg-white" id="password" type="password" placeholder="••••••••" value={password} onChange={(event) => setPassword(event.target.value)} required minLength={6} /></div>
                <Button type="submit" className="h-11 w-full shadow-soft" disabled={submitting}>
                  {submitting ? <Loader2 className="h-4 w-4 animate-spin" /> : <ArrowRight className="h-4 w-4" />}
                  {submitting ? 'Procesando…' : isLogin ? 'Iniciar sesión' : 'Registrarse'}
                </Button>
              </form>

              <div className="my-5 flex items-center gap-3"><div className="h-px flex-1 bg-border" /><span className="text-xs uppercase tracking-widest text-muted-foreground">o</span><div className="h-px flex-1 bg-border" /></div>
              <Button type="button" variant="outline" className="h-11 w-full border-onefacility-border bg-white hover:bg-onefacility-surface hover:text-onefacility-navy" onClick={loginWithGoogle} disabled={submitting}>Continuar con Google</Button>
              <div className="mt-5 text-center text-sm"><button type="button" onClick={() => setIsLogin(!isLogin)} className="font-medium text-primary hover:underline">{isLogin ? '¿No tienes cuenta? Regístrate' : '¿Ya tienes cuenta? Inicia sesión'}</button></div>

              {isLogin && isDemoUiEnabled && <div className="mt-6 space-y-2 rounded-lg bg-muted p-4"><h3 className="text-center text-sm font-semibold">Cuentas Demo (un clic)</h3><Button variant="secondary" size="sm" className="w-full" disabled={submitting} onClick={() => handleDemo('cliente@test.com', 'cliente')}>Entrar como Cliente</Button><Button variant="secondary" size="sm" className="w-full" disabled={submitting} onClick={() => handleDemo('proveedor@test.com', 'proveedor')}>Entrar como Proveedor</Button><Button variant="secondary" size="sm" className="w-full" disabled={submitting} onClick={() => handleDemo('equipo@test.com', 'team_member')}>Entrar como Equipo</Button></div>}
            </CardContent>
          </Card>
          <p className="mt-6 text-center text-xs text-muted-foreground">Acceso seguro a la plataforma OneFacility</p>
        </div>
      </section>
    </main>
  );
};

export default Login;
