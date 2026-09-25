import { useState } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Badge } from '@/components/ui/badge';
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter,
} from '@/components/ui/dialog';
import {
  Table, TableBody, TableCell, TableHead, TableHeader, TableRow,
} from '@/components/ui/table';
import { Plus, Pencil, Power } from 'lucide-react';
import { useToast } from '@/hooks/use-toast';
import { ClientBranch } from '@/types/request';
import { useBranches } from '@/hooks/useBranches';

export const BranchesList = () => {
  const { currentOrganization, currentMembership } = useAuth();
  const { toast } = useToast();
  const [dialogOpen, setDialogOpen] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [form, setForm] = useState({ name: '', city: '', site: '', address: '' });

  const {
    branches,
    loading,
    error,
    canManageBranches,
    createBranch,
    updateBranch,
    setBranchActive,
  } = useBranches(currentOrganization?.id, currentMembership?.role);

  const openNew = () => {
    setEditingId(null);
    setForm({ name: '', city: '', site: '', address: '' });
    setDialogOpen(true);
  };

  const openEdit = (b: ClientBranch) => {
    setEditingId(b.id);
    setForm({ name: b.name, city: b.city, site: b.site, address: b.address || '' });
    setDialogOpen(true);
  };

  const save = async () => {
    if (!form.name.trim() || !form.city.trim() || !form.site.trim()) {
      toast({ title: 'Datos incompletos', description: 'Nombre, Ciudad y Sede son obligatorios', variant: 'destructive' });
      return;
    }
    const branchData = {
      name: form.name.trim(), city: form.city.trim(), site: form.site.trim(), address: form.address.trim() || undefined,
    };
    if (editingId) {
      const { error } = await updateBranch(editingId, branchData);
      if (error) { toast({ title: 'Error', description: error, variant: 'destructive' }); return; }
      toast({ title: 'Sucursal actualizada' });
    } else {
      const { error } = await createBranch(branchData);
      if (error) { toast({ title: 'Error', description: error, variant: 'destructive' }); return; }
      toast({ title: 'Sucursal creada' });
    }
    setDialogOpen(false);
  };

  const toggleActive = async (b: ClientBranch) => {
    const { error } = await setBranchActive(b.id, !b.isActive);
    if (error) { toast({ title: 'Error', description: error, variant: 'destructive' }); return; }
    toast({ title: b.isActive ? 'Sucursal desactivada' : 'Sucursal activada' });
  };

  return (
    <div className="p-6 space-y-6">
      <div className="flex justify-between items-center">
        <h2 className="text-2xl font-bold">Sucursales</h2>
        {canManageBranches && (
          <Button onClick={openNew}>
            <Plus className="w-4 h-4 mr-2" /> Nueva sucursal
          </Button>
        )}
      </div>

      <Card>
        <CardContent className="p-0">
          {!currentOrganization ? (
            <p className="p-8 text-center text-muted-foreground">Selecciona una organización para administrar sucursales</p>
          ) : loading ? (
            <p className="p-8 text-center text-muted-foreground">Cargando...</p>
          ) : error ? (
            <p className="p-8 text-center text-destructive">No se pudieron cargar las sucursales: {error}</p>
          ) : branches.length === 0 ? (
            <p className="p-8 text-center text-muted-foreground">Aún no tienes sucursales registradas</p>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Nombre</TableHead>
                  <TableHead>Ciudad</TableHead>
                  <TableHead>Sede</TableHead>
                  <TableHead>Dirección</TableHead>
                  <TableHead>Estado</TableHead>
                  {canManageBranches && <TableHead className="text-right">Acciones</TableHead>}
                </TableRow>
              </TableHeader>
              <TableBody>
                {branches.map(b => (
                  <TableRow key={b.id}>
                    <TableCell className="font-medium">{b.name}</TableCell>
                    <TableCell>{b.city}</TableCell>
                    <TableCell>{b.site}</TableCell>
                    <TableCell className="text-muted-foreground">{b.address || '-'}</TableCell>
                    <TableCell>
                      <Badge variant={b.isActive ? 'default' : 'secondary'}>
                        {b.isActive ? 'Activa' : 'Inactiva'}
                      </Badge>
                    </TableCell>
                    {canManageBranches && (
                      <TableCell className="text-right">
                        <Button variant="ghost" size="icon" onClick={() => openEdit(b)} title="Editar">
                          <Pencil className="w-4 h-4" />
                        </Button>
                        <Button variant="ghost" size="icon" onClick={() => toggleActive(b)} title={b.isActive ? 'Desactivar' : 'Activar'}>
                          <Power className="w-4 h-4" />
                        </Button>
                      </TableCell>
                    )}
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>

      <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{editingId ? 'Editar sucursal' : 'Nueva sucursal'}</DialogTitle>
          </DialogHeader>
          <div className="space-y-4 py-2">
            <div className="space-y-2">
              <Label>Nombre *</Label>
              <Input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} maxLength={120} />
            </div>
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label>Ciudad *</Label>
                <Input value={form.city} onChange={(e) => setForm({ ...form, city: e.target.value })} maxLength={80} />
              </div>
              <div className="space-y-2">
                <Label>Sede *</Label>
                <Input value={form.site} onChange={(e) => setForm({ ...form, site: e.target.value })} maxLength={80} />
              </div>
            </div>
            <div className="space-y-2">
              <Label>Dirección</Label>
              <Input value={form.address} onChange={(e) => setForm({ ...form, address: e.target.value })} maxLength={200} />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setDialogOpen(false)}>Cancelar</Button>
            <Button onClick={save}>{editingId ? 'Guardar cambios' : 'Crear sucursal'}</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
};
