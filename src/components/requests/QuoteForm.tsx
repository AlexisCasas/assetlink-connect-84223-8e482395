import { useState, useEffect } from 'react';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Checkbox } from '@/components/ui/checkbox';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Request, Quote } from '@/types/request';
import { QuoteField, PercentageField, QuoteSummaryData, QuoteTableItem } from '@/types/quote-template';
import { X, Plus, Trash2, Edit2, ArrowUp, ArrowDown, Save, Percent } from 'lucide-react';
import { useToast } from '@/hooks/use-toast';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { TemplateSelector } from './TemplateSelector';
import { SaveTemplateDialog } from './SaveTemplateDialog';
import { QuoteSummary } from './QuoteSummary';
import { useQuoteTemplates } from '@/hooks/useQuoteTemplates';

interface QuoteFormProps {
  request: Request;
  onClose: () => void;
  onSave: (quote: Quote) => void;
}

export const QuoteForm = ({ request, onClose, onSave }: QuoteFormProps) => {
  const { toast } = useToast();
  const { user } = useAuth();
  const providerId = user?.providerId || '';
  const teamMemberId = user?.id || '';
  
  const { templates, loading: templatesLoading, saveTemplate, deleteTemplate } = useQuoteTemplates(providerId, teamMemberId);

  const [description, setDescription] = useState('');
  const [files, setFiles] = useState<FileList | null>(null);
  const [needsTechnicalVisit, setNeedsTechnicalVisit] = useState(false);
  const [elaboradoPor, setElaboradoPor] = useState('');
  const [revisadoPor, setRevisadoPor] = useState('');
  const [validoPor, setValidoPor] = useState('');
  const [deliveryDays, setDeliveryDays] = useState(1);
  const [validityDays, setValidityDays] = useState(30);
  const [teamMembers, setTeamMembers] = useState<Array<{ id: string; name: string; email: string }>>([]);
  const [loadingTeamMembers, setLoadingTeamMembers] = useState(true);
  
  // Dynamic fields
  const [fields, setFields] = useState<QuoteField[]>([
    {
      id: crypto.randomUUID(),
      title: 'Descripción del servicio',
      items: [{ id: crypto.randomUUID(), description: '', unit: 'UND', quantity: 0, unitPrice: 0, total: 0 }],
      order: 0,
    },
  ]);

  // Percentage fields
  const [percentageFields, setPercentageFields] = useState<PercentageField[]>([]);

  // Template management
  const [selectedTemplateId, setSelectedTemplateId] = useState<string | null>(null);
  const [showSaveTemplateDialog, setShowSaveTemplateDialog] = useState(false);
  const [editingFieldId, setEditingFieldId] = useState<string | null>(null);
  const [editingFieldTitle, setEditingFieldTitle] = useState('');

  // Load team members
  useEffect(() => {
    const loadTeamMembers = async () => {
      if (!providerId) return;
      
      setLoadingTeamMembers(true);
      try {
        const { data, error } = await supabase
          .from('team_members')
          .select('id, name, email')
          .eq('provider_id', providerId);
        
        if (error) throw error;
        setTeamMembers(data || []);
      } catch (error) {
        console.error('Error loading team members:', error);
        toast({
          title: "Error",
          description: "No se pudo cargar los miembros del equipo",
          variant: "destructive",
        });
      } finally {
        setLoadingTeamMembers(false);
      }
    };
    
    loadTeamMembers();
  }, [providerId, toast]);

  // Auto-complete "Elaborado por"
  useEffect(() => {
    if (user?.name) {
      setElaboradoPor(user.name);
    }
  }, [user]);

  // Load template when selected
  useEffect(() => {
    if (selectedTemplateId) {
      const template = templates.find(t => t.id === selectedTemplateId);
      if (template) {
        setFields(template.fields.map(f => ({ ...f, id: crypto.randomUUID() })));
        setPercentageFields(template.percentage_fields.map(p => ({ ...p, id: crypto.randomUUID() })));
      }
    }
  }, [selectedTemplateId, templates]);

  const addField = () => {
    const newField: QuoteField = {
      id: crypto.randomUUID(),
      title: 'Nuevo campo',
      items: [{ id: crypto.randomUUID(), description: '', unit: 'UND', quantity: 0, unitPrice: 0, total: 0 }],
      order: fields.length,
    };
    setFields([...fields, newField]);
  };

  const removeField = (fieldId: string) => {
    if (fields.length === 1) {
      toast({
        title: "Error",
        description: "Debe haber al menos un campo",
        variant: "destructive",
      });
      return;
    }
    setFields(fields.filter(f => f.id !== fieldId));
  };

  const updateFieldTitle = (fieldId: string, newTitle: string) => {
    setFields(fields.map(f => f.id === fieldId ? { ...f, title: newTitle } : f));
  };

  const moveField = (fieldId: string, direction: 'up' | 'down') => {
    const index = fields.findIndex(f => f.id === fieldId);
    if ((direction === 'up' && index === 0) || (direction === 'down' && index === fields.length - 1)) return;
    
    const newFields = [...fields];
    const targetIndex = direction === 'up' ? index - 1 : index + 1;
    [newFields[index], newFields[targetIndex]] = [newFields[targetIndex], newFields[index]];
    setFields(newFields);
  };

  const addItem = (fieldId: string) => {
    setFields(fields.map(field => {
      if (field.id === fieldId) {
        return {
          ...field,
          items: [...field.items, { id: crypto.randomUUID(), description: '', unit: 'UND', quantity: 0, unitPrice: 0, total: 0 }],
        };
      }
      return field;
    }));
  };

  const removeItem = (fieldId: string, itemId: string) => {
    setFields(fields.map(field => {
      if (field.id === fieldId && field.items.length > 1) {
        return {
          ...field,
          items: field.items.filter(item => item.id !== itemId),
        };
      }
      return field;
    }));
  };

  const updateItem = (fieldId: string, itemId: string, key: keyof QuoteTableItem, value: string | number) => {
    setFields(fields.map(field => {
      if (field.id === fieldId) {
        return {
          ...field,
          items: field.items.map(item => {
            if (item.id === itemId) {
              const updated = { ...item, [key]: value };
              if (key === 'quantity' || key === 'unitPrice') {
                updated.total = updated.quantity * updated.unitPrice;
              }
              return updated;
            }
            return item;
          }),
        };
      }
      return field;
    }));
  };

  const calculateFieldSubtotal = (field: QuoteField) => {
    return field.items.reduce((sum, item) => sum + item.total, 0);
  };

  const calculateSubtotal = () => {
    return fields.reduce((sum, field) => sum + calculateFieldSubtotal(field), 0);
  };

  // Percentage fields management
  const addPercentageField = () => {
    const newField: PercentageField = {
      id: crypto.randomUUID(),
      name: 'Nuevo campo',
      percentage: 0,
      order: percentageFields.length,
    };
    setPercentageFields([...percentageFields, newField]);
  };

  const removePercentageField = (fieldId: string) => {
    setPercentageFields(percentageFields.filter(f => f.id !== fieldId));
  };

  const updatePercentageField = (fieldId: string, key: 'name' | 'percentage', value: string | number) => {
    setPercentageFields(percentageFields.map(f => 
      f.id === fieldId ? { ...f, [key]: value } : f
    ));
  };

  const calculatePercentageAmounts = () => {
    let runningTotal = calculateSubtotal();
    const amounts: Array<{ name: string; amount: number }> = [];

    percentageFields.forEach(field => {
      const amount = (runningTotal * field.percentage) / 100;
      amounts.push({ name: field.name, amount });
      runningTotal += amount;
    });

    return amounts;
  };

  const calculateTotalWithPercentages = () => {
    const subtotal = calculateSubtotal();
    const percentageTotal = calculatePercentageAmounts().reduce((sum, p) => sum + p.amount, 0);
    return subtotal + percentageTotal;
  };

  const calculateIGV = () => {
    return calculateTotalWithPercentages() * 0.18;
  };

  const calculateFinalTotal = () => {
    return calculateTotalWithPercentages() + calculateIGV();
  };

  const handleSaveTemplate = async (name: string) => {
    const fieldsToSave = fields.map(f => ({
      ...f,
      items: [], // Don't save actual values
    }));
    
    return await saveTemplate(name, fieldsToSave, percentageFields);
  };

  const handleSubmit = async (isDraft: boolean) => {
    if (!description) {
      toast({
        title: "Error",
        description: "Por favor completa la descripción",
        variant: "destructive",
      });
      return;
    }

    // Validation for non-draft quotes
    if (!isDraft) {
      if (!elaboradoPor) {
        toast({
          title: "Error",
          description: "El campo 'Elaborado por' es obligatorio",
          variant: "destructive",
        });
        return;
      }
      
      if (!revisadoPor) {
        toast({
          title: "Error",
          description: "Por favor selecciona quién revisará la cotización",
          variant: "destructive",
        });
        return;
      }
      
      if (!validoPor) {
        toast({
          title: "Error",
          description: "Por favor selecciona quién aprobará la cotización",
          variant: "destructive",
        });
        return;
      }
    }

    const totalAmount = calculateFinalTotal();

    const quote: Quote = {
      id: crypto.randomUUID(),
      requestId: request.id,
      providerId,
      teamMemberId,
      amount: totalAmount,
      description,
      files: files ? Array.from(files) : undefined,
      createdAt: new Date().toISOString(),
      status: isDraft ? 'draft' : 'submitted',
      needsTechnicalVisit,
      elaboradoPor: elaboradoPor || undefined,
      revisadoPor: revisadoPor || undefined,
      validoPor: validoPor || undefined,
    };

    onSave(quote);
    
    if (needsTechnicalVisit && !isDraft) {
      try {
        await supabase.from('notifications').insert({
          user_email: request.createdBy,
          type: 'technical_visit',
          title: 'Visita técnica solicitada',
          message: `El proveedor ha solicitado una visita técnica para la solicitud ${request.requestNumber}.`,
          request_id: request.id,
          quote_id: quote.id,
        });
      } catch (error) {
        console.error('Error creating notification:', error);
      }
    }
    
    toast({
      title: isDraft ? "Borrador guardado" : "Cotización enviada",
      description: isDraft 
        ? "Tu cotización ha sido guardada como borrador" 
        : "La cotización ha sido enviada al cliente",
    });
    onClose();
  };

  const summaryData: QuoteSummaryData = {
    fields: fields.map(f => ({
      title: f.title,
      total: calculateFieldSubtotal(f),
    })),
    subtotal: calculateSubtotal(),
    percentageFields: calculatePercentageAmounts(),
    igv: calculateIGV(),
    total: calculateFinalTotal(),
  };

  return (
    <div className="fixed inset-0 bg-background/80 backdrop-blur-sm z-50 flex items-center justify-center p-4">
      <Card className="w-full max-w-5xl max-h-[90vh] overflow-y-auto">
        <CardHeader className="flex flex-row items-center justify-between sticky top-0 bg-background z-10 border-b">
          <CardTitle>Crear Cotización - {request.requestNumber}</CardTitle>
          <Button variant="ghost" size="icon" onClick={onClose}>
            <X className="w-4 h-4" />
          </Button>
        </CardHeader>
        <CardContent className="space-y-6 p-6">
          {/* Request Details */}
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

          {/* Template Selector */}
          <TemplateSelector
            templates={templates}
            selectedTemplateId={selectedTemplateId}
            onSelect={setSelectedTemplateId}
            onDelete={deleteTemplate}
            loading={templatesLoading}
          />

          {/* Description */}
          <div className="space-y-2">
            <Label htmlFor="description">Descripción general de la cotización *</Label>
            <Textarea
              id="description"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="Describe los trabajos a realizar, condiciones, garantías, etc."
              rows={3}
              required
            />
          </div>

          {/* Dynamic Fields */}
          <div className="space-y-4">
            <div className="flex items-center justify-between">
              <h3 className="text-lg font-semibold">Detalle de la Cotización</h3>
              <Button size="sm" onClick={addField}>
                <Plus className="h-4 w-4 mr-1" />
                Agregar Campo
              </Button>
            </div>

            {fields.map((field, fieldIndex) => (
              <div key={field.id} className="space-y-2 border rounded-lg p-4 bg-card">
                {/* Field Header */}
                <div className="flex items-center justify-between bg-muted p-3 rounded-lg">
                  <div className="flex items-center gap-2 flex-1">
                    {editingFieldId === field.id ? (
                      <Input
                        value={editingFieldTitle}
                        onChange={(e) => setEditingFieldTitle(e.target.value)}
                        onBlur={() => {
                          updateFieldTitle(field.id, editingFieldTitle);
                          setEditingFieldId(null);
                        }}
                        onKeyDown={(e) => {
                          if (e.key === 'Enter') {
                            updateFieldTitle(field.id, editingFieldTitle);
                            setEditingFieldId(null);
                          }
                        }}
                        className="h-8 max-w-md"
                        autoFocus
                      />
                    ) : (
                      <>
                        <h4 className="font-semibold">{fieldIndex + 1}. {field.title}</h4>
                        <Button
                          size="sm"
                          variant="ghost"
                          onClick={() => {
                            setEditingFieldId(field.id);
                            setEditingFieldTitle(field.title);
                          }}
                        >
                          <Edit2 className="h-3 w-3" />
                        </Button>
                      </>
                    )}
                  </div>
                  <div className="flex gap-1">
                    <Button
                      size="sm"
                      variant="ghost"
                      onClick={() => moveField(field.id, 'up')}
                      disabled={fieldIndex === 0}
                    >
                      <ArrowUp className="h-4 w-4" />
                    </Button>
                    <Button
                      size="sm"
                      variant="ghost"
                      onClick={() => moveField(field.id, 'down')}
                      disabled={fieldIndex === fields.length - 1}
                    >
                      <ArrowDown className="h-4 w-4" />
                    </Button>
                    <Button
                      size="sm"
                      variant="ghost"
                      onClick={() => addItem(field.id)}
                    >
                      <Plus className="h-4 w-4" />
                    </Button>
                    <Button
                      size="sm"
                      variant="ghost"
                      onClick={() => removeField(field.id)}
                      disabled={fields.length === 1}
                      className="text-destructive"
                    >
                      <Trash2 className="h-4 w-4" />
                    </Button>
                  </div>
                </div>

                {/* Field Table */}
                <div className="border rounded-lg overflow-hidden">
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead className="w-[40%]">Detalle</TableHead>
                        <TableHead className="w-[10%]">UND</TableHead>
                        <TableHead className="w-[10%]">CANT.</TableHead>
                        <TableHead className="w-[15%]">S/. Unitario</TableHead>
                        <TableHead className="w-[15%]">S/. Total</TableHead>
                        <TableHead className="w-[10%]"></TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {field.items.map((item) => (
                        <TableRow key={item.id}>
                          <TableCell>
                            <Input
                              value={item.description}
                              onChange={(e) => updateItem(field.id, item.id, 'description', e.target.value)}
                              placeholder="Descripción del ítem"
                              className="h-8"
                            />
                          </TableCell>
                          <TableCell>
                            <Input
                              value={item.unit}
                              onChange={(e) => updateItem(field.id, item.id, 'unit', e.target.value)}
                              placeholder="UND"
                              className="h-8"
                            />
                          </TableCell>
                          <TableCell>
                            <Input
                              type="number"
                              step="0.01"
                              value={item.quantity || ''}
                              onChange={(e) => updateItem(field.id, item.id, 'quantity', parseFloat(e.target.value) || 0)}
                              placeholder="0"
                              className="h-8"
                            />
                          </TableCell>
                          <TableCell>
                            <Input
                              type="number"
                              step="0.01"
                              value={item.unitPrice || ''}
                              onChange={(e) => updateItem(field.id, item.id, 'unitPrice', parseFloat(e.target.value) || 0)}
                              placeholder="0.00"
                              className="h-8"
                            />
                          </TableCell>
                          <TableCell>
                            <span className="font-medium">S/. {item.total.toFixed(2)}</span>
                          </TableCell>
                          <TableCell>
                            <Button
                              size="sm"
                              variant="ghost"
                              onClick={() => removeItem(field.id, item.id)}
                              disabled={field.items.length === 1}
                            >
                              <Trash2 className="h-4 w-4" />
                            </Button>
                          </TableCell>
                        </TableRow>
                      ))}
                      <TableRow>
                        <TableCell colSpan={4} className="text-right font-semibold">
                          Subtotal:
                        </TableCell>
                        <TableCell className="font-bold">
                          S/. {calculateFieldSubtotal(field).toFixed(2)}
                        </TableCell>
                        <TableCell></TableCell>
                      </TableRow>
                    </TableBody>
                  </Table>
                </div>
              </div>
            ))}
          </div>

          {/* Percentage Fields */}
          <div className="space-y-4">
            <div className="flex items-center justify-between">
              <h3 className="text-lg font-semibold flex items-center gap-2">
                <Percent className="w-5 h-5" />
                Campos de Porcentaje
              </h3>
              <Button size="sm" variant="outline" onClick={addPercentageField}>
                <Plus className="h-4 w-4 mr-1" />
                Agregar Campo %
              </Button>
            </div>

            {percentageFields.length > 0 && (
              <div className="border rounded-lg p-4 space-y-3 bg-muted/50">
                <div className="flex items-center justify-between text-sm font-medium">
                  <span>Subtotal Base:</span>
                  <span>S/. {calculateSubtotal().toFixed(2)}</span>
                </div>
                {percentageFields.map((field, index) => {
                  const amounts = calculatePercentageAmounts();
                  return (
                    <div key={field.id} className="flex items-center gap-3 bg-background p-3 rounded-lg">
                      <Input
                        value={field.name}
                        onChange={(e) => updatePercentageField(field.id, 'name', e.target.value)}
                        placeholder="Nombre del campo"
                        className="flex-1 h-8"
                      />
                      <div className="flex items-center gap-2">
                        <Input
                          type="number"
                          step="0.01"
                          value={field.percentage || ''}
                          onChange={(e) => updatePercentageField(field.id, 'percentage', parseFloat(e.target.value) || 0)}
                          placeholder="0"
                          className="w-20 h-8"
                        />
                        <span className="text-sm">%</span>
                      </div>
                      <span className="text-sm font-medium min-w-[100px] text-right">
                        S/. {amounts[index]?.amount.toFixed(2) || '0.00'}
                      </span>
                      <Button
                        size="sm"
                        variant="ghost"
                        onClick={() => removePercentageField(field.id)}
                        className="text-destructive"
                      >
                        <Trash2 className="h-4 w-4" />
                      </Button>
                    </div>
                  );
                })}
              </div>
            )}
          </div>

          {/* Summary */}
          <QuoteSummary data={summaryData} deliveryDays={deliveryDays} validityDays={validityDays} />

          {/* Delivery and Validity */}
          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-2">
              <Label htmlFor="delivery-days">Plazo de Entrega (días)</Label>
              <Input
                id="delivery-days"
                type="number"
                value={deliveryDays}
                onChange={(e) => setDeliveryDays(parseInt(e.target.value) || 1)}
                min="1"
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="validity-days">Vigencia (días)</Label>
              <Input
                id="validity-days"
                type="number"
                value={validityDays}
                onChange={(e) => setValidityDays(parseInt(e.target.value) || 30)}
                min="1"
              />
            </div>
          </div>

          {/* Files */}
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
            </div>
            {files && files.length > 0 && (
              <div className="text-sm text-muted-foreground">
                {files.length} archivo(s) seleccionado(s)
              </div>
            )}
          </div>

          {/* Responsible persons */}
          <div className="grid grid-cols-3 gap-4">
            <div className="space-y-2">
              <Label htmlFor="elaborado-por">Elaborado por</Label>
              <Input
                id="elaborado-por"
                value={elaboradoPor}
                disabled
                className="bg-muted"
                placeholder="Auto-completado"
              />
              <p className="text-xs text-muted-foreground">
                Se completa automáticamente con tu nombre
              </p>
            </div>
            <div className="space-y-2">
              <Label htmlFor="revisado-por">Revisado por</Label>
              <Select 
                value={revisadoPor} 
                onValueChange={setRevisadoPor}
                disabled={loadingTeamMembers || teamMembers.length === 0}
              >
                <SelectTrigger>
                  <SelectValue placeholder={
                    loadingTeamMembers 
                      ? "Cargando..." 
                      : teamMembers.length === 0 
                        ? "No hay miembros disponibles" 
                        : "Seleccionar responsable"
                  } />
                </SelectTrigger>
                <SelectContent>
                  {user?.name && (
                    <SelectItem value={user.name}>
                      {user.name} (Yo)
                    </SelectItem>
                  )}
                  {teamMembers
                    .filter(member => member.id !== user?.id)
                    .map(member => (
                      <SelectItem key={member.id} value={member.name}>
                        {member.name}
                      </SelectItem>
                    ))
                  }
                </SelectContent>
              </Select>
              <p className="text-xs text-muted-foreground">
                Selecciona quien revisará la cotización
              </p>
            </div>
            <div className="space-y-2">
              <Label htmlFor="aprobado-por">Aprobado por</Label>
              <Select 
                value={validoPor} 
                onValueChange={setValidoPor}
                disabled={loadingTeamMembers || teamMembers.length === 0}
              >
                <SelectTrigger>
                  <SelectValue placeholder={
                    loadingTeamMembers 
                      ? "Cargando..." 
                      : teamMembers.length === 0 
                        ? "No hay miembros disponibles" 
                        : "Seleccionar aprobador"
                  } />
                </SelectTrigger>
                <SelectContent>
                  {user?.name && (
                    <SelectItem value={user.name}>
                      {user.name} (Yo)
                    </SelectItem>
                  )}
                  {teamMembers
                    .filter(member => member.id !== user?.id)
                    .map(member => (
                      <SelectItem key={member.id} value={member.name}>
                        {member.name}
                      </SelectItem>
                    ))
                  }
                </SelectContent>
              </Select>
              <p className="text-xs text-muted-foreground">
                Selecciona quien aprobará la cotización
              </p>
            </div>
          </div>

          {/* Technical Visit */}
          <div className="flex items-center space-x-2 p-4 border rounded-lg bg-muted/50">
            <Checkbox 
              id="technical-visit" 
              checked={needsTechnicalVisit}
              onCheckedChange={(checked) => setNeedsTechnicalVisit(checked as boolean)}
            />
            <label 
              htmlFor="technical-visit" 
              className="text-sm font-medium leading-none peer-disabled:cursor-not-allowed peer-disabled:opacity-70 cursor-pointer"
            >
              Se necesita una visita técnica previa
            </label>
          </div>

          {/* Action Buttons */}
          <div className="flex gap-3 justify-between pt-4 border-t sticky bottom-0 bg-background">
            <Button variant="outline" onClick={() => setShowSaveTemplateDialog(true)}>
              <Save className="h-4 w-4 mr-2" />
              Guardar Plantilla
            </Button>
            <div className="flex gap-3">
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
          </div>
        </CardContent>
      </Card>

      {showSaveTemplateDialog && (
        <SaveTemplateDialog
          onSave={handleSaveTemplate}
          onClose={() => setShowSaveTemplateDialog(false)}
        />
      )}
    </div>
  );
};
