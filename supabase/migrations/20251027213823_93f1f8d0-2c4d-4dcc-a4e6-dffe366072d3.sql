-- Add client_observation column to quotes table
ALTER TABLE public.quotes
ADD COLUMN client_observation TEXT;

COMMENT ON COLUMN public.quotes.client_observation IS 'Observations from the client about this specific quote';