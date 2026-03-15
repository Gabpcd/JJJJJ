-- 1. Fix fn_modifier_mon_profil to accept all frontend params
CREATE OR REPLACE FUNCTION public.fn_modifier_mon_profil(
    p_telephone text DEFAULT NULL,
    p_adresse_rue text DEFAULT NULL,
    p_adresse_ville text DEFAULT NULL,
    p_adresse_code_postal text DEFAULT NULL,
    p_rayon_deplacement_km integer DEFAULT NULL,
    p_prenom text DEFAULT NULL,
    p_nom text DEFAULT NULL,
    p_date_naissance text DEFAULT NULL,
    p_type_contrat text DEFAULT NULL,
    p_types_contrat_acceptes text DEFAULT NULL,
    p_numero_rpps text DEFAULT NULL,
    p_numero_adeli text DEFAULT NULL,
    p_adresse_lat numeric DEFAULT NULL,
    p_adresse_lng numeric DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
    UPDATE soignants SET
        prenom = COALESCE(p_prenom, prenom),
        nom = COALESCE(p_nom, nom),
        telephone = COALESCE(p_telephone, telephone),
        date_naissance = CASE WHEN p_date_naissance IS NOT NULL AND p_date_naissance <> '' THEN p_date_naissance::date ELSE date_naissance END,
        type_contrat = COALESCE(p_type_contrat, type_contrat),
        types_contrat_acceptes = CASE WHEN p_types_contrat_acceptes IS NOT NULL THEN p_types_contrat_acceptes::jsonb ELSE types_contrat_acceptes END,
        numero_rpps = COALESCE(p_numero_rpps, numero_rpps),
        numero_adeli = COALESCE(p_numero_adeli, numero_adeli),
        adresse_rue = COALESCE(p_adresse_rue, adresse_rue),
        adresse_ville = COALESCE(p_adresse_ville, adresse_ville),
        adresse_code_postal = COALESCE(p_adresse_code_postal, adresse_code_postal),
        adresse_lat = COALESCE(p_adresse_lat, adresse_lat),
        adresse_lng = COALESCE(p_adresse_lng, adresse_lng),
        rayon_deplacement_km = COALESCE(p_rayon_deplacement_km, rayon_deplacement_km),
        modifie_le = NOW()
        -- JAMAIS : rpps_verifie, diplome_verifie, identite_verifiee,
        -- score_fiabilite, tous_documents_valides, heures_cumulees
    WHERE id = auth.uid();

    RETURN '{"success":true}'::JSONB;
END;
$$;

-- 2. Fix documents_soignants INSERT RLS to allow valide_depuis/valide_jusqua/est_critique
DROP POLICY IF EXISTS pol_doc_insert ON public.documents_soignants;
CREATE POLICY pol_doc_insert ON public.documents_soignants
FOR INSERT TO authenticated
WITH CHECK (
    est_admin() OR (
        (soignant_id = auth.uid())
        AND (statut_verification = 'EN_ATTENTE'::statut_verification)
        AND (verifie_par IS NULL)
        AND (verifie_le IS NULL)
        AND (motif_rejet IS NULL)
    )
);