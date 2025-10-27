import { useEffect, useState } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { supabase } from '@/integrations/supabase/client';
import { FileText, Clock, CheckCircle, User } from 'lucide-react';
import type { Request } from '@/types/request';

interface QuoteListDialogProps {
  open: boolean;
  onClose: () => void;
  request: Request;
}

interface Quote {
  id: string;
  provider_id: string;
  team_member_id: string;
  amount: number;
  description: string;
  status: string;
  created_at: string;
  team_member_name?: string;
  provider_name?: string;
}

export const QuoteListDialog = ({ open, onClose, request }: QuoteListDialogProps) => {
  const [quotes, setQuotes] = useState<Quote[]>([]);
  const [loading, setLoading] = useState(true);
  const [totalProviders, setTotalProviders] = useState(0);
  const [showPrices, setShowPrices] = useState(false);

  useEffect(() => {
    if (open && request.id) {
      loadQuotes();
    }
  }, [open, request.id]);

  const loadQuotes = async () => {
    try {
      setLoading(true);

      // Get total number of providers invited to this request
      const { count: providerCount } = await supabase
        .from('request_providers')
        .select('*', { count: 'exact', head: true })
        .eq('request_id', request.id);

      setTotalProviders(providerCount || 0);

      // Load all submitted quotes for this request
      const { data: quotesData, error } = await supabase
        .from('quotes')
        .select(`
          *,
          team_members!inner(name, provider_id),
          providers!inner(name)
        `)
        .eq('request_id', request.id)
        .eq('status', 'submitted')
        .order('created_at', { ascending: false });

      if (error) throw error;

      const transformedQuotes = (quotesData || []).map((q: any) => ({
        id: q.id,
        provider_id: q.provider_id,
        team_member_id: q.team_member_id,
        amount: q.amount,
        description: q.description,
        status: q.status,
        created_at: q.created_at,
        team_member_name: q.team_members?.name,
        provider_name: q.providers?.name,
      }));

      setQuotes(transformedQuotes);

      // Show prices only if all providers have submitted
      const submittedProviders = new Set(transformedQuotes.map(q => q.provider_id)).size;
      setShowPrices(submittedProviders >= (providerCount || 0) && providerCount > 0);
    } catch (error) {
      console.error('Error loading quotes:', error);
      setQuotes([]);
    } finally {
      setLoading(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onClose}>
      <DialogContent className="max-w-4xl max-h-[80vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Cotizaciones - {request.requestNumber}</DialogTitle>
          <p className="text-sm text-muted-foreground">
            {request.description}
          </p>
        </DialogHeader>

        <div className="space-y-4 mt-4">
          {/* Status Banner */}
          <Card className={showPrices ? 'border-green-500/50 bg-green-50 dark:bg-green-950' : 'border-orange-500/50 bg-orange-50 dark:bg-orange-950'}>
            <CardContent className="py-4">
              <div className="flex items-center gap-3">
                {showPrices ? (
                  <>
                    <CheckCircle className="h-5 w-5 text-green-600 dark:text-green-400" />
                    <div>
                      <p className="font-medium text-green-900 dark:text-green-100">
                        Todas las cotizaciones recibidas
                      </p>
                      <p className="text-sm text-green-700 dark:text-green-300">
                        {quotes.length} de {totalProviders} proveedores han enviado sus cotizaciones. Los precios ahora son visibles.
                      </p>
                    </div>
                  </>
                ) : (
                  <>
                    <Clock className="h-5 w-5 text-orange-600 dark:text-orange-400" />
                    <div>
                      <p className="font-medium text-orange-900 dark:text-orange-100">
                        Esperando cotizaciones
                      </p>
                      <p className="text-sm text-orange-700 dark:text-orange-300">
                        {quotes.length} de {totalProviders} proveedores han enviado sus cotizaciones. Los precios se mostrarán cuando todos respondan.
                      </p>
                    </div>
                  </>
                )}
              </div>
            </CardContent>
          </Card>

          {/* Quotes List */}
          {loading ? (
            <Card>
              <CardContent className="py-12 text-center">
                <p className="text-muted-foreground">Cargando cotizaciones...</p>
              </CardContent>
            </Card>
          ) : quotes.length === 0 ? (
            <Card>
              <CardContent className="py-12 text-center">
                <FileText className="h-12 w-12 mx-auto mb-4 text-muted-foreground" />
                <p className="text-muted-foreground">
                  Aún no se han recibido cotizaciones para esta solicitud
                </p>
              </CardContent>
            </Card>
          ) : (
            <div className="grid gap-4">
              {quotes.map((quote) => (
                <Card key={quote.id}>
                  <CardHeader>
                    <div className="flex items-start justify-between">
                      <div className="space-y-1">
                        <CardTitle className="text-lg flex items-center gap-2">
                          <User className="h-4 w-4" />
                          {quote.provider_name || 'Proveedor'}
                        </CardTitle>
                        {quote.team_member_name && (
                          <p className="text-sm text-muted-foreground">
                            Cotizado por: {quote.team_member_name}
                          </p>
                        )}
                      </div>
                      <Badge variant="secondary">
                        {new Date(quote.created_at).toLocaleDateString('es-ES', {
                          day: '2-digit',
                          month: 'short',
                        })}
                      </Badge>
                    </div>
                  </CardHeader>
                  <CardContent className="space-y-3">
                    <div>
                      <p className="text-sm font-medium text-muted-foreground mb-1">
                        Descripción:
                      </p>
                      <p className="text-sm">{quote.description}</p>
                    </div>

                    {showPrices ? (
                      <div className="pt-3 border-t">
                        <div className="flex items-baseline justify-between">
                          <p className="text-sm font-medium text-muted-foreground">
                            Monto Total:
                          </p>
                          <p className="text-2xl font-bold text-primary">
                            S/. {quote.amount.toFixed(2)}
                          </p>
                        </div>
                      </div>
                    ) : (
                      <div className="pt-3 border-t">
                        <div className="flex items-center gap-2 text-muted-foreground">
                          <Clock className="h-4 w-4" />
                          <p className="text-sm italic">
                            El precio se mostrará cuando todos los proveedores envíen sus cotizaciones
                          </p>
                        </div>
                      </div>
                    )}
                  </CardContent>
                </Card>
              ))}
            </div>
          )}
        </div>
      </DialogContent>
    </Dialog>
  );
};
