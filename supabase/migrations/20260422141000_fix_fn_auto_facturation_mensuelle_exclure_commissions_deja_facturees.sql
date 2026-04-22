-- Phase 2 Option Y — garde anti-double-facturation commission mensuelle.
-- Exclure les missions déjà rattachées à une facture commission (typiquement
-- les LIBERAL+Stripe Connect dont le webhook a créé une facture PAYEE à la
-- source). Sans cette garde, le cron mensuel créerait une 2ème facture
-- commission en fin de mois pour ces missions.

CREATE OR REPLACE FUNCTION public.fn_auto_facturation_mensuelle()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_etab RECORD;
    v_facture_id UUID;
    v_num TEXT;
    v_compteur INT := 0;
    v_mois TEXT;
    v_recalc_info JSONB;
BEGIN
    IF NOT est_admin() THEN
        RETURN jsonb_build_object('success', false, 'error', 'Non autorisé');
    END IF;

    v_recalc_info := public.fn_recalculer_commissions_post_litige();

    v_mois := TO_CHAR(now(), 'YYYY-MM');

    FOR v_etab IN
        SELECT etablissement_id,
               COUNT(*) as nb,
               SUM(COALESCE(montant_commission_ht, 0)) as sum_ht,
               SUM(COALESCE(montant_commission_tva, 0)) as sum_tva,
               SUM(COALESCE(montant_commission_ttc, 0)) as sum_ttc
        FROM missions m
        WHERE m.statut = 'TERMINEE'
          AND m.commission_facturee = false
          AND m.facture_id IS NULL
          AND NOT EXISTS (SELECT 1 FROM factures f WHERE f.mission_id = m.id)
        GROUP BY etablissement_id
    LOOP
        IF v_etab.sum_ht <= 0 THEN CONTINUE; END IF;

        v_compteur := v_compteur + 1;
        v_num := 'FACT-' || v_mois || '-' || LPAD(v_compteur::TEXT, 4, '0');

        INSERT INTO factures (
            etablissement_id, numero_facture, montant_ht, montant_tva, montant_ttc,
            nombre_missions, statut, date_emission, date_echeance, periode_debut, periode_fin
        ) VALUES (
            v_etab.etablissement_id, v_num, v_etab.sum_ht, v_etab.sum_tva, v_etab.sum_ttc,
            v_etab.nb, 'EMISE', now(), (now() + INTERVAL '30 days')::date,
            date_trunc('month', now())::date,
            (date_trunc('month', now()) + INTERVAL '1 month' - INTERVAL '1 day')::date
        ) RETURNING id INTO v_facture_id;

        UPDATE missions
        SET facture_id = v_facture_id, commission_facturee = true
        WHERE etablissement_id = v_etab.etablissement_id
          AND statut = 'TERMINEE'
          AND commission_facturee = false
          AND facture_id IS NULL
          AND NOT EXISTS (SELECT 1 FROM factures f WHERE f.mission_id = missions.id);
    END LOOP;

    RETURN jsonb_build_object(
      'success', true,
      'factures_generees', v_compteur,
      'recalc_post_litige', v_recalc_info
    );
END;
$function$;
