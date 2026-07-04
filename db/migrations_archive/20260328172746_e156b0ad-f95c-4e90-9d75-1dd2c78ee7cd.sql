
CREATE OR REPLACE FUNCTION public.fn_bfa_info(p_annee INTEGER DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = public
AS $$
DECLARE
    v_etab_id UUID;
    v_groupe_id UUID;
    v_bfa_eligible BOOLEAN;
    v_bfa_contrat_signe TIMESTAMP WITH TIME ZONE;
    v_annee INTEGER;
    v_bfa RECORD;
    v_missions INTEGER;
    v_commissions NUMERIC;
    v_paliers JSONB;
    v_palier_actuel TEXT;
    v_prochain RECORD;
    v_missions_manquantes INTEGER;
BEGIN
    v_etab_id := mon_etablissement_id();
    IF v_etab_id IS NULL AND NOT est_admin() THEN 
        RETURN jsonb_build_object('eligible', false, 'raison', 'Non autorise'); 
    END IF;
    
    v_annee := COALESCE(p_annee, EXTRACT(YEAR FROM NOW())::INTEGER);

    SELECT e.groupe_sante_id, g.bfa_eligible, g.bfa_contrat_signe_le
    INTO v_groupe_id, v_bfa_eligible, v_bfa_contrat_signe
    FROM etablissements e
    LEFT JOIN groupes_sante g ON g.id = e.groupe_sante_id
    WHERE e.id = v_etab_id;

    IF v_groupe_id IS NULL OR v_bfa_eligible IS NOT TRUE OR v_bfa_contrat_signe IS NULL THEN
        RETURN jsonb_build_object('eligible', false, 'raison', 
            CASE 
                WHEN v_groupe_id IS NULL THEN 'Reserve aux groupes de sante'
                WHEN v_bfa_eligible IS NOT TRUE THEN 'Votre groupe nest pas eligible au BFA'
                ELSE 'Contrat BFA non signe'
            END
        );
    END IF;

    SELECT COUNT(*), COALESCE(SUM(montant_commission_ht), 0)
    INTO v_missions, v_commissions
    FROM missions m JOIN etablissements e ON e.id = m.etablissement_id
    WHERE e.groupe_sante_id = v_groupe_id AND m.statut = 'TERMINEE'
    AND EXTRACT(YEAR FROM m.fin_le) = v_annee;

    SELECT * INTO v_bfa FROM bfa_suivi WHERE groupe_id = v_groupe_id AND annee = v_annee;

    SELECT nom INTO v_palier_actuel FROM paliers_bfa
    WHERE est_actif = TRUE AND missions_min <= v_missions
    AND (missions_max IS NULL OR missions_max >= v_missions)
    ORDER BY ordre DESC LIMIT 1;

    SELECT * INTO v_prochain FROM paliers_bfa
    WHERE est_actif = TRUE AND missions_min > v_missions
    ORDER BY missions_min ASC LIMIT 1;

    v_missions_manquantes := CASE WHEN v_prochain IS NOT NULL THEN v_prochain.missions_min - v_missions ELSE 0 END;

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'nom', nom, 'taux_bfa', taux_bfa, 'missions_min', missions_min, 'missions_max', missions_max,
        'atteint', (v_missions >= missions_min)
    ) ORDER BY ordre), '[]'::JSONB) INTO v_paliers FROM paliers_bfa WHERE est_actif = TRUE;

    RETURN jsonb_build_object(
        'eligible', true,
        'annee', v_annee,
        'est_groupe', true,
        'missions_annee', v_missions,
        'commissions_ht_annee', v_commissions,
        'palier_actuel', COALESCE(v_palier_actuel, 'Aucun'),
        'montant_bfa_estime', CASE 
            WHEN v_palier_actuel IS NOT NULL THEN ROUND(v_commissions * (
                SELECT taux_bfa FROM paliers_bfa WHERE nom = v_palier_actuel AND est_actif = TRUE LIMIT 1
            ) / 100, 2)
            ELSE 0 END,
        'prochain_palier', CASE WHEN v_prochain IS NOT NULL THEN v_prochain.nom ELSE NULL END,
        'missions_manquantes', v_missions_manquantes,
        'bfa_verse', COALESCE(v_bfa.bfa_verse, FALSE),
        'montant_verse', v_bfa.montant_bfa,
        'paliers', v_paliers,
        'explication', 'Le Bonus Fidelite Annuel (BFA) vous reverse un pourcentage des commissions payees dans lannee. Plus vous utilisez Jolene, plus le bonus est eleve. Il est calcule automatiquement en janvier et verse sous forme davoir.'
    );
END;
$$;
