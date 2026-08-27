export type WorkOrderActivityStatus = 'pending' | 'assigned' | 'in_progress' | 'completed';

export interface WorkOrderActivityTechnician {
  memberId: string;
  name: string;
  email: string;
  isPrimary: boolean;
}

export interface WorkOrderActivity {
  id: string;
  workOrderId: string;
  description: string;
  estimatedHours: number | null;
  dueAt: string | null;
  status: WorkOrderActivityStatus;
  sequence: number;
  createdAt: string;
  updatedAt: string;
  technicians: WorkOrderActivityTechnician[];
}

/** Payload for upsert_work_order_activity. `memberIds[0]` becomes the
 * primary technician server-side — the initial UI has no separate control
 * to pick a primary among several. */
export interface WorkOrderActivityInput {
  description: string;
  estimatedHours: number | null;
  dueAt: string | null;
  status: WorkOrderActivityStatus;
  memberIds: string[];
}
