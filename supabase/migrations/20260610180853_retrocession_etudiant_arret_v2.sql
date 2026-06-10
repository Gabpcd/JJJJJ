-- ① Contrat rétrocession : placeholders {{retrocession_pct}}/{{mode_remuneration}}
--    injectés dans le contrat généré (patch ciblé de fn_traiter_candidature via
--    pg_get_functiondef + replace + EXECUTE — ligne d'ancrage : REPLACE {{taux_horaire}}).
-- ② Matching : taux horaire 0 (mission rétrocession) = score tarif neutre 12
--    (patch ciblé fn_calculer_score_matching, ancre : WHEN taux IS NULL THEN 12).
-- ③ Statut étudiant : soignants.est_etudiant + etudiant_details, exposés à l'étab
--    (patch ciblé fn_soignant_pour_etablissement, ancre : disponible_urgence).
-- ④ Arrêt maladie : checklist employeur CPAM dans la notification établissement
--    (recreate fn_declarer_arret_maladie).
-- NOTE : appliquée prod via MCP (version 20260610180853), les 3 patches vérifiés
-- (fn_traiter_candidature LIKE '%retrocession_pct%', score LIKE '%= 0 THEN 12%',
--  fn_soignant_pour_etablissement LIKE '%est_etudiant%').
ALTER TABLE public.soignants ADD COLUMN IF NOT EXISTS est_etudiant boolean NOT NULL DEFAULT false;
ALTER TABLE public.soignants ADD COLUMN IF NOT EXISTS etudiant_details text;
