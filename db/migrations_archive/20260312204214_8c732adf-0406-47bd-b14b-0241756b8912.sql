-- Protect etablissement commercial fields from self-modification by admin_etablissement
CREATE OR REPLACE FUNCTION public.fn_protect_etablissement_commercial()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- If caller is an etablissement admin (not platform admin), block commercial fields
  IF public.est_admin_etablissement() AND NOT public.est_admin() THEN
    NEW.taux_commission_negocie := OLD.taux_commission_negocie;
    NEW.palier_commission_id := OLD.palier_commission_id;
    NEW.missions_mois_precedent := OLD.missions_mois_precedent;
    NEW.palier_recalcule_le := OLD.palier_recalcule_le;
    NEW.formule_abonnement := OLD.formule_abonnement;
    NEW.stripe_customer_id := OLD.stripe_customer_id;
    NEW.delai_paiement_jours := OLD.delai_paiement_jours;
    NEW.mode_facturation := OLD.mode_facturation;
    NEW.chorus_pro_actif := OLD.chorus_pro_actif;
    NEW.chorus_pro_identifiant := OLD.chorus_pro_identifiant;
    NEW.groupe_sante_id := OLD.groupe_sante_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_protect_etablissement_commercial ON public.etablissements;
CREATE TRIGGER trg_protect_etablissement_commercial
  BEFORE UPDATE ON public.etablissements
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_protect_etablissement_commercial();