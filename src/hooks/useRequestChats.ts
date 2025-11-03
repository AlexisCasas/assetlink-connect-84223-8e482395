import { useState, useEffect } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { ContactListItem } from '@/types/contact';

export const useRequestChats = (userEmail: string) => {
  const [chats, setChats] = useState<ContactListItem[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!userEmail) return;
    
    loadChats();
    
    // Suscribirse a nuevos mensajes
    const channel = supabase
      .channel('request_chats_updates')
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'chat_messages'
        },
        () => {
          loadChats();
        }
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [userEmail]);

  const loadChats = async () => {
    try {
      setLoading(true);
      
      // Obtener solicitudes donde el usuario participa
      const { data: participations } = await supabase
        .from('request_chat_participants')
        .select('request_id, last_read_at')
        .eq('user_email', userEmail);

      if (!participations || participations.length === 0) {
        setChats([]);
        setLoading(false);
        return;
      }

      const requestIds = participations.map(p => p.request_id);

      // Obtener información de las solicitudes
      const { data: requests } = await supabase
        .from('requests')
        .select('id, request_number, description')
        .in('id', requestIds);

      if (!requests) {
        setChats([]);
        setLoading(false);
        return;
      }

      // Para cada solicitud, obtener el último mensaje y contar no leídos
      const chatsData: ContactListItem[] = await Promise.all(
        requests.map(async (request) => {
          const participation = participations.find(p => p.request_id === request.id);
          
          // Último mensaje
          const { data: lastMsg } = await supabase
            .from('chat_messages')
            .select('message, created_at, sender_name')
            .eq('request_id', request.id)
            .order('created_at', { ascending: false })
            .limit(1)
            .single();

          // Contar mensajes no leídos
          const { count } = await supabase
            .from('chat_messages')
            .select('*', { count: 'exact', head: true })
            .eq('request_id', request.id)
            .neq('sender_email', userEmail)
            .gt('created_at', participation?.last_read_at || '1970-01-01');

          // Obtener participantes
          const { data: participants } = await supabase
            .from('request_chat_participants')
            .select('user_name')
            .eq('request_id', request.id)
            .neq('user_email', userEmail);

          return {
            requestId: request.id,
            requestNumber: request.request_number,
            requestDescription: request.description,
            lastMessage: lastMsg?.message || 'No hay mensajes',
            lastMessageTime: lastMsg?.created_at || '',
            lastMessageSender: lastMsg?.sender_name || '',
            unreadCount: count || 0,
            participants: participants?.map(p => p.user_name || '') || []
          };
        })
      );

      // Ordenar por último mensaje más reciente
      chatsData.sort((a, b) => 
        new Date(b.lastMessageTime).getTime() - new Date(a.lastMessageTime).getTime()
      );

      setChats(chatsData);
    } catch (error) {
      console.error('Error loading chats:', error);
      setChats([]);
    } finally {
      setLoading(false);
    }
  };

  const markAsRead = async (requestId: string) => {
    try {
      await supabase
        .from('request_chat_participants')
        .update({ last_read_at: new Date().toISOString() })
        .eq('request_id', requestId)
        .eq('user_email', userEmail);

      // Actualizar estado local
      setChats(prevChats =>
        prevChats.map(chat =>
          chat.requestId === requestId
            ? { ...chat, unreadCount: 0 }
            : chat
        )
      );
    } catch (error) {
      console.error('Error marking as read:', error);
    }
  };

  return { chats, loading, markAsRead, refreshChats: loadChats };
};
