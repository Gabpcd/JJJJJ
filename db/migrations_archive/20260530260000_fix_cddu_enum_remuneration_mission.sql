-- P0 : fn_calculer_remuneration_mission déclarait v_contrat type_contrat := 'CDDU'
-- (et comparait IN ('CDDU','CDDU_USAGE')) alors que l'enum type_contrat ne contient
-- que CDDU_USAGE (renommé). L'init de variable plantait → trigger dec_calculer_finance_mission
-- → CRÉATION DE MISSION IMPOSSIBLE. Correction : CDDU → CDDU_USAGE.
CREATE OR REPLACE FUNCTION public.fn_calculer_remuneration_mission(p_debut timestamp with time zone, p_fin timestamp with time zone, p_taux_base numeric, p_etablissement_id uuid, p_soignant_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
DECLARE
    v_etab RECORD;
    v_contrat type_contrat := 'CDD';
    v_curseur TIMESTAMPTZ;
    v_fin_creneau TIMESTAMPTZ;
    v_date_heure DATE;
    v_heure_du_jour INTEGER;
    v_jour_semaine INTEGER;
    v_heures_totales NUMERIC := 0;
    v_heures_nuit NUMERIC := 0;
    v_heures_dimanche NUMERIC := 0;
    v_heures_ferie NUMERIC := 0;
    v_heures_normales NUMERIC := 0;
    v_montant_base NUMERIC := 0;
    v_majoration_nuit NUMERIC := 0;
    v_majoration_dimanche NUMERIC := 0;
    v_majoration_ferie NUMERIC := 0;
    v_total_brut NUMERIC := 0;
    v_ifm NUMERIC := 0;
    v_icp NUMERIC := 0;
    v_net_a_payer NUMERIC := 0;
    v_taux_ifm NUMERIC := 0;
    v_taux_icp NUMERIC := 0;
BEGIN
    SELECT e.taux_majoration_nuit_pourcent,
           e.taux_majoration_dimanche_pourcent,
           e.taux_majoration_ferie_pourcent
    INTO v_etab
    FROM etablissements e WHERE e.id = p_etablissement_id;

    IF p_soignant_id IS NOT NULL THEN
        SELECT s.type_contrat INTO v_contrat
        FROM soignants s WHERE s.id = p_soignant_id;
    END IF;

    v_curseur := p_debut;
    WHILE v_curseur < p_fin LOOP
        v_fin_creneau := LEAST(v_curseur + INTERVAL '1 hour', p_fin);
        DECLARE
            v_duree_creneau NUMERIC := EXTRACT(EPOCH FROM (v_fin_creneau - v_curseur)) / 3600.0;
            v_est_nuit BOOLEAN;
            v_est_dimanche BOOLEAN;
            v_est_ferie BOOLEAN;
        BEGIN
            v_date_heure := (v_curseur AT TIME ZONE 'Europe/Paris')::DATE;
            v_heure_du_jour := EXTRACT(HOUR FROM (v_curseur AT TIME ZONE 'Europe/Paris'));
            v_jour_semaine := EXTRACT(ISODOW FROM (v_curseur AT TIME ZONE 'Europe/Paris'));
            v_est_nuit := (v_heure_du_jour >= 21 OR v_heure_du_jour < 6);
            v_est_dimanche := (v_jour_semaine = 7);
            v_est_ferie := fn_est_jour_ferie(v_date_heure);
            v_heures_totales := v_heures_totales + v_duree_creneau;
            IF v_est_nuit THEN v_heures_nuit := v_heures_nuit + v_duree_creneau; END IF;
            IF v_est_dimanche THEN v_heures_dimanche := v_heures_dimanche + v_duree_creneau; END IF;
            IF v_est_ferie THEN v_heures_ferie := v_heures_ferie + v_duree_creneau; END IF;
            IF NOT v_est_nuit AND NOT v_est_dimanche AND NOT v_est_ferie THEN
                v_heures_normales := v_heures_normales + v_duree_creneau;
            END IF;
        END;
        v_curseur := v_fin_creneau;
    END LOOP;

    v_montant_base := v_heures_totales * p_taux_base;
    v_majoration_nuit := v_heures_nuit * p_taux_base * (COALESCE(v_etab.taux_majoration_nuit_pourcent, 25) / 100.0);
    v_majoration_dimanche := v_heures_dimanche * p_taux_base * (COALESCE(v_etab.taux_majoration_dimanche_pourcent, 50) / 100.0);
    v_majoration_ferie := v_heures_ferie * p_taux_base * (COALESCE(v_etab.taux_majoration_ferie_pourcent, 100) / 100.0);
    v_total_brut := v_montant_base + v_majoration_nuit + v_majoration_dimanche + v_majoration_ferie;

    -- IFM (prime de précarité) + ICP pour les contrats CDD (et CDDU_USAGE résiduel)
    IF v_contrat IN ('CDD', 'CDDU_USAGE') THEN
        v_taux_ifm := 0.10;
        v_taux_icp := 0.10;
        v_ifm := v_total_brut * v_taux_ifm;
        v_icp := (v_total_brut + v_ifm) * v_taux_icp;
    END IF;

    v_net_a_payer := v_total_brut + v_ifm + v_icp;

    RETURN jsonb_build_object(
        'heures_totales', ROUND(v_heures_totales, 2),
        'heures_normales', ROUND(v_heures_normales, 2),
        'heures_nuit', ROUND(v_heures_nuit, 2),
        'heures_dimanche', ROUND(v_heures_dimanche, 2),
        'heures_ferie', ROUND(v_heures_ferie, 2),
        'taux_horaire_base', p_taux_base,
        'montant_base', ROUND(v_montant_base, 2),
        'majoration_nuit_pourcent', COALESCE(v_etab.taux_majoration_nuit_pourcent, 25),
        'montant_majoration_nuit', ROUND(v_majoration_nuit, 2),
        'majoration_dimanche_pourcent', COALESCE(v_etab.taux_majoration_dimanche_pourcent, 50),
        'montant_majoration_dimanche', ROUND(v_majoration_dimanche, 2),
        'majoration_ferie_pourcent', COALESCE(v_etab.taux_majoration_ferie_pourcent, 100),
        'montant_majoration_ferie', ROUND(v_majoration_ferie, 2),
        'total_brut', ROUND(v_total_brut, 2),
        'taux_ifm', v_taux_ifm,
        'montant_ifm', ROUND(v_ifm, 2),
        'taux_icp', v_taux_icp,
        'montant_icp', ROUND(v_icp, 2),
        'net_a_payer', ROUND(v_net_a_payer, 2),
        'type_contrat', v_contrat::TEXT
    );
END;
$function$;

NOTIFY pgrst, 'reload schema';
