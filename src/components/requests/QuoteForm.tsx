import { useState, useEffect, useMemo } from 'react';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Switch } from '@/components/ui/switch';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Request, QuoteSection, QuoteSectionItem, QuoteSalesConditions } from '@/types/request';
import { X, Plus, Trash2, Edit2, Save, Mail, FileText } from 'lucide-react';
import { useToast } from '@/hooks/use-toast';
import { useAuth } from '@/contexts/AuthContext';
import { isProviderFacingOrganizationType } from '@/types/providerRelationship';
import { supabase } from '@/integrations/supabase/client';
import { QuoteSummary } from './QuoteSummary';
import {
  createDefaultSections,
  createGeneralSection,
  createSection,
  createEmptyItem,
  calcSectionSubtotal,
  calculateQuote,
  formatSoles,
  DEFAULT_SALES_CONDITIONS,
} from '@/lib/quoteCalculations';

interface QuoteFormProps {
  request: Request;
  onClose: () => void;
  onSave?: (quote: any) => void;
  existingQuote?: any;
}

export const QuoteForm = ({ request, onClose, onSave, existingQuote }: QuoteFormProps) => {
  const { toast } = useToast();
  const { user, currentOrganization } = useAuth();
  const isProviderOrganization = isProviderFacingOrganizationType(currentOrganization?.organizationType);

  const initial = useMemo(() => {
    if (existingQuote?.quote_sections && Array.isArray(existingQuote.quote_sections) && existingQuote.quote_sections.length > 0) {
      return {
        sections: existingQuote.quote_sections as QuoteSection[],
        gPct: Number(existingQuote.general_expenses_percentage) || 0,
        uPct: Number(existingQuote.utilities_percentage) || 0,
        gEnabled: Number(existingQuote.general_expenses_percentage) > 0 || existingQuote.general_expenses_enabled || true,
        uEnabled: Number(existingQuote.utilities_percentage) > 0 || existingQuote.utilities_enabled || true,
        sales: { ...DEFAULT_SALES_CONDITIONS, ...(existingQuote.sales_conditions || {}) } as QuoteSalesConditions,
        description: existingQuote.description || '',
      };
    }
    return {
      sections: createDefaultSections(),
      gPct: 10,
      uPct: 10,
      gEnabled: true,
      uEnabled: true,
      sales: { ...DEFAULT_SALES_CONDITIONS },
      description: '',
    };
  }, [existingQuote]);

  const [sections, setSections] = useState<QuoteSection[]>(initial.sections);
  const [generalExpensesPercentage, setGEPct] = useState<number>(initial.gPct);
  const [utilitiesPercentage, setUPct] = useState<number>(initial.uPct);
  const [generalExpensesEnabled, setGEEnabled] = useState<boolean>(initial.gEnabled);
  const [utilitiesEnabled, setUEnabled] = useState<boolean>(initial.uEnabled);
  const [salesConditions, setSalesConditions] = useState<QuoteSalesConditions>(initial.sales);
  const [description, setDescription] = useState<string>(initial.description);
  const [elaboradoPor, setElaboradoPor] = useState<string>(user?.name || '');
  const [editingSectionId, setEditingSectionId] = useState<string | null>(null);
  const [editingName, setEditingName] = useState('');
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (user?.name && !elaboradoPor) setElaboradoPor(user.name);
  }, [user, elaboradoPor]);

  // Section ops
  const addSection = () => {
    setSections([...sections, createSection('Nueva sección', sections.length)]);
  };
  const removeSection = (id: string) => {
    if (sections.length === 1) {
      toast({ title: 'Error', description: 'Debe haber al menos una sección', variant: 'destructive' });
      return;
    }
    setSections(sections.filter(s => s.id !== id));
  };
  const renameSection = (id: string, name: string) => {
    setSections(sections.map(s => s.id === id ? { ...s, name } : s));
  };
  const useGeneralMode = () => {
    setSections(createGeneralSection());
  };
  const useStandardMode = () => {
    setSections(createDefaultSections());
  };

  // Item ops
  const addItem = (sectionId: string) => {
    setSections(sections.map(s => s.id === sectionId ? { ...s, items: [...s.items, createEmptyItem()] } : s));
  };
  const removeItem = (sectionId: string, itemId: string) => {
    setSections(sections.map(s => {
      if (s.id !== sectionId) return s;
      if (s.items.length === 1) return s;
      return { ...s, items: s.items.filter(i => i.id !== itemId) };
    }));
  };
  const updateItem = (sectionId: string, itemId: string, key: keyof QuoteSectionItem, value: string | number) => {
    setSections(sections.map(s => {
      if (s.id !== sectionId) return s;
      return {
        ...s,
        items: s.items.map(i => {
          if (i.id !== itemId) return i;
          let v: any = value;
          if (key === 'quantity' || key === 'totalPrice') {
            v = Math.max(0, Number(value) || 0);
          }
          return { ...i, [key]: v };
        }),
      };
    }));
  };

  const calc = calculateQuote(sections, generalExpensesPercentage, utilitiesPercentage, generalExpensesEnabled, utilitiesEnabled);

  const validateForSubmit = (): boolean => {
    const hasValidLine = sections.some(s => s.enabled && s.items.some(i => i.description.trim() && Number(i.totalPrice) > 0));
    if (!hasValidLine) {
      toast({ title: 'Error', description: 'Agrega al menos una línea con descripción y precio total mayor a 0', variant: 'destructive' });
      return false;
    }
    if (!elaboradoPor.trim()) {
      toast({ title: 'Error', description: 'Indica quién elabora la cotización', variant: 'destructive' });
      return false;
    }
    return true;
  };

  type Mode = 'draft' | 'submit' | 'email';

  const handleSave = async (mode: Mode) => {
    if (mode !== 'draft' && !validateForSubmit()) return;

    if (!user || !currentOrganization || !isProviderOrganization) {
      toast({ title: 'Organization required', description: 'Select a provider or facility manager organization before quoting.', variant: 'destructive' });
      return;
    }

    setSaving(true);
    try {
      const sectionsWithSubtotals = sections.map(s => ({ ...s, subtotal: calcSectionSubtotal(s) }));
      const summaryDesc = description.trim() || `${sections.filter(s => s.enabled).map(s => `${s.name}: ${formatSoles(calcSectionSubtotal(s))}`).join(' | ')} - Elaborado por: ${elaboradoPor}`;

      const status = mode === 'draft' ? 'draft' : 'submitted';
      const payload: any = {
        request_id: request.id,
        provider_organization_id: currentOrganization.id,
        created_by_user_id: user.id,
        amount: calc.totalAmount,
        description: summaryDesc,
        status,
        quote_sections: sectionsWithSubtotals,
        base_subtotal: calc.baseSubtotal,
        general_expenses_percentage: calc.generalExpensesPercentage,
        general_expenses_amount: calc.generalExpensesAmount,
        utilities_percentage: calc.utilitiesPercentage,
        utilities_amount: calc.utilitiesAmount,
        subtotal: calc.subtotal,
        igv_amount: calc.igvAmount,
        total_amount: calc.totalAmount,
        sales_conditions: salesConditions,
      };

      if (mode === 'submit' || mode === 'email') {
        payload.sent_at = new Date().toISOString();
      }
      if (mode === 'email') {
        payload.emailed_at = new Date().toISOString();
      }

      // The UI keeps one editable quote per request and provider organization.
      let quoteId = existingQuote?.id;
      if (!quoteId) {
        const { data: existing } = await supabase
          .from('quotes')
          .select('id')
          .eq('request_id', request.id)
          .eq('provider_organization_id', currentOrganization.id)
          .order('updated_at', { ascending: false })
          .limit(1)
          .maybeSingle();
        if (existing) quoteId = existing.id;
      }

      let savedId = quoteId;
      if (quoteId) {
        const { error } = await supabase.from('quotes').update(payload).eq('id', quoteId);
        if (error) throw error;
      } else {
        const { data, error } = await supabase.from('quotes').insert(payload).select('id').single();
        if (error) throw error;
        savedId = data.id;
      }

      // Database triggers create tenant notifications when the quote reaches a
      // notification-worthy status. The frontend never inserts notifications.

      toast({
        title: mode === 'draft' ? 'Borrador guardado' : mode === 'email' ? 'Cotización enviada por correo' : 'Cotización enviada',
        description: mode === 'draft'
          ? 'Tu cotización quedó en borrador'
          : mode === 'email'
            ? 'Se simuló el envío por correo al cliente'
            : 'La cotización fue enviada al cliente',
      });

      onSave?.({ id: savedId, ...payload });
      onClose();
    } catch (e: any) {
      console.error('Error saving quote:', e);
      toast({ title: 'Error', description: e.message || 'No se pudo guardar la cotización', variant: 'destructive' });
    } finally {
      setSaving(false);
    }
  };

  const updSales = (k: keyof QuoteSalesConditions, v: any) => setSalesConditions({ ...salesConditions, [k]: v });

  return (
    <div className="fixed inset-0 bg-background/80 backdrop-blur-sm z-50 flex items-center justify-center p-4">
      <Card className="w-full max-w-6xl max-h-[92vh] overflow-y-auto">
        <CardHeader className="flex flex-row items-center justify-between sticky top-0 bg-background z-10 border-b">
          <CardTitle>Cotización - {(request as any).requestNumber || (request as any).request_number}</CardTitle>
          <Button variant="ghost" size="icon" onClick={onClose}><X className="w-4 h-4" /></Button>
        </CardHeader>
        <CardContent className="space-y-6 p-6">
          {/* Request summary */}
          <div className="p-4 bg-muted rounded-lg space-y-2">
            <h3 className="font-medium">Detalles de la solicitud</h3>
            <p className="text-sm text-muted-foreground">{request.description}</p>
          </div>

          {/* Mode toggles */}
          <div className="flex flex-wrap items-center gap-2">
            <Button size="sm" variant="outline" onClick={useStandardMode}>Secciones estándar</Button>
            <Button size="sm" variant="outline" onClick={useGeneralMode}>Usar sección general</Button>
            <Button size="sm" onClick={addSection}><Plus className="h-4 w-4 mr-1" />Agregar sección</Button>
          </div>

          {/* Sections */}
          <div className="space-y-4">
            {sections.map((section, idx) => (
              <div key={section.id} className="border rounded-lg p-4 bg-card space-y-2">
                <div className="flex items-center justify-between bg-muted p-3 rounded-md">
                  <div className="flex items-center gap-2 flex-1">
                    {editingSectionId === section.id ? (
                      <Input
                        autoFocus
                        value={editingName}
                        onChange={e => setEditingName(e.target.value)}
                        onBlur={() => { renameSection(section.id, editingName); setEditingSectionId(null); }}
                        onKeyDown={(e) => { if (e.key === 'Enter') { renameSection(section.id, editingName); setEditingSectionId(null); } }}
                        className="h-8 max-w-md"
                      />
                    ) : (
                      <>
                        <h4 className="font-semibold">{idx + 1}. {section.name}</h4>
                        <Button size="sm" variant="ghost" onClick={() => { setEditingSectionId(section.id); setEditingName(section.name); }}>
                          <Edit2 className="h-3 w-3" />
                        </Button>
                      </>
                    )}
                  </div>
                  <div className="flex gap-1">
                    <Button size="sm" variant="ghost" onClick={() => addItem(section.id)}>
                      <Plus className="h-4 w-4" />
                    </Button>
                    <Button size="sm" variant="ghost" className="text-destructive" onClick={() => removeSection(section.id)} disabled={sections.length === 1}>
                      <Trash2 className="h-4 w-4" />
                    </Button>
                  </div>
                </div>

                <div className="border rounded-lg overflow-hidden">
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead className="w-[45%]">Descripción</TableHead>
                        <TableHead className="w-[15%]">Cantidad</TableHead>
                        <TableHead className="w-[15%]">Unidad</TableHead>
                        <TableHead className="w-[20%]">Precio Total (S/)</TableHead>
                        <TableHead className="w-[5%]"></TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {section.items.map(item => (
                        <TableRow key={item.id}>
                          <TableCell>
                            <Input value={item.description} onChange={e => updateItem(section.id, item.id, 'description', e.target.value)} placeholder="Descripción" className="h-8" />
                          </TableCell>
                          <TableCell>
                            <Input type="number" min="0" step="0.01" value={item.quantity || ''} onChange={e => updateItem(section.id, item.id, 'quantity', parseFloat(e.target.value) || 0)} placeholder="0" className="h-8" />
                          </TableCell>
                          <TableCell>
                            <Input value={item.unitMeasure} onChange={e => updateItem(section.id, item.id, 'unitMeasure', e.target.value)} placeholder="m2, und, glns..." className="h-8" />
                          </TableCell>
                          <TableCell>
                            <Input type="number" min="0" step="0.01" value={item.totalPrice || ''} onChange={e => updateItem(section.id, item.id, 'totalPrice', parseFloat(e.target.value) || 0)} placeholder="0.00" className="h-8" />
                          </TableCell>
                          <TableCell>
                            <Button size="sm" variant="ghost" onClick={() => removeItem(section.id, item.id)} disabled={section.items.length === 1}>
                              <Trash2 className="h-4 w-4" />
                            </Button>
                          </TableCell>
                        </TableRow>
                      ))}
                      <TableRow>
                        <TableCell colSpan={3} className="text-right font-semibold">Subtotal:</TableCell>
                        <TableCell className="font-bold font-mono">{formatSoles(calcSectionSubtotal(section))}</TableCell>
                        <TableCell />
                      </TableRow>
                    </TableBody>
                  </Table>
                </div>
              </div>
            ))}
          </div>

          {/* Percentage fields */}
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <Card>
              <CardHeader className="pb-3">
                <div className="flex items-center justify-between">
                  <CardTitle className="text-base">Gastos Generales</CardTitle>
                  <Switch checked={generalExpensesEnabled} onCheckedChange={setGEEnabled} />
                </div>
              </CardHeader>
              <CardContent>
                <div className="flex items-center gap-2">
                  <Input type="number" min="0" step="0.01" disabled={!generalExpensesEnabled}
                    value={generalExpensesPercentage || ''}
                    onChange={e => setGEPct(Math.max(0, parseFloat(e.target.value) || 0))}
                    placeholder="0" className="w-28" />
                  <span>%</span>
                  <span className="ml-auto font-mono text-sm">{formatSoles(calc.generalExpensesAmount)}</span>
                </div>
              </CardContent>
            </Card>
            <Card>
              <CardHeader className="pb-3">
                <div className="flex items-center justify-between">
                  <CardTitle className="text-base">Utilidades</CardTitle>
                  <Switch checked={utilitiesEnabled} onCheckedChange={setUEnabled} />
                </div>
              </CardHeader>
              <CardContent>
                <div className="flex items-center gap-2">
                  <Input type="number" min="0" step="0.01" disabled={!utilitiesEnabled}
                    value={utilitiesPercentage || ''}
                    onChange={e => setUPct(Math.max(0, parseFloat(e.target.value) || 0))}
                    placeholder="0" className="w-28" />
                  <span>%</span>
                  <span className="ml-auto font-mono text-sm">{formatSoles(calc.utilitiesAmount)}</span>
                </div>
              </CardContent>
            </Card>
          </div>

          {/* Summary */}
          <QuoteSummary
            sections={sections}
            generalExpensesPercentage={generalExpensesPercentage}
            utilitiesPercentage={utilitiesPercentage}
            generalExpensesEnabled={generalExpensesEnabled}
            utilitiesEnabled={utilitiesEnabled}
          />

          {/* Sales conditions */}
          <Card>
            <CardHeader>
              <CardTitle className="text-base">Condiciones de Venta</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                <div className="space-y-2">
                  <Label>Validez de la cotización (días)</Label>
                  <Input type="number" min="0" value={salesConditions.validityDays}
                    onChange={e => updSales('validityDays', Math.max(0, parseInt(e.target.value) || 0))} />
                </div>
                <div className="space-y-2">
                  <Label>Garantía (meses)</Label>
                  <Input type="number" min="0" value={salesConditions.warrantyMonths}
                    onChange={e => updSales('warrantyMonths', Math.max(0, parseInt(e.target.value) || 0))} />
                </div>
                <div className="space-y-2">
                  <Label>Tiempo de entrega (días)</Label>
                  <Input type="number" min="0" value={salesConditions.deliveryDays}
                    onChange={e => updSales('deliveryDays', Math.max(0, parseInt(e.target.value) || 0))} />
                </div>
              </div>
              <div className="space-y-2">
                <Label>Condiciones de pago</Label>
                <Input value={salesConditions.paymentTerms} onChange={e => updSales('paymentTerms', e.target.value)} />
              </div>
              <div className="space-y-2">
                <Label>Notas adicionales</Label>
                <Textarea rows={3} value={salesConditions.additionalNotes || ''} onChange={e => updSales('additionalNotes', e.target.value)} placeholder="Observaciones, exclusiones, etc." />
              </div>
            </CardContent>
          </Card>

          {/* Description / Elaborated by */}
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div className="space-y-2">
              <Label>Elaborado por</Label>
              <Input value={elaboradoPor} onChange={e => setElaboradoPor(e.target.value)} />
            </div>
            <div className="space-y-2">
              <Label>Descripción / título de la cotización</Label>
              <Input value={description} onChange={e => setDescription(e.target.value)} placeholder="Ej. Pintado de fachada" />
            </div>
          </div>

          {/* Action buttons */}
          <div className="flex flex-wrap gap-3 justify-end pt-4 border-t sticky bottom-0 bg-background">
            <Button variant="outline" onClick={onClose} disabled={saving}>Cancelar</Button>
            <Button variant="outline" onClick={() => handleSave('draft')} disabled={saving}>
              <Save className="h-4 w-4 mr-1" /> Guardar borrador
            </Button>
            <Button variant="outline" onClick={() => handleSave('email')} disabled={saving}>
              <Mail className="h-4 w-4 mr-1" /> Enviar por correo
            </Button>
            <Button onClick={() => handleSave('submit')} disabled={saving}>
              <FileText className="h-4 w-4 mr-1" /> Enviar cotización
            </Button>
          </div>
        </CardContent>
      </Card>
    </div>
  );
};
