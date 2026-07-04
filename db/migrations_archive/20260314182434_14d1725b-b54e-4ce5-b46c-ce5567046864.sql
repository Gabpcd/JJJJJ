
-- Table to store calendar tokens per user
CREATE TABLE IF NOT EXISTS public.tokens_calendrier (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  soignant_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE UNIQUE,
  token text NOT NULL DEFAULT encode(gen_random_bytes(32), 'hex'),
  cree_le timestamptz DEFAULT now()
);

ALTER TABLE public.tokens_calendrier ENABLE ROW LEVEL SECURITY;

CREATE POLICY "pol_tcal_select" ON public.tokens_calendrier
  FOR SELECT TO authenticated
  USING (soignant_id = auth.uid());

CREATE POLICY "pol_tcal_insert" ON public.tokens_calendrier
  FOR INSERT TO authenticated
  WITH CHECK (soignant_id = auth.uid());

-- Function to get or create the calendar token for the current user
CREATE OR REPLACE FUNCTION public.fn_mon_token_calendrier()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_token text;
BEGIN
  SELECT token INTO v_token FROM tokens_calendrier WHERE soignant_id = auth.uid();
  IF v_token IS NULL THEN
    INSERT INTO tokens_calendrier (soignant_id)
    VALUES (auth.uid())
    ON CONFLICT (soignant_id) DO NOTHING
    RETURNING token INTO v_token;
    -- In case of race condition
    IF v_token IS NULL THEN
      SELECT token INTO v_token FROM tokens_calendrier WHERE soignant_id = auth.uid();
    END IF;
  END IF;
  RETURN v_token;
END;
$$;
