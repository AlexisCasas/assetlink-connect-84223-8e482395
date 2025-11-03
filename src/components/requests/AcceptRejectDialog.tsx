import { useState } from 'react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Textarea } from '@/components/ui/textarea';
import { Label } from '@/components/ui/label';
import { CheckCircle, XCircle } from 'lucide-react';

interface AcceptRejectDialogProps {
  requestNumber: string;
  requestDescription: string;
  maxDeadline: string;
  reason?: string;
  onAccept: () => void;
  onReject: (reason: string) => void;
  onClose: () => void;
}

export const AcceptRejectDialog = ({
  requestNumber,
  requestDescription,
  maxDeadline,
  reason,
  onAccept,
  onReject,
  onClose,
}: AcceptRejectDialogProps) => {
  const [showRejectForm, setShowRejectForm] = useState(false);
  const [rejectionReason, setRejectionReason] = useState('');

  const handleReject = () => {
    if (!rejectionReason.trim()) {
      return;
    }
    onReject(rejectionReason);
  };

  return (
    <div className="fixed inset-0 bg-background/80 backdrop-blur-sm z-50 flex items-center justify-center p-4">
      <Card className="w-full max-w-2xl">
        <CardHeader>
          <CardTitle>Responder a Asignación</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="space-y-2">
            <p className="text-sm text-muted-foreground">
              Se te ha asignado la siguiente solicitud:
            </p>
            <div className="bg-muted p-4 rounded-lg space-y-2">
              <p><strong>Solicitud:</strong> {requestNumber}</p>
              <p><strong>Descripción:</strong> {requestDescription}</p>
              <p><strong>Fecha límite:</strong> {new Date(maxDeadline).toLocaleDateString()}</p>
              {reason && (
                <p><strong>Motivo:</strong> {reason}</p>
              )}
            </div>
          </div>

          {!showRejectForm ? (
            <div className="flex gap-3 justify-end">
              <Button variant="outline" onClick={onClose}>
                Cerrar
              </Button>
              <Button
                variant="destructive"
                onClick={() => setShowRejectForm(true)}
              >
                <XCircle className="w-4 h-4 mr-2" />
                Rechazar
              </Button>
              <Button onClick={onAccept}>
                <CheckCircle className="w-4 h-4 mr-2" />
                Aceptar
              </Button>
            </div>
          ) : (
            <div className="space-y-4">
              <div className="space-y-2">
                <Label htmlFor="rejection-reason">
                  Motivo del rechazo <span className="text-destructive">*</span>
                </Label>
                <Textarea
                  id="rejection-reason"
                  value={rejectionReason}
                  onChange={(e) => setRejectionReason(e.target.value)}
                  placeholder="Explica por qué rechazas esta asignación..."
                  rows={4}
                />
              </div>
              <div className="flex gap-3 justify-end">
                <Button
                  variant="outline"
                  onClick={() => {
                    setShowRejectForm(false);
                    setRejectionReason('');
                  }}
                >
                  Cancelar
                </Button>
                <Button
                  variant="destructive"
                  onClick={handleReject}
                  disabled={!rejectionReason.trim()}
                >
                  Confirmar Rechazo
                </Button>
              </div>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
};
