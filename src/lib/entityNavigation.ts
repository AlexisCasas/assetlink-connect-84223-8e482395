import { supabase } from '@/integrations/supabase/client';
import type { OrganizationNotification } from '@/hooks/useOrganizationNotifications';
import { isValidUuid } from '@/lib/providerHelpers';

/** Single source of truth for Dashboard's hash-routed views — Dashboard.tsx
 * imports this instead of declaring its own union, so a view can never be
 * added to one list and forgotten in the other. */
export type DashboardView =
  | 'dashboard'
  | 'assets'
  | 'requests'
  | 'drafts'
  | 'public-requests'
  | 'profile'
  | 'notifications'
  | 'approved-providers'
  | 'branches'
  | 'work-orders'
  | 'my-work-orders'
  | 'inventory'
  | 'efficiency'
  | 'criticality'
  | 'inspections'
  | 'preventive-maintenance'
  | 'backlog'
  | 'contact'
  | 'admin'
  | 'users'
  | 'facility-management';

export const ALL_DASHBOARD_VIEWS: DashboardView[] = [
  'dashboard', 'assets', 'requests', 'drafts', 'public-requests', 'profile', 'notifications',
  'approved-providers', 'branches', 'work-orders', 'my-work-orders', 'inventory', 'efficiency',
  'criticality', 'inspections', 'preventive-maintenance', 'backlog', 'contact', 'admin', 'users',
  'facility-management',
];

export interface EntityNavigationTarget {
  view: DashboardView;
  organizationId?: string;
  requestId?: string;
  quoteId?: string;
  workOrderId?: string;
  activityId?: string;
  inspectionPlanId?: string;
  inspectionRunId?: string;
  noticeId?: string;
  preventivePlanId?: string;
  preventiveOccurrenceId?: string;
  preventiveAssetId?: string;
  /** Opens an asset's own detail sheet in #assets (QR / "abrir activo" deep
   * links). Deliberately a DIFFERENT query key ("assetId") from
   * preventiveAssetId ("asset"): that one means "create a plan for this
   * asset" in #preventive-maintenance, this one means "open this asset's
   * sheet" in #assets. Never conflate the two. */
  assetId?: string;
  /** Facility Manager delegated mode (#assets / #criticality): the client
   * organization being operated. VISUAL CONTEXT ONLY — it is validated
   * against get_my_facility_management_clients() before any query, and RLS/
   * RPCs re-check every access. Never an authorization input. */
  managedClientId?: string;
}

/** What parseEntityHash extracts from window.location.hash: a logical view
 * (or null if the pathname segment isn't a known view) plus whichever
 * entity params were present in the query string. Every id here is a UUID
 * or undefined — never a name, correlativo, or title. */
export type ParsedEntityHash = Omit<EntityNavigationTarget, 'view'> & { view: DashboardView | null };

const QUERY_KEYS = {
  organizationId: 'org',
  requestId: 'request',
  quoteId: 'quote',
  workOrderId: 'workOrder',
  activityId: 'activity',
  inspectionPlanId: 'plan',
  inspectionRunId: 'run',
  noticeId: 'notice',
  preventivePlanId: 'plan',
  preventiveOccurrenceId: 'occurrence',
  preventiveAssetId: 'asset',
  assetId: 'assetId',
  managedClientId: 'managedClient',
} as const;

/**
 * Canonical hash format: `#<view>` or `#<view>?<key>=<uuid>&<key>=<uuid>...`.
 * Examples: `#requests?request=<uuid>`, `#work-orders?workOrder=<uuid>&activity=<uuid>`.
 * Never encodes names/correlativos/titles — only the view segment and UUIDs.
 */
export function buildEntityHash(target: EntityNavigationTarget): string {
  const params = new URLSearchParams();
  (Object.keys(QUERY_KEYS) as (keyof typeof QUERY_KEYS)[]).forEach((key) => {
    const value = target[key];
    if (value) params.set(QUERY_KEYS[key], value);
  });
  const query = params.toString();
  return `#${target.view}${query ? `?${query}` : ''}`;
}

/**
 * Inverse of buildEntityHash. Splits the hash into its pathname-like view
 * segment and its query params, instead of testing the whole string against
 * the view list (that whole-string test is exactly why
 * `#work-orders?workOrder=<uuid>` used to be silently ignored).
 */
