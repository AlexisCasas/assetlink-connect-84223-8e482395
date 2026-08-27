/** Labels for organization_notifications.type. Includes the pre-existing
 * quote_* types (still emitted by notify_quote_status_change, untouched by
 * this phase) alongside the operational ones. inspection_due_soon_future/
 * inspection_overdue_future were reserved placeholders until the generic
 * checklist/inspection engine (see docs/GENERIC_CHECKLISTS_INSPECTIONS.md)
 * — now actually emitted by generate_inspection_due_notifications(). */
export const NOTIFICATION_TYPE_LABELS: Record<string, string> = {
  internal_request_created: 'Nueva solicitud interna',
  work_order_created: 'Nueva orden de trabajo',
  technician_assigned: 'Técnico asignado',
  activity_assigned: 'Actividad asignada',
  work_order_due_soon: 'OT próxima a vencer',
  work_order_overdue: 'OT vencida',
  work_completed: 'Trabajo completado',
  inspection_due_soon_future: 'Inspección próxima a vencer',
  inspection_overdue_future: 'Inspección vencida',
  quote_submitted: 'Cotización recibida',
  quote_approved: 'Cotización aprobada',
  quote_rejected: 'Cotización no seleccionada',
};

const OPERATIONAL_NOTIFICATION_TYPES = new Set([
  'internal_request_created',
  'work_order_created',
  'technician_assigned',
  'activity_assigned',
  'work_order_due_soon',
  'work_order_overdue',
  'work_completed',
  'inspection_due_soon_future',
  'inspection_overdue_future',
]);

export const isOperationalNotificationType = (type: string) => OPERATIONAL_NOTIFICATION_TYPES.has(type);

export const NOTIFICATION_PRIORITY_LABELS: Record<string, string> = {
  low: 'Baja',
  medium: 'Media',
  high: 'Alta',
  urgent: 'Urgente',
};

export const NOTIFICATION_PRIORITY_COLORS: Record<string, string> = {
  low: 'bg-slate-500/10 text-slate-600 border-slate-500/20',
  medium: 'bg-blue-500/10 text-blue-600 border-blue-500/20',
  high: 'bg-orange-500/10 text-orange-600 border-orange-500/20',
  urgent: 'bg-red-500/10 text-red-600 border-red-500/20',
};

/** Short textual reference to the OT/Solicitud/Actividad a notification is
 * about — link-style but text-only for now, no routing wired up yet. */
export const notificationEntityReference = (entityType: string | null, metadata: unknown): string | null => {
  if (!entityType) return null;
  const meta = (metadata ?? {}) as Record<string, unknown>;
  switch (entityType) {
    case 'work_order':
      return typeof meta.work_order_number === 'string' ? `OT: ${meta.work_order_number}` : 'Orden de trabajo';
    case 'request':
      return typeof meta.request_number === 'string' ? `Solicitud: ${meta.request_number}` : 'Solicitud';
    case 'activity':
      return typeof meta.work_order_number === 'string' ? `Actividad — OT: ${meta.work_order_number}` : 'Actividad';
    case 'quote':
      return 'Cotización';
    case 'inspection_plan': {
      // metadata shape from generate_inspection_due_notifications() — see
      // docs/INSPECTION_SCHEDULING_ALERTS.md. plan_title replaced the
      // earlier phase's `title` key when alert rules became configurable.
      const planTitle = typeof meta.plan_title === 'string' ? meta.plan_title : null;
      if (!planTitle) return 'Plan de inspección';
      if (meta.alert_type === 'overdue') return `Inspección vencida: ${planTitle}`;
      if (meta.alert_type === 'before_due') {
        const daysBefore = typeof meta.days_before === 'number' ? `${meta.days_before} días antes` : 'próxima a vencer';
        return `Inspección: ${planTitle} · ${daysBefore}`;
      }
      return `Inspección: ${planTitle}`;
    }
    default:
      return null;
  }
};
