import { Fragment } from 'react';
import { Card, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table';
import {
  ArrowUpDown,
  ArrowUp,
  ArrowDown,
  GripVertical,
  ChevronDown,
  ChevronRight,
  Eye,
  Pencil,
  MessageSquare,
  DollarSign,
  Trash2,
  Package,
} from 'lucide-react';
import { format } from 'date-fns';
import { es } from 'date-fns/locale';
import { Request } from '@/types/request';
import type { Asset } from '@/types/asset';
import { ServiceTypeBadge, StatusBadge, QuotesProgressBadge } from './StatusBadge';

export type ColumnKey =
  | 'requestNumber'
  | 'title'
  | 'serviceType'
  | 'status'
  | 'branch'
  | 'asset'
  | 'createdAt'
  | 'store'
  | 'createdBy'
  | 'deadline'
  | 'quotesProgress'
  | 'actions';

export type SortKey = Exclude<ColumnKey, 'actions' | 'title' | 'asset'>;

export const COLUMN_LABELS: Record<ColumnKey, string> = {
  requestNumber: 'Nro. Solicitud',
  title: 'Título',
  serviceType: 'Tipo de Servicio',
  status: 'Estado',
  branch: 'Sede',
  asset: 'Activo asociado',
  createdAt: 'Fecha de Registro',
  store: 'Sucursal',
  createdBy: 'Usuario',
  deadline: 'Fecha Entrega Cotizaciones',
  quotesProgress: 'Cotizaciones',
  actions: 'Acciones',
};

export const DEFAULT_COLUMN_ORDER: ColumnKey[] = [
  'requestNumber', 'title', 'serviceType', 'status', 'branch', 'asset',
  'createdAt', 'store', 'createdBy', 'deadline', 'quotesProgress', 'actions',
];

interface OrderTableProps {
  requests: Request[];
  quoteCounts: Record<string, number>;
  assetsById: Map<string, Asset>;
  assetPaths: Map<string, string>;
  expandedRequestId: string | null;
  expandedDetails: any[];
  columnOrder: ColumnKey[];
  visibleColumns: Record<ColumnKey, boolean>;
  sortKey: SortKey | null;
  sortOrder: 'asc' | 'desc';
  draggedColumn: ColumnKey | null;
  dragOverColumn: ColumnKey | null;
  onSort: (key: SortKey) => void;
  onTogglePreview: (id: string) => void;
  onView: (r: Request) => void;
  onEdit: (r: Request) => void;
  onOpenChat: (r: Request) => void;
  onOpenQuotes: (r: Request) => void;
  onDelete: (id: string) => void;
  onDragStart: (col: ColumnKey) => void;
  onDragOver: (e: React.DragEvent, col: ColumnKey) => void;
  onDrop: (col: ColumnKey) => void;
  onDragEnd: () => void;
}

export const OrderTable = ({
  requests,
  quoteCounts,
  assetsById,
  assetPaths,
  expandedRequestId,
  expandedDetails,
  columnOrder,
  visibleColumns,
  sortKey,
  sortOrder,
  dragOverColumn,
  onSort,
  onTogglePreview,
  onView,
  onEdit,
  onOpenChat,
  onOpenQuotes,
  onDelete,
  onDragStart,
  onDragOver,
  onDrop,
  onDragEnd,
}: OrderTableProps) => {
  const visibleOrdered = columnOrder.filter((c) => visibleColumns[c]);

  const renderSortIcon = (key: SortKey) => {
    if (sortKey !== key) return <ArrowUpDown className="ml-1 h-3 w-3 opacity-50" />;
    return sortOrder === 'asc'
      ? <ArrowUp className="ml-1 h-3 w-3" />
      : <ArrowDown className="ml-1 h-3 w-3" />;
  };

  const renderCell = (request: Request, column: ColumnKey) => {
    switch (column) {
      case 'requestNumber':
        return <TableCell key={column} className="font-medium">{request.requestNumber}</TableCell>;
      case 'title':
        return (
          <TableCell key={column} className="font-medium max-w-[260px] truncate" title={request.title || ''}>
            {request.title || <span className="text-muted-foreground italic">Sin título</span>}
          </TableCell>
        );
      case 'serviceType':
        return <TableCell key={column}><ServiceTypeBadge type={request.serviceType} /></TableCell>;
      case 'status':
        return <TableCell key={column}><StatusBadge status={request.status} /></TableCell>;
      case 'branch':
        return <TableCell key={column}>{request.branch || request.clientBranch || '-'}</TableCell>;
      case 'asset': {
        if (!request.assetId) {
          return <TableCell key={column} className="text-muted-foreground">{request.asset || '-'}</TableCell>;
        }
        const liveAsset = assetsById.get(request.assetId);
        const path = assetPaths.get(request.assetId);
        return (
          <TableCell key={column} className="max-w-[220px]">
            <div className="flex items-center gap-1.5" title={path || undefined}>
              <Package className="h-3.5 w-3.5 shrink-0 text-muted-foreground" />
              <div className="min-w-0">
                <p className="truncate text-sm">{liveAsset?.name || request.asset || '-'}</p>
                {path && <p className="truncate text-xs text-muted-foreground">{path}</p>}
              </div>
            </div>
          </TableCell>
        );
      }
      case 'createdAt':
        return (
          <TableCell key={column}>
            {request.createdAt ? format(new Date(request.createdAt), 'dd/MM/yyyy', { locale: es }) : '-'}
          </TableCell>
        );
      case 'store':
        return <TableCell key={column}>{request.store || '-'}</TableCell>;
      case 'createdBy':
        return <TableCell key={column}>{request.createdBy}</TableCell>;
      case 'deadline':
        return (
          <TableCell key={column}>
            {request.deadline ? format(new Date(request.deadline), 'dd/MM/yyyy', { locale: es }) : '-'}
          </TableCell>
        );
      case 'quotesProgress': {
        const received = quoteCounts[request.id] || 0;
        const minRequired = request.minQuotes ?? 3;
        return (
          <TableCell key={column}>
            <QuotesProgressBadge received={received} minRequired={minRequired} />
          </TableCell>
        );
      }
      case 'actions':
        return (
          <TableCell key={column} className="text-right">
            <div className="flex justify-end gap-1">
              <Button variant="ghost" size="icon" onClick={() => onView(request)} title="Ver solicitud">
                <Eye className="h-4 w-4" />
              </Button>
              <Button variant="ghost" size="icon" onClick={() => onEdit(request)} title="Editar solicitud">
                <Pencil className="h-4 w-4" />
              </Button>
              <Button variant="ghost" size="icon" onClick={() => onOpenChat(request)} title="Foro de Preguntas">
                <MessageSquare className="h-4 w-4" />
              </Button>
              <Button variant="ghost" size="icon" onClick={() => onOpenQuotes(request)} title="Ver cotizaciones">
                <DollarSign className="h-4 w-4" />
              </Button>
              <Button
                variant="ghost"
                size="icon"
                onClick={() => onDelete(request.id)}
                title="Eliminar solicitud"
                className="text-destructive hover:text-destructive"
              >
                <Trash2 className="h-4 w-4" />
              </Button>
            </div>
          </TableCell>
        );
      default:
        return null;
    }
  };

  return (
    <Card>
      <CardContent className="p-0">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead className="w-10 px-2"></TableHead>
              {visibleOrdered.map((column) => {
                const isActions = column === 'actions';
                const isSortable = column !== 'actions' && column !== 'title';
                return (
                  <TableHead
                    key={column}
                    className={`${isActions ? 'text-right' : 'cursor-pointer hover:bg-muted/50'} select-none transition-colors ${dragOverColumn === column ? 'bg-primary/10' : ''}`}
                    draggable
                    onDragStart={() => onDragStart(column)}
                    onDragOver={(e) => onDragOver(e, column)}
                    onDrop={() => onDrop(column)}
                    onDragEnd={onDragEnd}
                    onClick={isSortable ? () => onSort(column as SortKey) : undefined}
                  >
                    <div className={`flex items-center gap-1 ${isActions ? 'justify-end' : ''}`}>
                      <GripVertical className="h-3 w-3 text-muted-foreground cursor-grab" />
                      {COLUMN_LABELS[column]}
                      {isSortable && renderSortIcon(column as SortKey)}
                    </div>
                  </TableHead>
                );
              })}
            </TableRow>
          </TableHeader>
          <TableBody>
            {requests.map((request) => (
              <Fragment key={request.id}>
                <TableRow key={request.id}>
                  <TableCell className="w-10 px-2">
                    <Button
                      variant="ghost"
                      size="icon"
                      className="h-6 w-6"
                      onClick={() => onTogglePreview(request.id)}
                      title="Previsualizar detalles"
                    >
                      {expandedRequestId === request.id
                        ? <ChevronDown className="h-4 w-4" />
                        : <ChevronRight className="h-4 w-4" />}
                    </Button>
                  </TableCell>
                  {visibleOrdered.map((column) => renderCell(request, column))}
                </TableRow>
                {expandedRequestId === request.id && (
                  <TableRow className="bg-muted/30">
                    <TableCell colSpan={visibleOrdered.length + 1} className="p-0">
                      <div className="overflow-x-auto">
                        <Table className="text-sm">
                          <TableHeader>
                            <TableRow className="bg-muted/50">
                              <TableHead className="min-w-[220px]">Actividad / Partida</TableHead>
                              <TableHead className="min-w-[80px]">Cantidad</TableHead>
                              <TableHead className="min-w-[80px]">U.M</TableHead>
                            </TableRow>
                          </TableHeader>
                          <TableBody>
                            {expandedDetails.length > 0 ? (
                              expandedDetails.map((detail) => (
                                <TableRow key={detail.id ?? `${request.id}-${detail.equipment ?? ''}-${detail.sub_equipment ?? ''}-${detail.area ?? ''}-${detail.activities ?? ''}`}>
                                  <TableCell>
                                    {detail.activities || '-'}
                                    {(detail.equipment || detail.area) && (
                                      <p className="mt-0.5 text-xs text-muted-foreground">
                                        {[detail.equipment, detail.area].filter(Boolean).join(' · ')}
                                      </p>
                                    )}
                                  </TableCell>
                                  <TableCell>{detail.quantity ?? '-'}</TableCell>
                                  <TableCell>{detail.unit_measure || '-'}</TableCell>
                                </TableRow>
                              ))
                            ) : (
                              <TableRow>
                                <TableCell colSpan={3} className="text-center text-muted-foreground py-4">
                                  Sin detalles registrados
                                </TableCell>
                              </TableRow>
                            )}
                          </TableBody>
                        </Table>
                      </div>
                    </TableCell>
                  </TableRow>
                )}
              </Fragment>
            ))}
          </TableBody>
        </Table>
      </CardContent>
    </Card>
  );
};
