-- ============================================================
-- CP-LITIGES-7a FIX 8 — Consommation commission_a_recalculer
-- ============================================================
-- Audit :
--   - missions.commission_a_recalculer (BOOL, CP-LITIGES-1) est posé à TRUE
--     par fn_admin_resoudre_litige (CP3, actions RECALCUL / ANNULER_REEMETTRE
--     / AVOIR) dès qu'un litige modifie le montant d'une facture d'honoraires.
--   - AVANT ce FIX, fn_auto_facturation_mensuelle ne lit jamais ce flag :
--     elle somme simplement missions.montant_commission_ht par etab. La
--     commission mensuelle Jolene pouvait donc refléter un montant obsolète
--     si un litige avait ajusté une facture d'honoraires entre-temps.
--   - Le trigger fn_calculer_financier_mission recalcule la commission quand
--     la mission change, mais pas quand factures_honoraires change : il faut
--     un recalcul explicite post-litige.
--
-- Scope FIX 8 — INFRASTRUCTURE uniquement :
--   1. fn_recalculer_commissions_post_litige() : traite les missions dont la
--      commission n'a PAS encore été facturée (facture_id IS NULL,
--      commission_facturee = FALSE). Le nouveau montant commission est
--      dérivé de la somme signée des factures d'honoraires de la mission
--      (FACTURE - AVOIR) × taux_commission.
--   2. Appel de cette fn AU DÉBUT de fn_auto_facturation_mensuelle pour
--      garantir que la commission mensuelle part de montants à jour.
--
-- Hors scope (reporté au FIX 9) :
--   - Missions dont la commission est DÉJÀ facturée (facture_id IS NOT NULL) :
--     nécessite l'émission d'un avoir de commission à l'étab. Le flag reste
--     TRUE pour ces missions, elles seront traitées par fn_recalculer_
--     commissions_post_litige côté FIX 9.
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_recalculer_commissions_post_litige()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_mission         RECORD;
  v_new_brut        NUMERIC(12,2);
  v_new_commission_ht  NUMERIC(12,2);
  v_new_commission_tva NUMERIC(12,2);
  v_new_commission_ttc NUMERIC(12,2);
  v_processed       INT := 0;
  v_deferred_to_fix9 INT := 0;
BEGIN
  FOR v_mission IN
    SELECT id, taux_commission, facture_id, commission_facturee,
           montant_commission_ht
      FROM public.missions
     WHERE commission_a_recalculer = TRUE
  LOOP
    -- Commission déjà facturée → avoir commission nécessaire (FIX 9).
    IF v_mission.facture_id IS NOT NULL OR v_mission.commission_facturee = TRUE THEN
      v_deferred_to_fix9 := v_deferred_to_fix9 + 1;
      CONTINUE;
    END IF;

    -- Recalcul : somme signée des factures d'honoraires non annulées et
    -- hors gel actif (EN_ATTENTE_LITIGE exclu pour ne pas figer un état
    -- transitoire). montant_signe : positif FACTURE, négatif AVOIR (CP1).
    SELECT COALESCE(SUM(fh.montant_signe), 0)
      INTO v_new_brut
      FROM public.factures_honoraires fh
     WHERE fh.mission_id = v_mission.id
       AND fh.statut NOT IN ('ANNULEE', 'REMPLACEE')
       AND fh.statut_litige <> 'EN_ATTENTE_LITIGE';

    v_new_commission_ht  := ROUND(v_new_brut * COALESCE(v_mission.taux_commission, 15) / 100.0, 2);
    v_new_commission_tva := ROUND(v_new_commission_ht * 0.20, 2);
    v_new_commission_ttc := v_new_commission_ht + v_new_commission_tva;

    UPDATE public.missions
       SET montant_commission_ht  = v_new_commission_ht,
           montant_commission_tva = v_new_commission_tva,
           montant_commission_ttc = v_new_commission_ttc,
           commission_a_recalculer = FALSE
     WHERE id = v_mission.id;

    v_processed := v_processed + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'processed_unbilled', v_processed,
    'deferred_to_fix9_billed', v_deferred_to_fix9
  );
END;
$$;

COMMENT ON FUNCTION public.fn_recalculer_commissions_post_litige() IS
  'CP-LITIGES-7a FIX 8 — recalcule les commissions Jolene des missions '
  'flaggées commission_a_recalculer=TRUE et non encore facturées '
  '(facture_id IS NULL). Missions déjà facturées laissées au FIX 9 '
  '(avoir commission). À appeler AVANT fn_auto_facturation_mensuelle.';

GRANT EXECUTE ON FUNCTION public.fn_recalculer_commissions_post_litige()
  TO service_role;

-- ──────────────────────────────────────────────────────────────
-- Intégration dans fn_auto_facturation_mensuelle : appel en tête.
-- ──────────────────────────────────────────────────────────────

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
    v_recalc_info JSONB;
BEGIN
    IF NOT est_admin() THEN
        RETURN jsonb_build_object('success', false, 'error', 'Non autorisé');
    END IF;

    -- [FIX 8] Recalcul préalable des commissions post-litige.
    v_recalc_info := public.fn_recalculer_commissions_post_litige();

    v_mois := TO_CHAR(now(), 'YYYY-MM');

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

        UPDATE missions
        SET facture_id = v_facture_id, commission_facturee = true
        WHERE etablissement_id = v_etab.etablissement_id
          AND statut = 'TERMINEE'
          AND commission_facturee = false
          AND facture_id IS NULL;
    END LOOP;

    RETURN jsonb_build_object(
      'success', true,
      'factures_generees', v_compteur,
      'recalc_post_litige', v_recalc_info
    );
END;
$$;

COMMIT;
