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
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { Badge } from '@/components/ui/badge';
import { toast } from 'sonner';
import { Plus, Pencil, Trash2, Users, Phone, Mail, Briefcase, Tag } from 'lucide-react';

interface ApprovedProvider {
  id: string;
  client_email: string;
  name: string;
  email: string;
  phone: string | null;
  specialty: string | null;
  created_at: string;
}

interface ClientSpecialty {
  id: string;
  client_email: string;
  name: string;
  created_at: string;
}

export const ApprovedProvidersList = () => {
  const { user } = useAuth();
  const [providers, setProviders] = useState<ApprovedProvider[]>([]);
  const [specialties, setSpecialties] = useState<ClientSpecialty[]>([]);
  const [loading, setLoading] = useState(true);
  const [showDialog, setShowDialog] = useState(false);
  const [showSpecialtyDialog, setShowSpecialtyDialog] = useState(false);
  const [editingProvider, setEditingProvider] = useState<ApprovedProvider | null>(null);
  const [newSpecialtyName, setNewSpecialtyName] = useState('');
  const [formData, setFormData] = useState({
    name: '',
    email: '',
    phone: '',
    specialty: '',
  });

  useEffect(() => {
    loadData();
  }, [user]);

  const loadData = async () => {
    if (!user?.email) return;
    
    try {
      const [providersResult, specialtiesResult] = await Promise.all([
        supabase
          .from('client_approved_providers')
          .select('*')
          .eq('client_email', user.email)
          .order('created_at', { ascending: false }),
        supabase
          .from('client_specialties')
          .select('*')
          .eq('client_email', user.email)
          .order('name', { ascending: true }),
      ]);

      if (providersResult.error) throw providersResult.error;
      if (specialtiesResult.error) throw specialtiesResult.error;
      
      setProviders(providersResult.data || []);
      setSpecialties(specialtiesResult.data || []);
    } catch (error) {
      console.error('Error loading data:', error);
      toast.error('Error al cargar datos');
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
            specialty: formData.specialty || null,
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
            specialty: formData.specialty || null,
          });

        if (error) throw error;
        toast.success('Proveedor agregado');
      }

      handleCloseDialog();
      loadData();
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
      loadData();
    } catch (error) {
      console.error('Error deleting provider:', error);
      toast.error('Error al eliminar proveedor');
    }
  };

  const handleAddSpecialty = async () => {
    if (!newSpecialtyName.trim()) {
      toast.error('Ingrese un nombre para la especialidad');
      return;
    }

    try {
      const { error } = await supabase
        .from('client_specialties')
        .insert({
          client_email: user?.email,
          name: newSpecialtyName.trim(),
        });

      if (error) {
        if (error.code === '23505') {
          toast.error('Esta especialidad ya existe');
        } else {
          throw error;
        }
        return;
      }

      toast.success('Especialidad agregada');
      setNewSpecialtyName('');
      loadData();
    } catch (error) {
      console.error('Error adding specialty:', error);
      toast.error('Error al agregar especialidad');
    }
  };

  const handleDeleteSpecialty = async (id: string, name: string) => {
    if (!confirm(`¿Está seguro de eliminar la especialidad "${name}"?`)) return;

    try {
      const { error } = await supabase
        .from('client_specialties')
        .delete()
        .eq('id', id);

      if (error) throw error;
      toast.success('Especialidad eliminada');
      loadData();
    } catch (error) {
      console.error('Error deleting specialty:', error);
      toast.error('Error al eliminar especialidad');
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
        <div className="flex gap-2">
          <Button variant="outline" onClick={() => setShowSpecialtyDialog(true)}>
            <Tag className="h-4 w-4 mr-2" />
            Gestionar Especialidades
          </Button>
          <Button onClick={() => handleOpenDialog()}>
            <Plus className="h-4 w-4 mr-2" />
            Agregar Proveedor
          </Button>
        </div>
      </div>

      {/* Specialty badges */}
      {specialties.length > 0 && (
        <div className="flex flex-wrap gap-2">
          <span className="text-sm text-muted-foreground">Especialidades:</span>
          {specialties.map((specialty) => (
            <Badge key={specialty.id} variant="secondary">
              {specialty.name}
            </Badge>
          ))}
        </div>
      )}

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
                        <Badge variant="outline">
                          <Briefcase className="h-3 w-3 mr-1" />
                          {provider.specialty}
                        </Badge>
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

      {/* Dialog para agregar/editar proveedor */}
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
              {specialties.length > 0 ? (
                <Select
                  value={formData.specialty}
                  onValueChange={(value) => setFormData({ ...formData, specialty: value })}
                >
                  <SelectTrigger>
                    <SelectValue placeholder="Selecciona una especialidad" />
                  </SelectTrigger>
                  <SelectContent className="bg-popover">
                    <SelectItem value="">Sin especialidad</SelectItem>
                    {specialties.map((specialty) => (
                      <SelectItem key={specialty.id} value={specialty.name}>
                        {specialty.name}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              ) : (
                <div className="text-sm text-muted-foreground p-3 border rounded-md">
                  No hay especialidades definidas. 
                  <Button
                    variant="link"
                    className="px-1 h-auto"
                    onClick={() => {
                      setShowDialog(false);
                      setShowSpecialtyDialog(true);
                    }}
                  >
                    Agregar especialidades
                  </Button>
                </div>
              )}
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

      {/* Dialog para gestionar especialidades */}
      <Dialog open={showSpecialtyDialog} onOpenChange={setShowSpecialtyDialog}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Tag className="h-5 w-5" />
              Gestionar Especialidades
            </DialogTitle>
          </DialogHeader>
          <div className="space-y-4 py-4">
            <div className="flex gap-2">
              <Input
                placeholder="Nueva especialidad..."
                value={newSpecialtyName}
                onChange={(e) => setNewSpecialtyName(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === 'Enter') {
                    e.preventDefault();
                    handleAddSpecialty();
                  }
                }}
              />
              <Button onClick={handleAddSpecialty}>
                <Plus className="h-4 w-4" />
              </Button>
            </div>

            {specialties.length === 0 ? (
              <p className="text-center text-muted-foreground py-4">
                No hay especialidades definidas
              </p>
            ) : (
              <div className="space-y-2 max-h-64 overflow-y-auto">
                {specialties.map((specialty) => (
                  <div
                    key={specialty.id}
                    className="flex items-center justify-between p-2 border rounded-md"
                  >
                    <span>{specialty.name}</span>
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => handleDeleteSpecialty(specialty.id, specialty.name)}
                      className="text-destructive hover:text-destructive h-8 w-8 p-0"
                    >
                      <Trash2 className="h-4 w-4" />
                    </Button>
                  </div>
                ))}
              </div>
            )}
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setShowSpecialtyDialog(false)}>
              Cerrar
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
};
