-- B2 : cohérence nom déclaré ↔ raison sociale SIRET/FINESS, calculée à l'inscription.
-- Si incohérent et non validé par un admin, l'établissement ne peut PAS publier
-- (gate dans le trigger d'onboarding). L'admin peut lever le blocage en validant.
ALTER TABLE public.etablissements ADD COLUMN IF NOT EXISTS coherence_identite text;
COMMENT ON COLUMN public.etablissements.coherence_identite IS
  'Cohérence nom déclaré ↔ raison sociale SIRET/FINESS, calculée à l''inscription : OK / PARTIEL / INCOHERENT / NULL (non calculée, legacy).';

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

  SELECT contrat_service_signe, rib_s3_key, representant_identite_verifiee,
         coherence_identite, rattachement_verifie
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

  -- Cohérence SIRET/FINESS/nom : si incohérent et pas encore validé par un admin, bloquer.
  IF v_etab.coherence_identite = 'INCOHERENT' AND NOT COALESCE(v_etab.rattachement_verifie, false) THEN
    RAISE EXCEPTION 'Vérification en cours : le nom de votre établissement ne correspond pas à la raison sociale officielle (SIRET/FINESS). Corrigez vos informations sur /etablissement/profil, ou attendez la validation de notre équipe (24-48h).'
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$function$;
