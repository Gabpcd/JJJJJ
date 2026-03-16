
-- Link terminated missions to their corresponding invoices by etablissement_id
-- Etab 1: b0000000-0000-0000-0000-000000000001 → FACT-2026-0001
UPDATE missions SET facture_id = 'd27dc496-319a-4ef6-8981-f6d7a3609410', commission_facturee = true
WHERE etablissement_id = 'b0000000-0000-0000-0000-000000000001' AND statut = 'TERMINEE' AND facture_id IS NULL;

-- Etab 2: b0000000-0000-0000-0000-000000000002 → FACT-2026-0002
UPDATE missions SET facture_id = '21fbf201-676a-40d2-9c02-441c87e530c7', commission_facturee = true
WHERE etablissement_id = 'b0000000-0000-0000-0000-000000000002' AND statut = 'TERMINEE' AND facture_id IS NULL;

-- Etab 3: b0000000-0000-0000-0000-000000000003 → FACT-2026-0003
UPDATE missions SET facture_id = 'df82ce36-fe6e-47d9-8b99-139b0be851ca', commission_facturee = true
WHERE etablissement_id = 'b0000000-0000-0000-0000-000000000003' AND statut = 'TERMINEE' AND facture_id IS NULL;

-- Also fix fn_auto_facturation_mensuelle to properly link missions when generating invoices
CREATE OR REPLACE FUNCTION public.fn_auto_facturation_mensuelle()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_etab RECORD;
    v_facture_id UUID;
    v_num TEXT;
    v_compteur INT := 0;
    v_mois TEXT;
    v_total_ht NUMERIC;
    v_total_tva NUMERIC;
    v_total_ttc NUMERIC;
    v_nb_missions INT;
BEGIN
    IF NOT est_admin() THEN
        RETURN jsonb_build_object('success', false, 'error', 'Non autorisé');
    END IF;

    v_mois := TO_CHAR(now(), 'YYYY-MM');

    -- Group unfactured terminated missions by etablissement
    FOR v_etab IN
        SELECT etablissement_id,
               COUNT(*) as nb,
               SUM(COALESCE(montant_commission_ht, 0)) as sum_ht,
               SUM(COALESCE(montant_commission_tva, 0)) as sum_tva,
               SUM(COALESCE(montant_commission_ttc, 0)) as sum_ttc
        FROM missions
        WHERE statut = 'TERMINEE'
          AND commission_facturee = false
          AND facture_id IS NULL
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

        -- Link all missions to this invoice
        UPDATE missions
        SET facture_id = v_facture_id, commission_facturee = true
        WHERE etablissement_id = v_etab.etablissement_id
          AND statut = 'TERMINEE'
          AND commission_facturee = false
          AND facture_id IS NULL;
    END LOOP;

    RETURN jsonb_build_object('success', true, 'factures_generees', v_compteur);
END;
$$;
