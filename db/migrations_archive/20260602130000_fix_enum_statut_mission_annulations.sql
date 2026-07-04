-- BUG (désynchronisation enum/code, même classe que Sprint 17) : l'enum
-- statut_mission vaut OUVERTE, ASSIGNEE, EN_COURS, TERMINEE,
-- ANNULEE_PAR_ETABLISSEMENT, ANNULEE_PAR_SOIGNANT, ABSENCE, LITIGE, EXPIREE.
-- Or 4 fonctions utilisaient des littéraux INEXISTANTS dans des comparaisons /
-- affectations de missions.statut (cast vers l'enum → erreur 22P02), rendant
-- l'annulation de mission par l'établissement totalement cassée (chemin jamais
-- exécuté de bout en bout côté établissement, donc bug latent). Remplacements :
--   ANNULEE_LITIGE   -> LITIGE
--   ANNULEE_ETAB     -> ANNULEE_PAR_ETABLISSEMENT
--   ANNULEE_SOIGNANT -> ANNULEE_PAR_SOIGNANT
-- Seuls les littéraux quotés EXACTS (contextes statut) sont remplacés ; les
-- chaînes de notification/audit type 'MISSION_ANNULEE_ETAB' ne matchent pas et
-- restent intactes.
-- Fonctions concernées : fn_annuler_mission_etab, fn_annuler_mission_complete,
-- fn_generer_qr_mission, fn_annuler_candidature_soignant.
DO $mig$
DECLARE r record; v_def text; v_new text; v_n int := 0;
BEGIN
  FOR r IN
    SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname IN
      ('fn_annuler_mission_etab','fn_annuler_mission_complete','fn_generer_qr_mission','fn_annuler_candidature_soignant')
  LOOP
    v_def := pg_get_functiondef(r.oid);
    v_new := replace(v_def, '''ANNULEE_LITIGE''', '''LITIGE''');
    v_new := replace(v_new, '''ANNULEE_ETAB''', '''ANNULEE_PAR_ETABLISSEMENT''');
    v_new := replace(v_new, '''ANNULEE_SOIGNANT''', '''ANNULEE_PAR_SOIGNANT''');
    IF v_new <> v_def THEN
      EXECUTE v_new;
      v_n := v_n + 1;
    END IF;
  END LOOP;
  IF v_n = 0 THEN RAISE EXCEPTION 'aucun remplacement effectué'; END IF;
END $mig$;
