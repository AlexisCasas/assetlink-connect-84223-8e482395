import { useEffect, useMemo, useRef, useState } from 'react';
import { format } from 'date-fns';
import { es } from 'date-fns/locale';
import { AlertTriangle, Loader2, Plus } from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { useToast } from '@/hooks/use-toast';
import { useMaintenanceNotices } from '@/hooks/useMaintenanceNotices';
import { useDirectMaintenanceNoticeScope, type MaintenanceNoticeScope } from '@/hooks/useMaintenanceNoticeScope';
import { cn } from '@/lib/utils';
import type { BacklogFilterState, MaintenanceNotice } from '@/types/maintenanceNotice';
import {
  MAINTENANCE_NOTICE_PRIORITY_COLORS,
  MAINTENANCE_NOTICE_PRIORITY_LABELS,
  MAINTENANCE_NOTICE_SOURCE_LABELS,
  MAINTENANCE_NOTICE_STATUS_COLORS,
  MAINTENANCE_NOTICE_STATUS_LABELS,
} from '@/types/maintenanceNotice';
import { BacklogFilters } from './BacklogFilters';
import { MaintenanceNoticeDetailDialog } from './MaintenanceNoticeDetailDialog';
import { MaintenanceNoticeDialog } from './MaintenanceNoticeDialog';
import { MaintenanceNoticePlanningDialog } from './MaintenanceNoticePlanningDialog';
import { MaintenanceNoticeTriageDialog } from './MaintenanceNoticeTriageDialog';

interface BacklogViewProps {
  /** Deep link #backlog?notice=<uuid>&org=<uuid>. El hash solo dice QUÉ
   * abrir: si el aviso no pertenece a la organización activa, la RLS no lo
   * devuelve y aquí simplemente no aparece. */
  focusNoticeId?: string;
  /** Omitted: direct mode (the active client organization, historic rules).
   * Delegated Facility Manager mode passes the operated client's scope. */
  scope?: MaintenanceNoticeScope;
}

const DEFAULT_FILTERS: BacklogFilterState = {
  status: 'pending',
  priority: 'all',
  branchId: 'all',
  source: 'all',
  search: '',
};

const normalize = (value: string) =>
  value.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');

