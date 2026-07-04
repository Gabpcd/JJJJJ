-- BUG (bloqueur lancement) : gen_random_bytes() vit dans le schéma `extensions`
-- (pgcrypto), mais 3 fonctions l'appelaient sans qualification avec
-- search_path=public → échec 42883 « function gen_random_bytes does not exist ».
--   * dec_auto_generer_qr_mission : trigger sur signature complète du contrat →
--     TOUTE signature de contrat échouait → aucune mission ne pouvait passer au
--     pointage (0 contrat SIGNE_COMPLET en prod = bug jamais exercé).
--   * fn_generer_qr_mission : génération QR de pointage.
--   * fn_generer_code_parrainage : génération du code de parrainage soignant.
-- Fix : qualifier l'appel en extensions.gen_random_bytes (robuste quel que soit
-- le search_path). Patch dynamique guardé (ne double-qualifie pas).
DO $mig$
DECLARE r RECORD; v_def text; v_new text;
BEGIN
  FOR r IN
    SELECT p.oid FROM pg_proc p
    WHERE p.pronamespace='public'::regnamespace
      AND p.proname IN ('dec_auto_generer_qr_mission','fn_generer_qr_mission','fn_generer_code_parrainage')
  LOOP
    v_def := pg_get_functiondef(r.oid);
    v_new := regexp_replace(v_def, '([^.])gen_random_bytes', '\1extensions.gen_random_bytes', 'g');
    IF v_new <> v_def THEN EXECUTE v_new; END IF;
  END LOOP;
END $mig$;
