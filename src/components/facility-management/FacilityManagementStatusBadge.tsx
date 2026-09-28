import { Badge } from '@/components/ui/badge';
import { FACILITY_MANAGEMENT_STATUS_LABELS } from '@/lib/facilityManagement';
import type { OrganizationRelationshipStatus } from '@/types/organization';

const STATUS_CLASSES: Record<OrganizationRelationshipStatus, string> = {
  pending: 'text-warning border-warning/40',
  active: 'text-success border-success/40',
  suspended: 'text-destructive border-destructive/40',
  ended: 'text-muted-foreground',
};

export function FacilityManagementStatusBadge({ status }: { status: OrganizationRelationshipStatus | null }) {
  if (!status) return <Badge variant="outline" className="text-muted-foreground">Sin vincular</Badge>;
  return <Badge variant="outline" className={STATUS_CLASSES[status]}>{FACILITY_MANAGEMENT_STATUS_LABELS[status]}</Badge>;
}
