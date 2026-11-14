import { Badge } from '@/components/ui/badge';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { QuoteItemsTable } from '@/components/requests/QuoteItemsTable';
import type {
  CommercialQuoteBreakdown, CommercialQuoteCostComponent, CommercialQuoteLineItem, CommercialQuoteSection,
} from '@/lib/commercialQuoteHistory';

const SECTION_NAMES: Record<CommercialQuoteLineItem['section_kind'], string> = {
  service: '1. Listado de servicios',
  material: '2. Descripción de materiales y consumibles',
  equipment: '3. Equipos de apoyo',
  other: '4. Otras partidas',
};

const COST_ORDER: CommercialQuoteCostComponent['component_kind'][] = [
  'labor', 'materials', 'mobilization', 'overhead_profit', 'net_total', 'tax', 'gross_total', 'other', 
];

const formatQuantity = (amount: number | null): string =>
  amount === null ? '—' : new Intl.NumberFormat('es-PE', { maximumFractionDigits: 4 }).format(amount);

const formatMoney = (amount: number | null, currency: string): string =>
  amount === null ? '—' : new Intl.NumberFormat('es-PE', { style: 'currency', currency }).format(amount);

/**
 * Preserve original text order and every non-empty line. PDF extraction may
 * flatten columns in arbitrary order, so these lines are NEVER turned into
 * quantities, unit rates or assigned descriptions automatically.
 */
function sourceTextRows(sourceText: string): string[] {
  return sourceText
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);
}

function ReviewLabel({ status }: { status: string }) {
  return (
    <Badge variant={status === 'verified' ? 'secondary' : 'outline'} className="whitespace-nowrap">
      {status === 'verified' ? 'Verificado' : status === 'needs_review' ? 'Revisar' : 'Extraído · sin validar'}
    </Badge>
  );
}

function QuoteReadOnlySection({
  kind,
  lines,
  groupLabel,
}: {
  kind: CommercialQuoteLineItem['section_kind'];
  lines: CommercialQuoteLineItem[];
  groupLabel?: string;
}) {
  const rows = lines
    .filter((line) => line.section_kind === kind)
    .sort((a, b) => a.line_order - b.line_order);
  const allPartialsPresent = rows.length > 0 && rows.every((line) => line.line_total !== null);
  const subtotal = allPartialsPresent
    ? rows.reduce((sum, line) => sum + (line.line_total ?? 0), 0)
    : null;
  const currency = rows[0]?.currency_code ?? 'PEN';

  return (
    <section className="space-y-2 rounded-lg border bg-card p-3 sm:p-4" aria-label={SECTION_NAMES[kind]}>
      <div className="flex flex-wrap items-center justify-between gap-2 rounded-md bg-muted px-3 py-2">
        <h4 className="font-semibold">{SECTION_NAMES[kind]}</h4>
        <Badge variant="outline">{rows.length ? rows.length + ' partida(s)' : 'Pendiente de homologar'}</Badge>
      </div>
      <QuoteItemsTable mode="historical" currencyLabel={currency === 'PEN' ? 'S/' : currency}>
        <TableBody>
          {groupLabel && rows.length > 0 && (
            <TableRow className="bg-muted/40 font-semibold">
              <TableCell colSpan={4} className="whitespace-normal break-words">
                {groupLabel}
              </TableCell>
              <TableCell className="text-right tabular-nums">
                {formatMoney(subtotal, currency)}
              </TableCell>
            </TableRow>
          )}
          {rows.length === 0 ? (
            <TableRow>
              <TableCell colSpan={5} className="py-5 text-center text-muted-foreground">
                Aún no hay partidas estructuradas de esta sección. El PDF y su transcripción se conservan como referencia.
              </TableCell>
            </TableRow>
          ) : rows.map((line) => (
            <TableRow key={line.id}>
              <TableCell className="min-w-[240px] align-top">
                <div className="font-medium break-words">{line.description}</div>
                <div className="mt-1 flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
                  <span>PDF · pág. {line.source_page}</span>
                  <ReviewLabel status={line.review_status} />
                </div>
              </TableCell>
              <TableCell className="text-right tabular-nums">{formatQuantity(line.quantity)}</TableCell>
              <TableCell>{line.unit_label || '—'}</TableCell>
              <TableCell className="whitespace-nowrap text-right tabular-nums">{formatMoney(line.unit_price, line.currency_code)}</TableCell>
              <TableCell className="whitespace-nowrap text-right font-mono tabular-nums">{formatMoney(line.line_total, line.currency_code)}</TableCell>
            </TableRow>
          ))}
          {subtotal !== null && !groupLabel && (
            <TableRow className="bg-muted/30">
              <TableCell colSpan={4} className="text-right font-semibold">
                Suma de parciales del PDF (sin validar):
              </TableCell>
              <TableCell className="text-right font-semibold tabular-nums">
                {formatMoney(subtotal, currency)}
              </TableCell>
            </TableRow>
          )}
        </TableBody>
      </QuoteItemsTable>
    </section>
  );
}

