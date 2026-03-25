-- 1. TRIGGER: empêcher la modification de cle_api et cle_secret après création
CREATE OR REPLACE FUNCTION fn_protect_api_key_secrets()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.cle_api IS DISTINCT FROM OLD.cle_api THEN
    RAISE EXCEPTION 'La clé API ne peut pas être modifiée après création';
  END IF;
  IF NEW.cle_secret IS DISTINCT FROM OLD.cle_secret THEN
    RAISE EXCEPTION 'Le secret API ne peut pas être modifié après création';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_protect_api_key_secrets ON api_keys;
CREATE TRIGGER trg_protect_api_key_secrets
  BEFORE UPDATE ON api_keys
  FOR EACH ROW
  EXECUTE FUNCTION fn_protect_api_key_secrets();

-- 2. CONFORMITE_TRAVAIL : protection en écriture explicite
-- Seuls les RPCs SECURITY DEFINER (service_role) peuvent écrire
CREATE POLICY pol_conf_insert_deny ON conformite_travail FOR INSERT TO authenticated WITH CHECK (false);
CREATE POLICY pol_conf_update_deny ON conformite_travail FOR UPDATE TO authenticated USING (false) WITH CHECK (false);
CREATE POLICY pol_conf_delete_deny ON conformite_travail FOR DELETE TO authenticated USING (false);
CREATE POLICY pol_conf_insert_deny_anon ON conformite_travail FOR INSERT TO anon WITH CHECK (false);
CREATE POLICY pol_conf_update_deny_anon ON conformite_travail FOR UPDATE TO anon USING (false) WITH CHECK (false);
CREATE POLICY pol_conf_delete_deny_anon ON conformite_travail FOR DELETE TO anon USING (false);