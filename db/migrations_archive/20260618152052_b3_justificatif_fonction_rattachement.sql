-- B3 : la personne physique rattachée à l'établissement n'est pas forcément le
-- dirigeant (RH, chef de service…). On exige donc :
--   • pièce d'identité vérifiée IA (déjà en place), ET
--   • soit un match dirigeant INSEE (auto), soit un JUSTIFICATIF DE FONCTION
--     authentifié par IA (attestation employeur, délégation, fiche de poste…).
-- L'ancien rattachement EMAIL_PRO (email confirmé = rattaché) est retiré : trop faible.

ALTER TABLE public.etablissements
  ADD COLUMN IF NOT EXISTS justificatif_fonction_s3_key text,
  ADD COLUMN IF NOT EXISTS justificatif_fonction_type text,
  ADD COLUMN IF NOT EXISTS justificatif_fonction_type_mime text,
  ADD COLUMN IF NOT EXISTS justificatif_fonction_verifie boolean,
  ADD COLUMN IF NOT EXISTS justificatif_fonction_verifie_le timestamptz,
  ADD COLUMN IF NOT EXISTS justificatif_fonction_resultat_ia jsonb;

-- Rattachement adaptatif : DIRIGEANT (match INSEE) OU JUSTIFICATIF (vérifié IA).
CREATE OR REPLACE FUNCTION public.fn_evaluer_rattachement_etablissement(p_etablissement_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_etab RECORD;
  v_methode text := 'ADMIN';
  v_verifie boolean := false;
  v_match boolean := false;
BEGIN
  IF NOT (est_admin() OR p_etablissement_id = mon_etablissement_id()) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non autorisé');
  END IF;

  SELECT finess_est_public, dirigeants, representant_nom, representant_prenom,
         representant_identite_verifiee, justificatif_fonction_verifie
  INTO v_etab FROM public.etablissements WHERE id = p_etablissement_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Établissement introuvable');
  END IF;

  -- 1) AUTO_DIRIGEANT : identité vérifiée + match avec un dirigeant personne physique.
  IF v_etab.representant_identite_verifiee IS TRUE
     AND v_etab.representant_nom IS NOT NULL
     AND v_etab.dirigeants IS NOT NULL THEN
    SELECT TRUE INTO v_match
    FROM jsonb_array_elements(v_etab.dirigeants) AS d
    WHERE public.fn_normaliser_nom(d->>'type_dirigeant') LIKE '%physique%'
      AND public.fn_normaliser_nom(d->>'nom') = public.fn_normaliser_nom(v_etab.representant_nom)
      AND (
        v_etab.representant_prenom IS NULL
        OR public.fn_normaliser_nom(d->>'prenoms') LIKE '%' || public.fn_normaliser_nom(v_etab.representant_prenom) || '%'
      )
    LIMIT 1;
    IF v_match IS TRUE THEN
      v_methode := 'AUTO_DIRIGEANT'; v_verifie := TRUE;
    END IF;
  END IF;

  -- 2) JUSTIFICATIF : identité vérifiée + justificatif de fonction authentifié IA
  --    (cas du non-dirigeant : RH, chef de service, délégataire).
  IF NOT v_verifie
     AND v_etab.representant_identite_verifiee IS TRUE
     AND v_etab.justificatif_fonction_verifie IS TRUE THEN
    v_methode := 'JUSTIFICATIF'; v_verifie := TRUE;
  END IF;

  -- 3) sinon ADMIN (revue manuelle).

  UPDATE public.etablissements SET
    rattachement_methode = v_methode,
    rattachement_verifie = v_verifie,
    rattachement_verifie_le = CASE WHEN v_verifie THEN now() ELSE NULL END
  WHERE id = p_etablissement_id;

  RETURN jsonb_build_object('success', true, 'methode', v_methode, 'verifie', v_verifie, 'match_dirigeant', COALESCE(v_match, false));
END;
$function$;

-- Gate publication : la personne doit être RATTACHÉE (dirigeant / justificatif / admin).
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

  -- Cohérence SIRET/FINESS/nom (B2).
  IF v_etab.coherence_identite = 'INCOHERENT' AND NOT COALESCE(v_etab.rattachement_verifie, false) THEN
    RAISE EXCEPTION 'Vérification en cours : le nom de votre établissement ne correspond pas à la raison sociale officielle (SIRET/FINESS). Corrigez vos informations sur /etablissement/profil, ou attendez la validation de notre équipe (24-48h).'
      USING ERRCODE = 'check_violation';
  END IF;

  -- Rattachement de la personne physique (B3) : dirigeant, justificatif IA, ou admin.
  IF NOT COALESCE(v_etab.rattachement_verifie, false) THEN
    RAISE EXCEPTION 'Vérification en cours : votre rattachement à l''établissement doit être confirmé. Si vous êtes le dirigeant, c''est automatique ; sinon, fournissez un justificatif de fonction sur /etablissement/verification. À défaut, notre équipe valide sous 24-48h.'
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$function$;
