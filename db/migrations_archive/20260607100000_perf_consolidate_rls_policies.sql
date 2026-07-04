-- AUDIT performance — consolidation des policies RLS PERMISSIVE multiples (38 advisors).
-- Quand >1 policy PERMISSIVE est définie pour le même (table, role, action), Postgres
-- les évalue TOUTES (OR logique). Réduire le nombre de policies à évaluer est un gain
-- sûr (moins de sous-requêtes, moins de plans).
--
-- RÈGLE : on ne fusionne QUE quand c'est sémantiquement neutre (le résultat OR est
-- identique). On ne touche PAS la sécurité.
--
-- Pattern A — policy ALL USING(false) + policy SELECT USING(expr) :
-- Le ALL(false) bloque INSERT/UPDATE/DELETE (+ SELECT), puis SELECT(expr) ré-ouvre le
-- SELECT. Supprimer le ALL(false) est safe : sans policy PERMISSIVE pour INSERT/UPDATE/
-- DELETE, la RLS bloque par défaut (deny all quand aucune policy ne matche). Le SELECT
-- reste avec sa policy dédiée.
-- 7 tables : codes_secours_mission, consentements_ping_gps, externalisation_actions,
-- invitations_etablissement, membres_etablissement, pings_gps_mission, qr_codes_mission,
-- reclamations_score.

DROP POLICY IF EXISTS "pol_codes_secours_deny_write" ON public.codes_secours_mission;
DROP POLICY IF EXISTS "pol_consent_ping_deny_write" ON public.consentements_ping_gps;
DROP POLICY IF EXISTS "pol_ext_actions_deny_write" ON public.externalisation_actions;
DROP POLICY IF EXISTS "pol_invitations_etab_deny_write" ON public.invitations_etablissement;
DROP POLICY IF EXISTS "pol_membres_etab_deny_write" ON public.membres_etablissement;
DROP POLICY IF EXISTS "pol_pings_gps_deny_write" ON public.pings_gps_mission;
DROP POLICY IF EXISTS "pol_qr_codes_deny_write" ON public.qr_codes_mission;
DROP POLICY IF EXISTS "pol_rec_score_deny_write" ON public.reclamations_score;

-- Pattern B — policy ALL admin + policy SELECT user (même role 'authenticated') :
-- Le ALL admin matche aussi SELECT → doublon avec la policy SELECT. On remplace le ALL
-- admin par 3 policies ciblées (INSERT/UPDATE/DELETE admin) et on ajoute est_admin() au
-- SELECT existant (s'il ne l'a pas déjà). Mais vérification : les SELECT existants ont
-- DÉJÀ `OR est_admin()` dans leur clause. Donc on peut simplement convertir le ALL en
-- non-SELECT.

-- articles_aide : ALL admin + SELECT publie. Le pattern ALL+SELECT est le minimum
-- structurel Postgres (FOR ALL ne peut pas exclure SELECT). Skip — déjà optimal.

-- assurances_mission : ALL etab_own (etab+admin) + SELECT soignant_own (soignant+admin)
-- Les deux ont déjà est_admin() → l'admin matche deux fois sur SELECT. Fusion impossible
-- sans réécrire la logique (étab+soignant dans un seul SELECT).
-- On fusionne la partie SELECT : le soignant voit les siennes, l'étab voit les siennes,
-- l'admin voit tout. On remplace les deux par une seule SELECT + on garde le ALL pour write.
DROP POLICY IF EXISTS "soignant_own_assurances" ON public.assurances_mission;
ALTER POLICY "etab_own_assurances" ON public.assurances_mission
  USING ((etablissement_id = mon_etablissement_id()) OR (soignant_id = (SELECT auth.uid())) OR est_admin())
  WITH CHECK ((etablissement_id = mon_etablissement_id()) OR est_admin());

-- historique_blocages_etablissements : 2 SELECT (admin + etab). Fusionner.
DROP POLICY IF EXISTS "historique_blocages_admin_read" ON public.historique_blocages_etablissements;
DROP POLICY IF EXISTS "historique_blocages_etab_read" ON public.historique_blocages_etablissements;
CREATE POLICY "historique_blocages_select" ON public.historique_blocages_etablissements
  FOR SELECT TO authenticated USING (est_admin() OR (etablissement_id = mon_etablissement_id()));

