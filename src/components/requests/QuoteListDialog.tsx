import { useEffect, useState } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Textarea } from '@/components/ui/textarea';
import { supabase } from '@/integrations/supabase/client';
import { FileText, Clock, CheckCircle, User, MessageSquare, MessageCircle, ThumbsUp, Lock, XCircle } from 'lucide-react';
import { useToast } from '@/hooks/use-toast';
import { useAuth } from '@/contexts/AuthContext';
import type { Request } from '@/types/request';
import { QuoteChatDialog } from './QuoteChatDialog';

interface QuoteListDialogProps {
  open: boolean;
  onClose: () => void;
  request: Request;
}

interface Quote {
  id: string;
  provider_id: string | null;
  provider_organization_id: string | null;
  team_member_id: string | null;
  amount: number;
  description: string;
  status: string;
  created_at: string;
  team_member_name?: string;
  provider_name?: string;
  client_observation?: string;
  approval_reason?: string;
  approved_at?: string | null;
  rejected_at?: string | null;
  rejection_reason?: string | null;
  work_order_id?: string | null;
}

export const QuoteListDialog = ({ open, onClose, request }: QuoteListDialogProps) => {
  const [quotes, setQuotes] = useState<Quote[]>([]);
  const [loading, setLoading] = useState(true);
  const [totalProviders, setTotalProviders] = useState(0);
  const [minQuotes, setMinQuotes] = useState(3);
  const [showPrices, setShowPrices] = useState(false);
  const [editingObservation, setEditingObservation] = useState<string | null>(null);
  const [observationText, setObservationText] = useState('');
  const [chatQuote, setChatQuote] = useState<{ id: string; providerName: string } | null>(null);
  const [quotesClosed, setQuotesClosed] = useState(false);
  const [closingQuotes, setClosingQuotes] = useState(false);
  const [creatingWorkOrderId, setCreatingWorkOrderId] = useState<string | null>(null);
  const { toast } = useToast();
  const { currentOrganization, currentMembership } = useAuth();
  const clientApprovalRoles = ['owner', 'admin', 'manager', 'requester'];
  const canApproveForClient = currentOrganization?.organizationType === 'client_company'
    && currentOrganization.id === request.organizationId
    && !!currentMembership
    && clientApprovalRoles.includes(currentMembership.role);
  const canApproveForPlatform = currentOrganization?.organizationType === 'platform_admin'
    && !!currentMembership
    && ['owner', 'admin'].includes(currentMembership.role);
  const canDecideQuotes = canApproveForClient || canApproveForPlatform;

  useEffect(() => {
    if (open && request.id) {
      loadQuotes();
    }
  }, [open, request.id]);

  const loadQuotes = async () => {
    try {
      setLoading(true);

      // Get request status to check if quotes are closed and min_quotes value
      const { data: requestData } = await supabase
        .from('requests')
        .select('quotes_closed, min_quotes')
        .eq('id', request.id)
        .single();

      setQuotesClosed(requestData?.quotes_closed || false);
      const reqMinQuotes = requestData?.min_quotes ?? 3;
      setMinQuotes(reqMinQuotes);

      // request_provider_access is the tenant-aware replacement for the
      // legacy request_providers table in this progress count.
      const { count: providerCount } = await supabase
        .from('request_provider_access')
        .select('*', { count: 'exact', head: true })
        .eq('request_id', request.id)
        .eq('status', 'active');

      setTotalProviders(providerCount || 0);

      // Load all submitted quotes for this request
      const { data: quotesData, error } = await supabase
        .from('quotes')
        .select('*')
        .eq('request_id', request.id)
        .order('created_at', { ascending: false });

      if (error) throw error;

      const visibleQuotes = (quotesData || [])
        .filter((q: any) => ['submitted', 'approved', 'rejected'].includes(q.status))
      const approvedQuoteIds = visibleQuotes
        .filter((quote: any) => quote.status === 'approved')
        .map((quote: any) => quote.id);
      const { data: workOrdersData, error: workOrdersError } = approvedQuoteIds.length > 0
        ? await supabase
          .from('work_orders')
          .select('id, quote_id')
          .in('quote_id', approvedQuoteIds)
        : { data: [], error: null };

      if (workOrdersError) throw workOrdersError;

      const workOrderByQuoteId = new Map(
        (workOrdersData || []).map((workOrder) => [workOrder.quote_id, workOrder.id])
      );
      const transformedQuotes = visibleQuotes
        .map((q: any) => ({
          id: q.id,
          provider_id: q.provider_id,
          provider_organization_id: q.provider_organization_id,
          team_member_id: q.team_member_id,
          amount: q.amount,
          description: q.description,
          status: q.status,
          created_at: q.created_at,
          provider_name: 'Proveedor',
          client_observation: q.client_observation,
          approval_reason: q.approval_reason,
          approved_at: q.approved_at,
          rejected_at: q.rejected_at,
          rejection_reason: q.rejection_reason,
          work_order_id: workOrderByQuoteId.get(q.id) || null,
        }));

      setQuotes(transformedQuotes);

      // Show prices ONLY when quotes received >= minQuotes (regardless of quotes_closed status)
      const quotesReceived = transformedQuotes.length;
      const shouldShowPrices = quotesReceived >= reqMinQuotes;
      setShowPrices(shouldShowPrices);
    } catch (error) {
      console.error('Error loading quotes:', error);
      setQuotes([]);
    } finally {
      setLoading(false);
    }
  };

  const handleSaveObservation = async (quoteId: string) => {
    try {
      const { error } = await supabase
        .from('quotes')
        .update({ client_observation: observationText })
        .eq('id', quoteId);

      if (error) throw error;

      setQuotes(quotes.map(q => 
        q.id === quoteId ? { ...q, client_observation: observationText } : q
      ));

      setEditingObservation(null);
      setObservationText('');

      toast({
        title: 'Observación guardada',
        description: 'La observación se ha guardado correctamente.',
      });
    } catch (error) {
      console.error('Error saving observation:', error);
      toast({
        title: 'Error',
        description: 'No se pudo guardar la observación.',
        variant: 'destructive',
      });
    }
  };

  const handleStartEditObservation = (quoteId: string, currentObservation?: string) => {
    setEditingObservation(quoteId);
    setObservationText(currentObservation || '');
  };

  const handleCloseQuotes = async () => {
    try {
      setClosingQuotes(true);
      const { error } = await supabase
        .from('requests')
        .update({ quotes_closed: true })
        .eq('id', request.id);

      if (error) throw error;

      setQuotesClosed(true);
      setShowPrices(true);

      toast({
        title: 'Envío de cotizaciones cerrado',
        description: 'Ya no se podrán enviar más cotizaciones y los precios son ahora visibles.',
      });
    } catch (error) {
      console.error('Error closing quotes:', error);
      toast({
        title: 'Error',
        description: 'No se pudo cerrar el envío de cotizaciones.',
        variant: 'destructive',
      });
    } finally {
      setClosingQuotes(false);
    }
  };

  const handleApproveQuote = async (quoteId: string) => {
    try {
      const { error } = await supabase.rpc('approve_quote', { target_quote_id: quoteId });

      if (error) throw error;
      await loadQuotes();

      toast({
        title: 'Cotización aprobada',
        description: 'La cotización ha sido aprobada exitosamente.',
      });
    } catch (error) {
      console.error('Error approving quote:', error);
      toast({
        title: 'Error',
        description: 'No se pudo aprobar la cotización.',
        variant: 'destructive',
      });
    }
  };

  const handleRejectQuote = async (quoteId: string) => {
    try {
      const { error } = await supabase.rpc('reject_quote', {
        target_quote_id: quoteId,
        reason: null,
      });
      if (error) throw error;
      await loadQuotes();
      toast({ title: 'Cotizacion rechazada', description: 'La cotizacion fue rechazada.' });
    } catch (error) {
      console.error('Error rejecting quote:', error);
      toast({ title: 'Error', description: 'No se pudo rechazar la cotizacion.', variant: 'destructive' });
    }
  };

  const handleCreateWorkOrder = async (quoteId: string) => {
    try {
      setCreatingWorkOrderId(quoteId);
      const { data, error } = await supabase.rpc('create_work_order_from_quote', {
        target_quote_id: quoteId,
      });

      if (error) throw error;

      setQuotes((current) => current.map((quote) => (
        quote.id === quoteId ? { ...quote, work_order_id: data.id } : quote
      )));
      toast({
        title: 'Orden creada',
        description: 'La orden de trabajo fue creada para la cotizacion aprobada.',
      });
    } catch (error) {
      console.error('Error creating work order:', error);
      toast({
        title: 'Error',
        description: 'No se pudo crear la orden de trabajo.',
        variant: 'destructive',
      });
    } finally {
      setCreatingWorkOrderId(null);
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
            <CardContent className="py-4 space-y-3">
              <div className="flex items-center gap-3">
                {showPrices ? (
                  <>
                    <CheckCircle className="h-5 w-5 text-green-600 dark:text-green-400" />
                    <div>
                      <p className="font-medium text-green-900 dark:text-green-100">
                        {quotesClosed ? 'Envío de cotizaciones cerrado' : `Mínimo de ${minQuotes} cotizaciones alcanzado`}
                      </p>
                      <p className="text-sm text-green-700 dark:text-green-300">
                        {quotes.length} de {minQuotes} cotizaciones mínimas recibidas. Los precios ahora son visibles.
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
                        {quotes.length} de {minQuotes} cotizaciones mínimas recibidas. Los precios se mostrarán al alcanzar el mínimo requerido.
                      </p>
                    </div>
                  </>
                )}
              </div>

              {/* Close Quotes Button */}
              {!quotesClosed && quotes.length > 0 && (
                <Button
                  variant="outline"
                  size="sm"
                  onClick={handleCloseQuotes}
                  disabled={closingQuotes}
                  className="w-full border-orange-500/50 hover:bg-orange-50 dark:hover:bg-orange-950"
                >
                  <Lock className="h-4 w-4 mr-2" />
                  {closingQuotes ? 'Cerrando...' : 'Cerrar envío de cotizaciones y ver precios'}
                </Button>
              )}
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
                      <Badge variant={quote.status === 'approved' ? 'default' : quote.status === 'rejected' ? 'destructive' : 'secondary'}>
                        {quote.status === 'approved' ? 'Aprobada' : quote.status === 'rejected' ? 'Rechazada' : 'En revision'}
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

                    {/* Approval Reason Display */}
                    {quote.status === 'approved' && quote.approval_reason && (
                      <div className="pt-3 border-t">
                        <div className="bg-green-50 dark:bg-green-950 p-3 rounded-md">
                          <p className="text-sm font-medium text-green-900 dark:text-green-100 mb-1">
                            Razones de aprobación:
                          </p>
                          <p className="text-sm text-green-700 dark:text-green-300">
                            {quote.approval_reason}
                          </p>
                        </div>
                      </div>
                    )}
                    {quote.status === 'rejected' && quote.rejection_reason && (
                      <div className="pt-3 border-t text-sm text-muted-foreground">
                        Motivo de rechazo: {quote.rejection_reason}
                      </div>
                    )}

                    {quote.status === 'approved' && (
                      <div className="flex items-center justify-between gap-3 border-t pt-3">
                        {quote.work_order_id ? (
                          <Badge variant="secondary">Orden creada</Badge>
                        ) : canDecideQuotes ? (
                          <Button
                            size="sm"
                            onClick={() => void handleCreateWorkOrder(quote.id)}
                            disabled={creatingWorkOrderId === quote.id}
                          >
                            <FileText className="mr-2 h-4 w-4" />
                            {creatingWorkOrderId === quote.id ? 'Creando orden...' : 'Crear orden'}
                          </Button>
                        ) : (
                          <p className="text-sm text-muted-foreground">Cotizacion aprobada</p>
                        )}
                      </div>
                    )}

                    {/* Action Buttons */}
                    {canDecideQuotes && quote.status === 'submitted' && (
                    <div className="pt-3 border-t flex gap-2">
                      <Button
                        variant="outline"
                        size="sm"
                        onClick={() => setChatQuote({ id: quote.id, providerName: quote.provider_name || 'Proveedor' })}
                        disabled
                        className="flex-1"
                      >
                        <MessageCircle className="h-4 w-4 mr-2" />
                        Contactar
                      </Button>
                      <Button
                        size="sm"
                        onClick={() => handleApproveQuote(quote.id)}
                        className="flex-1"
                      >
                        <ThumbsUp className="h-4 w-4 mr-2" />
                        {quote.status === 'approved' ? 'Aprobada' : 'Aprobar'}
                      </Button>
                      <Button
                        size="sm"
                        variant="destructive"
                        onClick={() => handleRejectQuote(quote.id)}
                        className="flex-1"
                      >
                        <XCircle className="h-4 w-4 mr-2" />
                        Rechazar
                      </Button>
                    </div>
                    )}

                    {/* Client Observations Section */}
                    <div className="pt-3 border-t">
                      {editingObservation === quote.id ? (
                        <div className="space-y-3">
                          <div>
                            <label className="text-sm font-medium text-muted-foreground mb-2 block">
                              Observaciones del Cliente:
                            </label>
                            <Textarea
                              value={observationText}
                              onChange={(e) => setObservationText(e.target.value)}
                              placeholder="Escribe tus observaciones sobre esta cotización..."
                              rows={3}
                              className="resize-none"
                            />
                          </div>
                          <div className="flex gap-2 justify-end">
                            <Button
                              variant="outline"
                              size="sm"
                              onClick={() => {
                                setEditingObservation(null);
                                setObservationText('');
                              }}
                            >
                              Cancelar
                            </Button>
                            <Button
                              size="sm"
                              onClick={() => handleSaveObservation(quote.id)}
                            >
                              Guardar
                            </Button>
                          </div>
                        </div>
                      ) : (
                        <div className="space-y-2">
                          {quote.client_observation ? (
                            <div className="bg-muted/50 p-3 rounded-md">
                              <p className="text-sm font-medium text-muted-foreground mb-1">
                                Tus observaciones:
                              </p>
                              <p className="text-sm">{quote.client_observation}</p>
                            </div>
                          ) : null}
                          <Button
                            variant="outline"
                            size="sm"
                            onClick={() => handleStartEditObservation(quote.id, quote.client_observation)}
                            disabled
                            className="w-full"
                          >
                            <MessageSquare className="h-4 w-4 mr-2" />
                            {quote.client_observation ? 'Editar observaciones' : 'Agregar observaciones'}
                          </Button>
                        </div>
                      )}
                    </div>
                  </CardContent>
                </Card>
              ))}
            </div>
          )}
        </div>

        {chatQuote && (
          <QuoteChatDialog
            open={!!chatQuote}
            onClose={() => setChatQuote(null)}
            quoteId={chatQuote.id}
            providerName={chatQuote.providerName}
          />
        )}
      </DialogContent>
    </Dialog>
  );
};