export function BacklogView({ focusNoticeId, scope: explicitScope }: BacklogViewProps) {
  const directScope = useDirectMaintenanceNoticeScope();
  const scope = explicitScope ?? directScope;
  const { toast } = useToast();
  const {
    notices, loading, error, createNotice, triageNotice, dismissNotice, convertNotice,
  } = useMaintenanceNotices(scope.canView ? scope.organizationId : null);

  const [filters, setFilters] = useState<BacklogFilterState>(DEFAULT_FILTERS);
  const [showCreate, setShowCreate] = useState(false);
  const [detailNotice, setDetailNotice] = useState<MaintenanceNotice | null>(null);
  const [triageNoticeTarget, setTriageNoticeTarget] = useState<MaintenanceNotice | null>(null);
  const [planningNotice, setPlanningNotice] = useState<MaintenanceNotice | null>(null);
  const handledFocusRef = useRef<string | null>(null);

  // Mismo criterio que las RPC: reportar es amplio, gestionar no. El backend
  // vuelve a validarlo — esto solo evita ofrecer un botón que fallaría.
  const { canReport, canManage } = scope;

  // Deep link: abre el detalle del aviso una sola vez, cuando ya cargó.
  useEffect(() => {
    if (!focusNoticeId || loading) return;
    if (handledFocusRef.current === focusNoticeId) return;
    handledFocusRef.current = focusNoticeId;

    const target = notices.find((notice) => notice.id === focusNoticeId);
    if (target) {
      setDetailNotice(target);
      return;
    }
    toast({
      title: 'No se pudo abrir el aviso',
      description: 'El aviso no existe o no pertenece a la organización activa.',
      variant: 'destructive',
    });
  }, [focusNoticeId, loading, notices, toast]);

  // Mantiene sincronizado el aviso abierto tras revisar/descartar/convertir,
  // sin cerrar el diálogo.
  useEffect(() => {
    setDetailNotice((current) => (current ? notices.find((notice) => notice.id === current.id) ?? null : null));
  }, [notices]);

  const branches = useMemo(() => {
    const map = new Map<string, string>();
    notices.forEach((notice) => {
      if (notice.branchIdSnapshot && notice.branchNameSnapshot) {
        map.set(notice.branchIdSnapshot, notice.branchNameSnapshot);
      }
    });
    return Array.from(map, ([id, name]) => ({ id, name })).sort((a, b) => a.name.localeCompare(b.name));
  }, [notices]);

  const visibleNotices = useMemo(() => {
    const search = normalize(filters.search.trim());
    return notices.filter((notice) => {
      if (filters.status === 'pending') {
        if (notice.status !== 'open' && notice.status !== 'triaged') return false;
      } else if (filters.status !== 'all' && notice.status !== filters.status) {
        return false;
      }
      if (filters.priority !== 'all' && notice.priority !== filters.priority) return false;
      if (filters.branchId !== 'all' && notice.branchIdSnapshot !== filters.branchId) return false;
      if (filters.source !== 'all' && notice.sourceType !== filters.source) return false;
      if (search) {
        const haystack = normalize([
          notice.noticeNumber, notice.title, notice.description,
          notice.assetNameSnapshot ?? '', notice.assetCodeSnapshot ?? '', notice.assetPathSnapshot ?? '',
        ].join(' '));
        if (!haystack.includes(search)) return false;
      }
      return true;
    });
  }, [notices, filters]);

  const pendingCount = useMemo(
    () => notices.filter((notice) => notice.status === 'open' || notice.status === 'triaged').length,
    [notices],
  );

  if (!scope.canView) {
    // Defensa ante un #backlog directo: el backlog es de quien opera los
    // activos. El backend rechaza igual, esto solo evita una pantalla vacía
    // sin explicación.
    return (
      <div className="flex h-full items-center justify-center p-6">
        <p className="text-sm text-muted-foreground">{scope.unavailableReason}</p>
      </div>
    );
  }

  return (
    <div className="space-y-6 p-6">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="flex items-center gap-2 text-2xl font-semibold">
            <AlertTriangle className="h-6 w-6 text-amber-500" />
            Backlog de mantenimiento
          </h1>
          <p className="text-sm text-muted-foreground">
            Avisos de avería reportados. Un aviso no es una solicitud ni una orden de trabajo: primero se
            revisa y luego se decide si se convierte en solicitud o se descarta.
          </p>
        </div>
        {canReport && (
          <Button onClick={() => setShowCreate(true)}>
            <Plus className="mr-2 h-4 w-4" />
            Nuevo aviso
          </Button>
        )}
      </div>

      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-base">
            {pendingCount} {pendingCount === 1 ? 'aviso pendiente' : 'avisos pendientes'}
            <span className="ml-2 text-sm font-normal text-muted-foreground">
              de {notices.length} en total
            </span>
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <BacklogFilters value={filters} onChange={setFilters} branches={branches} />

          {error && <p className="text-sm text-destructive">{error}</p>}

          {loading ? (
            <div className="flex items-center justify-center py-12 text-muted-foreground">
              <Loader2 className="mr-2 h-5 w-5 animate-spin" />
              Cargando avisos…
            </div>
          ) : visibleNotices.length === 0 ? (
            <p className="py-12 text-center text-sm text-muted-foreground">
              {notices.length === 0
                ? 'Todavía no hay avisos de avería registrados.'
                : 'Ningún aviso coincide con los filtros aplicados.'}
            </p>
          ) : (
            <div className="overflow-x-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>N°</TableHead>
                    <TableHead>Aviso</TableHead>
                    <TableHead>Activo</TableHead>
                    <TableHead>Sede</TableHead>
                    <TableHead>Prioridad</TableHead>
                    <TableHead>Estado</TableHead>
                    <TableHead>Origen</TableHead>
                    <TableHead>Reportado</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {visibleNotices.map((notice) => (
                    <TableRow
                      key={notice.id}
                      className={cn('cursor-pointer', notice.id === focusNoticeId && 'bg-primary/5')}
                      onClick={() => setDetailNotice(notice)}
                    >
                      <TableCell className="font-mono text-xs">{notice.noticeNumber}</TableCell>
                      <TableCell className="max-w-[260px]">
                        <p className="truncate font-medium">{notice.title}</p>
                        <p className="truncate text-xs text-muted-foreground">{notice.description}</p>
                      </TableCell>
                      <TableCell className="max-w-[200px]">
                        <p className="truncate">{notice.assetNameSnapshot ?? '—'}</p>
                        {notice.assetCodeSnapshot && (
                          <p className="truncate text-xs text-muted-foreground">{notice.assetCodeSnapshot}</p>
                        )}
                      </TableCell>
                      <TableCell>{notice.branchNameSnapshot ?? '—'}</TableCell>
                      <TableCell>
                        <Badge variant="outline" className={MAINTENANCE_NOTICE_PRIORITY_COLORS[notice.priority]}>
                          {MAINTENANCE_NOTICE_PRIORITY_LABELS[notice.priority]}
                        </Badge>
                      </TableCell>
                      <TableCell>
                        <Badge variant="outline" className={MAINTENANCE_NOTICE_STATUS_COLORS[notice.status]}>
                          {MAINTENANCE_NOTICE_STATUS_LABELS[notice.status]}
                        </Badge>
                      </TableCell>
                      <TableCell className="text-xs text-muted-foreground">
                        {MAINTENANCE_NOTICE_SOURCE_LABELS[notice.sourceType]}
                      </TableCell>
                      <TableCell className="whitespace-nowrap text-xs text-muted-foreground">
                        {format(new Date(notice.reportedAt), 'd MMM yyyy', { locale: es })}
                        <br />
                        {notice.reportedByName ?? '—'}
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          )}
        </CardContent>
      </Card>

      <MaintenanceNoticeDialog
        open={showCreate}
        onOpenChange={setShowCreate}
        onCreate={createNotice}
        assetDirectoryClientId={scope.mode === 'facility_manager' ? scope.assetDirectoryClientId : null}
      />

      <MaintenanceNoticeDetailDialog
        open={!!detailNotice}
        onOpenChange={(next) => { if (!next) setDetailNotice(null); }}
        notice={detailNotice}
        canManage={canManage}
        canConvertToRequest={scope.canConvertToRequest}
        showCriticality={scope.canViewCriticality}
        onTriage={() => { setTriageNoticeTarget(detailNotice); setDetailNotice(null); }}
        onPlan={() => { setPlanningNotice(detailNotice); setDetailNotice(null); }}
        onDismiss={dismissNotice}
      />

      <MaintenanceNoticeTriageDialog
        open={!!triageNoticeTarget}
        onOpenChange={(next) => { if (!next) setTriageNoticeTarget(null); }}
        notice={triageNoticeTarget}
        organizationId={scope.canChooseResponsible ? scope.organizationId : null}
        canChooseResponsible={scope.canChooseResponsible}
        onTriage={triageNotice}
      />

      {scope.canConvertToRequest && planningNotice && (
        <MaintenanceNoticePlanningDialog
          notice={planningNotice}
          onClose={() => setPlanningNotice(null)}
          onConvert={convertNotice}
        />
      )}
    </div>
  );
}
