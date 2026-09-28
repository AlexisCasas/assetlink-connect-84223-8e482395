import { useEffect, useMemo, useRef, useState } from 'react';
import { Download, FileSpreadsheet, Upload } from 'lucide-react';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { useAssets } from '@/hooks/useAssets';
import type { AssetScope } from '@/hooks/useAssetScope';
import { buildAssetPathMap } from '@/lib/assetTree';
import { ASSET_CRITICALITY_LABELS } from '@/lib/assetLabels';
import {
  buildBulkErrorsWorkbook,
  buildBulkTemplateWorkbook,
  bulkErrorsFileName,
  bulkTemplateFileName,
  downloadBlob,
  parseBulkWorkbook,
} from '@/lib/criticalityExcel';
import { prepareBulkRows } from '@/lib/criticalityImportValidation';
import { CriticalityBulkAssessmentPreview } from './CriticalityBulkAssessmentPreview';
import type {
  BulkCriticalityPreviewRow,
  BulkCriticalityResult,
  BulkCriticalityRow,
  CriticalityParameter,
} from '@/types/criticalityMatrix';

interface CriticalityBulkAssessmentDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  organizationName: string;
  /** Delegated FM mode: the client's asset scope. Omitted = direct mode. */
  assetScope?: AssetScope;
  activeParameters: CriticalityParameter[];
  saving: boolean;
  onPreview: (rows: BulkCriticalityRow[]) => Promise<BulkCriticalityPreviewRow[]>;
  onApply: (rows: BulkCriticalityRow[]) => Promise<BulkCriticalityResult | null>;
  onApplied: () => void;
}

