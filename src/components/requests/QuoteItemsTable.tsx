import type { ReactNode } from 'react';
import { Table, TableHead, TableHeader, TableRow } from '@/components/ui/table';

/**
 * Shared quote-line table shell.
 * - Editing mode preserves the existing live quote form and its input cells.
 * - Historical mode uses the same visual hierarchy, but its rows are read-only.
 * Keeping this a presentation-only component prevents any historical action
 * from triggering live quote calculations, saves, or status changes.
 */
interface QuoteItemsTableProps {
  children: ReactNode;
  mode: 'editing' | 'historical';
  currencyLabel?: string;
}

export function QuoteItemsTable({
  children,
  mode,
  currencyLabel = 'S/',
}: QuoteItemsTableProps) {
  const historical = mode === 'historical';
  return (
    <div className="overflow-x-auto rounded-lg border bg-card">
      <Table>
        <TableHeader className="bg-muted/70">
          <TableRow>
            <TableHead className={historical ? 'min-w-[240px] w-[45%]' : 'w-[45%]'}>Descripción</TableHead>
            <TableHead className={historical ? 'min-w-[80px] text-right' : 'w-[15%]'}>Cantidad</TableHead>
            <TableHead className={historical ? 'min-w-[75px]' : 'w-[15%]'}>Unidad</TableHead>
            {historical && <TableHead className="min-w-[125px] text-right">Precio unit. ({currencyLabel})</TableHead>}
            <TableHead className={historical ? 'min-w-[125px] text-right' : 'w-[20%]'}>
              {historical ? 'Parcial (' + currencyLabel + ')' : 'Precio Total (' + currencyLabel + ')'}
            </TableHead>
            {!historical && <TableHead className="w-[5%]" aria-label="Acciones" />}
          </TableRow>
        </TableHeader>
        {children}
      </Table>
    </div>
  );
}
