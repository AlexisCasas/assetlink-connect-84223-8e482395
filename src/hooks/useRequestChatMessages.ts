import { useState, useEffect } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { ChatMessage, ChatParticipant } from '@/types/contact';

export const useRequestChatMessages = (requestId: string, userEmail: string) => {
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [participants, setParticipants] = useState<ChatParticipant[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!requestId) return;

    loadMessages();
    loadParticipants();

    // Suscribirse a nuevos mensajes en tiempo real
    const channel = supabase
      .channel(`chat_${requestId}`)
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'chat_messages',
          filter: `request_id=eq.${requestId}`
        },
        (payload) => {
          setMessages(prev => [...prev, payload.new as ChatMessage]);
        }
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [requestId]);

  const loadMessages = async () => {
    try {
      const { data, error } = await supabase
        .from('chat_messages')
        .select('*')
        .eq('request_id', requestId)
        .order('created_at', { ascending: true });

      if (error) throw error;
      setMessages((data || []) as ChatMessage[]);
    } catch (error) {
      console.error('Error loading messages:', error);
    } finally {
      setLoading(false);
    }
  };

  const loadParticipants = async () => {
    try {
      const { data, error } = await supabase
        .from('request_chat_participants')
        .select('*')
        .eq('request_id', requestId);

      if (error) throw error;
      setParticipants((data || []) as ChatParticipant[]);
    } catch (error) {
      console.error('Error loading participants:', error);
    }
  };

  const sendMessage = async (message: string, senderName: string, senderType: 'client' | 'provider' | 'team_member') => {
    try {
      const { error } = await supabase
        .from('chat_messages')
        .insert({
          request_id: requestId,
          sender_type: senderType,
          sender_email: userEmail,
          sender_name: senderName,
          message: message.trim()
        });

      if (error) throw error;
      return { success: true };
    } catch (error) {
      console.error('Error sending message:', error);
      return { success: false, error };
    }
  };

  return { messages, participants, loading, sendMessage, refreshMessages: loadMessages };
};
