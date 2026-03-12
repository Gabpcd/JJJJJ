
-- 1. PRESENCES: Replace soignant UPDATE policy to only allow pointage columns
DROP POLICY IF EXISTS pol_pres_update ON public.presences;

-- Soignant can only update pointage-related columns (not fraud/validation fields)
CREATE POLICY pol_pres_update_soignant ON public.presences
  FOR UPDATE TO authenticated
  USING (soignant_id = auth.uid())
  WITH CHECK (soignant_id = auth.uid());

-- Create a trigger to block soignants from modifying integrity fields
CREATE OR REPLACE FUNCTION fn_protect_presence_integrity()
RETURNS TRIGGER AS $$
BEGIN
  -- If caller is the soignant (not admin/etablissement), block changes to integrity fields
  IF OLD.soignant_id = auth.uid() 
     AND NOT public.est_admin() 
     AND NOT public.est_admin_etablissement() THEN
    -- Prevent tampering with fraud/validation fields
    NEW.alerte_teleportation := OLD.alerte_teleportation;
    NEW.alertes_fraude := OLD.alertes_fraude;
    NEW.perimetre_gps_valide := OLD.perimetre_gps_valide;
    NEW.distance_etablissement_m := OLD.distance_etablissement_m;
    NEW.valide_par_etablissement := OLD.valide_par_etablissement;
    NEW.valide_le := OLD.valide_le;
    NEW.motif_litige := OLD.motif_litige;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_protect_presence_integrity ON public.presences;
CREATE TRIGGER trg_protect_presence_integrity
  BEFORE UPDATE ON public.presences
  FOR EACH ROW EXECUTE FUNCTION fn_protect_presence_integrity();

-- Admin etablissement can update presences for their missions
CREATE POLICY pol_pres_update_etab ON public.presences
  FOR UPDATE TO authenticated
  USING (est_admin_etablissement() AND (mission_id IN (
    SELECT id FROM missions WHERE etablissement_id = mon_etablissement_id()
  )))
  WITH CHECK (est_admin_etablissement() AND (mission_id IN (
    SELECT id FROM missions WHERE etablissement_id = mon_etablissement_id()
  )));

-- Admin can update all
CREATE POLICY pol_pres_update_admin ON public.presences
  FOR UPDATE TO authenticated
  USING (est_admin())
  WITH CHECK (est_admin());

-- 2. SOIGNANTS: Add trigger to protect verification fields from self-modification
CREATE OR REPLACE FUNCTION fn_protect_soignant_verification()
RETURNS TRIGGER AS $$
BEGIN
  -- If the user is updating their own row and is not an admin
  IF OLD.id = auth.uid() AND NOT public.est_admin() THEN
    NEW.diplome_verifie := OLD.diplome_verifie;
    NEW.identite_verifiee := OLD.identite_verifiee;
    NEW.tous_documents_valides := OLD.tous_documents_valides;
    NEW.rpps_verifie := OLD.rpps_verifie;
    NEW.rpps_verifie_le := OLD.rpps_verifie_le;
    NEW.rpps_nom_api := OLD.rpps_nom_api;
    NEW.rpps_profession_api := OLD.rpps_profession_api;
    NEW.statut_verification_aria := OLD.statut_verification_aria;
    NEW.score_fiabilite := OLD.score_fiabilite;
    NEW.total_absences := OLD.total_absences;
    NEW.total_retards_pointage := OLD.total_retards_pointage;
    NEW.total_missions_annulees := OLD.total_missions_annulees;
    NEW.total_missions_terminees := OLD.total_missions_terminees;
    NEW.heures_cumulees := OLD.heures_cumulees;
    NEW.heures_plateforme := OLD.heures_plateforme;
    NEW.eligible_conversion_3200h := OLD.eligible_conversion_3200h;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_protect_soignant_verification ON public.soignants;
CREATE TRIGGER trg_protect_soignant_verification
  BEFORE UPDATE ON public.soignants
  FOR EACH ROW EXECUTE FUNCTION fn_protect_soignant_verification();

-- 3. HEURES_EXTERNES: Replace ALL policy with separate INSERT/SELECT for soignants
DROP POLICY IF EXISTS pol_hext_all ON public.heures_externes;

CREATE POLICY pol_hext_select ON public.heures_externes
  FOR SELECT TO authenticated
  USING ((soignant_id = auth.uid()) OR est_admin());

