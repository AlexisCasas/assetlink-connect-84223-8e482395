import { useState } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Checkbox } from '@/components/ui/checkbox';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';

interface ApprovalDialogProps {
  open: boolean;
  onClose: () => void;
  onApprove: (reasons: string) => void;
  providerName: string;
}

const APPROVAL_REASONS = [
  'Precio competitivo',
  'Experiencia en el servicio',
  'Historial de trabajos ejecutados',
  'Rapidez',
  'Tiempo de atención',
  'Tiempo de ejecución',
  'Calidad de ejecución',
  'Trazabilidad por el informe',
  'Seguridad',
];

export const ApprovalDialog = ({ open, onClose, onApprove, providerName }: ApprovalDialogProps) => {
  const [selectedReasons, setSelectedReasons] = useState<string[]>([]);
  const [additionalNotes, setAdditionalNotes] = useState('');

  const handleToggleReason = (reason: string) => {
    setSelectedReasons(prev => 
      prev.includes(reason) 
        ? prev.filter(r => r !== reason)
        : [...prev, reason]
    );
  };

  const handleApprove = () => {
    const reasonsText = selectedReasons.length > 0 
      ? selectedReasons.join(', ')
      : '';
    
    const fullReason = additionalNotes 
      ? `${reasonsText}${reasonsText ? '. ' : ''}${additionalNotes}`
      : reasonsText;

    onApprove(fullReason);
    setSelectedReasons([]);
    setAdditionalNotes('');
  };

  const handleClose = () => {
    setSelectedReasons([]);
    setAdditionalNotes('');
    onClose();
  };

  return (
    <Dialog open={open} onOpenChange={handleClose}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>Aprobar cotización de {providerName}</DialogTitle>
          <p className="text-sm text-muted-foreground mt-2">
            Selecciona las razones por las que elegiste esta cotización
          </p>
        </DialogHeader>

        <div className="space-y-4 py-4">
          <div className="grid gap-3">
            {APPROVAL_REASONS.map((reason) => (
              <div key={reason} className="flex items-center space-x-2">
                <Checkbox
                  id={reason}
                  checked={selectedReasons.includes(reason)}
                  onCheckedChange={() => handleToggleReason(reason)}
                />
                <Label
                  htmlFor={reason}
                  className="text-sm font-normal cursor-pointer"
                >
                  {reason}
                </Label>
              </div>
            ))}
          </div>

          <div className="space-y-2">
            <Label htmlFor="additional-notes">
              Observaciones adicionales (opcional)
            </Label>
            <Textarea
              id="additional-notes"
              value={additionalNotes}
              onChange={(e) => setAdditionalNotes(e.target.value)}
              placeholder="Escribe cualquier otra razón o comentario..."
              rows={3}
              className="resize-none"
            />
          </div>
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={handleClose}>
            Cancelar
          </Button>
          <Button 
            onClick={handleApprove}
            disabled={selectedReasons.length === 0 && !additionalNotes.trim()}
          >
            Aprobar cotización
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
};
