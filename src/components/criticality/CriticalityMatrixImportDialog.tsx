import { useEffect, useRef, useState } from 'react';
import { FileSpreadsheet, Upload } from 'lucide-react';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { parseMatrixWorkbook } from '@/lib/criticalityExcel';
import { validateMatrixWorkbook, type MatrixImportPreview } from '@/lib/criticalityImportValidation';
import { CriticalityMatrixImportPreview } from './CriticalityMatrixImportPreview';
import type { CriticalityMatrixPayloadParameter, CriticalityThresholdValues } from '@/types/criticalityMatrix';

interface CriticalityMatrixImportDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  hasActiveMatrix: boolean;
  /** Current effective thresholds, shown next to the ones the file carries. */
  currentThresholds: CriticalityThresholdValues | null;
  saving: boolean;
  /** Applies matrix + thresholds atomically (replace_criticality_configuration).
   * thresholds = null for a legacy file: current thresholds are kept. */
  onApply: (parameters: CriticalityMatrixPayloadParameter[], thresholds: CriticalityThresholdValues | null) => Promise<boolean>;
}

/**
 * Selecting a file NEVER writes anything: parse → validate → preview →
 * explicit confirmation → replace_criticality_configuration (matrix and, when
 * the file has a "Configuración" sheet, thresholds — in one transaction; the
 * server revalidates the whole payload again).
 */
export function CriticalityMatrixImportDialog({
  open,
  onOpenChange,
  hasActiveMatrix,
  currentThresholds,
  saving,
  onApply,
}: CriticalityMatrixImportDialogProps) {
  const inputRef = useRef<HTMLInputElement>(null);
  const [fileName, setFileName] = useState<string | null>(null);
  const [preview, setPreview] = useState<MatrixImportPreview | null>(null);
  const [parseError, setParseError] = useState<string | null>(null);
  const [parsing, setParsing] = useState(false);

  useEffect(() => {
    if (open) {
      setFileName(null);
      setPreview(null);
      setParseError(null);
      setParsing(false);
    }
  }, [open]);

  const handleFile = async (file: File) => {
    setFileName(file.name);
    setPreview(null);
    setParseError(null);

    if (!file.name.toLowerCase().endsWith('.xlsx')) {
      setParseError('El archivo debe ser .xlsx generado por OneFacility.');
      return;
    }

    setParsing(true);
    try {
      setPreview(validateMatrixWorkbook(await parseMatrixWorkbook(file)));
    } catch (error) {
      setParseError(error instanceof Error ? error.message : 'No se pudo leer el archivo.');
    } finally {
      setParsing(false);
    }
  };

  const handleApply = async () => {
    if (!preview || preview.errors.length > 0) return;
    if (await onApply(preview.parameters, preview.thresholds)) {
      onOpenChange(false);
    }
  };

  const canApply = !!preview && preview.errors.length === 0 && preview.parameters.length > 0;

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-3xl max-h-[85vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <FileSpreadsheet className="h-5 w-5" /> Importar matriz desde Excel
          </DialogTitle>
          <DialogDescription>
            Solo se aceptan archivos con el formato que genera “Exportar matriz”. Nada se guarda hasta que confirmes.
          </DialogDescription>
        </DialogHeader>

        <div className="flex flex-wrap items-center gap-3">
          <input
            ref={inputRef}
            type="file"
            accept=".xlsx"
            className="hidden"
            onChange={(event) => {
              const file = event.target.files?.[0];
              if (file) void handleFile(file);
              event.target.value = '';
            }}
          />
          <Button variant="outline" onClick={() => inputRef.current?.click()} disabled={parsing || saving}>
            <Upload className="mr-2 h-4 w-4" /> Seleccionar archivo
          </Button>
          {fileName && <span className="text-sm text-muted-foreground">{fileName}</span>}
        </div>

        {parsing && <p className="text-sm text-muted-foreground">Leyendo archivo…</p>}
        {parseError && <p className="text-sm text-destructive">{parseError}</p>}

        {preview && <CriticalityMatrixImportPreview preview={preview} currentThresholds={currentThresholds} />}

        {canApply && hasActiveMatrix && (
          <div className="rounded-md border border-amber-500/40 bg-amber-500/10 p-3 text-sm">
            Al importar se reemplazará la matriz activa{preview?.thresholds ? ' y los umbrales de clasificación' : ''}.
            La configuración anterior queda desactivada (no se borra) y las evaluaciones históricas se conservan
            intactas, con la clasificación y los umbrales con que se calcularon.
          </div>
        )}

        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={saving}>Cancelar</Button>
          <Button onClick={() => void handleApply()} disabled={!canApply || saving || parsing}>
            {saving ? 'Aplicando…' : 'Aplicar matriz'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
