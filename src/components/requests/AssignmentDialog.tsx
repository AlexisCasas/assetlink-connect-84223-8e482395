import { useState, useEffect } from 'react';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Checkbox } from '@/components/ui/checkbox';
import { Request, Assignment } from '@/types/request';
import { X } from 'lucide-react';
import { useToast } from '@/hooks/use-toast';
import { supabase } from '@/integrations/supabase/client';

interface AssignmentDialogProps {
  request: Request;
  providerId: string;
  onClose: () => void;
  onAssign: (assignment: Assignment) => void;
}

export const AssignmentDialog = ({ request, providerId, onClose, onAssign }: AssignmentDialogProps) => {
  const { toast } = useToast();
  const currentAssignment = request.assignments?.[providerId];
  
  const [selectedMember, setSelectedMember] = useState('');
  const [deadline, setDeadline] = useState('');
  const [reason, setReason] = useState('');
  const [isSubcontractor, setIsSubcontractor] = useState(false);
  const [subcontractorName, setSubcontractorName] = useState('');
  const [subcontractorEmail, setSubcontractorEmail] = useState('');
  const [teamMembers, setTeamMembers] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetchTeamMembers();
  }, [providerId]);

  const fetchTeamMembers = async () => {
    try {
      setLoading(true);
      const { data, error } = await supabase
        .from('team_members')
        .select('*')
        .eq('provider_id', providerId);

      if (error) throw error;
      setTeamMembers(data || []);
    } catch (error) {
      console.error('Error fetching team members:', error);
      toast({
        title: "Error",
        description: "No se pudieron cargar los miembros del equipo",
        variant: "destructive",
      });
    } finally {
      setLoading(false);
    }
  };

  const handleAssign = async () => {
    if (isSubcontractor) {
      if (!subcontractorName || !subcontractorEmail || !deadline) {
        toast({
          title: "Error",
          description: "Por favor completa todos los campos del subcontratista",
          variant: "destructive",
        });
        return;
      }

      try {
        const { data: newMember, error } = await supabase
          .from('team_members')
          .insert({
            name: `${subcontractorName} (Subcontratista)`,
            email: subcontractorEmail,
            provider_id: providerId,
          })
          .select()
          .single();

        if (error) throw error;

        const assignment: Assignment = {
          teamMemberId: newMember.id,
          teamMemberName: newMember.name,
          assignedAt: new Date().toISOString(),
          maxDeadline: deadline,
          reason: reason || undefined,
        };

        const { error: assignError } = await supabase
          .from('assignments')
          .insert({
            request_id: request.id,
            provider_id: providerId,
            team_member_id: newMember.id,
            team_member_name: newMember.name,
            max_deadline: deadline,
            reason: reason || null,
          });

        if (assignError) throw assignError;

        onAssign(assignment);
        toast({
          title: "Asignado exitosamente",
          description: `Solicitud asignada al subcontratista ${subcontractorName}`,
        });
        onClose();
      } catch (error) {
        console.error('Error creating subcontractor assignment:', error);
        toast({
          title: "Error",
          description: "No se pudo crear la asignación al subcontratista",
          variant: "destructive",
        });
      }
    } else {
      if (!selectedMember || !deadline) {
        toast({
          title: "Error",
          description: "Por favor completa todos los campos obligatorios",
          variant: "destructive",
        });
        return;
      }

      const member = teamMembers.find(m => m.id === selectedMember);
      if (!member) return;

      const assignment: Assignment = {
        teamMemberId: selectedMember,
        teamMemberName: member.name,
        assignedAt: new Date().toISOString(),
        maxDeadline: deadline,
        reason: reason || undefined,
      };

      try {
        const { error } = await supabase
          .from('assignments')
          .insert({
            request_id: request.id,
            provider_id: providerId,
            team_member_id: selectedMember,
            team_member_name: member.name,
            max_deadline: deadline,
            reason: reason || null,
          });

        if (error) throw error;

        onAssign(assignment);
        toast({
          title: currentAssignment ? "Reasignado exitosamente" : "Asignado exitosamente",
          description: `Solicitud asignada a ${member.name}`,
        });
        onClose();
      } catch (error) {
        console.error('Error creating assignment:', error);
        toast({
          title: "Error",
          description: "No se pudo crear la asignación",
          variant: "destructive",
        });
      }
    }
  };

  return (
    <div className="fixed inset-0 bg-background/80 backdrop-blur-sm z-50 flex items-center justify-center p-4">
      <Card className="w-full max-w-md">
        <CardHeader className="flex flex-row items-center justify-between">
          <CardTitle>
            {currentAssignment ? 'Reasignar solicitud' : 'Asignar a equipo'}
          </CardTitle>
          <Button variant="ghost" size="icon" onClick={onClose}>
            <X className="w-4 h-4" />
          </Button>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="p-4 bg-muted rounded-lg space-y-2">
            <h3 className="font-medium">Detalles de la solicitud</h3>
            <p className="text-sm text-muted-foreground">{request.description}</p>
            <div className="grid grid-cols-2 gap-2 text-sm">
              <div>
                <span className="text-muted-foreground">Activo:</span>
                <span className="ml-2 font-medium">{request.asset}</span>
              </div>
              <div>
                <span className="text-muted-foreground">Ubicación:</span>
                <span className="ml-2 font-medium">{request.location}</span>
              </div>
            </div>
          </div>

          {loading ? (
            <div className="flex justify-center py-4">
              <div className="animate-spin rounded-full h-6 w-6 border-b-2 border-primary"></div>
            </div>
          ) : (
            <>
              {!isSubcontractor && (
                <div className="space-y-2">
                  <Label htmlFor="member">Asignar a miembro del equipo *</Label>
                  <Select value={selectedMember} onValueChange={setSelectedMember}>
                    <SelectTrigger>
                      <SelectValue placeholder="Selecciona un miembro del equipo" />
                    </SelectTrigger>
                    <SelectContent>
                      {teamMembers.map((member) => (
                        <SelectItem key={member.id} value={member.id}>
                          {member.name} - {member.email}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
              )}

              <div className="flex items-center space-x-2 p-3 border rounded-lg">
                <Checkbox
                  id="subcontractor"
                  checked={isSubcontractor}
                  onCheckedChange={(checked) => {
                    setIsSubcontractor(checked as boolean);
                    setSelectedMember('');
                  }}
                />
                <Label htmlFor="subcontractor" className="cursor-pointer">
                  Asignar el trabajo a un subcontratista
                </Label>
              </div>

              {isSubcontractor && (
                <div className="space-y-3 p-4 border rounded-lg bg-muted/50">
                  <h4 className="font-medium">Datos del subcontratista</h4>
                  <div className="space-y-2">
                    <Label htmlFor="subcontractor-name">Nombre completo *</Label>
                    <Input
                      id="subcontractor-name"
                      value={subcontractorName}
                      onChange={(e) => setSubcontractorName(e.target.value)}
                      placeholder="Nombre del subcontratista"
                    />
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="subcontractor-email">Email *</Label>
                    <Input
                      id="subcontractor-email"
                      type="email"
                      value={subcontractorEmail}
                      onChange={(e) => setSubcontractorEmail(e.target.value)}
                      placeholder="email@ejemplo.com"
                    />
                  </div>
                </div>
              )}

              <div className="space-y-2">
                <Label htmlFor="deadline">Fecha máxima de entrega de cotización *</Label>
                <Input
                  id="deadline"
                  type="datetime-local"
                  value={deadline}
                  onChange={(e) => setDeadline(e.target.value)}
                  required
                />
              </div>

              {currentAssignment && (
                <div className="space-y-2">
                  <Label htmlFor="reason">Razón de la reasignación</Label>
                  <Textarea
                    id="reason"
                    value={reason}
                    onChange={(e) => setReason(e.target.value)}
                    placeholder="Explica por qué se está reasignando esta solicitud"
                    rows={3}
                  />
                </div>
              )}
            </>
          )}

          <div className="flex gap-3 justify-end pt-4 border-t">
            <Button variant="outline" onClick={onClose}>
              Cancelar
            </Button>
            <Button onClick={handleAssign} disabled={loading}>
              {currentAssignment ? 'Reasignar' : 'Asignar'}
            </Button>
          </div>
        </CardContent>
      </Card>
    </div>
  );
};
