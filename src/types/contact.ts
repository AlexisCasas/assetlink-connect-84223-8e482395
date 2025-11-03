export interface ChatMessage {
  id: string;
  request_id: string;
  sender_type: 'client' | 'provider' | 'team_member';
  sender_email: string;
  sender_name: string;
  message: string;
  created_at: string;
}

export interface ChatParticipant {
  id: string;
  request_id: string;
  user_email: string;
  user_name: string;
  user_role: 'client' | 'provider' | 'team_member';
  joined_at: string;
  last_read_at: string;
}

export interface ContactListItem {
  requestId: string;
  requestNumber: string;
  requestDescription: string;
  lastMessage: string;
  lastMessageTime: string;
  lastMessageSender: string;
  unreadCount: number;
  participants: string[];
}
