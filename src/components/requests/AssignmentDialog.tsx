import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Request, MOCK_PROVIDERS, Assignment } from '@/types/request';
import { X } from 'lucide-react';
import { useToast } from '@/hooks/use-toast';

interface AssignmentDialogProps {
  request: Request;
  providerId: string;
  onClose: () => void;
  onAssign: (assignment: Assignment) => void;
}

export const AssignmentDialog = ({ request, providerId, onClose, onAssign }: AssignmentDialogProps) => {
  const { toast } = useToast();
  const provider = MOCK_PROVIDERS.find(p => p.id === providerId);
  const currentAssignment = request.assignments?.[providerId];
  
  const [selectedMember, setSelectedMember] = useState('');
  const [deadline, setDeadline] = useState('');
  const [reason, setReason] = useState('');

  const handleAssign = () => {
    if (!selectedMember || !deadline) {
      toast({
        title: "Error",
        description: "Por favor completa todos los campos",
        variant: "destructive",
      });
      return;
    }

    if (currentAssignment && !reason) {
      toast({
        title: "Error",
        description: "Debes proporcionar una razón para la reasignación",
        variant: "destructive",
      });
      return;
    }

    const member = provider?.team?.find(m => m.id === selectedMember);
    if (!member) return;

    const assignment: Assignment = {
      teamMemberId: member.id,
      teamMemberName: member.name,
      assignedAt: new Date().toISOString(),
      maxDeadline: deadline,
      reason: currentAssignment ? reason : undefined,
    };

    onAssign(assignment);
    toast({
      title: currentAssignment ? "Reasignado exitosamente" : "Asignado exitosamente",
      description: `Solicitud asignada a ${member.name}`,
    });
    onClose();
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
          {currentAssignment && (
            <div className="p-3 bg-muted rounded-lg">
              <p className="text-sm text-muted-foreground">Actualmente asignado a:</p>
              <p className="font-medium">{currentAssignment.teamMemberName}</p>
            </div>
          )}

          <div className="space-y-2">
            <Label>Miembro del equipo *</Label>
            <Select value={selectedMember} onValueChange={setSelectedMember}>
              <SelectTrigger>
                <SelectValue placeholder="Seleccionar miembro" />
              </SelectTrigger>
              <SelectContent>
                {provider?.team?.map((member) => (
                  <SelectItem key={member.id} value={member.id}>
                    {member.name} ({member.email})
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          <div className="space-y-2">
            <Label>Fecha límite para enviar cotización *</Label>
            <Input
              type="datetime-local"
              value={deadline}
              onChange={(e) => setDeadline(e.target.value)}
            />
          </div>

          {currentAssignment && (
            <div className="space-y-2">
              <Label>Razón de la reasignación *</Label>
              <Textarea
                value={reason}
                onChange={(e) => setReason(e.target.value)}
                placeholder="Explica por qué se está reasignando esta solicitud"
                rows={3}
              />
            </div>
          )}

          <div className="flex gap-3 justify-end pt-4 border-t">
            <Button variant="outline" onClick={onClose}>
              Cancelar
            </Button>
            <Button onClick={handleAssign}>
              {currentAssignment ? 'Reasignar' : 'Asignar'}
            </Button>
          </div>
        </CardContent>
      </Card>
    </div>
  );
};
