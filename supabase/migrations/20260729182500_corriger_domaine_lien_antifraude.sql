-- La migration de durcissement des crons a recompilé la fonction antifraude
-- avec l'ancien sous-domaine. Restaurer le domaine canonique sans modifier
-- l'historique des migrations déjà appliquées au staging.

DO $canonicaliser_lien_antifraude$
DECLARE
  v_oid oid;
  v_definition text;
BEGIN
  SELECT p.oid
  INTO v_oid
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'fn_detecter_teleportations'
    AND p.prokind = 'f'
    AND p.prosrc LIKE '%https://app.jolene.app%'
  ORDER BY p.oid
  LIMIT 1;

  IF v_oid IS NULL THEN
    RETURN;
  END IF;

  v_definition := pg_get_functiondef(v_oid);
  EXECUTE replace(
    v_definition,
    'https://app.jolene.app',
    'https://jolene.app'
  );
END;
$canonicaliser_lien_antifraude$;
