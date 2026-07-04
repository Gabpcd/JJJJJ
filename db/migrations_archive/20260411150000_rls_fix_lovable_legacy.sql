-- ─── Fix RLS : remplacer le pattern Lovable legacy `etablissement_id = auth.uid()` ───
--
-- Contexte : 7 policies héritées de Lovable utilisent le pattern
-- `etablissement_id = auth.uid()` qui ne fonctionne que si l'id
-- établissement est strictement égal à l'id utilisateur. C'est vrai
-- aujourd'hui par convention (register-etablissement crée le row avec
-- `id = user.id`) mais c'est fragile : tout le reste du codebase utilise
-- `mon_etablissement_id()` qui lit app_metadata.etablissement_id.
--
-- On uniformise tout sur `mon_etablissement_id()` pour :
-- 1. Cohérence architecturale (un seul pattern)
-- 2. Support futur des utilisateurs admin-d'établissement qui ne sont pas
--    le owner (auth.uid() != etab.id)
-- 3. Résilience aux changements du modèle (si on séparait auth.user de etab.id)
-- 4. Ajout de est_admin() partout pour permettre aux admins de modérer

-- ─── 1. assurance_config ───
DROP POLICY IF EXISTS etab_own_config ON public.assurance_config;
CREATE POLICY etab_own_config ON public.assurance_config
  FOR ALL
  TO authenticated
  USING (etablissement_id = mon_etablissement_id() OR est_admin())
  WITH CHECK (etablissement_id = mon_etablissement_id() OR est_admin());

-- ─── 2. assurances_mission ───
DROP POLICY IF EXISTS etab_own_assurances ON public.assurances_mission;
CREATE POLICY etab_own_assurances ON public.assurances_mission
  FOR ALL
  TO authenticated
  USING (etablissement_id = mon_etablissement_id() OR est_admin())
  WITH CHECK (etablissement_id = mon_etablissement_id() OR est_admin());

-- Préserver la policy de lecture soignant
DROP POLICY IF EXISTS soignant_own_assurances ON public.assurances_mission;
CREATE POLICY soignant_own_assurances ON public.assurances_mission
  FOR SELECT
  TO authenticated
  USING (soignant_id = auth.uid() OR est_admin());

-- ─── 3. equipes ───
DROP POLICY IF EXISTS etab_own_equipes ON public.equipes;
CREATE POLICY etab_own_equipes ON public.equipes
  FOR ALL
  TO authenticated
  USING (etablissement_id = mon_etablissement_id() OR est_admin())
  WITH CHECK (etablissement_id = mon_etablissement_id() OR est_admin());

-- ─── 4. equipe_membres ───
DROP POLICY IF EXISTS etab_own_membres ON public.equipe_membres;
CREATE POLICY etab_own_membres ON public.equipe_membres
  FOR ALL
  TO authenticated
  USING (
    equipe_id IN (
      SELECT id FROM equipes
      WHERE etablissement_id = mon_etablissement_id()
    ) OR est_admin()
  )
  WITH CHECK (
    equipe_id IN (
      SELECT id FROM equipes
      WHERE etablissement_id = mon_etablissement_id()
    ) OR est_admin()
  );

-- ─── 5. shifts ───
DROP POLICY IF EXISTS etab_own_shifts ON public.shifts;
CREATE POLICY etab_own_shifts ON public.shifts
  FOR ALL
  TO authenticated
  USING (etablissement_id = mon_etablissement_id() OR est_admin())
  WITH CHECK (etablissement_id = mon_etablissement_id() OR est_admin());

-- ─── 6. shift_affectations ───
DROP POLICY IF EXISTS etab_own_affectations ON public.shift_affectations;
CREATE POLICY etab_own_affectations ON public.shift_affectations
  FOR ALL
  TO authenticated
  USING (
    shift_id IN (
      SELECT id FROM shifts
      WHERE etablissement_id = mon_etablissement_id()
    ) OR est_admin()
  )
  WITH CHECK (
    shift_id IN (
      SELECT id FROM shifts
      WHERE etablissement_id = mon_etablissement_id()
    ) OR est_admin()
  );

-- ─── 7. factures_honoraires — retirer le fallback legacy ───
DROP POLICY IF EXISTS "Etab lit ses factures honoraires" ON public.factures_honoraires;
CREATE POLICY "Etab lit ses factures honoraires" ON public.factures_honoraires
  FOR SELECT
  TO authenticated
  USING (etablissement_id = mon_etablissement_id() OR est_admin());

-- ─── 8. rpps_test — restreindre aux admins ───
-- Table de test avec 3 lignes qui était lisible par TOUS les authenticated.
-- Restreinte aux admins pour défense en profondeur.
DROP POLICY IF EXISTS pol_rpps_select ON public.rpps_test;
CREATE POLICY pol_rpps_select ON public.rpps_test
  FOR SELECT
  TO authenticated
  USING (est_admin());
