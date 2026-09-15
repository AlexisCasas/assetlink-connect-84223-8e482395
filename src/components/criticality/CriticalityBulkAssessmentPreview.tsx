import { Badge } from '@/components/ui/badge';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import type { BulkCriticalityPreviewRow } from '@/types/criticalityMatrix';

interface CriticalityBulkAssessmentPreviewProps {
  rows: BulkCriticalityPreviewRow[];
}

const CRITICALITY_LABELS: Record<string, string> = {
  low: 'Baja',
  medium: 'Media',
  high: 'Alta',
  critical: 'Crítica',
};

const criticalityVariant = (value: string | null) => {
  if (value === 'critical') return 'destructive' as const;
  if (value === 'high') return 'default' as const;
  return 'secondary' as const;
};

/** Per-row result of the SERVER-side dry run. The score column always comes
 * from preview_bulk_asset_criticality — never recomputed here. */
export function CriticalityBulkAssessmentPreview({ rows }: CriticalityBulkAssessmentPreviewProps) {
  const valid = rows.filter((row) => row.valid).length;
  const invalid = rows.length - valid;

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center gap-2">
        <Badge variant="outline">{rows.length} filas</Badge>
        <Badge variant="secondary">{valid} válidas</Badge>
        {invalid > 0 && <Badge variant="destructive">{invalid} inválidas</Badge>}
      </div>

      <div className="max-h-72 overflow-y-auto rounded-md border">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead className="w-16">Fila</TableHead>
              <TableHead>Activo</TableHead>
              <TableHead className="w-24">Estado</TableHead>
              <TableHead className="w-24">Score</TableHead>
              <TableHead className="w-28">Criticidad</TableHead>
              <TableHead>Errores</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.map((row) => (
              <TableRow key={`${row.rowNumber}-${row.assetId ?? 'sin-id'}`} className={row.valid ? '' : 'bg-destructive/5'}>
                <TableCell className="text-xs text-muted-foreground">{row.rowNumber}</TableCell>
                <TableCell className="text-sm">
                  <span className="font-medium">{row.assetCode || '—'}</span>
                  {row.assetName && <span className="ml-2 text-muted-foreground">{row.assetName}</span>}
                </TableCell>
                <TableCell>
                  <Badge variant={row.valid ? 'secondary' : 'destructive'}>{row.valid ? 'OK' : 'ERROR'}</Badge>
                </TableCell>
                <TableCell className="text-sm">{row.score ?? '—'}</TableCell>
                <TableCell>
                  {row.calculatedCriticality ? (
                    <Badge variant={criticalityVariant(row.calculatedCriticality)}>
                      {CRITICALITY_LABELS[row.calculatedCriticality] ?? row.calculatedCriticality}
                    </Badge>
                  ) : '—'}
                </TableCell>
                <TableCell className="text-xs text-muted-foreground">
                  {row.errors.length > 0 ? row.errors.join(' · ') : (row.warnings.join(' · ') || '—')}
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
    </div>
  );
}
