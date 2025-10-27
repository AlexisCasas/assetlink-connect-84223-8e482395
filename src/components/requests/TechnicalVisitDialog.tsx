import { useState } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Textarea } from '@/components/ui/textarea';
import { Label } from '@/components/ui/label';
import { Input } from '@/components/ui/input';
import { Upload, X, FileText } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

interface TechnicalVisitDialogProps {
  open: boolean;
  onClose: () => void;
  requestId: string;
  assignmentId: string;
  teamMemberId: string;
}

export const TechnicalVisitDialog = ({
  open,
  onClose,
  requestId,
  assignmentId,
  teamMemberId,
}: TechnicalVisitDialogProps) => {
  const [files, setFiles] = useState<File[]>([]);
  const [notes, setNotes] = useState('');
  const [uploading, setUploading] = useState(false);

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    if (e.target.files) {
      setFiles(Array.from(e.target.files));
    }
  };

  const removeFile = (index: number) => {
    setFiles(prev => prev.filter((_, i) => i !== index));
  };

  const handleSubmit = async () => {
    if (files.length === 0) {
      toast.error('Debe subir al menos un archivo');
      return;
    }

    setUploading(true);
    try {
      // Upload files to Supabase Storage
      const fileUrls: string[] = [];
      
      for (const file of files) {
        const fileName = `${requestId}/${Date.now()}-${file.name}`;
        const { error: uploadError } = await supabase.storage
          .from('request-documents')
          .upload(fileName, file);

        if (uploadError) throw uploadError;

        const { data: { publicUrl } } = supabase.storage
          .from('request-documents')
          .getPublicUrl(fileName);

        fileUrls.push(publicUrl);
      }

      // Save to database
      const { error: dbError } = await supabase
        .from('technical_visit_documents')
        .insert({
          request_id: requestId,
          assignment_id: assignmentId,
          team_member_id: teamMemberId,
          file_urls: fileUrls,
          notes: notes || null,
        });

      if (dbError) throw dbError;

      toast.success('Documentación de visita guardada exitosamente');
      setFiles([]);
      setNotes('');
      onClose();
    } catch (error) {
      console.error('Error uploading technical visit documents:', error);
      toast.error('Error al guardar la documentación');
    } finally {
      setUploading(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onClose}>
      <DialogContent className="max-w-2xl">
        <DialogHeader>
          <DialogTitle>Documentar Visita Técnica</DialogTitle>
        </DialogHeader>

        <div className="space-y-4">
          <div>
            <Label htmlFor="files">Archivos de la visita *</Label>
            <div className="mt-2">
              <Input
                id="files"
                type="file"
                multiple
                onChange={handleFileChange}
                className="cursor-pointer"
                accept="image/*,.pdf,.doc,.docx"
              />
              <p className="text-xs text-muted-foreground mt-1">
                Sube fotos, informes o documentos relacionados con la visita
              </p>
            </div>
          </div>

          {files.length > 0 && (
            <div className="space-y-2">
              <Label>Archivos seleccionados:</Label>
              <div className="space-y-2">
                {files.map((file, index) => (
                  <div
                    key={index}
                    className="flex items-center justify-between p-2 border rounded-lg"
                  >
                    <div className="flex items-center gap-2">
                      <FileText className="h-4 w-4 text-muted-foreground" />
                      <span className="text-sm">{file.name}</span>
                      <span className="text-xs text-muted-foreground">
                        ({(file.size / 1024).toFixed(1)} KB)
                      </span>
                    </div>
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => removeFile(index)}
                    >
                      <X className="h-4 w-4" />
                    </Button>
                  </div>
                ))}
              </div>
            </div>
          )}

          <div>
            <Label htmlFor="notes">Notas adicionales (opcional)</Label>
            <Textarea
              id="notes"
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              placeholder="Describe los hallazgos de la visita, trabajos realizados, recomendaciones, etc."
              rows={5}
              className="mt-2"
            />
          </div>

          <div className="flex justify-end gap-2 pt-4">
            <Button variant="outline" onClick={onClose} disabled={uploading}>
              Cancelar
            </Button>
            <Button onClick={handleSubmit} disabled={uploading}>
              <Upload className="mr-2 h-4 w-4" />
              {uploading ? 'Guardando...' : 'Guardar documentación'}
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
};