CREATE POLICY pol_hext_insert ON public.heures_externes
  FOR INSERT TO authenticated
  WITH CHECK ((soignant_id = auth.uid()) OR est_admin());

CREATE POLICY pol_hext_update ON public.heures_externes
  FOR UPDATE TO authenticated
  USING (est_admin());

CREATE POLICY pol_hext_delete ON public.heures_externes
  FOR DELETE TO authenticated
  USING (est_admin());

-- 4. CONVERSIONS_LIBERAL: Replace ALL policy with restricted access
DROP POLICY IF EXISTS pol_conv_all ON public.conversions_liberal;

CREATE POLICY pol_conv_select ON public.conversions_liberal
  FOR SELECT TO authenticated
  USING ((soignant_id = auth.uid()) OR est_admin());

CREATE POLICY pol_conv_insert ON public.conversions_liberal
  FOR INSERT TO authenticated
  WITH CHECK ((soignant_id = auth.uid()) OR est_admin());

CREATE POLICY pol_conv_update ON public.conversions_liberal
  FOR UPDATE TO authenticated
  USING (est_admin());

CREATE POLICY pol_conv_delete ON public.conversions_liberal
  FOR DELETE TO authenticated
  USING (est_admin());

-- 5. SOUSCRIPTIONS_PREVOYANCE: Restrict to SELECT only for soignants
DROP POLICY IF EXISTS pol_prevoy_all ON public.souscriptions_prevoyance;

CREATE POLICY pol_prevoy_select ON public.souscriptions_prevoyance
  FOR SELECT TO authenticated
  USING ((soignant_id = auth.uid()) OR est_admin());

CREATE POLICY pol_prevoy_insert ON public.souscriptions_prevoyance
  FOR INSERT TO authenticated
  WITH CHECK (est_admin());

CREATE POLICY pol_prevoy_update ON public.souscriptions_prevoyance
  FOR UPDATE TO authenticated
  USING (est_admin());

CREATE POLICY pol_prevoy_delete ON public.souscriptions_prevoyance
  FOR DELETE TO authenticated
  USING (est_admin());

-- 6. MISSIONS: Add trigger to block soignant from modifying financial columns
CREATE OR REPLACE FUNCTION fn_protect_mission_financials()
RETURNS TRIGGER AS $$
BEGIN
  -- If the caller is the assigned soignant (not admin/etablissement)
  IF OLD.soignant_assigne_id = auth.uid()
     AND NOT public.est_admin()
     AND NOT public.est_admin_etablissement() THEN
    -- Only allow soignant_assigne_id and statut changes
    NEW.taux_horaire_base := OLD.taux_horaire_base;
    NEW.total_brut := OLD.total_brut;
    NEW.net_a_payer := OLD.net_a_payer;
    NEW.montant_ifm := OLD.montant_ifm;
    NEW.montant_icp := OLD.montant_icp;
    NEW.taux_ifm := OLD.taux_ifm;
    NEW.taux_icp := OLD.taux_icp;
    NEW.montant_majoration_nuit := OLD.montant_majoration_nuit;
    NEW.montant_majoration_dimanche := OLD.montant_majoration_dimanche;
    NEW.montant_majoration_ferie := OLD.montant_majoration_ferie;
    NEW.heures_nuit := OLD.heures_nuit;
    NEW.heures_dimanche := OLD.heures_dimanche;
    NEW.heures_ferie := OLD.heures_ferie;
    NEW.taux_commission := OLD.taux_commission;
    NEW.montant_commission_ht := OLD.montant_commission_ht;
    NEW.montant_commission_tva := OLD.montant_commission_tva;
    NEW.montant_commission_ttc := OLD.montant_commission_ttc;
    NEW.taux_rist_plafonne := OLD.taux_rist_plafonne;
    NEW.rist_plafond_applique := OLD.rist_plafond_applique;
    NEW.etablissement_id := OLD.etablissement_id;
    NEW.profession_requise := OLD.profession_requise;
    NEW.duree_heures := OLD.duree_heures;
    NEW.debut_le := OLD.debut_le;
    NEW.fin_le := OLD.fin_le;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_protect_mission_financials ON public.missions;
CREATE TRIGGER trg_protect_mission_financials
  BEFORE UPDATE ON public.missions
  FOR EACH ROW EXECUTE FUNCTION fn_protect_mission_financials();
