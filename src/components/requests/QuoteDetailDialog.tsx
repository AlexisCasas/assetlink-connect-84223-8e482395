import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { CheckCircle, DollarSign, FileText, Calendar, Users } from 'lucide-react';

interface QuoteDetailDialogProps {
  quote: any;
  request: any;
  onClose: () => void;
}

export const QuoteDetailDialog = ({ quote, request, onClose }: QuoteDetailDialogProps) => {
  const formatAmount = (amount: number) => {
    return new Intl.NumberFormat('es-PE', {
      style: 'currency',
      currency: 'PEN',
    }).format(amount);
  };

  const extractNames = () => {
    const elaborado = quote.description.match(/Elaborado por: ([^\n.]+)/)?.[1] || 'No especificado';
    const revisado = quote.description.match(/Revisado por: ([^\n.]+)/)?.[1] || 'No especificado';
    return { elaborado, revisado };
  };

  const { elaborado, revisado } = extractNames();

  return (
    <Dialog open={true} onOpenChange={onClose}>
      <DialogContent className="max-w-3xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <div className="flex items-center justify-between">
            <DialogTitle className="text-2xl">
              Cotización - Solicitud {request.request_number}
            </DialogTitle>
            <Badge className="bg-green-600 hover:bg-green-700">
              <CheckCircle className="h-3 w-3 mr-1" />
              APROBADA
            </Badge>
          </div>
        </DialogHeader>

        <div className="space-y-4">
          {/* Monto Total */}
          <Card className="border-green-200 bg-green-50 dark:bg-green-950">
            <CardContent className="pt-6">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <DollarSign className="h-8 w-8 text-green-600" />
                  <div>
                    <p className="text-sm text-muted-foreground">Monto Total</p>
                    <p className="text-3xl font-bold text-green-600">
                      {formatAmount(parseFloat(quote.amount))}
                    </p>
                  </div>
                </div>
                <div className="text-right">
                  <p className="text-xs text-muted-foreground">ID Cotización</p>
                  <p className="text-sm font-mono">{quote.id.slice(0, 8)}</p>
                </div>
              </div>
            </CardContent>
          </Card>

          {/* Descripción */}
          <Card>
            <CardHeader>
              <CardTitle className="text-lg flex items-center gap-2">
                <FileText className="h-5 w-5" />
                Descripción del Servicio
              </CardTitle>
            </CardHeader>
            <CardContent>
              <p className="text-sm whitespace-pre-wrap bg-muted p-4 rounded-md">
                {quote.description}
              </p>
            </CardContent>
          </Card>

          {/* Responsables */}
          <Card>
            <CardHeader>
              <CardTitle className="text-lg flex items-center gap-2">
                <Users className="h-5 w-5" />
                Equipo Responsable
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-3">
              <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                <div className="p-3 bg-blue-50 dark:bg-blue-950 rounded-lg">
                  <p className="text-xs text-muted-foreground mb-1">Elaborado por</p>
                  <p className="font-medium text-sm">{elaborado}</p>
                </div>
                <div className="p-3 bg-orange-50 dark:bg-orange-950 rounded-lg">
                  <p className="text-xs text-muted-foreground mb-1">Revisado por</p>
                  <p className="font-medium text-sm">{revisado}</p>
                </div>
                <div className="p-3 bg-green-50 dark:bg-green-950 rounded-lg">
                  <p className="text-xs text-muted-foreground mb-1">Aprobado por</p>
                  <p className="font-medium text-sm">Gerente Técnico</p>
                </div>
              </div>
            </CardContent>
          </Card>

          {/* Información Adicional */}
          <Card>
            <CardHeader>
              <CardTitle className="text-lg flex items-center gap-2">
                <Calendar className="h-5 w-5" />
                Información Adicional
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-2">
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <p className="text-sm text-muted-foreground">Fecha de Creación</p>
                  <p className="font-medium">
                    {new Date(quote.created_at).toLocaleString('es-ES')}
                  </p>
                </div>
                <div>
                  <p className="text-sm text-muted-foreground">Estado</p>
                  <Badge variant="outline" className="text-green-600">
                    {quote.status === 'submitted' ? 'Enviada' : 'Aprobada'}
                  </Badge>
                </div>
              </div>
              {quote.client_observation && (
                <div className="mt-3">
                  <p className="text-sm text-muted-foreground mb-1">Observaciones del Cliente</p>
                  <p className="text-sm bg-muted p-3 rounded-md">
                    {quote.client_observation}
                  </p>
                </div>
              )}
            </CardContent>
          </Card>
        </div>
      </DialogContent>
    </Dialog>
  );
};
