CREATE OR REPLACE FUNCTION public.fn_upsert_token_push(p_token text, p_plateforme text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO tokens_push (utilisateur_id, token, plateforme)
  VALUES (auth.uid(), p_token, p_plateforme)
  ON CONFLICT (token) DO UPDATE SET
    utilisateur_id = auth.uid(),
    plateforme = p_plateforme;
END;
$$;