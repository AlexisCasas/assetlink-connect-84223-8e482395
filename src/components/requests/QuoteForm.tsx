import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Checkbox } from '@/components/ui/checkbox';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Request, Quote, QuoteTableItem } from '@/types/request';
import { X, Plus, Trash2 } from 'lucide-react';
import { useToast } from '@/hooks/use-toast';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';

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
  const [needsTechnicalVisit, setNeedsTechnicalVisit] = useState(false);
  
  // Estados para las tablas de cotización
  const [serviceItems, setServiceItems] = useState<QuoteTableItem[]>([
    { id: crypto.randomUUID(), description: '', unit: 'UND', quantity: 0, unitPrice: 0, total: 0 }
  ]);
  const [equipmentItems, setEquipmentItems] = useState<QuoteTableItem[]>([
    { id: crypto.randomUUID(), description: '', unit: 'UND', quantity: 0, unitPrice: 0, total: 0 }
  ]);
  const [materialItems, setMaterialItems] = useState<QuoteTableItem[]>([
    { id: crypto.randomUUID(), description: '', unit: 'UND', quantity: 0, unitPrice: 0, total: 0 }
  ]);
  
  // Estados para condiciones de cotización
  const [conditions, setConditions] = useState([
    { id: crypto.randomUUID(), description: 'Validez de la cotización: 30 días calendario' },
    { id: crypto.randomUUID(), description: 'Precios incluyen IGV' },
    { id: crypto.randomUUID(), description: 'Forma de pago: 50% adelanto, 50% contra entrega' }
  ]);
  const [validityDate, setValidityDate] = useState('');
  const [includesIGV, setIncludesIGV] = useState(true);

  const addItem = (section: 'service' | 'equipment' | 'material') => {
    const newItem: QuoteTableItem = {
      id: crypto.randomUUID(),
      description: '',
      unit: 'UND',
      quantity: 0,
      unitPrice: 0,
      total: 0
    };
    
    if (section === 'service') setServiceItems([...serviceItems, newItem]);
    if (section === 'equipment') setEquipmentItems([...equipmentItems, newItem]);
    if (section === 'material') setMaterialItems([...materialItems, newItem]);
  };

  const removeItem = (section: 'service' | 'equipment' | 'material', id: string) => {
    if (section === 'service') setServiceItems(serviceItems.filter(item => item.id !== id));
    if (section === 'equipment') setEquipmentItems(equipmentItems.filter(item => item.id !== id));
    if (section === 'material') setMaterialItems(materialItems.filter(item => item.id !== id));
  };

  const updateItem = (section: 'service' | 'equipment' | 'material', id: string, field: keyof QuoteTableItem, value: string | number) => {
    const updateItems = (items: QuoteTableItem[]) => {
      return items.map(item => {
        if (item.id === id) {
          const updated = { ...item, [field]: value };
          // Recalcular total si cambia cantidad o precio unitario
          if (field === 'quantity' || field === 'unitPrice') {
            updated.total = updated.quantity * updated.unitPrice;
          }
          return updated;
        }
        return item;
      });
    };

    if (section === 'service') setServiceItems(updateItems(serviceItems));
    if (section === 'equipment') setEquipmentItems(updateItems(equipmentItems));
    if (section === 'material') setMaterialItems(updateItems(materialItems));
  };

  const calculateSubtotal = (items: QuoteTableItem[]) => {
    return items.reduce((sum, item) => sum + item.total, 0);
  };

  const calculateTotal = () => {
    return calculateSubtotal(serviceItems) + calculateSubtotal(equipmentItems) + calculateSubtotal(materialItems);
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

    const totalAmount = calculateTotal();

    const quote: Quote = {
      id: crypto.randomUUID(),
      requestId: request.id,
      providerId: user?.providerId || '',
      teamMemberId: user?.id || '',
      amount: totalAmount,
      description,
      files: files ? Array.from(files) : undefined,
      createdAt: new Date().toISOString(),
      status: isDraft ? 'draft' : 'submitted',
      serviceItems: serviceItems.filter(item => item.description.trim() !== ''),
      equipmentItems: equipmentItems.filter(item => item.description.trim() !== ''),
      materialItems: materialItems.filter(item => item.description.trim() !== ''),
      conditions: conditions.filter(c => c.description.trim() !== ''),
      validityDate: validityDate || undefined,
      includesIGV,
      needsTechnicalVisit,
    };

    onSave(quote);
    
    // Create notification if technical visit is needed
    if (needsTechnicalVisit && !isDraft) {
      try {
        await supabase.from('notifications').insert({
          user_email: request.createdBy,
          type: 'technical_visit',
          title: 'Visita técnica solicitada',
          message: `El proveedor ha solicitado una visita técnica para la solicitud ${request.requestNumber}. Se pondrán en contacto contigo para coordinar los detalles.`,
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

  const renderTableSection = (
    title: string,
    items: QuoteTableItem[],
    section: 'service' | 'equipment' | 'material'
  ) => (
    <div className="space-y-2">
      <div className="flex items-center justify-between bg-muted p-3 rounded-t-lg">
        <h4 className="font-semibold">{title}</h4>
        <Button size="sm" variant="outline" onClick={() => addItem(section)}>
          <Plus className="h-4 w-4 mr-1" />
          Agregar fila
        </Button>
      </div>
      <div className="border rounded-b-lg overflow-hidden">
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
            {items.map((item) => (
              <TableRow key={item.id}>
                <TableCell>
                  <Input
                    value={item.description}
                    onChange={(e) => updateItem(section, item.id, 'description', e.target.value)}
                    placeholder="Descripción del ítem"
                    className="h-8"
                  />
                </TableCell>
                <TableCell>
                  <Input
                    value={item.unit}
                    onChange={(e) => updateItem(section, item.id, 'unit', e.target.value)}
                    placeholder="UND"
                    className="h-8"
                  />
                </TableCell>
                <TableCell>
                  <Input
                    type="number"
                    step="0.01"
                    value={item.quantity}
                    onChange={(e) => updateItem(section, item.id, 'quantity', parseFloat(e.target.value) || 0)}
                    placeholder="0"
                    className="h-8"
                  />
                </TableCell>
                <TableCell>
                  <Input
                    type="number"
                    step="0.01"
                    value={item.unitPrice}
                    onChange={(e) => updateItem(section, item.id, 'unitPrice', parseFloat(e.target.value) || 0)}
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
                    onClick={() => removeItem(section, item.id)}
                    disabled={items.length === 1}
                  >
                    <Trash2 className="h-4 w-4" />
                  </Button>
                </TableCell>
              </TableRow>
            ))}
            <TableRow>
              <TableCell colSpan={4} className="text-right font-semibold">
                Subtotal {title}:
              </TableCell>
              <TableCell className="font-bold">
                S/. {calculateSubtotal(items).toFixed(2)}
              </TableCell>
              <TableCell></TableCell>
            </TableRow>
          </TableBody>
        </Table>
      </div>
    </div>
  );

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

          {/* Tabla de cotización */}
          <div className="space-y-4">
            <h3 className="text-lg font-semibold">Detalle de la Cotización</h3>
            
            {renderTableSection('1. Descripción del servicio', serviceItems, 'service')}
            {renderTableSection('2. Descripción de equipos de alto riesgo (En caso aplique)', equipmentItems, 'equipment')}
            {renderTableSection('3. Descripción de materiales relevantes', materialItems, 'material')}

            <div className="flex justify-end p-4 bg-primary/10 rounded-lg">
              <div className="text-right">
                <p className="text-lg font-semibold">COSTO TOTAL</p>
                <p className="text-2xl font-bold text-primary">S/. {calculateTotal().toFixed(2)}</p>
              </div>
            </div>
          </div>

          {/* Condiciones de la cotización */}
          <div className="space-y-2">
            <div className="flex items-center justify-between">
              <Label>Condiciones de la Cotización</Label>
              <Button 
                size="sm" 
                variant="outline" 
                onClick={() => setConditions([...conditions, { id: crypto.randomUUID(), description: '' }])}
              >
                <Plus className="h-4 w-4 mr-1" />
                Agregar condición
              </Button>
            </div>
            <div className="space-y-2 border rounded-lg p-4">
              {conditions.map((condition, index) => (
                <div key={condition.id} className="flex gap-2 items-start">
                  <span className="text-sm text-muted-foreground mt-2 w-4">{index + 1}.</span>
                  <Input
                    value={condition.description}
                    onChange={(e) => {
                      const updated = conditions.map(c => 
                        c.id === condition.id ? { ...c, description: e.target.value } : c
                      );
                      setConditions(updated);
                    }}
                    placeholder="Describe una condición de la cotización"
                    className="flex-1"
                  />
                  <Button
                    size="sm"
                    variant="ghost"
                    onClick={() => setConditions(conditions.filter(c => c.id !== condition.id))}
                    disabled={conditions.length === 1}
                  >
                    <Trash2 className="h-4 w-4" />
                  </Button>
                </div>
              ))}
            </div>
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

          {/* Technical Visit Checkbox */}
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
