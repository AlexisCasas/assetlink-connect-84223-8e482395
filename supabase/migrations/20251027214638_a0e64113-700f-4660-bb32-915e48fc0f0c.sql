-- Add approval_reason column to quotes table
ALTER TABLE public.quotes
ADD COLUMN approval_reason TEXT;

COMMENT ON COLUMN public.quotes.approval_reason IS 'Justification for approving this quote';