function HistoricalCostTable({ components }: { components: CommercialQuoteCostComponent[] }) {
  const ordered = [...components].sort(
    (a, b) => COST_ORDER.indexOf(a.component_kind) - COST_ORDER.indexOf(b.component_kind),
  );

  return (
    <section className="space-y-2 rounded-lg border bg-card p-3 sm:p-4" aria-label="Resumen económico">
      <div className="rounded-md bg-muted px-3 py-2">
        <h4 className="font-semibold">Resumen económico del documento</h4>
      </div>
      <div className="overflow-x-auto rounded-lg border">
        <Table>
          <TableHeader className="bg-muted/70">
            <TableRow>
              <TableHead>Concepto registrado en PDF</TableHead>
              <TableHead className="text-right">Importe histórico</TableHead>
              <TableHead className="text-center">Página</TableHead>
              <TableHead>Revisión</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {ordered.length === 0 ? (
              <TableRow>
                <TableCell colSpan={4} className="py-5 text-center text-muted-foreground">
                  Resumen económico pendiente de estructurar.
                </TableCell>
              </TableRow>
            ) : ordered.map((component) => (
              <TableRow
                key={component.id}
                className={component.component_kind === 'net_total' || component.component_kind === 'gross_total' ? 'bg-muted/30 font-semibold' : ''}
              >
                <TableCell className="min-w-[220px]">{component.source_label}</TableCell>
                <TableCell className="whitespace-nowrap text-right tabular-nums">{formatMoney(component.amount, component.currency_code)}</TableCell>
                <TableCell className="text-center">{component.source_page ?? 'Por confirmar'}</TableCell>
                <TableCell><ReviewLabel status={component.review_status} /></TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
      <p className="text-xs text-muted-foreground">
        No se calcula ni presupone IGV o total con IGV si el documento no lo registra. Los importes históricos no son tarifas vigentes.
      </p>
    </section>
  );
}

const TYPE_LABELS: Record<string,string> = {
  service_scope: 'Alcance y trabajos incluidos',
  material_scope: 'Materiales y consumibles',
  labor: 'Mano de obra',
  equipment: 'Equipos y herramientas',
  additional_costs: 'Costos adicionales',
  technical: 'Aclaraciones técnicas',
  safety: 'Consideraciones de seguridad',
  management_delivery: 'Gestión y entrega',
  commercial_terms: 'Condiciones comerciales',
  economic_summary: 'Resumen económico',
  internal_costs: 'Estructura de costos internos',
  other: 'Otras condiciones',
};

function HistoricalQuoteSections({ sections }: { sections: CommercialQuoteSection[] }) {
  if (sections.length === 0) return null;
  return (
    <section className="space-y-2 rounded-lg border bg-card p-3 sm:p-4" aria-label="Otras secciones del documento">
      <div className="rounded-md bg-muted px-3 py-2">
        <h4 className="font-semibold">Aclaraciones técnicas, seguridad y condiciones</h4>
      </div>
      <p className="text-xs text-muted-foreground">
        Se conserva la redacción del documento. Una sección extraída no equivale a una partida económica
        validada; los precios y cantidades se homologan por separado.
      </p>
      <div className="overflow-x-auto rounded-lg border">
        <Table>
          <TableHeader className="bg-muted/70">
            <TableRow>
              <TableHead className="min-w-[170px]">Sección</TableHead>
              <TableHead className="min-w-[280px]">Detalle del documento</TableHead>
              <TableHead className="min-w-[100px]">Procedencia</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {sections.map((section) => (
              <TableRow key={section.id}>
                <TableCell className="align-top">
                  <p className="font-medium">{TYPE_LABELS[section.section_kind] ?? 'Sección complementaria'}</p>
                  <p className="mt-1 text-xs text-muted-foreground">{section.original_heading}</p>
                </TableCell>
                <TableCell className="align-top">
                  <p className="whitespace-pre-wrap break-words text-sm">{section.section_text}</p>
                </TableCell>
                <TableCell className="align-top">
                  <p className="text-xs text-muted-foreground">
                    {section.source_page ? 'PDF · pág. ' + section.source_page : 'Página por confirmar'}
                  </p>
                  <div className="mt-1"><ReviewLabel status={section.review_status} /></div>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
    </section>
  );
}

function SourceTextTable({ text }: { text: string }) {
  const lines = sourceTextRows(text);
  const visible = lines.slice(0, 300);
  return (
    <details className="rounded-lg border bg-card p-3 sm:p-4">
      <summary className="cursor-pointer font-semibold">
        Transcripción tabular del PDF · {lines.length} líneas (no homologadas)
      </summary>
      <p className="my-3 text-xs text-muted-foreground">
        Estas filas respetan el orden devuelto por el extractor, que puede diferir del orden visual del PDF.
        Cada número o descripción se mantiene independiente: no se le atribuye una cantidad ni un precio automáticamente.
      </p>
      <div className="max-h-72 overflow-auto rounded-md border">
        <Table>
          <TableHeader className="sticky top-0 bg-muted">
            <TableRow>
              <TableHead className="w-16 text-right">Línea</TableHead>
              <TableHead>Contenido extraído (sin clasificar)</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {visible.map((line, index) => (
              <TableRow key={index}>
                <TableCell className="text-right text-xs tabular-nums text-muted-foreground">{index + 1}</TableCell>
                <TableCell className="whitespace-pre-wrap break-words font-mono text-xs">{line}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
      {lines.length > visible.length && (
        <p className="mt-2 text-xs text-muted-foreground">
          Se muestran las primeras {visible.length} líneas. El PDF de origen conserva el documento completo.
        </p>
      )}
    </details>
  );
}

export function HistoricalQuoteTables({ breakdown }: { breakdown: CommercialQuoteBreakdown }) {
  const hasStructuredLines = breakdown.lines.length > 0;
  const hasServiceLines = breakdown.lines.some((line) => line.section_kind === 'service');
  const hasMaterialLines = breakdown.lines.some((line) => line.section_kind === 'material');
  const serviceGroup = breakdown.sections.find((section) => section.section_kind === 'service_scope');
  const groupLabel = hasServiceLines ? serviceGroup?.section_text.split('\n')[0]?.trim() : undefined;
  // The PDF proposal heading and economic-summary labels are represented by
  // the structured services/summary tables. Hide only these duplicate narrative
  // copies, never the independent technical or contractual sections.
  const supplementarySections = breakdown.sections.filter((section) =>
    !(section.section_kind === 'service_scope' && hasServiceLines)
    && !(section.section_kind === 'economic_summary' && breakdown.components.length > 0)
  );
  const hasAdditionalKinds = breakdown.lines.some(
    (line) => line.section_kind === 'equipment' || line.section_kind === 'other',
  );
  return (
    <div className="space-y-4" aria-label="Desglose tabular histórico">
      {!hasStructuredLines && (
        <p className="rounded-md border p-3 text-sm text-muted-foreground">
          El PDF ya está conservado, pero sus columnas todavía necesitan homologación.
          Se presenta la misma tabla de cotización sin completar unidades, cantidades o tarifas no comprobadas.
        </p>
      )}
      <QuoteReadOnlySection kind="service" lines={breakdown.lines} groupLabel={groupLabel} />
      {(hasMaterialLines || !hasServiceLines) && (
        <QuoteReadOnlySection kind="material" lines={breakdown.lines} />
      )}
      {hasServiceLines && !hasMaterialLines && (
        <p className="text-xs text-muted-foreground">
          Este documento no contiene un listado independiente de materiales y consumibles.
          El suministro incluido se conserva dentro de las partidas de servicios.
        </p>
      )}
      {hasAdditionalKinds && (
        <>
          <QuoteReadOnlySection kind="equipment" lines={breakdown.lines} />
          <QuoteReadOnlySection kind="other" lines={breakdown.lines} />
        </>
      )}
      <HistoricalCostTable components={breakdown.components} />
      <HistoricalQuoteSections sections={supplementarySections} />
      {breakdown.source && <SourceTextTable text={breakdown.source.source_text} />}
      {!breakdown.source && !hasStructuredLines && breakdown.components.length === 0 && (
        <p className="text-xs text-muted-foreground">La extracción documental aún no está disponible para este registro.</p>
      )}
    </div>
  );
}
