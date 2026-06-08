-- FIX bug page admin AdminFinances : fn_admin_finances plantait avec
-- "aggregate function calls cannot be nested" → page Vue d'ensemble finances cassée.
-- Cause : dans 'commissions_par_mois', jsonb_agg(... SUM(...) ...) imbriquait deux
-- agrégats. Correction : on calcule les SUM dans une sous-requête groupée par mois,
-- puis jsonb_agg au niveau au-dessus. Reste de la fonction inchangé.
CREATE OR REPLACE FUNCTION public.fn_admin_finances()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_result JSONB;
    v_mois_en_cours DATE := DATE_TRUNC('month', NOW())::DATE;
    v_mois_precedent DATE := (DATE_TRUNC('month', NOW()) - INTERVAL '1 month')::DATE;
BEGIN
    IF NOT est_admin() THEN RETURN '{"error":"Accès refusé"}'::JSONB; END IF;

    SELECT jsonb_build_object(
        'commissions_mois_ht', COALESCE((
            SELECT SUM(montant_commission_ht) FROM missions
            WHERE statut = 'TERMINEE' AND terminee_le >= v_mois_en_cours
        ), 0),
        'commissions_mois_ttc', COALESCE((
            SELECT SUM(montant_commission_ttc) FROM missions
            WHERE statut = 'TERMINEE' AND terminee_le >= v_mois_en_cours
        ), 0),
        'commissions_mois_tva', COALESCE((
            SELECT SUM(montant_commission_tva) FROM missions
            WHERE statut = 'TERMINEE' AND terminee_le >= v_mois_en_cours
        ), 0),
        'commissions_mois_prec_ht', COALESCE((
            SELECT SUM(montant_commission_ht) FROM missions
            WHERE statut = 'TERMINEE' AND terminee_le >= v_mois_precedent AND terminee_le < v_mois_en_cours
        ), 0),
        'commissions_total_ht', COALESCE((SELECT SUM(montant_commission_ht) FROM missions WHERE statut = 'TERMINEE'), 0),
        'commissions_total_ttc', COALESCE((SELECT SUM(montant_commission_ttc) FROM missions WHERE statut = 'TERMINEE'), 0),
        'commissions_total_tva', COALESCE((SELECT SUM(montant_commission_tva) FROM missions WHERE statut = 'TERMINEE'), 0),
        'factures_emises_total', COALESCE((SELECT SUM(montant_ttc) FROM factures WHERE statut = 'EMISE'), 0),
        'factures_payees_total', COALESCE((SELECT SUM(montant_ttc) FROM factures WHERE statut = 'PAYEE'), 0),
        'factures_impayees_total', COALESCE((SELECT SUM(montant_ttc) FROM factures WHERE statut = 'EMISE' AND date_echeance < CURRENT_DATE), 0),
        'nb_factures_emises', (SELECT COUNT(*) FROM factures WHERE statut = 'EMISE'),
        'nb_factures_payees', (SELECT COUNT(*) FROM factures WHERE statut = 'PAYEE'),
        'nb_factures_impayees', (SELECT COUNT(*) FROM factures WHERE statut = 'EMISE' AND date_echeance < CURRENT_DATE),
        'nb_missions_mois', (SELECT COUNT(*) FROM missions WHERE statut = 'TERMINEE' AND terminee_le >= v_mois_en_cours),
        'nb_missions_total', (SELECT COUNT(*) FROM missions WHERE statut = 'TERMINEE'),
        'volume_brut_mois', COALESCE((
            SELECT SUM(taux_horaire_base * duree_heures + COALESCE(montant_majoration_nuit,0) + COALESCE(montant_majoration_dimanche,0) + COALESCE(montant_majoration_ferie,0))
            FROM missions WHERE statut = 'TERMINEE' AND terminee_le >= v_mois_en_cours
        ), 0),
        'volume_brut_total', COALESCE((
            SELECT SUM(taux_horaire_base * duree_heures + COALESCE(montant_majoration_nuit,0) + COALESCE(montant_majoration_dimanche,0) + COALESCE(montant_majoration_ferie,0))
            FROM missions WHERE statut = 'TERMINEE'
        ), 0),
        -- Commissions par mois (6 derniers mois) — SUM dans sous-requête, jsonb_agg au-dessus
        'commissions_par_mois', COALESCE((
            SELECT jsonb_agg(jsonb_build_object('mois', to_char(sub.m, 'YYYY-MM'), 'ht', sub.ht, 'ttc', sub.ttc) ORDER BY sub.m)
            FROM (
                SELECT m,
                       COALESCE(SUM(montant_commission_ht), 0) AS ht,
                       COALESCE(SUM(montant_commission_ttc), 0) AS ttc
                FROM generate_series(
                    DATE_TRUNC('month', NOW()) - INTERVAL '5 months',
                    DATE_TRUNC('month', NOW()),
                    INTERVAL '1 month'
                ) AS m
                LEFT JOIN missions ON statut = 'TERMINEE'
                    AND DATE_TRUNC('month', terminee_le) = m
                GROUP BY m
            ) sub
        ), '[]'::JSONB),
        'taux_commission_moyen', COALESCE((SELECT ROUND(AVG(taux_commission), 2) FROM missions WHERE statut = 'TERMINEE' AND taux_commission IS NOT NULL), 0)
    ) INTO v_result;

    RETURN v_result;
END;
$function$;
