-- Add status and rejection_reason to assignments table
CREATE TYPE assignment_status AS ENUM ('pending', 'accepted', 'rejected');

ALTER TABLE public.assignments 
  ADD COLUMN status assignment_status NOT NULL DEFAULT 'pending',
  ADD COLUMN rejection_reason text,
  ADD COLUMN responded_at timestamp with time zone;