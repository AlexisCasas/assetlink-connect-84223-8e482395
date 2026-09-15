import { AlertTriangle, CheckCircle2, XCircle } from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import type { MatrixImportPreview } from '@/lib/criticalityImportValidation';

interface CriticalityMatrixImportPreviewProps {
  preview: MatrixImportPreview;
}

/** What the file WOULD become, before anything is sent. The backend
 * revalidates all of it anyway — this is only so the user can see and fix
 * problems first. */
export function CriticalityMatrixImportPreview({ preview }: CriticalityMatrixImportPreviewProps) {
  const blocking = preview.errors.length > 0;

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center gap-2">
        <Badge variant="outline">{preview.parameterCount} parámetros</Badge>
        <Badge variant="outline">{preview.optionCount} opciones</Badge>
        <Badge variant={preview.totalWeight === 100 ? 'secondary' : 'outline'}>
          Peso total: {preview.totalWeight}%
        </Badge>
        {blocking ? (
          <Badge variant="destructive" className="gap-1">
            <XCircle className="h-3 w-3" /> {preview.errors.length} error(es)
          </Badge>
        ) : (
          <Badge variant="secondary" className="gap-1">
            <CheckCircle2 className="h-3 w-3" /> Sin errores bloqueantes
          </Badge>
        )}
      </div>

      {preview.warnings.length > 0 && (
        <div className="space-y-1 rounded-md border border-amber-500/40 bg-amber-500/10 p-3 text-sm">
          {preview.warnings.map((warning, index) => (
            <p key={index} className="flex items-start gap-2">
              <AlertTriangle className="mt-0.5 h-3.5 w-3.5 shrink-0 text-amber-600" />
              <span>{warning.row ? `Fila ${warning.row}: ` : ''}{warning.message}</span>
            </p>
          ))}
        </div>
      )}

      {blocking && (
        <div className="max-h-48 space-y-1 overflow-y-auto rounded-md border border-destructive/40 bg-destructive/5 p-3 text-sm">
          {preview.errors.map((issue, index) => (
            <p key={index} className="flex items-start gap-2">
              <XCircle className="mt-0.5 h-3.5 w-3.5 shrink-0 text-destructive" />
              <span>{issue.row ? `Fila ${issue.row}: ` : ''}{issue.message}</span>
            </p>
          ))}
        </div>
      )}

      {preview.parameters.length > 0 && (
        <div className="max-h-64 space-y-2 overflow-y-auto">
          {preview.parameters.map((parameter) => (
            <div key={parameter.code} className="rounded-md border p-2.5">
              <div className="flex flex-wrap items-center gap-2">
                <span className="text-sm font-medium">{parameter.name}</span>
                <Badge variant="outline" className="font-mono text-[10px]">{parameter.code}</Badge>
                <Badge variant="secondary">{parameter.weight}%</Badge>
                {!parameter.isActive && <Badge variant="outline">Inactivo</Badge>}
              </div>
              <div className="mt-1.5 flex flex-wrap gap-1.5">
                {parameter.options.map((option) => (
                  <Badge key={option.code} variant="outline" className="text-xs">
                    {option.label} · {option.score}
                  </Badge>
                ))}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
