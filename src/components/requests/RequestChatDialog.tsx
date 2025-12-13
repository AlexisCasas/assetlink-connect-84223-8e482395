import { useState } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Textarea } from '@/components/ui/textarea';
import { ScrollArea } from '@/components/ui/scroll-area';
import { Send, User } from 'lucide-react';
import { useToast } from '@/hooks/use-toast';
import { useRequestChatMessages } from '@/hooks/useRequestChatMessages';
import { useAuth } from '@/contexts/AuthContext';

interface RequestChatDialogProps {
  open: boolean;
  onClose: () => void;
  requestId: string;
  requestNumber: string;
}

export const RequestChatDialog = ({ open, onClose, requestId, requestNumber }: RequestChatDialogProps) => {
  const { user } = useAuth();
  const [newMessage, setNewMessage] = useState('');
  const [sending, setSending] = useState(false);
  const { toast } = useToast();
  
  const { messages, loading, sendMessage } = useRequestChatMessages(
    requestId, 
    user?.email || ''
  );

  const handleSendMessage = async () => {
    if (!newMessage.trim() || !user) return;

    try {
      setSending(true);
      const senderType = user.role === 'cliente' ? 'client' : 
                         user.role === 'proveedor' ? 'provider' : 'team_member';
      
      const result = await sendMessage(newMessage, user.name || user.email, senderType);
      
      if (result.success) {
        setNewMessage('');
      } else {
        throw result.error;
      }
    } catch (error) {
      console.error('Error sending message:', error);
      toast({
        title: 'Error',
        description: 'No se pudo enviar el mensaje.',
        variant: 'destructive',
      });
    } finally {
      setSending(false);
    }
  };

  const getSenderColor = (senderType: string) => {
    switch (senderType) {
      case 'client':
        return 'bg-primary text-primary-foreground';
      case 'provider':
        return 'bg-secondary text-secondary-foreground';
      default:
        return 'bg-muted text-muted-foreground';
    }
  };

  const getSenderLabel = (senderType: string) => {
    switch (senderType) {
      case 'client':
        return 'Cliente';
      case 'provider':
        return 'Proveedor';
      default:
        return 'Equipo';
    }
  };

  return (
    <Dialog open={open} onOpenChange={onClose}>
      <DialogContent className="max-w-2xl max-h-[600px] flex flex-col">
        <DialogHeader>
          <DialogTitle>Chat - Solicitud {requestNumber}</DialogTitle>
        </DialogHeader>

        <ScrollArea className="flex-1 pr-4 min-h-[300px]">
          <div className="space-y-4">
            {loading ? (
              <p className="text-center text-muted-foreground py-8">
                Cargando mensajes...
              </p>
            ) : messages.length === 0 ? (
              <p className="text-center text-muted-foreground py-8">
                No hay mensajes aún. Inicia la conversación con los proveedores.
              </p>
            ) : (
              messages.map((msg) => {
                const isCurrentUser = msg.sender_email === user?.email;
                return (
                  <div
                    key={msg.id}
                    className={`flex ${isCurrentUser ? 'justify-end' : 'justify-start'}`}
                  >
                    <div
                      className={`max-w-[70%] rounded-lg p-3 ${getSenderColor(msg.sender_type)}`}
                    >
                      <div className="flex items-center gap-2 mb-1">
                        <User className="h-3 w-3" />
                        <span className="text-xs font-medium">
                          {msg.sender_name || msg.sender_email} ({getSenderLabel(msg.sender_type)})
                        </span>
                      </div>
                      <p className="text-sm">{msg.message}</p>
                      <p className="text-xs opacity-70 mt-1">
                        {new Date(msg.created_at).toLocaleTimeString('es-ES', {
                          hour: '2-digit',
                          minute: '2-digit',
                        })}
                      </p>
                    </div>
                  </div>
                );
              })
            )}
          </div>
        </ScrollArea>

        <div className="flex gap-2 pt-4 border-t">
          <Textarea
            value={newMessage}
            onChange={(e) => setNewMessage(e.target.value)}
            placeholder="Escribe tu mensaje..."
            rows={2}
            className="resize-none"
            onKeyDown={(e) => {
              if (e.key === 'Enter' && !e.shiftKey) {
                e.preventDefault();
                handleSendMessage();
              }
            }}
          />
          <Button
            onClick={handleSendMessage}
            disabled={sending || !newMessage.trim()}
            size="icon"
            className="self-end"
          >
            <Send className="h-4 w-4" />
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
};
