
ALTER TABLE public.quotes
  ADD COLUMN IF NOT EXISTS quote_sections jsonb NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS base_subtotal numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS general_expenses_percentage numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS general_expenses_amount numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS utilities_percentage numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS utilities_amount numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS subtotal numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS igv_amount numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS total_amount numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS sales_conditions jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS sent_at timestamptz,
  ADD COLUMN IF NOT EXISTS emailed_at timestamptz,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

DROP TRIGGER IF EXISTS trg_quotes_updated_at ON public.quotes;
CREATE TRIGGER trg_quotes_updated_at
BEFORE UPDATE ON public.quotes
FOR EACH ROW
EXECUTE FUNCTION public.touch_updated_at();
