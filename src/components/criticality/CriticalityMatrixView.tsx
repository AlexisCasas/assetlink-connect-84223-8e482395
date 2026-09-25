import { useEffect, useState } from 'react';
import { Gauge, Plus, Pencil, EyeOff, Eye, AlertTriangle, ListChecks, LayoutTemplate, FileSpreadsheet, Upload, Download, Save, FilePlus2 } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { useCriticalityMatrix } from '@/hooks/useCriticalityMatrix';
import { useCriticalityTemplates } from '@/hooks/useCriticalityTemplates';
import { useCriticalityThresholds } from '@/hooks/useCriticalityThresholds';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
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
import { CriticalityParameterDialog } from './CriticalityParameterDialog';
import { CriticalityOptionDialog } from './CriticalityOptionDialog';
import { CriticalityTemplatesDialog } from './CriticalityTemplatesDialog';
import { CriticalitySaveTemplateDialog } from './CriticalitySaveTemplateDialog';
import { CriticalityMatrixImportDialog } from './CriticalityMatrixImportDialog';
import { CriticalityBulkAssessmentDialog } from './CriticalityBulkAssessmentDialog';
import { CriticalityThresholdsCard } from './CriticalityThresholdsCard';
import { CriticalityThresholdsDialog } from './CriticalityThresholdsDialog';
import { buildMatrixWorkbook, downloadBlob, matrixFileName } from '@/lib/criticalityExcel';
import type { CriticalityOption, CriticalityOptionInput, CriticalityParameter, CriticalityParameterInput } from '@/types/criticalityMatrix';

