export type ActivityReportStatus = 'pending' | 'in_progress' | 'completed' | 'blocked';

export interface ActivityReportFormTechnician {
  memberId: string;
  name: string;
  email: string;
}

export interface ActivityReportFormMaterial {
  workOrderMaterialId: string;
  materialId: string;
  code: string;
  name: string;
  unit: string;
  plannedQuantity: number;
  usedQuantity: number;
  currentStock: number;
}

export interface ActivityReportSummary {
  id: string;
  startedAt: string;
  finishedAt: string;
  actualHours: number;
  observations: string | null;
  finalStatus: ActivityReportStatus;
  createdAt: string;
}

export interface ActivityReportFormData {
  activity: {
    id: string;
    description: string;
    estimatedHours: number | null;
    status: string;
    sequence: number;
    dueAt: string | null;
  };
  workOrder: {
    id: string;
    workOrderNumber: string;
    title: string | null;
    status: string;
  };
  assignedTechnicians: ActivityReportFormTechnician[];
  availableMaterials: ActivityReportFormMaterial[];
  /** The caller's own previous reports for this activity — multiple
   * reports per activity are allowed (e.g. a second work shift), so this
   * is a list, not a single value. */
  myPreviousReports: ActivityReportSummary[];
}

export interface ActivityReportMaterialInput {
  materialId: string;
  workOrderMaterialId?: string;
  quantityUsed: number;
  unit: string;
  notes?: string;
}

export interface ActivityReportEvidenceInput {
  fileName: string;
  /** Pasted link only in this phase — no real file upload yet, see
   * docs/TECHNICIAN_ACTIVITY_REPORTS.md. */
  fileUrl?: string;
  notes?: string;
}

export interface SubmitActivityReportInput {
  activityId: string;
  startedAt: string;
  finishedAt: string;
  observations?: string;
  finalStatus: ActivityReportStatus;
  materials: ActivityReportMaterialInput[];
  evidences: ActivityReportEvidenceInput[];
}

export interface ActivityReportMaterialUsed {
  id: string;
  materialCode: string;
  materialName: string;
  unit: string;
  quantityUsed: number;
  notes: string | null;
}

export interface ActivityReportEvidence {
  id: string;
  fileName: string;
  fileUrl: string | null;
  filePath: string | null;
  mimeType: string | null;
  sizeBytes: number | null;
  notes: string | null;
}

export interface WorkOrderActivityReport {
  id: string;
  activityId: string;
  activityDescription: string;
  estimatedHours: number | null;
  memberId: string;
  technicianName: string;
  technicianEmail: string;
  startedAt: string;
  finishedAt: string;
  actualHours: number;
  hoursDifference: number;
  observations: string | null;
  finalStatus: ActivityReportStatus;
  materials: ActivityReportMaterialUsed[];
  evidences: ActivityReportEvidence[];
  createdAt: string;
}
