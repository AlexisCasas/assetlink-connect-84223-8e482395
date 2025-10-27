-- Add quotes_closed column to requests table
ALTER TABLE public.requests
ADD COLUMN quotes_closed BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN public.requests.quotes_closed IS 'Indicates if quote submission is closed for this request';