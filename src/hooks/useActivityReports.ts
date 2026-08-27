import { useCallback, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import type {
  ActivityReportFormData,
  SubmitActivityReportInput,
  WorkOrderActivityReport,
} from '@/types/activityReport';

interface RawFormData {
  activity: {
    id: string;
    description: string;
    estimated_hours: number | null;
    status: string;
    sequence: number;
    due_at: string | null;
  };
  work_order: {
    id: string;
    work_order_number: string;
    title: string | null;
    status: string;
  };
  assigned_technicians: { member_id: string; name: string; email: string }[];
  available_materials: {
    work_order_material_id: string;
    material_id: string;
    code: string;
    name: string;
    unit: string;
    planned_quantity: number;
    used_quantity: number;
    current_stock: number;
  }[];
  my_previous_reports: {
    id: string;
    started_at: string;
    finished_at: string;
    actual_hours: number;
    observations: string | null;
    final_status: string;
    created_at: string;
  }[];
}

const toFormData = (raw: RawFormData): ActivityReportFormData => ({
  activity: {
    id: raw.activity.id,
    description: raw.activity.description,
    estimatedHours: raw.activity.estimated_hours,
    status: raw.activity.status,
    sequence: raw.activity.sequence,
    dueAt: raw.activity.due_at,
  },
  workOrder: {
    id: raw.work_order.id,
    workOrderNumber: raw.work_order.work_order_number,
    title: raw.work_order.title,
    status: raw.work_order.status,
  },
  assignedTechnicians: (raw.assigned_technicians ?? []).map((row) => ({
    memberId: row.member_id,
    name: row.name,
    email: row.email,
  })),
  availableMaterials: (raw.available_materials ?? []).map((row) => ({
    workOrderMaterialId: row.work_order_material_id,
    materialId: row.material_id,
    code: row.code,
    name: row.name,
    unit: row.unit,
    plannedQuantity: row.planned_quantity,
    usedQuantity: row.used_quantity,
    currentStock: row.current_stock,
  })),
  myPreviousReports: (raw.my_previous_reports ?? []).map((row) => ({
    id: row.id,
    startedAt: row.started_at,
    finishedAt: row.finished_at,
    actualHours: row.actual_hours,
    observations: row.observations,
    finalStatus: row.final_status as ActivityReportFormData['myPreviousReports'][number]['finalStatus'],
    createdAt: row.created_at,
  })),
});

interface RawMaterialUsed {
  id: string;
  material_code: string;
  material_name: string;
  unit: string;
  quantity_used: number;
  notes: string | null;
}

interface RawEvidence {
  id: string;
  file_name: string;
  file_url: string | null;
  file_path: string | null;
  mime_type: string | null;
  size_bytes: number | null;
  notes: string | null;
}

/**
 * "Reportar actividad": planificación (work_order_activities.estimated_hours)
 * vs. ejecución real, vía get_activity_report_form_data /
 * submit_activity_report / get_activity_reports_for_work_order (all
 * SECURITY DEFINER, tenant + assignment scoped — see
 * docs/TECHNICIAN_ACTIVITY_REPORTS.md). Multiple reports per activity are
 * allowed on purpose (e.g. a second work shift); submitReport always
 * inserts a new report, never updates a previous one.
 */
export function useActivityReports() {
  const [formData, setFormData] = useState<ActivityReportFormData | null>(null);
  const [loadingForm, setLoadingForm] = useState(false);
  const [reports, setReports] = useState<WorkOrderActivityReport[]>([]);
  const [loadingReports, setLoadingReports] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const loadFormData = useCallback(async (activityId: string) => {
    setLoadingForm(true);
    setError(null);
    try {
      const { data, error: rpcError } = await supabase.rpc('get_activity_report_form_data', {
        p_activity_id: activityId,
      });
      if (rpcError) throw rpcError;
      setFormData(data ? toFormData(data as unknown as RawFormData) : null);
    } catch (err) {
      setFormData(null);
      setError(err instanceof Error ? err.message : 'No se pudo cargar el formulario de reporte.');
    } finally {
      setLoadingForm(false);
    }
  }, []);

  const submitReport = useCallback(async (input: SubmitActivityReportInput): Promise<boolean> => {
    setSaving(true);
    setError(null);
    try {
      const { error: rpcError } = await supabase.rpc('submit_activity_report', {
        p_activity_id: input.activityId,
        p_started_at: input.startedAt,
        p_finished_at: input.finishedAt,
        p_observations: input.observations || null,
        p_final_status: input.finalStatus,
        p_materials: input.materials.map((material) => ({
          material_id: material.materialId,
          work_order_material_id: material.workOrderMaterialId ?? null,
          quantity_used: material.quantityUsed,
          unit: material.unit,
          notes: material.notes ?? null,
        })),
        p_evidences: input.evidences.map((evidence) => ({
          file_name: evidence.fileName,
          file_url: evidence.fileUrl ?? null,
          notes: evidence.notes ?? null,
        })),
      });
      if (rpcError) throw rpcError;
      return true;
    } catch (err) {
      setError(err instanceof Error ? err.message : 'No se pudo guardar el reporte.');
      return false;
    } finally {
      setSaving(false);
    }
  }, []);

  const loadReportsForWorkOrder = useCallback(async (workOrderId: string) => {
    setLoadingReports(true);
    setError(null);
    try {
      const { data, error: rpcError } = await supabase.rpc('get_activity_reports_for_work_order', {
        p_work_order_id: workOrderId,
      });
      if (rpcError) throw rpcError;
      setReports((data ?? []).map((row) => ({
        id: row.id,
        activityId: row.activity_id,
        activityDescription: row.activity_description,
        estimatedHours: row.estimated_hours,
        memberId: row.member_id,
        technicianName: row.technician_name,
        technicianEmail: row.technician_email,
        startedAt: row.started_at,
        finishedAt: row.finished_at,
        actualHours: row.actual_hours,
        hoursDifference: row.hours_difference,
        observations: row.observations,
        finalStatus: row.final_status as WorkOrderActivityReport['finalStatus'],
        materials: (row.materials as unknown as RawMaterialUsed[] ?? []).map((material) => ({
          id: material.id,
          materialCode: material.material_code,
          materialName: material.material_name,
          unit: material.unit,
          quantityUsed: material.quantity_used,
          notes: material.notes,
        })),
        evidences: (row.evidences as unknown as RawEvidence[] ?? []).map((evidence) => ({
          id: evidence.id,
          fileName: evidence.file_name,
          fileUrl: evidence.file_url,
          filePath: evidence.file_path,
          mimeType: evidence.mime_type,
          sizeBytes: evidence.size_bytes,
          notes: evidence.notes,
        })),
        createdAt: row.created_at,
      })));
    } catch (err) {
      setReports([]);
      setError(err instanceof Error ? err.message : 'No se pudieron cargar los reportes.');
    } finally {
      setLoadingReports(false);
    }
  }, []);

  return {
    formData,
    loadingForm,
    reports,
    loadingReports,
    saving,
    error,
    loadFormData,
    submitReport,
    loadReportsForWorkOrder,
  };
}
