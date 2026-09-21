import { useState } from 'react';
import { Activity, Plus, RotateCcw, XCircle } from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { useAssetMeters } from '@/hooks/useAssetMeters';
import { useToast } from '@/hooks/use-toast';

interface Props { assetId: string; organizationId: string; canManage: boolean; }

const localNow = () => {
  const date = new Date();
  date.setMinutes(date.getMinutes() - date.getTimezoneOffset());
  return date.toISOString().slice(0, 16);
};

export function AssetMetersPanel({ assetId, organizationId, canManage }: Props) {
  const meterState = useAssetMeters(assetId, organizationId);
  const { toast } = useToast();
  const [createOpen, setCreateOpen] = useState(false);
  const [readingMeterId, setReadingMeterId] = useState<string | null>(null);
  const [name, setName] = useState('');
  const [unit, setUnit] = useState('horas');
  const [value, setValue] = useState('0');
  const [recordedAt, setRecordedAt] = useState(localNow());
  const [notes, setNotes] = useState('');

  const saveMeter = async () => {
    const ok = await meterState.createMeter(organizationId, name.trim(), unit.trim(), Number(value), new Date(recordedAt).toISOString());
    if (ok) { setCreateOpen(false); setName(''); toast({ title: 'Medidor creado' }); }
  };
  const saveReading = async () => {
    if (!readingMeterId) return;
    const ok = await meterState.recordReading(readingMeterId, Number(value), new Date(recordedAt).toISOString(), notes);
    if (ok) { setReadingMeterId(null); setNotes(''); toast({ title: 'Lectura registrada' }); }
  };

  const retire = async (meterId: string) => {
    const reason = window.prompt('Motivo obligatorio para retirar el medidor:');
    if (!reason) return;
    if (await meterState.retireMeter(meterId, reason)) toast({ title: 'Medidor retirado' });
  };

  const replace = async (meterId: string, currentName: string, currentUnit: string) => {
    const replacementName = window.prompt('Nombre del nuevo medidor:', currentName);
    if (!replacementName) return;
    const replacementUnit = window.prompt('Unidad del nuevo medidor:', currentUnit);
    if (!replacementUnit) return;
    const initial = window.prompt('Lectura inicial del nuevo medidor:', '0');
    if (initial === null) return;
    const reason = window.prompt('Motivo obligatorio del reemplazo:');
    if (!reason) return;
    if (await meterState.replaceMeter(meterId, replacementName, replacementUnit, Number(initial), new Date().toISOString(), reason)) {
      toast({ title: 'Medidor reemplazado', description: 'El medidor anterior y sus lecturas permanecen en el historial.' });
    }
  };

  const correct = async (readingId: string, current: number) => {
    const next = window.prompt('Valor corregido:', String(current));
    if (next === null) return;
    const reason = window.prompt('Motivo obligatorio de la corrección:');
    if (!reason) return;
    if (await meterState.correctReading(readingId, Number(next), reason)) toast({ title: 'Lectura corregida', description: 'La original permanece anulada en auditoría.' });
  };

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <div><h3 className="font-semibold">Medidores del activo</h3><p className="text-sm text-muted-foreground">Lecturas acumulativas; no se permite disminuir el mismo medidor.</p></div>
        {canManage && <Button size="sm" onClick={() => { setValue('0'); setRecordedAt(localNow()); setCreateOpen(true); }}><Plus className="mr-2 h-4 w-4" />Nuevo medidor</Button>}
      </div>
      {meterState.error && <p className="text-sm text-destructive">{meterState.error}</p>}
      {meterState.loading ? <p className="text-sm text-muted-foreground">Cargando medidores…</p> : meterState.meters.length === 0 ? (
        <p className="rounded-lg border border-dashed p-4 text-sm text-muted-foreground">Este activo todavía no tiene medidores.</p>
      ) : meterState.meters.map((meter) => (
        <Card key={meter.id}>
          <CardHeader className="pb-2"><div className="flex items-center justify-between gap-3"><CardTitle className="text-base"><Activity className="mr-2 inline h-4 w-4" />{meter.name} · {meter.unit}</CardTitle><Badge variant={meter.is_active ? 'default' : 'secondary'}>{meter.is_active ? 'Activo' : 'Retirado'}</Badge></div></CardHeader>
          <CardContent className="space-y-2">
            <div className="flex flex-wrap items-center gap-2">
              <span className="text-2xl font-semibold">{meter.readings[0]?.value ?? 'Sin lectura'}</span>
              {meter.readings[0] && <span className="text-xs text-muted-foreground">al {new Date(meter.readings[0].recorded_at).toLocaleString()}</span>}
              <div className="ml-auto flex gap-2">
                {meter.is_active && <Button size="sm" variant="outline" onClick={() => { setValue(String(meter.readings[0]?.value ?? 0)); setRecordedAt(localNow()); setReadingMeterId(meter.id); }}>Registrar</Button>}
                {canManage && meter.is_active && <Button size="sm" variant="ghost" onClick={() => void replace(meter.id, meter.name, meter.unit)}><RotateCcw className="mr-1 h-4 w-4" />Reemplazar</Button>}
                {canManage && meter.is_active && <Button size="sm" variant="ghost" onClick={() => void retire(meter.id)}><XCircle className="mr-1 h-4 w-4" />Retirar</Button>}
              </div>
            </div>
            {meter.readings.slice(0, 5).map((reading) => (
              <div key={reading.id} className="flex items-center justify-between border-t pt-2 text-sm"><span>{reading.value} {meter.unit} · {new Date(reading.recorded_at).toLocaleString()}</span>{canManage && <Button size="sm" variant="ghost" onClick={() => void correct(reading.id, reading.value)}><RotateCcw className="mr-1 h-3 w-3" />Corregir</Button>}</div>
            ))}
          </CardContent>
        </Card>
      ))}

      <Dialog open={createOpen} onOpenChange={setCreateOpen}><DialogContent><DialogHeader><DialogTitle>Nuevo medidor</DialogTitle></DialogHeader><div className="grid gap-3"><div><Label>Nombre</Label><Input value={name} onChange={(e) => setName(e.target.value)} placeholder="Horómetro" /></div><div><Label>Unidad</Label><Input value={unit} onChange={(e) => setUnit(e.target.value)} /></div><div><Label>Lectura inicial</Label><Input type="number" min="0" value={value} onChange={(e) => setValue(e.target.value)} /></div><div><Label>Fecha efectiva</Label><Input type="datetime-local" value={recordedAt} onChange={(e) => setRecordedAt(e.target.value)} /></div></div><DialogFooter><Button variant="outline" onClick={() => setCreateOpen(false)}>Cancelar</Button><Button disabled={!name.trim() || !unit.trim() || meterState.saving} onClick={() => void saveMeter()}>Crear</Button></DialogFooter></DialogContent></Dialog>
      <Dialog open={!!readingMeterId} onOpenChange={(open) => !open && setReadingMeterId(null)}><DialogContent><DialogHeader><DialogTitle>Registrar lectura</DialogTitle></DialogHeader><div className="grid gap-3"><div><Label>Valor acumulado</Label><Input type="number" min="0" value={value} onChange={(e) => setValue(e.target.value)} /></div><div><Label>Fecha efectiva</Label><Input type="datetime-local" value={recordedAt} onChange={(e) => setRecordedAt(e.target.value)} /></div><div><Label>Notas</Label><Textarea value={notes} onChange={(e) => setNotes(e.target.value)} /></div></div><DialogFooter><Button variant="outline" onClick={() => setReadingMeterId(null)}>Cancelar</Button><Button disabled={meterState.saving} onClick={() => void saveReading()}>Guardar lectura</Button></DialogFooter></DialogContent></Dialog>
    </div>
  );
}
