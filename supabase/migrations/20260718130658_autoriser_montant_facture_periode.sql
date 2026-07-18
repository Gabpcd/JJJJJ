-- Le garde-fou anti-seed historique comparait chaque note d'honoraires au
-- montant total de la mission. Il bloquait donc mécaniquement toute facture
-- hebdomadaire correcte. Pour une mission HEBDO_ET_FINALE, la référence est
-- désormais le montant calculé sur la période exacte portée par la facture.
CREATE OR REPLACE FUNCTION public.fn_anti_seed_facture_honoraire()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_mission_net numeric;
  v_strategie public.strategie_facturation;
  v_montant_attendu numeric;
  v_calcul_periode jsonb;
  v_ecart numeric;
  v_ctx text;
  v_admin_reason text;
BEGIN
  v_ctx := NULLIF(current_setting('jolene.generate_invoice_context', true), '');
  IF v_ctx = 'true' THEN
    RETURN NEW;
  END IF;

  v_admin_reason := NULLIF(current_setting('jolene.admin_seed_override_reason', true), '');
  IF v_admin_reason IS NOT NULL THEN
    INSERT INTO public.journaux_audit (
      acteur_id, type_acteur, action, type_ressource, id_ressource, details
    ) VALUES (
      auth.uid(), 'ADMIN_PLATEFORME', 'OVERRIDE_ANTI_SEED',
      'factures_honoraires', NEW.id,
      jsonb_build_object(
        'reason', v_admin_reason,
        'mission_id', NEW.mission_id,
        'montant_ht', NEW.montant_ht,
        'numero_facture', NEW.numero_facture
      )
    );
    RETURN NEW;
  END IF;

  IF public.est_admin() THEN
    INSERT INTO public.journaux_audit (
      acteur_id, type_acteur, action, type_ressource, id_ressource, details
    ) VALUES (
      auth.uid(), 'ADMIN_PLATEFORME', 'OVERRIDE_ANTI_SEED',
      'factures_honoraires', NEW.id,
      jsonb_build_object(
        'reason', 'admin_context (résolution litige / ajustement financier)',
        'mission_id', NEW.mission_id,
        'montant_ht', NEW.montant_ht,
        'numero_facture', NEW.numero_facture
      )
    );
    RETURN NEW;
  END IF;

  SELECT m.net_a_payer, m.strategie_facturation
  INTO v_mission_net, v_strategie
  FROM public.missions m
  WHERE m.id = NEW.mission_id;

  IF v_mission_net IS NULL THEN
    RAISE EXCEPTION 'anti-seed facture: mission % sans snapshot financier (net_a_payer=NULL). Utilisez generate-invoice ou définissez jolene.admin_seed_override_reason.',
      NEW.mission_id USING ERRCODE = 'check_violation';
  END IF;

  IF v_strategie = 'HEBDO_ET_FINALE'
     AND NEW.periode_debut IS NOT NULL
     AND NEW.periode_fin IS NOT NULL THEN
    v_calcul_periode := public.fn_calculer_montant_periode(
      NEW.mission_id,
      NEW.periode_debut,
      NEW.periode_fin
    );
    v_montant_attendu := NULLIF(v_calcul_periode->>'montant_ht_periode', '')::numeric;
  ELSE
    v_montant_attendu := v_mission_net;
  END IF;

  IF v_montant_attendu IS NULL THEN
    RAISE EXCEPTION 'anti-seed facture: montant attendu indéterminable pour mission % et période %–%.',
      NEW.mission_id, NEW.periode_debut, NEW.periode_fin
      USING ERRCODE = 'check_violation';
  END IF;

  v_ecart := abs(COALESCE(NEW.montant_ht, 0) - v_montant_attendu);
  IF v_ecart > 0.50 THEN
    RAISE EXCEPTION 'anti-seed facture: montant_ht % incohérent avec le montant attendu % pour la période %–% (écart=%€ > 0.50€).',
      NEW.montant_ht,
      v_montant_attendu,
      NEW.periode_debut,
      NEW.periode_fin,
      v_ecart
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_anti_seed_facture_honoraire()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_anti_seed_facture_honoraire()
  TO service_role;
