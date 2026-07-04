-- Fix 1: pol_soig_insert — allow default values (score_fiabilite=50, heures=0, etc.)
DROP POLICY IF EXISTS pol_soig_insert ON public.soignants;
CREATE POLICY pol_soig_insert ON public.soignants
FOR INSERT TO authenticated
WITH CHECK (
  id = auth.uid()
  AND rpps_verifie IS NOT TRUE
  AND diplome_verifie IS NOT TRUE
  AND identite_verifiee IS NOT TRUE
  AND tous_documents_valides IS NOT TRUE
  AND (score_fiabilite IS NULL OR score_fiabilite = 50.00)
  AND (total_missions_terminees IS NULL OR total_missions_terminees = 0)
  AND (heures_cumulees IS NULL OR heures_cumulees = 0)
  AND (heures_plateforme IS NULL OR heures_plateforme = 0)
  AND eligible_conversion_3200h IS NOT TRUE
  AND (statut_verification_aria IS NULL OR statut_verification_aria = 'EN_ATTENTE')
);

-- Fix 2: pol_etab_update — split into admin-only (all fields) and etab-admin (safe fields only)
DROP POLICY IF EXISTS pol_etab_update ON public.etablissements;

-- Platform admins can update everything
CREATE POLICY pol_etab_update_admin ON public.etablissements
FOR UPDATE TO authenticated
USING (est_admin())
WITH CHECK (est_admin());

-- Establishment admins can only update operational fields (trigger blocks the rest)
-- The WITH CHECK ensures they cannot change their own id or group assignment
CREATE POLICY pol_etab_update_self ON public.etablissements
FOR UPDATE TO authenticated
USING (est_admin_etablissement() AND id = mon_etablissement_id())
WITH CHECK (est_admin_etablissement() AND id = mon_etablissement_id());

-- Strengthen the existing trigger to also block subscription/billing fields
CREATE OR REPLACE FUNCTION fn_protect_etablissement_commercial()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Allow platform admins to change anything
  IF est_admin() THEN
    RETURN NEW;
  END IF;

  -- Block establishment admins from modifying financial/commercial fields
  IF NEW.taux_commission_negocie IS DISTINCT FROM OLD.taux_commission_negocie THEN
    RAISE EXCEPTION 'Modification du taux de commission non autorisée';
  END IF;
  IF NEW.stripe_customer_id IS DISTINCT FROM OLD.stripe_customer_id THEN
    RAISE EXCEPTION 'Modification du Stripe ID non autorisée';
  END IF;
  IF NEW.palier_commission_id IS DISTINCT FROM OLD.palier_commission_id THEN
    RAISE EXCEPTION 'Modification du palier de commission non autorisée';
  END IF;
  IF NEW.formule_abonnement IS DISTINCT FROM OLD.formule_abonnement THEN
    RAISE EXCEPTION 'Modification de la formule d''abonnement non autorisée';
  END IF;
  IF NEW.mode_facturation IS DISTINCT FROM OLD.mode_facturation THEN
    RAISE EXCEPTION 'Modification du mode de facturation non autorisée';
  END IF;
  IF NEW.chorus_pro_actif IS DISTINCT FROM OLD.chorus_pro_actif THEN
    RAISE EXCEPTION 'Modification de Chorus Pro non autorisée';
  END IF;
  IF NEW.chorus_pro_identifiant IS DISTINCT FROM OLD.chorus_pro_identifiant THEN
    RAISE EXCEPTION 'Modification de l''identifiant Chorus Pro non autorisée';
  END IF;
  IF NEW.delai_paiement_jours IS DISTINCT FROM OLD.delai_paiement_jours THEN
    RAISE EXCEPTION 'Modification du délai de paiement non autorisée';
  END IF;
  IF NEW.missions_mois_precedent IS DISTINCT FROM OLD.missions_mois_precedent THEN
    RAISE EXCEPTION 'Modification du compteur de missions non autorisée';
  END IF;
  IF NEW.palier_recalcule_le IS DISTINCT FROM OLD.palier_recalcule_le THEN
    RAISE EXCEPTION 'Modification de la date de recalcul non autorisée';
  END IF;
  IF NEW.groupe_sante_id IS DISTINCT FROM OLD.groupe_sante_id THEN
    RAISE EXCEPTION 'Modification du groupe de santé non autorisée';
  END IF;

  RETURN NEW;
END;
$$;

-- Ensure trigger exists (DROP + CREATE to be idempotent)
DROP TRIGGER IF EXISTS dec_proteger_etablissement_commercial ON public.etablissements;
CREATE TRIGGER dec_proteger_etablissement_commercial
  BEFORE UPDATE ON public.etablissements
  FOR EACH ROW
  EXECUTE FUNCTION fn_protect_etablissement_commercial();