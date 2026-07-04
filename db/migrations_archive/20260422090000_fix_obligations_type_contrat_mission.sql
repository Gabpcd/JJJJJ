-- ============================================================
-- Fix A — fn_obligations_financieres expose type_contrat_applique
-- ============================================================
-- Problème UX : la carte "Missions à payer aux soignants" affiche
-- uniquement le type_exercice du soignant (MIXTE) sans indiquer le
-- type de contrat réellement appliqué à la mission. L'étab ne sait
-- pas s'il doit faire un bulletin de paie (SALARIE) ou une note
-- d'honoraires (LIBERAL).
--
-- Fix : ajouter type_contrat_applique, type_paiement_soignant,
-- mode_paiement_soignant dans la sous-requête missions_non_payees.
-- ============================================================

CREATE OR REPLACE FUNCTION public.fn_obligations_financieres()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_etab_id UUID := mon_etablissement_id();
    v_total_soignants_du NUMERIC;
    v_total_commissions_du NUMERIC;
BEGIN
    IF v_etab_id IS NULL THEN RETURN jsonb_build_object('error', 'Etablissement introuvable'); END IF;

    v_total_soignants_du := COALESCE((
        SELECT SUM(m.net_a_payer) FROM missions m
        WHERE m.etablissement_id = v_etab_id AND m.statut = 'TERMINEE' AND m.soignant_assigne_id IS NOT NULL
        AND NOT EXISTS (SELECT 1 FROM paiements_soignant p WHERE p.mission_id = m.id AND p.statut IN ('DECLARE','CONFIRME'))
    ), 0);

    v_total_commissions_du := COALESCE((
        SELECT SUM(montant_ttc) FROM factures WHERE etablissement_id = v_etab_id AND statut IN ('EMISE', 'EN_RETARD')
    ), 0);

    RETURN jsonb_build_object(
        'total_du', v_total_soignants_du + v_total_commissions_du,
        'total_soignants_du', v_total_soignants_du,
        'total_commissions_du', v_total_commissions_du,

        'nb_missions_non_payees', (SELECT COUNT(*) FROM missions m WHERE m.etablissement_id = v_etab_id AND m.statut = 'TERMINEE' AND m.soignant_assigne_id IS NOT NULL
            AND NOT EXISTS (SELECT 1 FROM paiements_soignant p WHERE p.mission_id = m.id AND p.statut IN ('DECLARE','CONFIRME'))),
        'nb_paiements_en_attente', (SELECT COUNT(*) FROM paiements_soignant WHERE etablissement_id = v_etab_id AND statut = 'DECLARE'),
        'nb_factures_impayees', (SELECT COUNT(*) FROM factures WHERE etablissement_id = v_etab_id AND statut IN ('EMISE', 'EN_RETARD')),

        'missions_non_payees', COALESCE((
            SELECT jsonb_agg(row_to_json(x)) FROM (
                SELECT m.id::TEXT AS mission_id, m.intitule, m.debut_le, m.fin_le,
                    m.total_brut, m.net_a_payer, m.montant_commission_ttc,
                    m.soignant_assigne_id::TEXT AS soignant_id,
                    EXTRACT(EPOCH FROM (m.fin_le - m.debut_le))/3600 AS heures,
                    EXTRACT(DAY FROM NOW() - m.fin_le)::INT AS jours_depuis_fin,
                    COALESCE(s.prenom, '') || ' ' || COALESCE(s.nom, '') AS soignant_nom,
                    s.profession::TEXT AS soignant_profession,
                    s.type_exercice AS soignant_type_exercice,
                    m.type_contrat_applique::TEXT AS type_contrat_applique,
                    m.type_paiement_soignant AS type_paiement_soignant,
                    m.mode_paiement_soignant AS mode_paiement_soignant,
                    (s.stripe_account_id IS NOT NULL AND EXISTS(
                        SELECT 1 FROM stripe_connect_onboarding sco
                        WHERE sco.soignant_id = s.id AND sco.charges_enabled = TRUE AND sco.payouts_enabled = TRUE
                    )) AS soignant_stripe_connect
                FROM missions m
                JOIN soignants s ON s.id = m.soignant_assigne_id
                WHERE m.etablissement_id = v_etab_id AND m.statut = 'TERMINEE' AND m.soignant_assigne_id IS NOT NULL
                AND NOT EXISTS (SELECT 1 FROM paiements_soignant p WHERE p.mission_id = m.id AND p.statut IN ('DECLARE','CONFIRME'))
                ORDER BY m.fin_le ASC
            ) x
        ), '[]'::JSONB),

        'paiements_soignants_en_attente', COALESCE((
            SELECT jsonb_agg(row_to_json(x)) FROM (
                SELECT p.id::TEXT AS paiement_id, p.mission_id::TEXT, p.montant_net, p.methode,
                    p.reference_virement, p.date_paiement, p.statut,
                    m.intitule AS mission_intitule,
                    COALESCE(s.prenom, '') || ' ' || COALESCE(s.nom, '') AS soignant_nom,
                    s.profession::TEXT AS soignant_profession
                FROM paiements_soignant p
                JOIN missions m ON m.id = p.mission_id
                JOIN soignants s ON s.id = p.soignant_id
                WHERE p.etablissement_id = v_etab_id AND p.statut = 'DECLARE'
                ORDER BY p.date_paiement DESC
            ) x
        ), '[]'::JSONB),

        'paiements_soignants_confirmes', COALESCE((
            SELECT jsonb_agg(row_to_json(x)) FROM (
                SELECT p.id::TEXT AS paiement_id, p.montant_net, p.methode, p.reference_virement,
                    p.date_paiement, p.confirme_par_soignant_le,
                    m.intitule AS mission_intitule,
                    COALESCE(s.prenom, '') || ' ' || COALESCE(s.nom, '') AS soignant_nom
                FROM paiements_soignant p
                JOIN missions m ON m.id = p.mission_id
                JOIN soignants s ON s.id = p.soignant_id
                WHERE p.etablissement_id = v_etab_id AND p.statut = 'CONFIRME'
                ORDER BY p.confirme_par_soignant_le DESC LIMIT 10
            ) x
        ), '[]'::JSONB),

        'factures_impayees', COALESCE((
            SELECT jsonb_agg(row_to_json(x)) FROM (
                SELECT f.id::TEXT AS facture_id, f.numero_facture, f.montant_ht, f.montant_tva, f.montant_ttc,
                    f.nombre_missions, f.date_echeance, f.statut,
                    f.stripe_hosted_url
                FROM factures f
                WHERE f.etablissement_id = v_etab_id AND f.statut IN ('EMISE', 'EN_RETARD', 'VIREMENT_DECLARE')
                ORDER BY f.date_echeance ASC
            ) x
        ), '[]'::JSONB),

        'missions_non_facturees', COALESCE((
            SELECT jsonb_agg(row_to_json(x)) FROM (
                SELECT m.id::TEXT AS mission_id, m.intitule, m.fin_le,
                    m.montant_commission_ht, m.montant_commission_ttc
                FROM missions m
                WHERE m.etablissement_id = v_etab_id AND m.statut = 'TERMINEE' AND m.commission_facturee = FALSE
                ORDER BY m.fin_le DESC
            ) x
        ), '[]'::JSONB)
    );
END;
$function$;