export function CriticalityMatrixView() {
  const { currentOrganization, currentMembership } = useAuth();
  const {
    matrix,
    activeParameters,
    totalActiveWeight,
    loading,
    saving,
    error,
    refresh,
    saveParameter,
    saveOption,
    toggleParameterActive,
    toggleOptionActive,
    replaceConfiguration,
    clearActiveMatrix,
    previewBulk,
    applyBulk,
  } = useCriticalityMatrix(currentOrganization?.id);
  const { saving: templateSaving, saveCurrentMatrixAsTemplate } = useCriticalityTemplates(currentOrganization?.id);
  const {
    thresholds,
    loading: thresholdsLoading,
    saving: thresholdsSaving,
    error: thresholdsError,
    refresh: refreshThresholds,
    saveThresholds,
  } = useCriticalityThresholds(currentOrganization?.id);
  const { toast } = useToast();

  const [parameterDialogOpen, setParameterDialogOpen] = useState(false);
  const [editingParameter, setEditingParameter] = useState<CriticalityParameter | null>(null);
  const [optionDialogOpen, setOptionDialogOpen] = useState(false);
  const [editingOption, setEditingOption] = useState<CriticalityOption | null>(null);
  const [optionParameter, setOptionParameter] = useState<CriticalityParameter | null>(null);
  const [templatesOpen, setTemplatesOpen] = useState(false);
  const [saveTemplateOpen, setSaveTemplateOpen] = useState(false);
  const [importOpen, setImportOpen] = useState(false);
  const [bulkOpen, setBulkOpen] = useState(false);
  const [exporting, setExporting] = useState(false);
  const [clearConfirmOpen, setClearConfirmOpen] = useState(false);
  const [thresholdsDialogOpen, setThresholdsDialogOpen] = useState(false);

  // The score range and the unreachable-category warnings depend on the active
  // matrix, so they are re-read from the server whenever the matrix changes
  // (parameter/option edits, import, template, blank matrix).
  useEffect(() => { void refreshThresholds(); }, [matrix, refreshThresholds]);

  if (!currentOrganization) {
    return <EmptyState message="Sin organización asignada" />;
  }

  const hasActiveMatrix = activeParameters.length > 0;
  // Same authorization set clear_active_criticality_matrix enforces
  // server-side (owner/admin/manager or platform_admin) — this only gates
  // the button's visibility, the RPC is still the real authority.
  const canManageMatrix = currentOrganization.organizationType === 'platform_admin'
    || (!!currentMembership?.isActive && ['owner', 'admin', 'manager'].includes(currentMembership.role));

  const handleClearActiveMatrix = async () => {
    const ok = await clearActiveMatrix();
    setClearConfirmOpen(false);
    toast(ok
      ? { title: 'Matriz en blanco', description: 'La configuración activa fue desactivada. Plantillas y evaluaciones históricas se conservan.' }
      : { title: 'No se pudo limpiar la matriz', description: error ?? 'Intenta nuevamente.', variant: 'destructive' });
  };

  const handleExportMatrix = async () => {
    if (!thresholds) return;
    setExporting(true);
    try {
      const blob = await buildMatrixWorkbook(matrix, currentOrganization.name, thresholds);
      downloadBlob(blob, matrixFileName(currentOrganization.name));
      toast({ title: 'Matriz exportada' });
    } catch (exportError) {
      toast({
        title: 'No se pudo exportar la matriz',
        description: exportError instanceof Error ? exportError.message : 'Intenta nuevamente.',
        variant: 'destructive',
      });
    } finally {
      setExporting(false);
    }
  };

  const openCreateParameter = () => { setEditingParameter(null); setParameterDialogOpen(true); };
  const openEditParameter = (parameter: CriticalityParameter) => { setEditingParameter(parameter); setParameterDialogOpen(true); };
  const openCreateOption = (parameter: CriticalityParameter) => { setOptionParameter(parameter); setEditingOption(null); setOptionDialogOpen(true); };
  const openEditOption = (parameter: CriticalityParameter, option: CriticalityOption) => { setOptionParameter(parameter); setEditingOption(option); setOptionDialogOpen(true); };

  const handleSaveParameter = async (input: CriticalityParameterInput, parameterId: string | undefined) => {
    const ok = await saveParameter(input, parameterId);
    toast(ok
      ? { title: parameterId ? 'Parámetro actualizado' : 'Parámetro creado' }
      : { title: 'No se pudo guardar el parámetro', description: error ?? 'Intenta nuevamente.', variant: 'destructive' });
    return ok;
  };

  const handleSaveOption = async (input: CriticalityOptionInput, optionId: string | undefined) => {
    const ok = await saveOption(input, optionId);
    toast(ok
      ? { title: optionId ? 'Opción actualizada' : 'Opción creada' }
      : { title: 'No se pudo guardar la opción', description: error ?? 'Intenta nuevamente.', variant: 'destructive' });
    return ok;
  };

  const handleToggleParameter = async (parameter: CriticalityParameter) => {
    const ok = await toggleParameterActive(parameter.id, !parameter.isActive);
    toast(ok
      ? { title: parameter.isActive ? 'Parámetro desactivado' : 'Parámetro activado' }
      : { title: 'No se pudo actualizar el parámetro', description: error ?? 'Intenta nuevamente.', variant: 'destructive' });
  };

  const handleToggleOption = async (option: CriticalityOption) => {
    const ok = await toggleOptionActive(option.id, !option.isActive);
    toast(ok
      ? { title: option.isActive ? 'Opción desactivada' : 'Opción activada' }
      : { title: 'No se pudo actualizar la opción', description: error ?? 'Intenta nuevamente.', variant: 'destructive' });
  };

  const nextParameterSequence = matrix.length === 0 ? 1 : Math.max(...matrix.map((p) => p.sequence)) + 1;
  const nextOptionSequence = (parameter: CriticalityParameter | null) =>
    !parameter || parameter.options.length === 0 ? 1 : Math.max(...parameter.options.map((o) => o.sequence)) + 1;

  return (
    <div className="space-y-6 p-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-2xl font-semibold">Criticidad</h1>
          <p className="mt-1 text-sm text-muted-foreground">
            Matriz de criticidad configurable: parámetros ponderados y opciones puntuadas para calcular la criticidad de un activo.
          </p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <Button variant="outline" onClick={() => setTemplatesOpen(true)} disabled={loading}>
            <LayoutTemplate className="mr-2 h-4 w-4" /> Plantillas
          </Button>
          <Button variant="outline" onClick={() => setBulkOpen(true)} disabled={loading || !hasActiveMatrix}>
            <FileSpreadsheet className="mr-2 h-4 w-4" /> Evaluar por Excel
          </Button>
          <Button variant="outline" onClick={() => setImportOpen(true)} disabled={loading}>
            <Upload className="mr-2 h-4 w-4" /> Importar matriz
          </Button>
          <Button variant="outline" onClick={() => void handleExportMatrix()} disabled={loading || exporting || !hasActiveMatrix || !thresholds}>
            <Download className="mr-2 h-4 w-4" /> {exporting ? 'Exportando…' : 'Exportar matriz'}
          </Button>
          {canManageMatrix && (
            <Button variant="outline" onClick={() => setClearConfirmOpen(true)} disabled={loading || saving || !hasActiveMatrix}>
              <FilePlus2 className="mr-2 h-4 w-4" /> Nueva matriz en blanco
            </Button>
          )}
          <Button variant="outline" onClick={() => setSaveTemplateOpen(true)} disabled={loading || !hasActiveMatrix}>
            <Save className="mr-2 h-4 w-4" /> Guardar como plantilla
          </Button>
          <Button onClick={openCreateParameter} disabled={loading}>
            <Plus className="mr-2 h-4 w-4" /> Crear parámetro
          </Button>
        </div>
      </div>

      {matrix.length > 0 && (
        <div className="flex flex-wrap items-center gap-2">
          <Badge variant={totalActiveWeight === 100 ? 'secondary' : 'outline'}>
            Suma de pesos activos: {totalActiveWeight}%
          </Badge>
          {totalActiveWeight !== 100 && (
            <span className="flex items-center gap-1 text-xs text-amber-600">
              <AlertTriangle className="h-3.5 w-3.5" />
              La suma de pesos no es 100% — esto es solo una advertencia, no bloquea la evaluación.
            </span>
          )}
        </div>
      )}

      <CriticalityThresholdsCard
        thresholds={thresholds}
        loading={thresholdsLoading}
        error={thresholdsError}
        canManage={canManageMatrix}
        onEdit={() => setThresholdsDialogOpen(true)}
      />

      {loading ? (
        <p className="text-sm text-muted-foreground">Cargando matriz de criticidad…</p>
      ) : matrix.length === 0 ? (
        <Card>
          <CardContent className="flex min-h-48 flex-col items-center justify-center gap-3 text-center">
            <Gauge className="h-8 w-8 text-muted-foreground" />
            <p className="font-medium">Aún no hay parámetros de criticidad configurados.</p>
            <div className="max-w-md text-sm text-muted-foreground">
              <p>Ejemplo de matriz:</p>
              <ul className="mt-1 space-y-0.5">
                <li>Sin equipo de respaldo — peso 30%</li>
                <li>Impacto operacional — peso 25%</li>
                <li>Tiempo detenido — peso 20%</li>
                <li>Frecuencia de falla — peso 15%</li>
                <li>Disponibilidad de repuesto — peso 10%</li>
              </ul>
            </div>
          </CardContent>
        </Card>
      ) : (
        <div className="space-y-4">
          {matrix.map((parameter) => (
            <Card key={parameter.id} className={!parameter.isActive ? 'opacity-60' : undefined}>
              <CardHeader className="flex flex-row items-start justify-between space-y-0">
                <div>
                  <CardTitle className="flex flex-wrap items-center gap-2 text-base">
                    <ListChecks className="h-4 w-4 text-muted-foreground" /> {parameter.name}
                    <Badge variant="outline" className="font-mono text-[10px]" title="Código técnico usado por el Excel">
                      {parameter.code}
                    </Badge>
                    <Badge variant="secondary">{parameter.weight}%</Badge>
                    {!parameter.isActive && <Badge variant="outline">Inactivo</Badge>}
                  </CardTitle>
                  {parameter.description && <p className="mt-1 text-sm text-muted-foreground">{parameter.description}</p>}
                </div>
                <div className="flex shrink-0 items-center gap-2">
                  <Button variant="outline" size="sm" onClick={() => openCreateOption(parameter)}>
                    <Plus className="mr-1 h-3.5 w-3.5" /> Opción
                  </Button>
                  <Button variant="ghost" size="icon" onClick={() => openEditParameter(parameter)} title="Editar parámetro">
                    <Pencil className="h-4 w-4" />
                  </Button>
                  <Button variant="ghost" size="icon" onClick={() => void handleToggleParameter(parameter)} title={parameter.isActive ? 'Desactivar' : 'Activar'}>
                    {parameter.isActive ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                  </Button>
                </div>
              </CardHeader>
              <CardContent>
                {parameter.options.length === 0 ? (
                  <p className="text-sm text-muted-foreground">Este parámetro todavía no tiene opciones.</p>
                ) : (
                  <div className="space-y-2">
                    {parameter.options.map((option) => (
                      <div key={option.id} className={`flex items-center justify-between rounded-md border p-2.5 ${!option.isActive ? 'opacity-60' : ''}`}>
                        <p className="text-sm font-medium">{option.label}</p>
                        <div className="flex shrink-0 items-center gap-2">
                          <Badge variant="secondary">Puntuación: {option.score}</Badge>
                          {!option.isActive && <Badge variant="outline">Inactiva</Badge>}
                          <Button variant="ghost" size="icon" className="h-7 w-7" onClick={() => openEditOption(parameter, option)} title="Editar opción">
                            <Pencil className="h-3.5 w-3.5" />
                          </Button>
                          <Button variant="ghost" size="icon" className="h-7 w-7" onClick={() => void handleToggleOption(option)} title={option.isActive ? 'Desactivar' : 'Activar'}>
                            {option.isActive ? <EyeOff className="h-3.5 w-3.5" /> : <Eye className="h-3.5 w-3.5" />}
                          </Button>
                        </div>
                      </div>
                    ))}
                  </div>
                )}
              </CardContent>
            </Card>
          ))}
        </div>
      )}

      <CriticalityParameterDialog
        open={parameterDialogOpen}
        onOpenChange={setParameterDialogOpen}
        parameter={editingParameter}
        nextSequence={nextParameterSequence}
        saving={saving}
        onSave={handleSaveParameter}
      />
      <CriticalityOptionDialog
        open={optionDialogOpen}
        onOpenChange={setOptionDialogOpen}
        parameterId={optionParameter?.id ?? null}
        parameterName={optionParameter?.name ?? ''}
        option={editingOption}
        nextSequence={nextOptionSequence(optionParameter)}
        saving={saving}
        onSave={handleSaveOption}
      />

      <CriticalityTemplatesDialog
        open={templatesOpen}
        onOpenChange={setTemplatesOpen}
        organizationId={currentOrganization.id}
        hasActiveMatrix={hasActiveMatrix}
        currentThresholds={thresholds}
        onApplied={() => {
          void refresh();
          toast({ title: 'Plantilla aplicada', description: 'La matriz activa fue reemplazada. Las evaluaciones históricas se conservan.' });
        }}
      />

      <CriticalitySaveTemplateDialog
        open={saveTemplateOpen}
        onOpenChange={setSaveTemplateOpen}
        saving={templateSaving}
        onSave={async (name, description, category) => {
          const ok = await saveCurrentMatrixAsTemplate(name, description, category);
          toast(ok
            ? { title: 'Plantilla guardada', description: `"${name}" quedó disponible para tu organización.` }
            : { title: 'No se pudo guardar la plantilla', description: 'Intenta nuevamente.', variant: 'destructive' });
          return ok;
        }}
      />

      <CriticalityMatrixImportDialog
        open={importOpen}
        onOpenChange={setImportOpen}
        hasActiveMatrix={hasActiveMatrix}
        currentThresholds={thresholds}
        saving={saving}
        onApply={async (parameters, importedThresholds) => {
          const ok = await replaceConfiguration(parameters, importedThresholds);
          toast(ok
            ? {
              title: importedThresholds ? 'Matriz y umbrales importados' : 'Matriz importada',
              description: 'La configuración anterior quedó desactivada, no eliminada.',
            }
            : { title: 'No se pudo importar la matriz', description: error ?? 'Intenta nuevamente.', variant: 'destructive' });
          return ok;
        }}
      />

      <CriticalityBulkAssessmentDialog
        open={bulkOpen}
        onOpenChange={setBulkOpen}
        organizationName={currentOrganization.name}
        activeParameters={activeParameters}
        saving={saving}
        onPreview={previewBulk}
        onApply={applyBulk}
        onApplied={() => void refresh()}
      />

      {thresholds && (
        <CriticalityThresholdsDialog
          open={thresholdsDialogOpen}
          onOpenChange={setThresholdsDialogOpen}
          thresholds={thresholds}
          saving={thresholdsSaving}
          onSave={async (values) => {
            const saveError = await saveThresholds(values);
            if (!saveError) {
              toast({ title: 'Umbrales guardados', description: 'Se aplicarán a las evaluaciones nuevas.' });
            }
            return saveError;
          }}
        />
      )}

      <AlertDialog open={clearConfirmOpen} onOpenChange={(open) => !saving && setClearConfirmOpen(open)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Nueva matriz en blanco</AlertDialogTitle>
            <AlertDialogDescription>
              La configuración activa actual quedará desactivada. Las plantillas guardadas y las evaluaciones
              históricas no serán eliminadas. Hasta que configures nuevos parámetros no se podrán realizar
              nuevas evaluaciones de criticidad.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={saving}>Cancelar</AlertDialogCancel>
            <AlertDialogAction onClick={() => void handleClearActiveMatrix()} disabled={saving}>
              {saving ? 'Aplicando…' : 'Sí, crear matriz en blanco'}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}

function EmptyState({ message }: { message: string }) {
  return (
    <div className="p-6">
      <Card><CardContent className="flex min-h-56 flex-col items-center justify-center gap-3 text-center">
        <Gauge className="h-10 w-10 text-muted-foreground" />
        <p className="font-medium">{message}</p>
      </CardContent></Card>
    </div>
  );
}
