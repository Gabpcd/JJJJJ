-- Fix CRITIQUE audit : fn_generer_code_parrainage + fn_auto_code_parrainage
-- sans SET search_path (vulnérabilité search_path hijacking SECURITY DEFINER)

CREATE OR REPLACE FUNCTION public.fn_generer_code_parrainage()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_code TEXT;
BEGIN
    v_code := 'JO-' || UPPER(SUBSTRING(encode(gen_random_bytes(4), 'hex') FROM 1 FOR 6));
    WHILE EXISTS (SELECT 1 FROM soignants WHERE code_parrainage = v_code) LOOP
        v_code := 'JO-' || UPPER(SUBSTRING(encode(gen_random_bytes(4), 'hex') FROM 1 FOR 6));
    END LOOP;
    RETURN v_code;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_auto_code_parrainage()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
    IF NEW.code_parrainage IS NULL OR NEW.code_parrainage = '' THEN
        NEW.code_parrainage := fn_generer_code_parrainage();
    END IF;
    RETURN NEW;
END;
$$;

NOTIFY pgrst, 'reload schema';
