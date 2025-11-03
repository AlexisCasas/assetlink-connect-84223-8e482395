import { useEffect, useState, useRef } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Textarea } from '@/components/ui/textarea';
import { ScrollArea } from '@/components/ui/scroll-area';
import { Badge } from '@/components/ui/badge';
import { useAuth } from '@/contexts/AuthContext';
import { useRequestChatMessages } from '@/hooks/useRequestChatMessages';
import { Send, Users } from 'lucide-react';
import { useToast } from '@/hooks/use-toast';

interface RequestChatDialogProps {
  open: boolean;
  onClose: () => void;
  requestId: string;
  requestNumber: string;
}

export const RequestChatDialog = ({ open, onClose, requestId, requestNumber }: RequestChatDialogProps) => {
  const { user } = useAuth();
  const { messages, participants, loading, sendMessage } = useRequestChatMessages(requestId, user?.email || '');
  const [newMessage, setNewMessage] = useState('');
  const [sending, setSending] = useState(false);
  const { toast } = useToast();
  const scrollRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  }, [messages]);

  const getSenderType = (): 'client' | 'provider' | 'team_member' => {
    if (user?.role === 'cliente') return 'client';
    if (user?.role === 'proveedor') return 'provider';
    return 'team_member';
  };

  const handleSendMessage = async () => {
    if (!newMessage.trim()) return;

    try {
      setSending(true);
      const result = await sendMessage(newMessage, user?.name || user?.email || 'Usuario', getSenderType());
      
      if (result.success) {
        setNewMessage('');
      } else {
        toast({
          title: 'Error',
          description: 'No se pudo enviar el mensaje.',
          variant: 'destructive',
        });
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

  const getRoleBadgeColor = (role: string) => {
    switch (role) {
      case 'client':
        return 'bg-blue-500';
      case 'provider':
        return 'bg-green-500';
      case 'team_member':
        return 'bg-purple-500';
      default:
        return 'bg-gray-500';
    }
  };

  const getRoleText = (role: string) => {
    switch (role) {
      case 'client':
        return 'Cliente';
      case 'provider':
        return 'Proveedor';
      case 'team_member':
        return 'Equipo';
      default:
        return role;
    }
  };

  return (
    <Dialog open={open} onOpenChange={onClose}>
      <DialogContent className="max-w-3xl max-h-[700px] flex flex-col">
        <DialogHeader>
          <DialogTitle className="flex items-center justify-between">
            <span>Chat - {requestNumber}</span>
            <div className="flex items-center gap-2 text-sm font-normal">
              <Users className="h-4 w-4" />
              <span className="text-muted-foreground">{participants.length} participantes</span>
            </div>
          </DialogTitle>
          <div className="flex flex-wrap gap-2 mt-2">
            {participants.map((p) => (
              <Badge key={p.id} variant="outline" className={getRoleBadgeColor(p.user_role)}>
                {p.user_name} ({getRoleText(p.user_role)})
              </Badge>
            ))}
          </div>
        </DialogHeader>

        <ScrollArea className="flex-1 pr-4" ref={scrollRef}>
          <div className="space-y-4 py-4">
            {messages.length === 0 && !loading ? (
              <p className="text-center text-muted-foreground py-8">
                No hay mensajes aún. Inicia la conversación.
              </p>
            ) : (
              messages.map((msg) => {
                const isOwnMessage = msg.sender_email === user?.email;
                return (
                  <div
                    key={msg.id}
                    className={`flex ${isOwnMessage ? 'justify-end' : 'justify-start'}`}
                  >
                    <div className={`max-w-[70%] ${isOwnMessage ? 'order-2' : 'order-1'}`}>
                      <div className="flex items-center gap-2 mb-1">
                        <span className="text-xs font-medium">
                          {msg.sender_name}
                        </span>
                        <Badge
                          variant="outline"
                          className={`text-[10px] px-1.5 py-0 ${getRoleBadgeColor(msg.sender_type)}`}
                        >
                          {getRoleText(msg.sender_type)}
                        </Badge>
                      </div>
                      <div
                        className={`rounded-lg p-3 ${
                          isOwnMessage
                            ? 'bg-primary text-primary-foreground'
                            : 'bg-muted'
                        }`}
                      >
                        <p className="text-sm whitespace-pre-wrap">{msg.message}</p>
                        <p className="text-xs opacity-70 mt-1">
                          {new Date(msg.created_at).toLocaleTimeString('es-ES', {
                            hour: '2-digit',
                            minute: '2-digit',
                          })}
                        </p>
                      </div>
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
