-- Create notification type enum
CREATE TYPE notification_type AS ENUM ('technical_visit', 'quote_received', 'assignment', 'general');

-- Create notifications table
CREATE TABLE notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_email text NOT NULL,
  type notification_type NOT NULL,
  title text NOT NULL,
  message text NOT NULL,
  request_id uuid REFERENCES requests(id),
  quote_id uuid REFERENCES quotes(id),
  read boolean NOT NULL DEFAULT false,
  created_at timestamp with time zone NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

-- RLS policies for notifications
CREATE POLICY "Anyone can view notifications"
  ON notifications FOR SELECT
  USING (true);

CREATE POLICY "Anyone can insert notifications"
  ON notifications FOR INSERT
  WITH CHECK (true);

CREATE POLICY "Anyone can update notifications"
  ON notifications FOR UPDATE
  USING (true);

-- Create technical visit documents table
CREATE TABLE technical_visit_documents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES requests(id),
  assignment_id uuid REFERENCES assignments(id),
  team_member_id uuid NOT NULL REFERENCES team_members(id),
  file_urls text[] NOT NULL,
  notes text,
  created_at timestamp with time zone NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE technical_visit_documents ENABLE ROW LEVEL SECURITY;

-- RLS policies for technical visit documents
CREATE POLICY "Anyone can view technical visit documents"
  ON technical_visit_documents FOR SELECT
  USING (true);

CREATE POLICY "Anyone can insert technical visit documents"
  ON technical_visit_documents FOR INSERT
  WITH CHECK (true);