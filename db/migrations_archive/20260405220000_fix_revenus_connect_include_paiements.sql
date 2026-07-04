-- fn_mes_revenus_connect now includes confirmed manual payments (virement/note honoraires)
-- so the soignant sees ALL confirmed revenue, not just Stripe Connect transfers
CREATE OR REPLACE FUNCTION fn_mes_revenus_connect(p_mois_debut DATE DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
    v_debut DATE;
    v_connect_mois NUMERIC;
    v_connect_total NUMERIC;
    v_connect_attente NUMERIC;
    v_paiements_mois NUMERIC;
    v_paiements_total NUMERIC;
BEGIN
    v_debut := COALESCE(p_mois_debut, DATE_TRUNC('month', CURRENT_DATE)::DATE);

    SELECT COALESCE(SUM(montant_soignant), 0) INTO v_connect_mois
    FROM stripe_transfers WHERE soignant_id = auth.uid() AND statut IN ('TRANSFERE','PAYE') AND transfere_le >= v_debut;

    SELECT COALESCE(SUM(montant_soignant), 0) INTO v_connect_total
    FROM stripe_transfers WHERE soignant_id = auth.uid() AND statut IN ('TRANSFERE','PAYE');

    SELECT COALESCE(SUM(montant_soignant), 0) INTO v_connect_attente
    FROM stripe_transfers WHERE soignant_id = auth.uid() AND statut IN ('EN_ATTENTE');

    SELECT COALESCE(SUM(montant_net), 0) INTO v_paiements_mois
    FROM paiements_soignant WHERE soignant_id = auth.uid() AND statut = 'CONFIRME' AND confirme_par_soignant_le >= v_debut;

    SELECT COALESCE(SUM(montant_net), 0) INTO v_paiements_total
    FROM paiements_soignant WHERE soignant_id = auth.uid() AND statut = 'CONFIRME';

    RETURN jsonb_build_object(
        'mois_en_cours', v_connect_mois + v_paiements_mois,
        'total', v_connect_total + v_paiements_total,
        'en_attente', v_connect_attente,
        'stripe_connect_actif', fn_soignant_stripe_connect_actif(auth.uid())
    );
END;
$$;
