-- Add parent_id column to chat_messages for forum-style Q&A threading
ALTER TABLE public.chat_messages 
ADD COLUMN IF NOT EXISTS parent_id uuid REFERENCES public.chat_messages(id);

-- Create index for faster parent lookups
CREATE INDEX IF NOT EXISTS idx_chat_messages_parent_id ON public.chat_messages(parent_id);