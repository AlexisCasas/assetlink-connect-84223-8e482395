import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { CheckCircle, FileText, Mail } from 'lucide-react';
import { formatSoles } from '@/lib/quoteCalculations';
import type { QuoteSection, QuoteSalesConditions } from '@/types/request';

interface QuoteDetailDialogProps {
  quote: any;
  request: any;
  onClose: () => void;
}

export const QuoteDetailDialog = ({ quote, request, onClose }: QuoteDetailDialogProps) => {
  const sections: QuoteSection[] = Array.isArray(quote.quote_sections) ? quote.quote_sections : [];
  const hasSections = sections.length > 0;
  const sales: QuoteSalesConditions | null = quote.sales_conditions && Object.keys(quote.sales_conditions).length > 0
    ? quote.sales_conditions
    : null;

  const baseSubtotal = Number(quote.base_subtotal) || 0;
  const gePct = Number(quote.general_expenses_percentage) || 0;
  const geAmt = Number(quote.general_expenses_amount) || 0;
  const utPct = Number(quote.utilities_percentage) || 0;
  const utAmt = Number(quote.utilities_amount) || 0;
  const subtotal = Number(quote.subtotal) || 0;
  const igv = Number(quote.igv_amount) || 0;
  const total = Number(quote.total_amount || quote.amount) || 0;

  const elaborado = quote.description?.match(/Elaborado por: ([^\n.|]+)/)?.[1]?.trim() || '—';

  const reqNumber = request.request_number || request.requestNumber || '';
  const isEmailed = !!quote.emailed_at;

  return (
    <Dialog open onOpenChange={onClose}>
      <DialogContent className="max-w-4xl max-h-[92vh] overflow-y-auto">
        <DialogHeader>
          <div className="flex items-center justify-between gap-3 flex-wrap">
            <DialogTitle className="text-xl">Cotización - Solicitud {reqNumber}</DialogTitle>
            <div className="flex gap-2">
              {isEmailed && (
                <Badge variant="secondary"><Mail className="h-3 w-3 mr-1" />Enviada por correo</Badge>
              )}
              <Badge className="bg-green-600 hover:bg-green-700">
                <CheckCircle className="h-3 w-3 mr-1" />
                {quote.status === 'submitted' ? 'ENVIADA' : (quote.status || '').toUpperCase()}
              </Badge>
            </div>
          </div>
        </DialogHeader>

        {!hasSections ? (
          // Legacy view fallback
          <Card>
            <CardHeader><CardTitle className="text-lg flex items-center gap-2"><FileText className="h-5 w-5" />Descripción</CardTitle></CardHeader>
            <CardContent>
              <p className="text-sm whitespace-pre-wrap bg-muted p-4 rounded-md">{quote.description}</p>
              <div className="mt-4 flex justify-between text-lg font-bold">
                <span>Total</span>
                <span className="font-mono">{formatSoles(total)}</span>
              </div>
            </CardContent>
          </Card>
        ) : (
          <Tabs defaultValue="resumen" className="w-full">
            <TabsList className="grid w-full grid-cols-2">
              <TabsTrigger value="resumen">Resumen</TabsTrigger>
              <TabsTrigger value="detalle">Detalle</TabsTrigger>
            </TabsList>

            <TabsContent value="resumen" className="space-y-4">
              <Card>
                <CardContent className="pt-6 space-y-2 text-sm">
                  <div className="flex justify-between"><span className="text-muted-foreground">Solicitud</span><span className="font-medium">{reqNumber}</span></div>
                  <div className="flex justify-between"><span className="text-muted-foreground">Elaborado por</span><span className="font-medium">{elaborado}</span></div>
                </CardContent>
              </Card>
              <Card>
                <CardHeader><CardTitle className="text-base">Resumen económico</CardTitle></CardHeader>
                <CardContent>
                  <div className="space-y-1.5 text-sm">
                    {sections.filter(s => s.enabled).map(s => (
                      <div key={s.id} className="flex justify-between">
                        <span className="text-muted-foreground">{s.name}</span>
                        <span className="font-mono">{formatSoles(s.subtotal)}</span>
                      </div>
                    ))}
                    <div className="flex justify-between border-t pt-2 font-semibold">
                      <span>Subtotal base</span><span className="font-mono">{formatSoles(baseSubtotal)}</span>
                    </div>
                    {gePct > 0 && (
                      <div className="flex justify-between"><span>Gastos Generales ({gePct}%)</span><span className="font-mono">{formatSoles(geAmt)}</span></div>
                    )}
                    {utPct > 0 && (
                      <div className="flex justify-between"><span>Utilidades ({utPct}%)</span><span className="font-mono">{formatSoles(utAmt)}</span></div>
                    )}
                    <div className="flex justify-between border-t pt-2 font-semibold"><span>Subtotal</span><span className="font-mono">{formatSoles(subtotal)}</span></div>
                    <div className="flex justify-between"><span>I.G.V. 18%</span><span className="font-mono">{formatSoles(igv)}</span></div>
                    <div className="flex justify-between border-t pt-2 text-lg font-bold text-primary"><span>Total</span><span className="font-mono">{formatSoles(total)}</span></div>
                  </div>
                </CardContent>
              </Card>
            </TabsContent>

            <TabsContent value="detalle" className="space-y-4">
              {sections.filter(s => s.enabled).map(section => (
                <Card key={section.id}>
                  <CardHeader className="pb-3"><CardTitle className="text-base">{section.name}</CardTitle></CardHeader>
                  <CardContent>
                    <div className="border rounded-md overflow-hidden">
                      <Table>
                        <TableHeader>
                          <TableRow>
                            <TableHead className="w-[50%]">Descripción</TableHead>
                            <TableHead>Cantidad</TableHead>
                            <TableHead>Unidad</TableHead>
                            <TableHead className="text-right">Precio Total</TableHead>
                          </TableRow>
                        </TableHeader>
                        <TableBody>
                          {section.items.map(it => (
                            <TableRow key={it.id}>
                              <TableCell>{it.description || '—'}</TableCell>
                              <TableCell>{it.quantity}</TableCell>
                              <TableCell>{it.unitMeasure}</TableCell>
                              <TableCell className="text-right font-mono">{formatSoles(it.totalPrice)}</TableCell>
                            </TableRow>
                          ))}
                          <TableRow>
                            <TableCell colSpan={3} className="text-right font-semibold">Subtotal</TableCell>
                            <TableCell className="text-right font-bold font-mono">{formatSoles(section.subtotal)}</TableCell>
                          </TableRow>
                        </TableBody>
                      </Table>
                    </div>
                  </CardContent>
                </Card>
              ))}

              <Card>
                <CardContent className="pt-6 space-y-1.5 text-sm">
                  <div className="flex justify-between"><span>Subtotal base</span><span className="font-mono">{formatSoles(baseSubtotal)}</span></div>
                  <div className="flex justify-between"><span>Gastos Generales ({gePct}%)</span><span className="font-mono">{formatSoles(geAmt)}</span></div>
                  <div className="flex justify-between"><span>Utilidades ({utPct}%)</span><span className="font-mono">{formatSoles(utAmt)}</span></div>
                  <div className="flex justify-between border-t pt-2 font-semibold"><span>Subtotal</span><span className="font-mono">{formatSoles(subtotal)}</span></div>
                  <div className="flex justify-between"><span>I.G.V. 18%</span><span className="font-mono">{formatSoles(igv)}</span></div>
                  <div className="flex justify-between border-t pt-2 text-lg font-bold text-primary"><span>Total</span><span className="font-mono">{formatSoles(total)}</span></div>
                </CardContent>
              </Card>

              {sales && (
                <Card>
                  <CardHeader><CardTitle className="text-base">Condiciones de Venta</CardTitle></CardHeader>
                  <CardContent>
                    <div className="grid grid-cols-1 md:grid-cols-2 gap-3 text-sm">
                      <div><span className="text-muted-foreground">Validez:</span> <span className="font-medium">{sales.validityDays} días</span></div>
                      <div><span className="text-muted-foreground">Garantía:</span> <span className="font-medium">{sales.warrantyMonths} meses</span></div>
                      <div><span className="text-muted-foreground">Tiempo de entrega:</span> <span className="font-medium">{sales.deliveryDays} días</span></div>
                      <div><span className="text-muted-foreground">Condiciones de pago:</span> <span className="font-medium">{sales.paymentTerms}</span></div>
                    </div>
                    {sales.additionalNotes && (
                      <div className="mt-3 text-sm">
                        <p className="text-muted-foreground mb-1">Notas adicionales</p>
                        <p className="bg-muted p-3 rounded-md whitespace-pre-wrap">{sales.additionalNotes}</p>
                      </div>
                    )}
                  </CardContent>
                </Card>
              )}
            </TabsContent>
          </Tabs>
        )}
      </DialogContent>
    </Dialog>
  );
};
