import { useState } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { toast } from 'sonner';

interface Props {
  open: boolean;
  onOpenChange: (v: boolean) => void;
}

export const ChangePasswordDialog = ({ open, onOpenChange }: Props) => {
  const [current, setCurrent] = useState('');
  const [next, setNext] = useState('');
  const [confirm, setConfirm] = useState('');

  const handleSave = () => {
    if (!current || !next || next !== confirm) {
      toast.error('Verifica los campos. La nueva contraseña debe coincidir.');
      return;
    }
    toast.success('Contraseña actualizada (mockup)');
    setCurrent(''); setNext(''); setConfirm('');
    onOpenChange(false);
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader><DialogTitle>Cambiar contraseña</DialogTitle></DialogHeader>
        <div className="space-y-3">
          <div><Label>Contraseña actual</Label><Input type="password" value={current} onChange={e => setCurrent(e.target.value)} /></div>
          <div><Label>Nueva contraseña</Label><Input type="password" value={next} onChange={e => setNext(e.target.value)} /></div>
          <div><Label>Confirmar nueva contraseña</Label><Input type="password" value={confirm} onChange={e => setConfirm(e.target.value)} /></div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>Cancelar</Button>
          <Button onClick={handleSave}>Guardar</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
};