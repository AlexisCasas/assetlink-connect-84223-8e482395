import { useState, useEffect } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { RequestForm } from './RequestForm';
import { Request } from '@/types/request';
import { FileText, Edit, Trash2 } from 'lucide-react';
import { useToast } from '@/hooks/use-toast';

export const DraftList = () => {
  const { user } = useAuth();
  const { toast } = useToast();
  const [showForm, setShowForm] = useState(false);
  const [editingDraft, setEditingDraft] = useState<Request | undefined>();
  const [drafts, setDrafts] = useState<Request[]>([]);

  const loadDrafts = () => {
    const stored = localStorage.getItem('requests');
    if (stored) {
      const allRequests = JSON.parse(stored);
      setDrafts(allRequests.filter((r: Request) => r.createdBy === user?.email && r.status === 'draft'));
    }
  };

  useEffect(() => {
    loadDrafts();
  }, [user]);

  const handleSaveRequest = (request: Request, isDraft: boolean) => {
    const stored = localStorage.getItem('requests');
    const allRequests = stored ? JSON.parse(stored) : [];
    
    const existingIndex = allRequests.findIndex((r: Request) => r.id === request.id);
    if (existingIndex >= 0) {
      allRequests[existingIndex] = request;
    } else {
      allRequests.push(request);
    }
    
    localStorage.setItem('requests', JSON.stringify(allRequests));
    loadDrafts();
  };

  const handleDelete = (id: string) => {
    const stored = localStorage.getItem('requests');
    if (stored) {
      const allRequests = JSON.parse(stored);
      const filtered = allRequests.filter((r: Request) => r.id !== id);
      localStorage.setItem('requests', JSON.stringify(filtered));
      loadDrafts();
      toast({
        title: "Borrador eliminado",
        description: "El borrador ha sido eliminado correctamente",
      });
    }
  };

  const handleEdit = (draft: Request) => {
    setEditingDraft(draft);
    setShowForm(true);
  };

  const getServiceTypeColor = (type: string) => {
    const colors = {
      emergencia: 'bg-red-500/10 text-red-500 border-red-500/20',
      correctivo: 'bg-orange-500/10 text-orange-500 border-orange-500/20',
      preventivo: 'bg-blue-500/10 text-blue-500 border-blue-500/20',
      proyecto: 'bg-purple-500/10 text-purple-500 border-purple-500/20',
    };
    return colors[type as keyof typeof colors] || '';
  };

  const getServiceTypeText = (type: string) => {
    const texts = {
      emergencia: 'Emergencia',
      correctivo: 'Correctivo',
      preventivo: 'Preventivo',
      proyecto: 'Proyecto',
    };
    return texts[type as keyof typeof texts] || type;
  };

  return (
    <div className="p-6 space-y-6">
      <div className="flex justify-between items-center">
        <h2 className="text-2xl font-bold">Borradores</h2>
      </div>

      {drafts.length === 0 ? (
        <Card>
          <CardContent className="py-12 text-center">
            <FileText className="w-12 h-12 mx-auto mb-4 text-muted-foreground" />
            <p className="text-muted-foreground">No tienes borradores guardados</p>
          </CardContent>
        </Card>
      ) : (
        <div className="grid gap-4">
          {drafts.map((draft) => (
            <Card key={draft.id}>
              <CardHeader>
                <div className="flex justify-between items-start">
                  <div className="flex-1">
                    <div className="flex items-center gap-3">
                      <CardTitle className="text-lg">{draft.requestNumber}</CardTitle>
                      <Badge variant="outline">Borrador</Badge>
                    </div>
                    <p className="text-sm text-muted-foreground mt-1">{draft.description}</p>
                  </div>
                  <div className="flex gap-2">
                    <Button
                      variant="outline"
                      size="icon"
                      onClick={() => handleEdit(draft)}
                    >
                      <Edit className="w-4 h-4" />
                    </Button>
                    <Button
                      variant="outline"
                      size="icon"
                      onClick={() => handleDelete(draft.id)}
                    >
                      <Trash2 className="w-4 h-4" />
                    </Button>
                  </div>
                </div>
              </CardHeader>
              <CardContent className="space-y-3">
                <div className="flex items-center gap-4 text-sm">
                  <Badge className={getServiceTypeColor(draft.serviceType)}>
                    {getServiceTypeText(draft.serviceType)}
                  </Badge>
                  <span className="text-muted-foreground">
                    Creado: {new Date(draft.createdAt).toLocaleDateString()}
                  </span>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}

      {showForm && (
        <RequestForm
          onClose={() => {
            setShowForm(false);
            setEditingDraft(undefined);
          }}
          onSave={handleSaveRequest}
          editingRequest={editingDraft}
        />
      )}
    </div>
  );
};
