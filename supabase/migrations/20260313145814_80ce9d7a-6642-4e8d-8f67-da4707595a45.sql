DROP FUNCTION IF EXISTS public.fn_modifier_tva_liberal(boolean, text);

CREATE OR REPLACE FUNCTION public.fn_modifier_tva_liberal(p_assujetti_tva boolean, p_numero_tva text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE soignants
  SET assujetti_tva = p_assujetti_tva,
      numero_tva = CASE WHEN p_assujetti_tva THEN p_numero_tva ELSE NULL END,
      modifie_le = now()
  WHERE id = auth.uid();
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Soignant introuvable');
  END IF;
  
  RETURN jsonb_build_object('success', true);
END;
$$;

-- Also recreate fn_modifier_mon_etablissement with convention_collective param
DROP FUNCTION IF EXISTS public.fn_modifier_mon_etablissement(text, text, text, text, text, text, text, text, numeric, numeric, numeric, numeric, numeric);

CREATE OR REPLACE FUNCTION public.fn_modifier_mon_etablissement(
  p_nom text,
  p_finess text DEFAULT NULL,
  p_adresse_rue text DEFAULT NULL,
  p_adresse_ville text DEFAULT NULL,
  p_adresse_code_postal text DEFAULT NULL,
  p_adresse_departement text DEFAULT NULL,
  p_email_contact text DEFAULT NULL,
  p_telephone_contact text DEFAULT NULL,
  p_adresse_lat numeric DEFAULT NULL,
  p_adresse_lng numeric DEFAULT NULL,
  p_taux_majoration_nuit numeric DEFAULT NULL,
  p_taux_majoration_dimanche numeric DEFAULT NULL,
  p_taux_majoration_ferie numeric DEFAULT NULL,
  p_convention_collective text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_etab_id uuid;
BEGIN
  SELECT etablissement_id INTO v_etab_id
  FROM admins_etablissement
  WHERE utilisateur_id = auth.uid()
  LIMIT 1;
  
  IF v_etab_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Établissement introuvable');
  END IF;
  
  UPDATE etablissements SET
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
    convention_collective = p_convention_collective,
    modifie_le = now()
  WHERE id = v_etab_id;
  
  RETURN jsonb_build_object('success', true);
END;
$$;