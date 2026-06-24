-- Retire le RIB de la gate d'onboarding établissement : il n'est PAS nécessaire pour
-- publier une mission. Jolene n'est pas tiers-payeur / agence d'intérim et ne prélève
-- pas directement au lancement (les étabs paient la commission via Stripe ou virement
-- déclaré ; le prélèvement SEPA auto n'est pas actif). Le RIB sera demandé au moment
-- réellement utile (1er prélèvement SEPA / 1er remboursement), pas à l'inscription.
--
-- Seuls restent requis pour publier : contrat de service signé + identité du
-- représentant vérifiée + rattachement confirmé.

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

  -- RIB retiré de la gate (cf. en-tête de la migration).

  IF NOT COALESCE(v_etab.representant_identite_verifiee, false) THEN
    RAISE EXCEPTION 'Inscription incomplète : l''identité du représentant légal doit être vérifiée avant de publier des missions. Rendez-vous sur /etablissement/verification.'
      USING ERRCODE = 'check_violation';
  END IF;

  IF v_etab.coherence_identite = 'INCOHERENT' AND NOT COALESCE(v_etab.rattachement_verifie, false) THEN
    RAISE EXCEPTION 'Vérification en cours : le nom de votre établissement ne correspond pas à la raison sociale officielle (SIRET/FINESS). Corrigez vos informations sur /etablissement/profil, ou attendez la validation de notre équipe (24-48h).'
      USING ERRCODE = 'check_violation';
  END IF;

  IF NOT COALESCE(v_etab.rattachement_verifie, false) THEN
    RAISE EXCEPTION 'Vérification en cours : votre rattachement à l''établissement doit être confirmé. Si vous êtes le dirigeant, c''est automatique ; sinon, fournissez un justificatif de fonction sur /etablissement/verification. À défaut, notre équipe valide sous 24-48h.'
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$function$;
