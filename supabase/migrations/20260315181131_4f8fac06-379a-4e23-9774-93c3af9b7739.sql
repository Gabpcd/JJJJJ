-- Add p_mode_paiement_commission to fn_modifier_mon_etablissement
CREATE OR REPLACE FUNCTION public.fn_modifier_mon_etablissement(
  p_nom text,
  p_finess text DEFAULT NULL,
  p_adresse_rue text DEFAULT NULL,
  p_adresse_ville text DEFAULT NULL,
  p_adresse_code_postal text DEFAULT NULL,
  p_adresse_departement text DEFAULT NULL,
  p_email_contact text DEFAULT NULL,
  p_telephone_contact text DEFAULT NULL,
  p_adresse_lat double precision DEFAULT NULL,
  p_adresse_lng double precision DEFAULT NULL,
  p_taux_majoration_nuit numeric DEFAULT NULL,
  p_taux_majoration_dimanche numeric DEFAULT NULL,
  p_taux_majoration_ferie numeric DEFAULT NULL,
  p_couleur_theme text DEFAULT NULL,
  p_convention_collective text DEFAULT NULL,
  p_mode_paiement_commission text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_etab_id uuid;
BEGIN
  -- Validate mode_paiement_commission
  IF p_mode_paiement_commission IS NOT NULL AND p_mode_paiement_commission NOT IN ('STRIPE_RESERVATION', 'FACTURE_MENSUELLE', 'CHORUS_PRO') THEN
    RETURN json_build_object('error', 'Mode de paiement invalide');
  END IF;

  SELECT etablissement_id INTO v_etab_id
  FROM public.utilisateurs_etablissements
  WHERE utilisateur_id = auth.uid()
  LIMIT 1;

  IF v_etab_id IS NULL THEN
    RETURN json_build_object('error', 'Établissement introuvable');
  END IF;

  UPDATE public.etablissements SET
    nom = COALESCE(p_nom, nom),
    finess = p_finess,
    adresse_rue = COALESCE(p_adresse_rue, adresse_rue),
    adresse_ville = COALESCE(p_adresse_ville, adresse_ville),
    adresse_code_postal = COALESCE(p_adresse_code_postal, adresse_code_postal),
    adresse_departement = p_adresse_departement,
    email_contact = COALESCE(p_email_contact, email_contact),
    telephone_contact = p_telephone_contact,
    adresse_lat = p_adresse_lat,
    adresse_lng = p_adresse_lng,
    taux_majoration_nuit_pourcent = COALESCE(p_taux_majoration_nuit, taux_majoration_nuit_pourcent),
    taux_majoration_dimanche_pourcent = COALESCE(p_taux_majoration_dimanche, taux_majoration_dimanche_pourcent),
    taux_majoration_ferie_pourcent = COALESCE(p_taux_majoration_ferie, taux_majoration_ferie_pourcent),
    couleur_theme = COALESCE(p_couleur_theme, couleur_theme),
    convention_collective = p_convention_collective,
    mode_paiement_commission = COALESCE(p_mode_paiement_commission, mode_paiement_commission),
    modifie_le = now()
  WHERE id = v_etab_id;

  RETURN json_build_object('success', true);
END;
$$;