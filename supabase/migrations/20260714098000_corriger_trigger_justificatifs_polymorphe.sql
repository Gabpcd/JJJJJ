-- Corrige la fonction déjà installée sur les environnements existants.
-- Un trigger RECORD ne peut pas référencer directement une colonne absente
-- de la table déclencheuse, même si cette référence se trouve dans une branche
-- CASE non retenue.

CREATE OR REPLACE FUNCTION public.fn_verrouiller_reference_justificatif()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_path text;
BEGIN
  IF auth.role() = 'service_role' OR public.est_admin() THEN
    RETURN NEW;
  END IF;

  v_path := CASE TG_TABLE_NAME
    WHEN 'missions'
      THEN pg_catalog.to_jsonb(NEW)->>'justificatif_honoraires_cle'
    ELSE pg_catalog.to_jsonb(NEW)->>'justificatif_storage_path'
  END;

  IF v_path IS NOT NULL
     AND NOT public.fn_peut_deposer_justificatif(v_path) THEN
    RAISE EXCEPTION 'Référence de justificatif non autorisée'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_verrouiller_reference_justificatif()
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_verrouiller_reference_justificatif()
TO service_role;
