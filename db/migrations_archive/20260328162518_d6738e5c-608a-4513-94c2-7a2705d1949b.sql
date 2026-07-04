
-- Fix fn_modifier_mon_etablissement: wrong column names (telephone vs telephone_contact, taux_majoration_* vs taux_majoration_*_pourcent)
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
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_etab_id UUID := mon_etablissement_id();
BEGIN
    IF v_etab_id IS NULL AND NOT est_admin() THEN
        RETURN '{"error":"Établissement non trouvé"}'::JSONB;
    END IF;

    -- Validation couleur hex
    IF p_couleur_theme IS NOT NULL AND p_couleur_theme !~ '^#[0-9a-fA-F]{6}$' THEN
        RETURN '{"error":"Couleur invalide (format #RRGGBB)"}'::JSONB;
    END IF;

    UPDATE etablissements SET
        nom = COALESCE(p_nom, nom),
        finess = COALESCE(p_finess, finess),
        adresse_rue = COALESCE(p_adresse_rue, adresse_rue),
        adresse_ville = COALESCE(p_adresse_ville, adresse_ville),
        adresse_code_postal = COALESCE(p_adresse_code_postal, adresse_code_postal),
        adresse_departement = COALESCE(p_adresse_departement, adresse_departement),
        email_contact = COALESCE(p_email_contact, email_contact),
        telephone_contact = COALESCE(p_telephone, telephone_contact),
        adresse_lat = COALESCE(p_adresse_lat, adresse_lat),
        adresse_lng = COALESCE(p_adresse_lng, adresse_lng),
        taux_majoration_nuit_pourcent = COALESCE(p_taux_majoration_nuit, taux_majoration_nuit_pourcent),
        taux_majoration_dimanche_pourcent = COALESCE(p_taux_majoration_dimanche, taux_majoration_dimanche_pourcent),
        taux_majoration_ferie_pourcent = COALESCE(p_taux_majoration_ferie, taux_majoration_ferie_pourcent),
        couleur_theme = COALESCE(p_couleur_theme, couleur_theme),
        convention_collective = COALESCE(p_convention_collective, convention_collective),
        mode_paiement_commission = COALESCE(p_mode_paiement_commission, mode_paiement_commission),
        logo_url = COALESCE(p_logo_url, logo_url),
        contrat_url = COALESCE(p_contrat_url, contrat_url),
        contrat_uploade_le = CASE WHEN p_contrat_url IS NOT NULL THEN NOW() ELSE contrat_uploade_le END,
        modifie_le = NOW()
    WHERE id = v_etab_id;

    RETURN '{"success":true}'::JSONB;
END;
$$;

-- Fix fn_exporter_rgpd_etablissement: wrong column names in contrats_mission
CREATE OR REPLACE FUNCTION public.fn_exporter_rgpd_etablissement()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_etab_id UUID := mon_etablissement_id();
    v_result JSONB;
BEGIN
    IF v_etab_id IS NULL THEN RETURN jsonb_build_object('error', 'Accès refusé'); END IF;

    SELECT jsonb_build_object(
        'etablissement', (SELECT row_to_json(e) FROM (
            SELECT nom, type::TEXT, siret, finess, email_contact, telephone_contact,
                adresse_rue, adresse_code_postal, adresse_ville, convention_collective,
                cree_le, modifie_le
            FROM etablissements WHERE id = v_etab_id
        ) e),
        'missions', (SELECT COALESCE(jsonb_agg(row_to_json(m)), '[]') FROM (
            SELECT id, intitule, statut::TEXT, debut_le, fin_le, taux_horaire_base, total_brut, cree_le
            FROM missions WHERE etablissement_id = v_etab_id ORDER BY cree_le DESC LIMIT 200
        ) m),
        'factures', (SELECT COALESCE(jsonb_agg(row_to_json(f)), '[]') FROM (
            SELECT numero_facture, montant_ht, montant_ttc, statut, date_emission, date_paiement
            FROM factures WHERE etablissement_id = v_etab_id ORDER BY date_emission DESC
        ) f),
        'contrats', (SELECT COALESCE(jsonb_agg(row_to_json(c)), '[]') FROM (
            SELECT type_contrat, statut, cree_le, modifie_le
            FROM contrats_mission WHERE etablissement_id = v_etab_id ORDER BY cree_le DESC LIMIT 200
        ) c),
        'export_date', NOW()
    ) INTO v_result;

    RETURN v_result;
END;
$$;

-- Revoke anon execute on both
REVOKE EXECUTE ON FUNCTION public.fn_modifier_mon_etablissement FROM anon;
REVOKE EXECUTE ON FUNCTION public.fn_exporter_rgpd_etablissement FROM anon;
