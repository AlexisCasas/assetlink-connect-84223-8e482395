import { useRef, useState, type FormEvent } from 'react';
import { useQuery } from '@tanstack/react-query';
import { MessageSquareText, RefreshCw } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { Button } from '@/components/ui/button';
import { Textarea } from '@/components/ui/textarea';
import { canFacilityManagerAddExternalFollowup } from '@/lib/facilityManagement';
import {
  addDelegatedExternalFollowup,
  fetchDelegatedExternalFollowups,
} from '@/lib/delegatedWorkOrderFollowups';
import type { FacilityManagementOperationalClient } from '@/types/facilityManagement';

const PAGE_SIZE = 20;
function formatNoteDate(raw: string): string {
  const d = new Date(raw);
  if (!Number.isFinite(d.getTime())) return 'Fecha no disponible';
  return new Intl.DateTimeFormat('es-PE', {
    dateStyle: 'medium', timeStyle: 'short',
  }).format(d);
}

/** D4 note panel: client-side FM coordination only. No provider materials,
 * work logs, operational note fields or client impersonation. */
export function DelegatedExternalFollowups({
  client, workOrderId,
}: {
  client: FacilityManagementOperationalClient;
  workOrderId: string;
}) {
  const { user, currentOrganization } = useAuth();
  const canWrite = canFacilityManagerAddExternalFollowup(client);
  const [page, setPage] = useState(0);
  const [body, setBody] = useState('');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState(false);
  const requestKey = useRef<string | null>(null);

  const query = useQuery({
    queryKey: [
      'fm-work-order-followups', user?.id, currentOrganization?.id,
      client.clientOrganizationId, client.relationshipId, workOrderId, page,
    ],
    queryFn: () => fetchDelegatedExternalFollowups(
      client.clientOrganizationId, client.relationshipId, workOrderId,
      PAGE_SIZE, page * PAGE_SIZE,
    ),
    enabled: !!user?.id,
    retry: false,
    staleTime: 0,
    gcTime: 0,
    refetchOnWindowFocus: 'always',
  });

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (saving || !canWrite) return;
    setError(null);
    setSuccess(false);
    const text = body.trim();
    if (text.length < 1 || text.length > 2000) {
      setError('La nota debe contener entre 1 y 2000 caracteres.');
      return;
    }
    // Keep the same intent UUID on retries; only change when body changes.
    if (!requestKey.current) requestKey.current = crypto.randomUUID();
    setSaving(true);
    try {
      await addDelegatedExternalFollowup(
        client.clientOrganizationId, client.relationshipId, workOrderId,
        text, requestKey.current,
      );
      setBody('');
      requestKey.current = null;
      setPage(0);
      setSuccess(true);
      await query.refetch();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'No se pudo registrar el seguimiento.');
    } finally {
      setSaving(false);
    }
  }

  const notes = query.data?.items ?? [];
  const total = query.data?.total ?? 0;

  return (
    <section className="space-y-3 rounded-md border p-4"
      aria-label="Seguimiento del cliente" data-testid="delegated-client-followups">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div>
          <h3 className="flex items-center gap-2 text-sm font-semibold">
            <MessageSquareText className="h-4 w-4" /> Seguimiento del cliente
          </h3>
          <p className="text-xs text-muted-foreground">
            Notas de coordinación del equipo Facility Manager asignado. No se comparten con el proveedor.
          </p>
        </div>
        <Button type="button" size="sm" variant="outline" disabled={query.isFetching}
          onClick={() => void query.refetch()}>
          <RefreshCw className="mr-2 h-4 w-4" /> Actualizar
        </Button>
      </div>

      {query.isLoading ? (
        <p role="status" className="text-sm text-muted-foreground">Cargando seguimiento autorizado…</p>
      ) : query.isError ? (
        <div role="alert" className="space-y-2">
          <p className="text-sm text-muted-foreground">
            El seguimiento aún no está disponible o ya no tienes acceso.
          </p>
          <Button type="button" size="sm" variant="outline" onClick={() => void query.refetch()}>
            Reintentar
          </Button>
        </div>
      ) : notes.length === 0 ? (
        <p className="text-sm text-muted-foreground">Aún no hay notas para esta orden y relación FM.</p>
      ) : (
        <ol className="space-y-3" aria-label="Notas de seguimiento">
          {notes.map((note) => (
            <li key={note.id} className="rounded-md border bg-muted/20 p-3">
              <div className="flex flex-wrap justify-between gap-2 text-xs text-muted-foreground">
                <span>{note.authorName}{note.authoredByMe ? ' · tú' : ''}</span>
                <time dateTime={note.createdAt}>{formatNoteDate(note.createdAt)}</time>
              </div>
              <p className="mt-2 whitespace-pre-wrap break-words text-sm">{note.body}</p>
            </li>
          ))}
        </ol>
      )}
      {query.isSuccess && total > PAGE_SIZE && (
        <div className="flex items-center justify-between gap-2">
          <p className="text-xs text-muted-foreground">
            {Math.min(page * PAGE_SIZE + 1, total)}–{Math.min((page + 1) * PAGE_SIZE, total)} de {total} notas
          </p>
          <div className="flex gap-2">
            <Button type="button" size="sm" variant="outline" disabled={page === 0 || query.isFetching}
              onClick={() => setPage(p => Math.max(0, p - 1))}>Anterior</Button>
            <Button type="button" size="sm" variant="outline"
              disabled={(page + 1) * PAGE_SIZE >= total || query.isFetching}
              onClick={() => setPage(p => p + 1)}>Siguiente</Button>
          </div>
        </div>
      )}

      {canWrite ? (
        <form className="space-y-2 border-t pt-3" onSubmit={(e) => void submit(e)}
          data-testid="delegated-client-followup-form">
          <label htmlFor="fm-work-order-followup" className="text-sm font-medium">
            Nueva nota de seguimiento
          </label>
          <Textarea id="fm-work-order-followup" rows={3} maxLength={2000}
            placeholder="Registra una coordinación del lado del cliente, sin datos privados del proveedor."
            value={body} disabled={saving}
            onChange={(event) => {
              setBody(event.target.value);
              requestKey.current = null;
              setSuccess(false);
            }} />
          <p className="text-xs text-muted-foreground">
            {body.length}/2000 caracteres. Las notas no editan la OT ni la bitácora operativa.
          </p>
          {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
          {success && <p role="status" className="text-sm text-green-700">Nota registrada correctamente.</p>}
          <Button type="submit" disabled={saving || body.trim().length === 0 || body.trim().length > 2000}>
            {saving ? 'Registrando…' : 'Registrar seguimiento'}
          </Button>
        </form>
      ) : (
        <p className="text-xs text-muted-foreground">
          El registro de notas requiere autorización de gestión para esta relación.
        </p>
      )}
    </section>
  );
}
