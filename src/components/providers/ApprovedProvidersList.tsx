import { useState, useEffect } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from '@/components/ui/dialog';
import { toast } from 'sonner';
import { Plus, Pencil, Trash2, Users, Phone, Mail, Briefcase } from 'lucide-react';

interface ApprovedProvider {
  id: string;
  client_email: string;
  name: string;
  email: string;
  phone: string | null;
  specialty: string | null;
  created_at: string;
}

export const ApprovedProvidersList = () => {
  const { user } = useAuth();
  const [providers, setProviders] = useState<ApprovedProvider[]>([]);
  const [loading, setLoading] = useState(true);
  const [showDialog, setShowDialog] = useState(false);
  const [editingProvider, setEditingProvider] = useState<ApprovedProvider | null>(null);
  const [formData, setFormData] = useState({
    name: '',
    email: '',
    phone: '',
    specialty: '',
  });

  useEffect(() => {
    loadProviders();
  }, [user]);

  const loadProviders = async () => {
    if (!user?.email) return;
    
    try {
      const { data, error } = await supabase
        .from('client_approved_providers')
        .select('*')
        .eq('client_email', user.email)
        .order('created_at', { ascending: false });

      if (error) throw error;
      setProviders(data || []);
    } catch (error) {
      console.error('Error loading providers:', error);
      toast.error('Error al cargar proveedores');
    } finally {
      setLoading(false);
    }
  };

  const handleOpenDialog = (provider?: ApprovedProvider) => {
    if (provider) {
      setEditingProvider(provider);
      setFormData({
        name: provider.name,
        email: provider.email,
        phone: provider.phone || '',
        specialty: provider.specialty || '',
      });
    } else {
      setEditingProvider(null);
      setFormData({ name: '', email: '', phone: '', specialty: '' });
    }
    setShowDialog(true);
  };

  const handleCloseDialog = () => {
    setShowDialog(false);
    setEditingProvider(null);
    setFormData({ name: '', email: '', phone: '', specialty: '' });
  };

  const handleSubmit = async () => {
    if (!formData.name.trim() || !formData.email.trim()) {
      toast.error('Nombre y correo son obligatorios');
      return;
    }

    try {
      if (editingProvider) {
        const { error } = await supabase
          .from('client_approved_providers')
          .update({
            name: formData.name.trim(),
            email: formData.email.trim(),
            phone: formData.phone.trim() || null,
            specialty: formData.specialty.trim() || null,
            updated_at: new Date().toISOString(),
          })
          .eq('id', editingProvider.id);

        if (error) throw error;
        toast.success('Proveedor actualizado');
      } else {
        const { error } = await supabase
          .from('client_approved_providers')
          .insert({
            client_email: user?.email,
            name: formData.name.trim(),
            email: formData.email.trim(),
            phone: formData.phone.trim() || null,
            specialty: formData.specialty.trim() || null,
          });

        if (error) throw error;
        toast.success('Proveedor agregado');
      }

      handleCloseDialog();
      loadProviders();
    } catch (error) {
      console.error('Error saving provider:', error);
      toast.error('Error al guardar proveedor');
    }
  };

  const handleDelete = async (id: string) => {
    if (!confirm('¿Está seguro de eliminar este proveedor?')) return;

    try {
      const { error } = await supabase
        .from('client_approved_providers')
        .delete()
        .eq('id', id);

      if (error) throw error;
      toast.success('Proveedor eliminado');
      loadProviders();
    } catch (error) {
      console.error('Error deleting provider:', error);
      toast.error('Error al eliminar proveedor');
    }
  };

  if (loading) {
    return (
      <div className="p-6">
        <div className="animate-pulse space-y-4">
          <div className="h-8 bg-muted rounded w-1/3"></div>
          <div className="h-64 bg-muted rounded"></div>
        </div>
      </div>
    );
  }

  return (
    <div className="p-6 space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold flex items-center gap-3">
            <Users className="h-8 w-8 text-primary" />
            Proveedores Homologados
          </h1>
          <p className="text-muted-foreground mt-1">
            Gestiona tu lista de proveedores aprobados
          </p>
        </div>
        <Button onClick={() => handleOpenDialog()}>
          <Plus className="h-4 w-4 mr-2" />
          Agregar Proveedor
        </Button>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-lg">Lista de Proveedores ({providers.length})</CardTitle>
        </CardHeader>
        <CardContent>
          {providers.length === 0 ? (
            <div className="text-center py-12 text-muted-foreground">
              <Users className="h-12 w-12 mx-auto mb-4 opacity-50" />
              <p>No tienes proveedores homologados registrados</p>
              <Button variant="outline" className="mt-4" onClick={() => handleOpenDialog()}>
                <Plus className="h-4 w-4 mr-2" />
                Agregar tu primer proveedor
              </Button>
            </div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Nombre</TableHead>
                  <TableHead>Correo</TableHead>
                  <TableHead>Celular</TableHead>
                  <TableHead>Especialidad</TableHead>
                  <TableHead className="text-right">Acciones</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {providers.map((provider) => (
                  <TableRow key={provider.id}>
                    <TableCell className="font-medium">{provider.name}</TableCell>
                    <TableCell>
                      <div className="flex items-center gap-2">
                        <Mail className="h-4 w-4 text-muted-foreground" />
                        {provider.email}
                      </div>
                    </TableCell>
                    <TableCell>
                      {provider.phone ? (
                        <div className="flex items-center gap-2">
                          <Phone className="h-4 w-4 text-muted-foreground" />
                          {provider.phone}
                        </div>
                      ) : (
                        <span className="text-muted-foreground">-</span>
                      )}
                    </TableCell>
                    <TableCell>
                      {provider.specialty ? (
                        <div className="flex items-center gap-2">
                          <Briefcase className="h-4 w-4 text-muted-foreground" />
                          {provider.specialty}
                        </div>
                      ) : (
                        <span className="text-muted-foreground">-</span>
                      )}
                    </TableCell>
                    <TableCell className="text-right">
                      <div className="flex justify-end gap-2">
                        <Button
                          variant="outline"
                          size="sm"
                          onClick={() => handleOpenDialog(provider)}
                        >
                          <Pencil className="h-4 w-4" />
                        </Button>
                        <Button
                          variant="outline"
                          size="sm"
                          onClick={() => handleDelete(provider.id)}
                          className="text-destructive hover:text-destructive"
                        >
                          <Trash2 className="h-4 w-4" />
                        </Button>
                      </div>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>

      {/* Dialog para agregar/editar */}
      <Dialog open={showDialog} onOpenChange={setShowDialog}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>
              {editingProvider ? 'Editar Proveedor' : 'Agregar Proveedor'}
            </DialogTitle>
          </DialogHeader>
          <div className="space-y-4 py-4">
            <div className="space-y-2">
              <Label htmlFor="name">Nombre *</Label>
              <Input
                id="name"
                value={formData.name}
                onChange={(e) => setFormData({ ...formData, name: e.target.value })}
                placeholder="Nombre del proveedor"
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="email">Correo electrónico *</Label>
              <Input
                id="email"
                type="email"
                value={formData.email}
                onChange={(e) => setFormData({ ...formData, email: e.target.value })}
                placeholder="correo@ejemplo.com"
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="phone">Celular</Label>
              <Input
                id="phone"
                value={formData.phone}
                onChange={(e) => setFormData({ ...formData, phone: e.target.value })}
                placeholder="+51 999 999 999"
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="specialty">Especialidad</Label>
              <Input
                id="specialty"
                value={formData.specialty}
                onChange={(e) => setFormData({ ...formData, specialty: e.target.value })}
                placeholder="Ej: Electricidad, Plomería, etc."
              />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={handleCloseDialog}>
              Cancelar
            </Button>
            <Button onClick={handleSubmit}>
              {editingProvider ? 'Guardar Cambios' : 'Agregar'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
};
