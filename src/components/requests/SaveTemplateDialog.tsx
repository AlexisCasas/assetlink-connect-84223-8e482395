import { useState } from 'react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Save } from 'lucide-react';

interface SaveTemplateDialogProps {
  onSave: (name: string) => Promise<boolean>;
  onClose: () => void;
}

export const SaveTemplateDialog = ({ onSave, onClose }: SaveTemplateDialogProps) => {
  const [name, setName] = useState('');
  const [saving, setSaving] = useState(false);

  const handleSave = async () => {
    if (!name.trim()) return;
    
    setSaving(true);
    const success = await onSave(name.trim());
    setSaving(false);
    
    if (success) {
      onClose();
    }
  };

  return (
    <div className="fixed inset-0 bg-background/80 backdrop-blur-sm z-50 flex items-center justify-center p-4">
      <Card className="w-full max-w-md">
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Save className="w-5 h-5" />
            Guardar Plantilla
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="template-name">
              Nombre de la plantilla <span className="text-destructive">*</span>
            </Label>
            <Input
              id="template-name"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="Ej: Plantilla Mantenimiento Preventivo"
              onKeyDown={(e) => {
                if (e.key === 'Enter' && name.trim()) {
                  handleSave();
                }
              }}
            />
            <p className="text-sm text-muted-foreground">
              Esta plantilla guardará la estructura de campos y porcentajes configurados.
            </p>
          </div>

          <div className="flex gap-3 justify-end">
            <Button variant="outline" onClick={onClose} disabled={saving}>
              Cancelar
            </Button>
            <Button onClick={handleSave} disabled={!name.trim() || saving}>
              {saving ? 'Guardando...' : 'Guardar'}
            </Button>
          </div>
        </CardContent>
      </Card>
    </div>
  );
};
