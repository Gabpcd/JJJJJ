-- 1. Gate de publication : exiger la vérification d'identité du représentant légal.
--
-- KYC : le représentant signe le contrat et engage juridiquement l'établissement.
-- Inscription libre, mais on bloque la PUBLICATION de missions tant que l'identité
-- du représentant n'est pas vérifiée (en plus du contrat de service + RIB). Cohérent
-- avec l'approche existante (gate publication, pas blocage au signup).

CREATE OR REPLACE FUNCTION public.fn_trg_verifier_onboarding_etab()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_etab RECORD;
BEGIN
  IF est_admin() THEN RETURN NEW; END IF;
  IF COALESCE(current_setting('app.internal_operation', true), '') = 'true' THEN RETURN NEW; END IF;

  SELECT contrat_service_signe, rib_s3_key, representant_identite_verifiee
  INTO v_etab
  FROM etablissements WHERE id = NEW.etablissement_id;

  IF NOT FOUND THEN RETURN NEW; END IF;

  IF NOT COALESCE(v_etab.contrat_service_signe, false) THEN
    RAISE EXCEPTION 'Inscription incomplète : vous devez signer le contrat de service Jolene avant de publier des missions. Rendez-vous sur /etablissement/finaliser-inscription.'
      USING ERRCODE = 'check_violation';
  END IF;

  IF v_etab.rib_s3_key IS NULL OR v_etab.rib_s3_key = '' THEN
    RAISE EXCEPTION 'Inscription incomplète : vous devez fournir un RIB avant de publier des missions. Rendez-vous sur /etablissement/finaliser-inscription.'
      USING ERRCODE = 'check_violation';
  END IF;

  IF NOT COALESCE(v_etab.representant_identite_verifiee, false) THEN
    RAISE EXCEPTION 'Inscription incomplète : l''identité du représentant légal doit être vérifiée avant de publier des missions. Rendez-vous sur /etablissement/verification.'
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$function$;
