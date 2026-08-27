import { useState } from 'react';
import { Boxes, Plus, Pencil, Trash2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from '@/components/ui/alert-dialog';
import { useToast } from '@/hooks/use-toast';
import { useWorkOrderMaterials } from '@/hooks/useWorkOrderMaterials';
import { WorkOrderMaterialWarningBadge } from '@/components/requests/StatusBadge';
import { WorkOrderMaterialEditorDialog } from './WorkOrderMaterialEditorDialog';
import type { WorkOrderMaterial, WorkOrderMaterialInput } from '@/types/workOrderMaterial';

interface WorkOrderMaterialsSectionProps {
  workOrderId: string;
  /** The OT's operating organization (provider_organization_id). */
  organizationId: string;
  canManage: boolean;
}

export function WorkOrderMaterialsSection({ workOrderId, organizationId, canManage }: WorkOrderMaterialsSectionProps) {
  const { materials, loading, saving, error, saveMaterial, deleteMaterial } = useWorkOrderMaterials(workOrderId);
  const { toast } = useToast();
  const [editorOpen, setEditorOpen] = useState(false);
  const [editingMaterial, setEditingMaterial] = useState<WorkOrderMaterial | null>(null);
  const [pendingDeleteId, setPendingDeleteId] = useState<string | null>(null);

  const openCreate = () => { setEditingMaterial(null); setEditorOpen(true); };
  const openEdit = (material: WorkOrderMaterial) => { setEditingMaterial(material); setEditorOpen(true); };

  const handleSave = async (input: WorkOrderMaterialInput, workOrderMaterialId: string | undefined): Promise<boolean> => {
    const ok = await saveMaterial(input, workOrderMaterialId);
    if (ok) {
      toast({ title: workOrderMaterialId ? 'Material actualizado' : 'Material agregado' });
    } else {
      toast({ title: 'No se pudo guardar el material', description: error ?? 'Intenta nuevamente.', variant: 'destructive' });
    }
    return ok;
  };

  const handleConfirmDelete = async () => {
    if (!pendingDeleteId) return;
    const ok = await deleteMaterial(pendingDeleteId);
    setPendingDeleteId(null);
    toast(ok
      ? { title: 'Material eliminado' }
      : { title: 'No se pudo eliminar el material', description: error ?? 'Intenta nuevamente.', variant: 'destructive' });
  };

  return (
    <div className="rounded-lg border p-3 space-y-3">
      <div className="flex items-center justify-between">
        <p className="flex items-center gap-2 text-xs font-medium uppercase tracking-wide text-muted-foreground">
          <Boxes className="h-3.5 w-3.5" /> Materiales
        </p>
        {canManage && (
          <Button size="sm" variant="outline" onClick={openCreate} disabled={loading}>
            <Plus className="mr-1 h-3.5 w-3.5" /> Agregar material
          </Button>
        )}
      </div>

      {loading ? (
        <p className="text-sm text-muted-foreground">Cargando materiales…</p>
      ) : materials.length === 0 ? (
        <p className="text-sm text-muted-foreground">Aún no hay materiales registrados para esta OT.</p>
      ) : (
        <div className="space-y-2">
          {materials.map((material) => (
            <div key={material.id} className="rounded-md border p-2.5">
              <div className="flex items-start justify-between gap-2">
                <div className="min-w-0 space-y-1">
                  <p className="text-sm font-medium break-words">
                    {material.materialCode} — {material.materialName}
                  </p>
                  <div className="flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-muted-foreground">
                    <span>{material.warehouseName}</span>
                    <span>Planificado: {material.plannedQuantity} {material.materialUnit}</span>
                    <span>Utilizado: {material.usedQuantity} {material.materialUnit}</span>
                    <span>Stock disponible: {material.currentStock} {material.materialUnit}</span>
                  </div>
                  {material.notes && <p className="text-xs text-muted-foreground">{material.notes}</p>}
                </div>
                <div className="flex shrink-0 items-center gap-1">
                  <WorkOrderMaterialWarningBadge status={material.warningStatus} />
                  {canManage && (
                    <>
                      <Button variant="ghost" size="icon" className="h-7 w-7" onClick={() => openEdit(material)} title="Editar material">
                        <Pencil className="h-3.5 w-3.5" />
                      </Button>
                      <Button variant="ghost" size="icon" className="h-7 w-7 text-destructive hover:text-destructive" onClick={() => setPendingDeleteId(material.id)} title="Eliminar material">
                        <Trash2 className="h-3.5 w-3.5" />
                      </Button>
                    </>
                  )}
                </div>
              </div>
            </div>
          ))}
        </div>
      )}

      {canManage && (
        <WorkOrderMaterialEditorDialog
          open={editorOpen}
          onOpenChange={setEditorOpen}
          organizationId={organizationId}
          material={editingMaterial}
          saving={saving}
          onSave={handleSave}
        />
      )}

      <AlertDialog open={pendingDeleteId !== null} onOpenChange={(open) => !open && setPendingDeleteId(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>¿Eliminar este material de la OT?</AlertDialogTitle>
            <AlertDialogDescription>
              Esto solo quita la línea de planificación de esta OT — el material del inventario no se modifica. Esta acción no se puede deshacer.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancelar</AlertDialogCancel>
            <AlertDialogAction onClick={() => void handleConfirmDelete()}>Eliminar</AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