export function parseEntityHash(hash: string): ParsedEntityHash {
  const raw = hash.startsWith('#') ? hash.slice(1) : hash;
  const [pathname = '', queryString = ''] = raw.split('?');
  const view = (ALL_DASHBOARD_VIEWS as string[]).includes(pathname) ? (pathname as DashboardView) : null;
  const params = new URLSearchParams(queryString);

  const result: ParsedEntityHash = { view };
  (Object.keys(QUERY_KEYS) as (keyof typeof QUERY_KEYS)[]).forEach((key) => {
    const value = params.get(QUERY_KEYS[key]);
    if (value) result[key] = value;
  });
  return result;
}

export type SafeLoginReturnTarget =
  | { pathname: '/'; search: ''; hash: string }
  | { pathname: '/invitations/accept'; search: string; hash: '' };

/**
 * Login.tsx calls this with `location.state?.from` (attached by
 * ProtectedRoute in App.tsx before redirecting an unauthenticated visit to
 * /login) to safely resume the original deep link — a scanned asset QR, or
 * an invitation-acceptance link — after signing in, WITHOUT ever becoming
 * an open redirect.
 *
 * Accepts ONLY two internal shapes:
 *   - `pathname` exactly `"/"` with a `hash` whose leading segment is a
 *     known view (the same ALL_DASHBOARD_VIEWS allowlist parseEntityHash
 *     enforces);
 *   - `pathname` exactly `"/invitations/accept"` with a `search` that is
 *     EXACTLY `?invitation=<uuid>` — one param, that name, a valid uuid,
 *     nothing else appended.
 *
 * Anything else — an external origin, a protocol-relative `"//host"`,
 * `"javascript:"`, a foreign pathname, an unrecognized view, an extra query
 * param, or a non-uuid invitation id — returns null so the caller falls
 * back to a bare `/`. Because every check is a fixed-string/format
 * allowlist, no crafted input can ever pass it into something react-router
 * would treat as leaving this app.
 */
export function resolveSafeLoginReturnTarget(from: unknown): SafeLoginReturnTarget | null {
  if (!from || typeof from !== 'object') return null;
  const candidate = from as { pathname?: unknown; search?: unknown; hash?: unknown };

  if (candidate.pathname === '/') {
    const hash = typeof candidate.hash === 'string' ? candidate.hash : '';
    if (hash === '') return { pathname: '/', search: '', hash: '' };
    if (!parseEntityHash(hash).view) return null;
    return { pathname: '/', search: '', hash };
  }

  if (candidate.pathname === '/invitations/accept') {
    const search = typeof candidate.search === 'string' ? candidate.search : '';
    const params = new URLSearchParams(search);
    const keys = Array.from(params.keys());
    const invitation = params.get('invitation');
    if (keys.length !== 1 || keys[0] !== 'invitation' || !invitation || !isValidUuid(invitation)) return null;
    return { pathname: '/invitations/accept', search: `?invitation=${invitation}`, hash: '' };
  }

  return null;
}

/** Sets window.location.hash to the canonical hash for `target`. This alone
 * triggers a 'hashchange' event Dashboard already listens to — it does not
 * push React state directly, so this stays the single navigation path
 * whether the click originated from the bell, the notification center, or
 * anywhere else. */
export function navigateToEntity(target: EntityNavigationTarget): void {
  window.location.hash = buildEntityHash(target);
}

const asNonEmptyString = (value: unknown): string | undefined =>
  typeof value === 'string' && value.length > 0 ? value : undefined;

/** The minimal notification shape resolveNotificationTarget needs — matches
 * organization_notifications' Row type without importing the full
 * Database['public']['Tables'] path in every caller. */
export type NavigableNotification = Pick<
  OrganizationNotification,
  'type' | 'entity_type' | 'entity_id' | 'related_request_id' | 'related_quote_id' | 'metadata'
>;

/**
 * THE single place that maps an organization_notifications row to a
 * navigation target. Driven by `entity_type` (and, for quotes, the legacy
 * related_request_id/related_quote_id columns) rather than by
 * `notification.type` — most operational types (work_order_created,
 * technician_assigned, work_order_due_soon, work_order_overdue,
 * work_completed, internal_request_created, request_private_invitation)
 * already carry a directly-navigable entity_id and need no type-specific
 * branch here at all. Returns null when nothing navigable can be resolved
 * (missing/unrecognized entity_type, or the activity/work_order lookup came
 * back empty because it was deleted or RLS denies it — never a bypass,
 * always a real read through the normal Supabase client).
 */
