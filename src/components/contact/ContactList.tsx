import { useState } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { useRequestChats } from '@/hooks/useRequestChats';
import { Card } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Badge } from '@/components/ui/badge';
import { ScrollArea } from '@/components/ui/scroll-area';
import { Search, MessageSquare, Users } from 'lucide-react';
import { RequestChatDialog } from './RequestChatDialog';
import { Skeleton } from '@/components/ui/skeleton';

export const ContactList = () => {
  const { user } = useAuth();
  const { chats, loading, markAsRead } = useRequestChats(user?.email || '');
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedRequestId, setSelectedRequestId] = useState<string | null>(null);
  const [selectedRequestNumber, setSelectedRequestNumber] = useState<string>('');

  const filteredChats = chats.filter(chat =>
    chat.requestNumber.toLowerCase().includes(searchQuery.toLowerCase()) ||
    chat.requestDescription.toLowerCase().includes(searchQuery.toLowerCase())
  );

  const handleOpenChat = (requestId: string, requestNumber: string) => {
    setSelectedRequestId(requestId);
    setSelectedRequestNumber(requestNumber);
    markAsRead(requestId);
  };

  const getTimeAgo = (dateString: string) => {
    if (!dateString) return '';
    
    const date = new Date(dateString);
    const now = new Date();
    const diffMs = now.getTime() - date.getTime();
    const diffMins = Math.floor(diffMs / 60000);
    
    if (diffMins < 1) return 'Ahora';
    if (diffMins < 60) return `Hace ${diffMins} min`;
    
    const diffHours = Math.floor(diffMins / 60);
    if (diffHours < 24) return `Hace ${diffHours}h`;
    
    const diffDays = Math.floor(diffHours / 24);
    return `Hace ${diffDays}d`;
  };

  if (loading) {
    return (
      <div className="container mx-auto p-6 space-y-4">
        <div className="flex items-center gap-3 mb-6">
          <MessageSquare className="h-8 w-8 text-primary" />
          <h1 className="text-3xl font-bold">Contacto</h1>
        </div>
        
        <Skeleton className="h-10 w-full" />
        <div className="space-y-3">
          {[1, 2, 3].map(i => (
            <Skeleton key={i} className="h-24 w-full" />
          ))}
        </div>
      </div>
    );
  }

  return (
    <div className="container mx-auto p-6">
      <div className="flex items-center gap-3 mb-6">
        <MessageSquare className="h-8 w-8 text-primary" />
        <h1 className="text-3xl font-bold">Contacto</h1>
      </div>

      <div className="relative mb-4">
        <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 h-4 w-4 text-muted-foreground" />
        <Input
          placeholder="Buscar conversaciones..."
          value={searchQuery}
          onChange={(e) => setSearchQuery(e.target.value)}
          className="pl-10"
        />
      </div>

      {filteredChats.length === 0 ? (
        <Card className="p-8 text-center">
          <MessageSquare className="h-12 w-12 text-muted-foreground mx-auto mb-4" />
          <p className="text-muted-foreground">
            {searchQuery ? 'No se encontraron conversaciones' : 'No tienes conversaciones activas'}
          </p>
        </Card>
      ) : (
        <ScrollArea className="h-[calc(100vh-250px)]">
          <div className="space-y-3">
            {filteredChats.map((chat) => (
              <Card
                key={chat.requestId}
                className="p-4 cursor-pointer hover:bg-accent/50 transition-colors"
                onClick={() => handleOpenChat(chat.requestId, chat.requestNumber)}
              >
                <div className="flex items-start justify-between mb-2">
                  <div className="flex items-center gap-2">
                    <MessageSquare className="h-5 w-5 text-primary" />
                    <h3 className="font-semibold text-lg">{chat.requestNumber}</h3>
                    {chat.unreadCount > 0 && (
                      <Badge variant="destructive" className="h-5 min-w-5 flex items-center justify-center px-1.5">
                        {chat.unreadCount}
                      </Badge>
                    )}
                  </div>
                  <span className="text-xs text-muted-foreground">
                    {getTimeAgo(chat.lastMessageTime)}
                  </span>
                </div>

                <p className="text-sm text-muted-foreground mb-2 line-clamp-1">
                  {chat.requestDescription}
                </p>

                {chat.lastMessage && (
                  <p className="text-sm line-clamp-2 mb-2">
                    <span className="font-medium">{chat.lastMessageSender}:</span> {chat.lastMessage}
                  </p>
                )}

                {chat.participants.length > 0 && (
                  <div className="flex items-center gap-1 text-xs text-muted-foreground">
                    <Users className="h-3 w-3" />
                    <span>{chat.participants.join(', ')}</span>
                  </div>
                )}
              </Card>
            ))}
          </div>
        </ScrollArea>
      )}

      {selectedRequestId && (
        <RequestChatDialog
          open={!!selectedRequestId}
          onClose={() => setSelectedRequestId(null)}
          requestId={selectedRequestId}
          requestNumber={selectedRequestNumber}
        />
      )}
    </div>
  );
};
