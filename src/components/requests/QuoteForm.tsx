import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Request, Quote } from '@/types/request';
import { X, Upload } from 'lucide-react';
import { useToast } from '@/hooks/use-toast';
import { useAuth } from '@/contexts/AuthContext';

interface QuoteFormProps {
  request: Request;
  onClose: () => void;
  onSave: (quote: Quote) => void;
}

export const QuoteForm = ({ request, onClose, onSave }: QuoteFormProps) => {
  const { toast } = useToast();
  const { user } = useAuth();
  const [amount, setAmount] = useState('');
  const [description, setDescription] = useState('');
  const [files, setFiles] = useState<FileList | null>(null);

  const handleSubmit = (isDraft: boolean) => {
    if (!amount || !description) {
      toast({
        title: "Error",
        description: "Por favor completa todos los campos obligatorios",
        variant: "destructive",
      });
      return;
    }

    const quote: Quote = {
      id: crypto.randomUUID(),
      requestId: request.id,
      providerId: user?.providerId || '',
      teamMemberId: user?.id || '',
      amount: parseFloat(amount),
      description,
      files: files ? Array.from(files) : undefined,
      createdAt: new Date().toISOString(),
      status: isDraft ? 'draft' : 'submitted',
    };

    onSave(quote);
    toast({
      title: isDraft ? "Borrador guardado" : "Cotización enviada",
      description: isDraft 
        ? "Tu cotización ha sido guardada como borrador" 
        : "La cotización ha sido enviada al cliente",
    });
    onClose();
  };

  return (
    <div className="fixed inset-0 bg-background/80 backdrop-blur-sm z-50 flex items-center justify-center p-4">
      <Card className="w-full max-w-2xl max-h-[90vh] overflow-y-auto">
        <CardHeader className="flex flex-row items-center justify-between">
          <CardTitle>Crear Cotización - {request.requestNumber}</CardTitle>
          <Button variant="ghost" size="icon" onClick={onClose}>
            <X className="w-4 h-4" />
          </Button>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="p-4 bg-muted rounded-lg space-y-2">
            <h3 className="font-medium">Detalles de la solicitud</h3>
            <p className="text-sm text-muted-foreground">{request.description}</p>
            <div className="grid grid-cols-2 gap-2 text-sm">
              <div>
                <span className="text-muted-foreground">Activo:</span>
                <span className="ml-2 font-medium">{request.asset}</span>
              </div>
              <div>
                <span className="text-muted-foreground">Ubicación:</span>
                <span className="ml-2 font-medium">{request.location}</span>
              </div>
            </div>
          </div>

          <div className="space-y-2">
            <Label htmlFor="amount">Monto de la cotización (S/.) *</Label>
            <Input
              id="amount"
              type="number"
              step="0.01"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              placeholder="0.00"
              required
            />
          </div>

          <div className="space-y-2">
            <Label htmlFor="description">Descripción de la cotización *</Label>
            <Textarea
              id="description"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="Describe los trabajos a realizar, materiales, tiempo estimado, etc."
              rows={5}
              required
            />
          </div>

          <div className="space-y-2">
            <Label htmlFor="files">Archivos de sustento (opcional)</Label>
            <div className="border-2 border-dashed rounded-lg p-4 hover:border-primary/50 transition-colors">
              <Input
                id="files"
                type="file"
                multiple
                onChange={(e) => setFiles(e.target.files)}
                className="cursor-pointer"
              />
              <p className="text-xs text-muted-foreground mt-2">
                Puedes adjuntar fotos, documentos PDF, hojas de cálculo, etc.
              </p>
            </div>
            {files && files.length > 0 && (
              <div className="text-sm text-muted-foreground">
                {files.length} archivo(s) seleccionado(s)
              </div>
            )}
          </div>

          <div className="flex gap-3 justify-end pt-4 border-t">
            <Button variant="outline" onClick={onClose}>
              Cancelar
            </Button>
            <Button variant="outline" onClick={() => handleSubmit(true)}>
              Guardar borrador
            </Button>
            <Button onClick={() => handleSubmit(false)}>
              Enviar cotización
            </Button>
          </div>
        </CardContent>
      </Card>
    </div>
  );
};