export function CriticalityBulkAssessmentDialog({
  open,
  onOpenChange,
  organizationName,
  assetScope,
  activeParameters,
  saving,
  onPreview,
  onApply,
  onApplied,
}: CriticalityBulkAssessmentDialogProps) {
  const { assets, assetTree } = useAssets(assetScope);
  const inputRef = useRef<HTMLInputElement>(null);

  const [busy, setBusy] = useState(false);
  const [fileName, setFileName] = useState<string | null>(null);
  const [fileError, setFileError] = useState<string | null>(null);
  const [structuralErrors, setStructuralErrors] = useState<string[]>([]);
  const [warnings, setWarnings] = useState<string[]>([]);
  const [previewRows, setPreviewRows] = useState<BulkCriticalityPreviewRow[] | null>(null);
  const [validRows, setValidRows] = useState<BulkCriticalityRow[]>([]);
  const [result, setResult] = useState<BulkCriticalityResult | null>(null);

  useEffect(() => {
    if (open) {
      setFileName(null);
      setFileError(null);
      setStructuralErrors([]);
      setWarnings([]);
      setPreviewRows(null);
      setValidRows([]);
      setResult(null);
      setBusy(false);
    }
  }, [open]);

  // Same "evaluable asset" rule the asset tree already uses: archived assets
  // are excluded (filterArchived in useAssets), no new filter invented here.
  const evaluableAssets = useMemo(() => {
    const paths = buildAssetPathMap(assetTree);
    return assets
      .filter((asset) => asset.status !== 'archived')
      .map((asset) => ({
        id: asset.id,
        code: asset.code ?? null,
        name: asset.name,
        path: paths.get(asset.id) ?? asset.name,
      }));
  }, [assets, assetTree]);

  const handleDownloadTemplate = async () => {
    setBusy(true);
    try {
      const blob = await buildBulkTemplateWorkbook(evaluableAssets, activeParameters, organizationName);
      downloadBlob(blob, bulkTemplateFileName(organizationName));
    } catch (error) {
      setFileError(error instanceof Error ? error.message : 'No se pudo generar la plantilla.');
    } finally {
      setBusy(false);
    }
  };

  const handleFile = async (file: File) => {
    setFileName(file.name);
    setFileError(null);
    setStructuralErrors([]);
    setWarnings([]);
    setPreviewRows(null);
    setValidRows([]);
    setResult(null);

    if (!file.name.toLowerCase().endsWith('.xlsx')) {
      setFileError('El archivo debe ser el .xlsx descargado desde OneFacility.');
      return;
    }

    setBusy(true);
    try {
      const parsed = await parseBulkWorkbook(file);
      const prepared = prepareBulkRows(parsed, activeParameters);
      setStructuralErrors(prepared.structuralErrors);
      setWarnings(prepared.warnings);

      if (prepared.structuralErrors.length > 0) {
        setPreviewRows(prepared.clientInvalidRows);
        return;
      }

      // The authoritative score/validation always comes from the server.
      const serverRows = prepared.rows.length > 0 ? await onPreview(prepared.rows) : [];
      const merged = [...serverRows, ...prepared.clientInvalidRows].sort((a, b) => a.rowNumber - b.rowNumber);
      setPreviewRows(merged);
      setValidRows(prepared.rows.filter((row) => serverRows.some((server) => server.rowNumber === row.rowNumber && server.valid)));
    } catch (error) {
      setFileError(error instanceof Error ? error.message : 'No se pudo leer el archivo.');
    } finally {
      setBusy(false);
    }
  };

  const handleApply = async () => {
    if (validRows.length === 0) return;
    const applied = await onApply(validRows);
    if (applied) {
      setResult(applied);
      onApplied();
    }
  };

  const handleDownloadErrors = async () => {
    const invalid = (previewRows ?? []).filter((row) => !row.valid);
    if (invalid.length === 0) return;
    const blob = await buildBulkErrorsWorkbook(invalid.map((row) => ({
      rowNumber: row.rowNumber,
      assetCode: row.assetCode,
      assetName: row.assetName,
      errors: row.errors,
    })));
    downloadBlob(blob, bulkErrorsFileName(organizationName));
  };

  const invalidCount = (previewRows ?? []).filter((row) => !row.valid).length;

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-4xl max-h-[85vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <FileSpreadsheet className="h-5 w-5" /> Evaluar criticidad por Excel
          </DialogTitle>
          <DialogDescription>
            Descarga la plantilla con tus activos, completa una opción por parámetro y vuelve a subirla.
            OneFacility calcula el score y la criticidad; el archivo solo aporta las respuestas.
          </DialogDescription>
        </DialogHeader>

        {activeParameters.length === 0 ? (
          <p className="rounded-md border border-dashed p-4 text-sm text-muted-foreground">
            Configura primero una matriz con parámetros activos para poder evaluar por Excel.
          </p>
        ) : (
          <>
            <div className="flex flex-wrap items-center gap-3">
              <Button variant="outline" onClick={() => void handleDownloadTemplate()} disabled={busy || saving}>
                <Download className="mr-2 h-4 w-4" /> Descargar plantilla ({evaluableAssets.length} activos)
              </Button>
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
              <Button variant="outline" onClick={() => inputRef.current?.click()} disabled={busy || saving}>
                <Upload className="mr-2 h-4 w-4" /> Subir archivo completado
              </Button>
              {fileName && <span className="text-sm text-muted-foreground">{fileName}</span>}
            </div>

            {busy && <p className="text-sm text-muted-foreground">Procesando…</p>}
            {fileError && <p className="text-sm text-destructive">{fileError}</p>}

            {structuralErrors.length > 0 && (
              <div className="space-y-1 rounded-md border border-destructive/40 bg-destructive/5 p-3 text-sm">
                {structuralErrors.map((message, index) => <p key={index}>{message}</p>)}
              </div>
            )}

            {warnings.length > 0 && (
              <div className="space-y-1 rounded-md border border-amber-500/40 bg-amber-500/10 p-3 text-sm">
                {warnings.map((message, index) => <p key={index}>{message}</p>)}
              </div>
            )}

            {previewRows && !result && <CriticalityBulkAssessmentPreview rows={previewRows} />}

            {result && (
              <div className="space-y-2 rounded-md border border-primary/40 bg-primary/5 p-4">
                <p className="font-medium">Importación completada</p>
                <div className="flex flex-wrap gap-2 text-sm">
                  <Badge variant="secondary">{result.evaluated} evaluados</Badge>
                  <Badge variant="outline">{invalidCount} omitidos</Badge>
                  <Badge variant="destructive">{ASSET_CRITICALITY_LABELS.critical}: {result.counts.critical}</Badge>
                  <Badge>{ASSET_CRITICALITY_LABELS.high}: {result.counts.high}</Badge>
                  <Badge variant="secondary">{ASSET_CRITICALITY_LABELS.medium}: {result.counts.medium}</Badge>
                  <Badge variant="outline">{ASSET_CRITICALITY_LABELS.low}: {result.counts.low}</Badge>
                </div>
              </div>
            )}
          </>
        )}

        <DialogFooter className="flex-wrap gap-2">
          {invalidCount > 0 && (
            <Button variant="outline" onClick={() => void handleDownloadErrors()} disabled={busy}>
              <Download className="mr-2 h-4 w-4" /> Descargar errores ({invalidCount})
            </Button>
          )}
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={saving}>
            {result ? 'Cerrar' : 'Cancelar y corregir'}
          </Button>
          {!result && previewRows && validRows.length > 0 && (
            <Button onClick={() => void handleApply()} disabled={saving || busy}>
              {saving ? 'Importando…' : `Importar ${validRows.length} válidas`}
            </Button>
          )}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
