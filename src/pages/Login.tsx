import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth, UserRole } from '@/contexts/AuthContext';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { useToast } from '@/hooks/use-toast';

const Login = () => {
  const isDemoUiEnabled = import.meta.env.DEV && import.meta.env.VITE_ENABLE_DEMO_SEED === 'true';
  const [isLogin, setIsLogin] = useState(true);
  const [selectedRole, setSelectedRole] = useState<UserRole>('cliente');
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
        const ok = await login(email, password, selectedRole);
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
        const ok = await register(email, password, name, selectedRole);
        if (ok) {
          toast({ title: 'Registro exitoso', description: 'Iniciando sesión...' });
          await login(email, password, selectedRole);
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
    <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-primary/5 via-background to-secondary/5 p-4">
      <Card className="w-full max-w-md">
        <CardHeader className="space-y-1">
          <CardTitle className="text-2xl font-bold text-center">One Facility</CardTitle>
          <CardDescription className="text-center">
            {isLogin ? 'Inicia sesión en tu cuenta' : 'Crea una nueva cuenta'}
          </CardDescription>
        </CardHeader>
        <CardContent>
          <Tabs value={selectedRole} onValueChange={(v) => setSelectedRole(v as UserRole)} className="mb-6">
            <TabsList className="grid w-full grid-cols-3">
              <TabsTrigger value="cliente">Cliente</TabsTrigger>
              <TabsTrigger value="proveedor">Proveedor</TabsTrigger>
              <TabsTrigger value="team_member">Equipo</TabsTrigger>
            </TabsList>
          </Tabs>

          <form onSubmit={handleSubmit} className="space-y-4">
            {!isLogin && (
              <div className="space-y-2">
                <Label htmlFor="name">Nombre</Label>
                <Input id="name" type="text" placeholder="Tu nombre" value={name} onChange={(e) => setName(e.target.value)} required />
              </div>
            )}
            <div className="space-y-2">
              <Label htmlFor="email">Email</Label>
              <Input id="email" type="email" placeholder="tu@email.com" value={email} onChange={(e) => setEmail(e.target.value)} required />
            </div>
            <div className="space-y-2">
              <Label htmlFor="password">Contraseña</Label>
              <Input id="password" type="password" placeholder="••••••••" value={password} onChange={(e) => setPassword(e.target.value)} required minLength={6} />
            </div>
            <Button type="submit" className="w-full" disabled={submitting}>
              {isLogin ? 'Iniciar Sesión' : 'Registrarse'}
            </Button>
          </form>

          <div className="my-4 flex items-center gap-2">
            <div className="flex-1 h-px bg-border" />
            <span className="text-xs text-muted-foreground">o</span>
            <div className="flex-1 h-px bg-border" />
          </div>

          <Button type="button" variant="outline" className="w-full" onClick={loginWithGoogle} disabled={submitting}>
            Continuar con Google
          </Button>

          <div className="mt-4 text-center text-sm">
            <button type="button" onClick={() => setIsLogin(!isLogin)} className="text-primary hover:underline">
              {isLogin ? '¿No tienes cuenta? Regístrate' : '¿Ya tienes cuenta? Inicia sesión'}
            </button>
          </div>

          {isLogin && isDemoUiEnabled && (
            <div className="mt-6 p-4 bg-muted rounded-lg space-y-2">
              <h3 className="text-sm font-semibold text-center">Cuentas Demo (un clic)</h3>
              <Button variant="secondary" size="sm" className="w-full" disabled={submitting} onClick={() => handleDemo('cliente@test.com', 'cliente')}>
                Entrar como Cliente
              </Button>
              <Button variant="secondary" size="sm" className="w-full" disabled={submitting} onClick={() => handleDemo('proveedor@test.com', 'proveedor')}>
                Entrar como Proveedor
              </Button>
              <Button variant="secondary" size="sm" className="w-full" disabled={submitting} onClick={() => handleDemo('equipo@test.com', 'team_member')}>
                Entrar como Equipo
              </Button>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
};

export default Login;
