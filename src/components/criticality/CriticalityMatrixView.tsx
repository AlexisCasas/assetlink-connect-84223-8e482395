import { useState } from 'react';
import { Gauge, Plus, Pencil, EyeOff, Eye, AlertTriangle, ListChecks } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { useCriticalityMatrix } from '@/hooks/useCriticalityMatrix';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { useToast } from '@/hooks/use-toast';
import { CriticalityParameterDialog } from './CriticalityParameterDialog';
import { CriticalityOptionDialog } from './CriticalityOptionDialog';
import type { CriticalityOption, CriticalityOptionInput, CriticalityParameter, CriticalityParameterInput } from '@/types/criticalityMatrix';

export function CriticalityMatrixView() {
  const { currentOrganization } = useAuth();
  const {
    matrix,
    totalActiveWeight,
    loading,
    saving,
    error,
    saveParameter,
    saveOption,
    toggleParameterActive,
    toggleOptionActive,
  } = useCriticalityMatrix(currentOrganization?.id);
  const { toast } = useToast();

  const [parameterDialogOpen, setParameterDialogOpen] = useState(false);
  const [editingParameter, setEditingParameter] = useState<CriticalityParameter | null>(null);
  const [optionDialogOpen, setOptionDialogOpen] = useState(false);
  const [editingOption, setEditingOption] = useState<CriticalityOption | null>(null);
  const [optionParameter, setOptionParameter] = useState<CriticalityParameter | null>(null);

  if (!currentOrganization) {
    return <EmptyState message="Sin organización asignada" />;
  }

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
        <Button onClick={openCreateParameter} disabled={loading}>
          <Plus className="mr-2 h-4 w-4" /> Crear parámetro
        </Button>
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
                  <CardTitle className="flex items-center gap-2 text-base">
                    <ListChecks className="h-4 w-4 text-muted-foreground" /> {parameter.name}
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