export async function resolveNotificationTarget(
  notification: NavigableNotification,
): Promise<EntityNavigationTarget | null> {
  const metadata = (notification.metadata ?? {}) as Record<string, unknown>;

  switch (notification.entity_type) {
    case 'request': {
      if (!notification.entity_id) return null;
      return { view: 'requests', requestId: notification.entity_id };
    }

    case 'quote': {
      // quote_submitted / quote_approved / quote_rejected (and any other
      // quote_* type) are emitted via the older create_organization_notification
      // path, which populates related_request_id/related_quote_id directly —
      // metadata is only a fallback, never invented when both are absent.
      const requestId = notification.related_request_id ?? asNonEmptyString(metadata.request_id);
      if (!requestId) return null;
      const quoteId = notification.related_quote_id
        ?? asNonEmptyString(metadata.quote_id)
        ?? notification.entity_id
        ?? undefined;
      return { view: 'requests', requestId, quoteId };
    }

    case 'work_order': {
      if (!notification.entity_id) return null;
      return { view: 'work-orders', workOrderId: notification.entity_id };
    }

    case 'activity': {
      // entity_id is the activity's own id, not the work order's — the only
      // navigable target here (#work-orders?workOrder=...) needs the parent
      // work_order_id, resolved via a normal RLS-scoped read. Only the
      // operating organization (or platform_admin) can read
      // work_order_activities; anyone else gets 0 rows here, same as any
      // other unauthorized deep link — never a bypass.
      if (!notification.entity_id) return null;
      const { data, error } = await supabase
        .from('work_order_activities')
        .select('work_order_id')
        .eq('id', notification.entity_id)
        .maybeSingle();
      if (error || !data) return null;
      return { view: 'work-orders', workOrderId: data.work_order_id, activityId: notification.entity_id };
    }

    case 'inspection_plan': {
      // IMPORTANT: entity_id here is a synthetic dedup key
      // (md5(plan_id|rule_id|next_due_at)), never inspection_plans.id — see
      // generate_inspection_due_notifications() in
      // 20260830100000_inspection_scheduling_alerts.sql. The real plan only
      // ever lives in metadata.plan_id.
      const planId = asNonEmptyString(metadata.plan_id);
      if (!planId) return null;
      return { view: 'inspections', inspectionPlanId: planId };
    }

    case 'maintenance_notice': {
      // entity_id es el id real del aviso (lo escribe
      // create_maintenance_notice). El deep link solo indica QUÉ abrir: si
      // quien hace clic no es miembro del tenant dueño del aviso, la RLS de
      // maintenance_notices devuelve 0 filas y el backlog muestra "no se
      // pudo abrir" — el hash nunca es autorización.
      if (!notification.entity_id) return null;
      return { view: 'backlog', noticeId: notification.entity_id };
    }

    case 'preventive_maintenance_occurrence': {
      if (!notification.entity_id) return null;
      return {
        view: 'preventive-maintenance',
        preventiveOccurrenceId: notification.entity_id,
        preventivePlanId: asNonEmptyString(metadata.plan_id),
      };
    }

    case 'inspection_run': {
      // No current trigger emits this entity_type yet, but the shape is
      // prepared for a future one where entity_id is a real run id.
      if (!notification.entity_id) return null;
      return { view: 'inspections', inspectionRunId: notification.entity_id };
    }

    default:
      return null;
  }
}

/**
 * Shared click handler for both NotificationBell and NotificationList — the
 * only place either of them should call. Marking-as-read and navigating are
 * deliberately independent: a markAsRead failure must never block
 * navigation, and a navigation failure (nothing resolvable, or RLS denies
 * the underlying lookup) must never leave the notification unread. Returns
 * whether navigation actually happened, so callers can show their own
 * "couldn't open" feedback if they want to.
 */
export async function handleNotificationNavigation(
  notification: NavigableNotification & { id: string; is_read: boolean },
  markAsRead?: (notificationId: string) => Promise<boolean>,
): Promise<boolean> {
  if (markAsRead && !notification.is_read) {
    try {
      await markAsRead(notification.id);
    } catch {
      // best-effort — navigation still proceeds below
    }
  }

  let target: EntityNavigationTarget | null = null;
  try {
    target = await resolveNotificationTarget(notification);
  } catch {
    target = null;
  }

  if (!target) return false;
  navigateToEntity(target);
  return true;
}