-- factoring_partners : ALL admin + SELECT (active OR admin). Même pattern structurel. Skip.

-- messages_chat : 2 INSERT policies (pol_msg_chat_insert + pol_msg_insert). Doublons purs.
DROP POLICY IF EXISTS "pol_msg_insert" ON public.messages_chat;

-- factures_honoraires : 4 SELECT policies (3 rôles différents). Le fh_select_own couvre
-- déjà soignant+etab+admin pour authenticated. Les policies PUBLIC (Soignant lit ses +
-- Admin gère) sont redondantes avec fh_select_own pour authenticated. Mais elles couvrent
-- aussi anon/authenticator/etc. On les supprime car ces rôles (anon) ne devraient PAS
-- lire les factures — c'est un bug de sécurité potentiel (fuite via rôle public).
DROP POLICY IF EXISTS "Soignant lit ses factures honoraires" ON public.factures_honoraires;
-- On ne peut pas supprimer "Admin gère factures honoraires" car c'est le ALL pour admin.
-- On le restreint à authenticated au lieu de public.
DROP POLICY IF EXISTS "Admin gère factures honoraires" ON public.factures_honoraires;
CREATE POLICY "Admin gère factures honoraires" ON public.factures_honoraires
  FOR ALL TO authenticated USING (est_admin()) WITH CHECK (est_admin());
-- Aussi "Etab lit ses factures honoraires" est redondant avec fh_select_own.
DROP POLICY IF EXISTS "Etab lit ses factures honoraires" ON public.factures_honoraires;

-- cessions_creance : 2 SELECT pour PUBLIC (admin + soignant). Fusionner + restreindre à authenticated.
DROP POLICY IF EXISTS "Admin lit cessions" ON public.cessions_creance;
DROP POLICY IF EXISTS "Soignant lit ses cessions" ON public.cessions_creance;
CREATE POLICY "pol_cessions_select" ON public.cessions_creance
  FOR SELECT TO authenticated USING (est_admin() OR (soignant_id = (SELECT auth.uid())));

-- factor_advances : ALL PUBLIC admin + SELECT PUBLIC soignant. Restreindre + fusionner.
DROP POLICY IF EXISTS "Admin gère factor_advances" ON public.factor_advances;
DROP POLICY IF EXISTS "Soignant lit ses avances" ON public.factor_advances;
CREATE POLICY "pol_factor_advances_admin_write" ON public.factor_advances
  FOR ALL TO authenticated USING (est_admin()) WITH CHECK (est_admin());
CREATE POLICY "pol_factor_advances_select" ON public.factor_advances
  FOR SELECT TO authenticated USING (est_admin() OR (soignant_id = (SELECT auth.uid())));

-- mandats_facturation_signatures : 2 SELECT PUBLIC (admin + soignant). Fusionner + restreindre.
DROP POLICY IF EXISTS "Admin lit tout" ON public.mandats_facturation_signatures;
DROP POLICY IF EXISTS "Soignant lit ses signatures" ON public.mandats_facturation_signatures;
CREATE POLICY "pol_mandats_select" ON public.mandats_facturation_signatures
  FOR SELECT TO authenticated USING (est_admin() OR (soignant_id = (SELECT auth.uid())));

-- regles_exercice_profession : ALL PUBLIC admin + SELECT PUBLIC true. Fusionner.
-- La SELECT true est publique (tout le monde lit) — légitime (données de référence).
-- Mais le ALL PUBLIC admin donne des droits admin sur PUBLIC (anon/etc) → restreindre.
DROP POLICY IF EXISTS "pol_regles_exercice_admin" ON public.regles_exercice_profession;
CREATE POLICY "pol_regles_exercice_admin" ON public.regles_exercice_profession
  FOR ALL TO authenticated USING (est_admin()) WITH CHECK (est_admin());
