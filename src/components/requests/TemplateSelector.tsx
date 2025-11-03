import { QuoteTemplate } from '@/types/quote-template';
import { Label } from '@/components/ui/label';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { Card, CardContent } from '@/components/ui/card';
import { FileText, Trash2 } from 'lucide-react';
import { Button } from '@/components/ui/button';

interface TemplateSelectorProps {
  templates: QuoteTemplate[];
  selectedTemplateId: string | null;
  onSelect: (templateId: string | null) => void;
  onDelete: (templateId: string) => void;
  loading?: boolean;
}

export const TemplateSelector = ({
  templates,
  selectedTemplateId,
  onSelect,
  onDelete,
  loading = false,
}: TemplateSelectorProps) => {
  const selectedTemplate = templates.find(t => t.id === selectedTemplateId);

  return (
    <Card className="border-dashed">
      <CardContent className="pt-6">
        <div className="space-y-4">
          <div className="flex items-start gap-4">
            <div className="flex-1 space-y-2">
              <Label htmlFor="template-select" className="flex items-center gap-2">
                <FileText className="w-4 h-4" />
                Usar Plantilla
              </Label>
              <Select
                value={selectedTemplateId || 'none'}
                onValueChange={(value) => onSelect(value === 'none' ? null : value)}
                disabled={loading}
              >
                <SelectTrigger id="template-select">
                  <SelectValue placeholder="Seleccionar plantilla..." />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="none">Sin plantilla (vacío)</SelectItem>
                  {templates.map((template) => (
                    <SelectItem key={template.id} value={template.id}>
                      {template.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              {templates.length === 0 && (
                <p className="text-sm text-muted-foreground">
                  No tienes plantillas guardadas. Crea tu primera cotización y guárdala como plantilla.
                </p>
              )}
            </div>

            {selectedTemplate && (
              <Button
                variant="ghost"
                size="icon"
                onClick={() => {
                  if (confirm(`¿Eliminar la plantilla "${selectedTemplate.name}"?`)) {
                    onDelete(selectedTemplate.id);
                  }
                }}
                className="text-destructive hover:text-destructive"
              >
                <Trash2 className="w-4 h-4" />
              </Button>
            )}
          </div>

          {selectedTemplate && (
            <div className="bg-muted p-3 rounded-lg text-sm">
              <p className="font-medium mb-1">Plantilla seleccionada: {selectedTemplate.name}</p>
              <p className="text-muted-foreground">
                {selectedTemplate.fields.length} campos • {selectedTemplate.percentage_fields.length} campos de porcentaje
              </p>
            </div>
          )}
        </div>
      </CardContent>
    </Card>
  );
};
