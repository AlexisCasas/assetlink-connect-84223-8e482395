import { useEffect, useRef, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import type { EmailOtpType } from '@supabase/supabase-js';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { useToast } from '@/hooks/use-toast';
import { isValidUuid } from '@/lib/providerHelpers';
import { ORGANIZATION_ROLE_LABELS } from '@/lib/organizationRoles';
import { INVITATION_STATUS_LABELS, type InvitationEffectiveStatus } from '@/lib/invitations';
import type { OrganizationMemberRole } from '@/types/organization';

interface MyInvitationDetails {
  invitation_id: string;
  organization_id: string;
  organization_name: string;
  role: OrganizationMemberRole;
  effective_status: InvitationEffectiveStatus;
  expires_at: string;
  invited_name: string | null;
}

type Phase =
  | 'verifying'
  | 'need_login'
  | 'set_password'
  | 'ready'
  | 'accepting'
  | 'accepted'
  | 'not_available'
  | 'error';

const KNOWN_OTP_TYPES: EmailOtpType[] = ['signup', 'invite', 'magiclink', 'recovery', 'email_change', 'email'];

/**
 * Route: /invitations/accept?invitation=<uuid>  (outside ProtectedRoute —
 * see App.tsx). Handles every case from the approved diagnosis: with or
 * without a prior session, a fresh invite/magic-link token in the URL, a
 * wrong logged-in account, and every invitation state (pending, expired,
 * revoked, accepted). Never accepts automatically just because the email
 * link was opened — the person must click "Aceptar invitación" explicitly.
 */
const AcceptInvitation = () => {
  const [searchParams, setSearchParams] = useSearchParams();
  const invitationId = searchParams.get('invitation');
  const navigate = useNavigate();
  const { toast } = useToast();
  const { isAuthenticated, loading: authLoading, refreshOrganizations, setCurrentOrganization, logout } = useAuth();

  const [phase, setPhase] = useState<Phase>('verifying');
  const [message, setMessage] = useState<string | null>(null);
  const [details, setDetails] = useState<MyInvitationDetails | null>(null);
  const [password, setPassword] = useState('');
  const [passwordConfirm, setPasswordConfirm] = useState('');
  const [savingPassword, setSavingPassword] = useState(false);
  const otpHandled = useRef(false);

  // Step 1: consume token_hash/type from the email link exactly once, then
  // strip them from the URL immediately (history.replaceState via
  // setSearchParams) so a re-render, a browser "forward" or a shared
  // screenshot never keeps the raw Auth token visible longer than needed.
  // The invitation id itself is not a secret and stays in the URL.
  useEffect(() => {
    if (otpHandled.current) return;
    otpHandled.current = true;

    const tokenHash = searchParams.get('token_hash');
    const type = searchParams.get('type');
    if (!tokenHash || !type || !KNOWN_OTP_TYPES.includes(type as EmailOtpType)) return;

    void (async () => {
      const { error } = await supabase.auth.verifyOtp({ token_hash: tokenHash, type: type as EmailOtpType });
      const next = new URLSearchParams(searchParams);
      next.delete('token_hash');
      next.delete('type');
      setSearchParams(next, { replace: true });
      if (error) {
        setMessage('El enlace no es válido o ya venció. Si tu invitación sigue vigente, pide que te la reenvíen.');
        setPhase('error');
        return;
      }
      // A brand-new account created via inviteUserByEmail has no password
      // yet — type=invite is the only case that needs this extra step.
      // An existing user arriving via the magic link already has one and
      // goes straight to reviewing the invitation.
      if (type === 'invite') setPhase('set_password');
    })();
  }, [searchParams, setSearchParams]);

  // Step 2: once there is a session (and no pending password setup), load
  // this user's own view of the invitation — never anyone else's.
  useEffect(() => {
    if (authLoading) return;
    if (phase === 'set_password' || phase === 'accepting' || phase === 'accepted') return;
    if (!invitationId || !isValidUuid(invitationId)) {
      setMessage('El enlace de invitación no es válido.');
      setPhase('error');
      return;
    }
    if (!isAuthenticated) {
      setPhase('need_login');
      return;
    }

    void (async () => {
      const { data, error } = await supabase.rpc('get_my_organization_invitation', { p_invitation_id: invitationId });
      const row = (Array.isArray(data) ? data[0] : data) as MyInvitationDetails | undefined;
      if (error || !row) {
        // Deliberately generic: never reveals whether the invitation exists
        // for a different account, per the approved diagnosis.
        setMessage('Esta invitación no está disponible para tu cuenta, o ya no existe.');
        setPhase('not_available');
        return;
      }
      setDetails(row);
      setPhase(row.effective_status === 'pending' ? 'ready' : 'not_available');
      if (row.effective_status !== 'pending') {
        setMessage(`Esta invitación está ${INVITATION_STATUS_LABELS[row.effective_status].toLowerCase()}.`);
      }
    })();
  }, [authLoading, isAuthenticated, invitationId, phase]);

  const handleSetPassword = async () => {
    if (password.length < 8) { setMessage('La contraseña debe tener al menos 8 caracteres.'); return; }
    if (password !== passwordConfirm) { setMessage('Las contraseñas no coinciden.'); return; }
    setSavingPassword(true);
    setMessage(null);
    const { error } = await supabase.auth.updateUser({ password });
    setSavingPassword(false);
    if (error) { setMessage('No se pudo guardar tu contraseña. Inténtalo nuevamente.'); return; }
    setPhase('verifying'); // re-enters step 2's effect on next render
  };

  const handleAccept = async () => {
    if (!invitationId) return;
    setPhase('accepting');
    const { data, error } = await supabase.rpc('accept_organization_invitation', { p_invitation_id: invitationId });
    const row = Array.isArray(data) ? data[0] : data;
    if (error || !row) {
      setMessage(error?.message ?? 'No se pudo aceptar la invitación.');
      setPhase('not_available');
      return;
    }
    await refreshOrganizations(row.organization_id);
    setCurrentOrganization(row.organization_id);
    setPhase('accepted');
    toast({ title: 'Invitación aceptada' });
    navigate('/', { replace: true });
  };

  if (phase === 'need_login') {
    return (
      <CenteredCard title="Inicia sesión para continuar">
        <p className="text-sm text-muted-foreground">Necesitas iniciar sesión para revisar esta invitación.</p>
        <Button
          className="mt-4"
          onClick={() => navigate('/login', {
            state: { from: { pathname: '/invitations/accept', search: `?invitation=${invitationId}`, hash: '' } },
          })}
        >
          Ir a iniciar sesión
        </Button>
      </CenteredCard>
    );
  }

  if (phase === 'set_password') {
    return (
      <CenteredCard title="Crea tu contraseña" description="Define una contraseña para acceder a One Facility.">
        <div className="space-y-3">
          <div className="space-y-1">
            <Label htmlFor="new-password">Nueva contraseña</Label>
            <Input id="new-password" type="password" minLength={8} value={password} onChange={(e) => setPassword(e.target.value)} />
          </div>
          <div className="space-y-1">
            <Label htmlFor="confirm-password">Confirma tu contraseña</Label>
            <Input id="confirm-password" type="password" minLength={8} value={passwordConfirm} onChange={(e) => setPasswordConfirm(e.target.value)} />
          </div>
          {message && <p className="text-sm text-destructive">{message}</p>}
          <Button className="w-full" disabled={savingPassword} onClick={() => void handleSetPassword()}>
            {savingPassword ? 'Guardando…' : 'Guardar contraseña'}
          </Button>
        </div>
      </CenteredCard>
    );
  }

  if (phase === 'ready' && details) {
    return (
      <CenteredCard title="Invitación a One Facility">
        <p className="text-sm">
          Te invitaron a <strong>{details.organization_name}</strong> como{' '}
          <strong>{ORGANIZATION_ROLE_LABELS[details.role]}</strong>.
        </p>
        <Button className="mt-4 w-full" onClick={() => void handleAccept()}>Aceptar invitación</Button>
      </CenteredCard>
    );
  }

  if (phase === 'accepting') {
    return <CenteredCard title="Aceptando invitación…"><p className="text-sm text-muted-foreground">Un momento…</p></CenteredCard>;
  }

  if (phase === 'not_available' || phase === 'error') {
    return (
      <CenteredCard title="No se pudo continuar">
        <p className="text-sm text-muted-foreground">{message}</p>
        {isAuthenticated && (
          <Button variant="outline" className="mt-4" onClick={() => void logout()}>
            Cerrar sesión y usar otra cuenta
          </Button>
        )}
      </CenteredCard>
    );
  }

  return <CenteredCard title="Verificando invitación…"><p className="text-sm text-muted-foreground">Un momento…</p></CenteredCard>;
};

const CenteredCard = ({ title, description, children }: { title: string; description?: string; children: React.ReactNode }) => (
  <main className="flex min-h-screen items-center justify-center bg-onefacility-background p-6">
    <Card className="w-full max-w-md">
      <CardHeader>
        <CardTitle>{title}</CardTitle>
        {description && <CardDescription>{description}</CardDescription>}
      </CardHeader>
      <CardContent>{children}</CardContent>
    </Card>
  </main>
);

export default AcceptInvitation;
