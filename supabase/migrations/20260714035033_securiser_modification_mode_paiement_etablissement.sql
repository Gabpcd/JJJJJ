-- Le RPC de profil établissement précède le durcissement du trigger
-- fn_protect_etablissement_commercial. Sans marqueur interne strictement local
-- à la transaction, toute sauvegarde qui modifie le mode de paiement est
-- rejetée. On restaure ce chemin légitime tout en validant le mode côté serveur :
--   * STRIPE_RESERVATION reste retiré du lancement ;
--   * CHORUS_PRO ne peut être nouvellement choisi que par un secteur public ;
--   * SEPA_DEBIT ne peut être nouvellement choisi qu'après un mandat Stripe
--     effectivement enregistré par setup-sepa.

CREATE OR REPLACE FUNCTION public.fn_modifier_mon_etablissement(
  p_nom text DEFAULT NULL,
  p_finess text DEFAULT NULL,
  p_adresse_rue text DEFAULT NULL,
  p_adresse_ville text DEFAULT NULL,
  p_adresse_code_postal text DEFAULT NULL,
  p_adresse_departement text DEFAULT NULL,
  p_email_contact text DEFAULT NULL,
  p_telephone text DEFAULT NULL,
  p_adresse_lat numeric DEFAULT NULL,
  p_adresse_lng numeric DEFAULT NULL,
  p_taux_majoration_nuit numeric DEFAULT NULL,
  p_taux_majoration_dimanche numeric DEFAULT NULL,
  p_taux_majoration_ferie numeric DEFAULT NULL,
  p_couleur_theme text DEFAULT NULL,
  p_convention_collective text DEFAULT NULL,
  p_mode_paiement_commission text DEFAULT NULL,
  p_logo_url text DEFAULT NULL,
  p_contrat_url text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_etab_id uuid := public.mon_etablissement_id();
  v_etab record;
  v_ip inet;
  v_user_agent text;
  v_headers jsonb;
  v_champs_modifies jsonb := '[]'::jsonb;
BEGIN
  IF auth.uid() IS NULL OR v_etab_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Établissement non trouvé');
  END IF;

  IF p_couleur_theme IS NOT NULL
     AND p_couleur_theme !~ '^#[0-9a-fA-F]{6}$' THEN
    RETURN jsonb_build_object('error', 'Couleur invalide (format #RRGGBB)');
  END IF;

  IF p_mode_paiement_commission IS NOT NULL
     AND p_mode_paiement_commission NOT IN (
       'FACTURE_MENSUELLE', 'SEPA_DEBIT', 'CHORUS_PRO'
     ) THEN
    RETURN jsonb_build_object('error', 'Mode de paiement non autorisé');
  END IF;

  SELECT e.mode_paiement_commission,
         COALESCE(e.est_secteur_public, false) AS est_secteur_public,
         e.stripe_customer_id,
         e.stripe_sepa_payment_method_id
    INTO v_etab
  FROM public.etablissements e
  WHERE e.id = v_etab_id
    AND e.supprime_le IS NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Établissement non trouvé');
  END IF;

  -- Une valeur historique inchangée ne bloque pas la sauvegarde du profil.
  -- Les prérequis sont exigés au moment exact où un nouveau mode est choisi.
  IF p_mode_paiement_commission IS DISTINCT FROM v_etab.mode_paiement_commission THEN
    IF p_mode_paiement_commission = 'CHORUS_PRO'
       AND NOT v_etab.est_secteur_public THEN
      RETURN jsonb_build_object(
        'error',
        'Chorus Pro est réservé aux établissements publics vérifiés.'
      );
    END IF;

    IF p_mode_paiement_commission = 'SEPA_DEBIT'
       AND (
         v_etab.stripe_customer_id IS NULL
         OR v_etab.stripe_customer_id !~ '^cus_[A-Za-z0-9]+$'
         OR v_etab.stripe_sepa_payment_method_id IS NULL
         OR v_etab.stripe_sepa_payment_method_id !~ '^pm_[A-Za-z0-9]+$'
       ) THEN
      RETURN jsonb_build_object(
        'error',
        'Confirmez d’abord votre mandat SEPA avant de choisir le prélèvement automatique.'
      );
    END IF;
  END IF;

  -- La GUC ne contourne dans le protector que les anciens champs commerciaux,
  -- après ses contrôles de conformité. Elle est révoquée immédiatement après
  -- l'UPDATE et ne sort jamais de cette transaction RPC.
  PERFORM pg_catalog.set_config('app.internal_operation', 'true', true);

  UPDATE public.etablissements
  SET nom = COALESCE(p_nom, nom),
      finess = COALESCE(p_finess, finess),
      adresse_rue = COALESCE(p_adresse_rue, adresse_rue),
      adresse_ville = COALESCE(p_adresse_ville, adresse_ville),
      adresse_code_postal = COALESCE(p_adresse_code_postal, adresse_code_postal),
      adresse_departement = COALESCE(p_adresse_departement, adresse_departement),
      email_contact = COALESCE(p_email_contact, email_contact),
      telephone_contact = COALESCE(p_telephone, telephone_contact),
      adresse_lat = COALESCE(p_adresse_lat, adresse_lat),
      adresse_lng = COALESCE(p_adresse_lng, adresse_lng),
      taux_majoration_nuit_pourcent = COALESCE(
        p_taux_majoration_nuit, taux_majoration_nuit_pourcent
      ),
      taux_majoration_dimanche_pourcent = COALESCE(
        p_taux_majoration_dimanche, taux_majoration_dimanche_pourcent
      ),
      taux_majoration_ferie_pourcent = COALESCE(
        p_taux_majoration_ferie, taux_majoration_ferie_pourcent
      ),
      couleur_theme = COALESCE(p_couleur_theme, couleur_theme),
      convention_collective = COALESCE(p_convention_collective, convention_collective),
      mode_paiement_commission = COALESCE(
        p_mode_paiement_commission, mode_paiement_commission
      ),
      logo_url = COALESCE(p_logo_url, logo_url),
      contrat_url = COALESCE(p_contrat_url, contrat_url),
      contrat_uploade_le = CASE
        WHEN p_contrat_url IS NOT NULL THEN transaction_timestamp()
        ELSE contrat_uploade_le
      END,
      contrat_valide = CASE
        WHEN p_contrat_url IS NOT NULL THEN false
        ELSE contrat_valide
      END,
      modifie_le = transaction_timestamp()
  WHERE id = v_etab_id;

  PERFORM pg_catalog.set_config('app.internal_operation', 'false', true);

  BEGIN
    v_headers := current_setting('request.headers', true)::jsonb;
    v_ip := NULLIF(
      btrim(split_part(COALESCE(v_headers->>'x-forwarded-for', ''), ',', 1)),
      ''
    )::inet;
    v_user_agent := NULLIF(v_headers->>'user-agent', '');
  EXCEPTION WHEN OTHERS THEN
    v_ip := NULL;
    v_user_agent := NULL;
  END;

  IF p_nom IS NOT NULL OR p_finess IS NOT NULL THEN
    v_champs_modifies := v_champs_modifies || '"identite"'::jsonb;
  END IF;
  IF p_adresse_rue IS NOT NULL OR p_adresse_ville IS NOT NULL THEN
    v_champs_modifies := v_champs_modifies || '"adresse"'::jsonb;
  END IF;
  IF p_email_contact IS NOT NULL OR p_telephone IS NOT NULL THEN
    v_champs_modifies := v_champs_modifies || '"contact"'::jsonb;
  END IF;
  IF p_taux_majoration_nuit IS NOT NULL
     OR p_taux_majoration_dimanche IS NOT NULL
     OR p_taux_majoration_ferie IS NOT NULL THEN
    v_champs_modifies := v_champs_modifies || '"taux_majoration"'::jsonb;
  END IF;
  IF p_convention_collective IS NOT NULL THEN
    v_champs_modifies := v_champs_modifies || '"convention_collective"'::jsonb;
  END IF;
  IF p_mode_paiement_commission IS NOT NULL THEN
    v_champs_modifies := v_champs_modifies || '"mode_paiement"'::jsonb;
  END IF;
  IF p_contrat_url IS NOT NULL THEN
    v_champs_modifies := v_champs_modifies || '"contrat"'::jsonb;
  END IF;

  PERFORM public.fn_ecrire_audit(
    auth.uid(),
    'ADMIN_ETABLISSEMENT',
    'ETABLISSEMENT_MODIFICATION',
    'etablissement',
    v_etab_id,
    NULL,
    jsonb_build_object('champs_modifies', v_champs_modifies),
    v_ip,
    v_user_agent
  );

  RETURN jsonb_build_object('success', true);
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_modifier_mon_etablissement(
  text, text, text, text, text, text, text, text,
  numeric, numeric, numeric, numeric, numeric,
  text, text, text, text, text
) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.fn_modifier_mon_etablissement(
  text, text, text, text, text, text, text, text,
  numeric, numeric, numeric, numeric, numeric,
  text, text, text, text, text
) TO authenticated, service_role;
