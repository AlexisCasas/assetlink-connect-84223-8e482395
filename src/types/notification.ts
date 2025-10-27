export type NotificationType = 'technical_visit' | 'quote_received' | 'assignment' | 'general';

export interface Notification {
  id: string;
  user_email: string;
  type: NotificationType;
  title: string;
  message: string;
  request_id?: string;
  quote_id?: string;
  read: boolean;
  created_at: string;
}
