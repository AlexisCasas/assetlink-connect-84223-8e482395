import { useState } from 'react';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { useToast } from '@/hooks/use-toast';
import { ORGANIZATION_ROLE_LABELS } from '@/lib/organizationRoles';
import type { OrganizationMemberRole } from '@/types/organization';
import type { InviteUserInput } from '@/hooks/useOrganizationAccess';

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

interface InviteUserDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  /** Roles the current caller may assign — an admin never sees 'owner' in
   * this list; only owner (or platform admin) does. Mirrors
   * can_manage_organization_role's own rule, so the UI never even offers a
   * choice the server would reject. */
  assignableRoles: OrganizationMemberRole[];
  onInvite: (input: InviteUserInput) => Promise<unknown>;
}

export function InviteUserDialog({ open, onOpenChange, assignableRoles, onInvite }: InviteUserDialogProps) {
  const { toast } = useToast();
  const [email, setEmail] = useState('');
  const [name, setName] = useState('');
  const [role, setRole] = useState<OrganizationMemberRole | ''>('');
  const [saving, setSaving] = useState(false);

  const reset = () => { setEmail(''); setName(''); setRole(''); };

  const handleSubmit = async () => {
    if (!EMAIL_RE.test(email) || !role) return;
    setSaving(true);
    try {
      await onInvite({ email, invitedName: name.trim() || undefined, role });
      toast({ title: 'Invitación enviada', description: `Se envió una invitación a ${email}.` });
      reset();
      onOpenChange(false);
    } catch (error) {
      toast({
        title: 'No se pudo invitar',
        description: error instanceof Error ? error.message : 'Ocurrió un error inesperado.',
        variant: 'destructive',
      });
    } finally {
      setSaving(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={(next) => { if (!saving) { onOpenChange(next); if (!next) reset(); } }}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Invitar usuario</DialogTitle>
          <DialogDescription>
            Se enviará un correo real: un enlace de acceso para completar su cuenta o iniciar sesión, según corresponda.
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-4 py-2">
          <div className="space-y-2">
            <Label htmlFor="invite-email">Email</Label>
            <Input id="invite-email" type="email" value={email} onChange={(event) => setEmail(event.target.value)} placeholder="persona@empresa.com" />
          </div>
          <div className="space-y-2">
            <Label htmlFor="invite-name">Nombre (opcional)</Label>
            <Input id="invite-name" value={name} onChange={(event) => setName(event.target.value)} placeholder="Nombre a mostrar" />
          </div>
          <div className="space-y-2">
            <Label>Rol</Label>
            <Select value={role} onValueChange={(value) => setRole(value as OrganizationMemberRole)}>
              <SelectTrigger><SelectValue placeholder="Selecciona un rol" /></SelectTrigger>
              <SelectContent>
                {assignableRoles.map((candidate) => (
                  <SelectItem key={candidate} value={candidate}>{ORGANIZATION_ROLE_LABELS[candidate]}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={saving}>Cancelar</Button>
          <Button onClick={() => void handleSubmit()} disabled={saving || !EMAIL_RE.test(email) || !role}>
            {saving ? 'Enviando…' : 'Enviar invitación'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
