-- ============================================================
-- CP-LITIGES-7a FIX 9 — Avoir commission étab + Facture complémentaire
-- ============================================================
-- Prérequis : FIX 8 (fn_recalculer_commissions_post_litige, infra).
--
-- Scope :
--   1. DDL : type_document, facture_precedente_id, montant_signe sur factures.
--   2. RPCs numérotation : next_avoir_commission_number (AVC-YYYY-MM-NNNN),
--      next_facture_complementaire_number (FC-YYYY-MM-NNNN).
--   3. Extension fn_recalculer_commissions_post_litige : traite les missions
--      dont la commission est DÉJÀ facturée (facture_id IS NOT NULL) :
--        delta > 0 → AVOIR commission (trop-perçu Jolene)
--        delta < 0 → FACTURE_COMPLEMENTAIRE (sous-perçu)
--        delta = 0 → reset flag, pas de document
--
-- Notifications étab : reportées (template email COMMISSION_AJUSTEE à créer
-- dans send-email edge function, hors scope SQL).
-- ============================================================

BEGIN;

-- ── 1. DDL ──────────────────────────────────────────────────

ALTER TABLE public.factures
  ADD COLUMN IF NOT EXISTS type_document TEXT NOT NULL DEFAULT 'FACTURE',
  ADD COLUMN IF NOT EXISTS facture_precedente_id UUID
    REFERENCES public.factures(id) ON DELETE SET NULL;

ALTER TABLE public.factures
  DROP CONSTRAINT IF EXISTS factures_type_document_check;
ALTER TABLE public.factures
  ADD CONSTRAINT factures_type_document_check
  CHECK (type_document IN ('FACTURE', 'AVOIR', 'FACTURE_COMPLEMENTAIRE'));

ALTER TABLE public.factures
  ADD COLUMN IF NOT EXISTS montant_signe NUMERIC(12,2)
    GENERATED ALWAYS AS (
      CASE WHEN type_document = 'AVOIR' THEN -montant_ht ELSE montant_ht END
    ) STORED;

CREATE INDEX IF NOT EXISTS idx_factures_type_avoir_fc
  ON public.factures(type_document)
  WHERE type_document IN ('AVOIR', 'FACTURE_COMPLEMENTAIRE');

CREATE INDEX IF NOT EXISTS idx_factures_facture_precedente
  ON public.factures(facture_precedente_id)
  WHERE facture_precedente_id IS NOT NULL;

-- ── 2. Numérotation avoirs / factures complémentaires ───────

CREATE OR REPLACE FUNCTION public.next_avoir_commission_number(p_etablissement_id UUID)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_mois TEXT; v_last_seq INTEGER; v_lock_key BIGINT;
BEGIN
  v_lock_key := ('x' || left(md5('AVC:' || p_etablissement_id::text), 15))::bit(64)::bigint;
  PERFORM pg_advisory_xact_lock(v_lock_key);
  v_mois := TO_CHAR(now(), 'YYYY-MM');
  SELECT MAX(NULLIF(SPLIT_PART(numero_facture, '-', 4), '')::INTEGER)
    INTO v_last_seq FROM public.factures
   WHERE numero_facture LIKE 'AVC-' || v_mois || '-%';
  RETURN 'AVC-' || v_mois || '-' || LPAD((COALESCE(v_last_seq, 0) + 1)::TEXT, 4, '0');
END; $$;

CREATE OR REPLACE FUNCTION public.next_facture_complementaire_number(p_etablissement_id UUID)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_mois TEXT; v_last_seq INTEGER; v_lock_key BIGINT;
BEGIN
  v_lock_key := ('x' || left(md5('FC:' || p_etablissement_id::text), 15))::bit(64)::bigint;
  PERFORM pg_advisory_xact_lock(v_lock_key);
  v_mois := TO_CHAR(now(), 'YYYY-MM');
  SELECT MAX(NULLIF(SPLIT_PART(numero_facture, '-', 4), '')::INTEGER)
    INTO v_last_seq FROM public.factures
   WHERE numero_facture LIKE 'FC-' || v_mois || '-%';
  RETURN 'FC-' || v_mois || '-' || LPAD((COALESCE(v_last_seq, 0) + 1)::TEXT, 4, '0');
END; $$;

GRANT EXECUTE ON FUNCTION public.next_avoir_commission_number(UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.next_facture_complementaire_number(UUID) TO service_role;

-- ── 3. Extension fn_recalculer_commissions_post_litige ──────

CREATE OR REPLACE FUNCTION public.fn_recalculer_commissions_post_litige()
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_mission            RECORD;
  v_new_brut           NUMERIC(12,2);
  v_new_commission_ht  NUMERIC(12,2);
  v_new_commission_tva NUMERIC(12,2);
  v_new_commission_ttc NUMERIC(12,2);
  v_delta_ht           NUMERIC(12,2);
  v_delta_tva          NUMERIC(12,2);
  v_delta_ttc          NUMERIC(12,2);
  v_doc_number         TEXT;
  v_processed_unbilled INT := 0;
  v_avoirs_emis        INT := 0;
  v_fc_emises          INT := 0;
BEGIN
  FOR v_mission IN
    SELECT id, taux_commission, facture_id, commission_facturee,
           montant_commission_ht, etablissement_id
      FROM public.missions
     WHERE commission_a_recalculer = TRUE
  LOOP
    SELECT COALESCE(SUM(fh.montant_signe), 0) INTO v_new_brut
      FROM public.factures_honoraires fh
     WHERE fh.mission_id = v_mission.id
       AND fh.statut NOT IN ('ANNULEE', 'REMPLACEE')
       AND fh.statut_litige <> 'EN_ATTENTE_LITIGE';

    v_new_commission_ht  := ROUND(v_new_brut * COALESCE(v_mission.taux_commission, 15) / 100.0, 2);
    v_new_commission_tva := ROUND(v_new_commission_ht * 0.20, 2);
    v_new_commission_ttc := v_new_commission_ht + v_new_commission_tva;

    -- [FIX 8] Commission non facturée → MAJ directe
    IF v_mission.facture_id IS NULL
       AND COALESCE(v_mission.commission_facturee, FALSE) = FALSE THEN
      UPDATE public.missions
         SET montant_commission_ht  = v_new_commission_ht,
             montant_commission_tva = v_new_commission_tva,
             montant_commission_ttc = v_new_commission_ttc,
             commission_a_recalculer = FALSE
       WHERE id = v_mission.id;
      v_processed_unbilled := v_processed_unbilled + 1;
      CONTINUE;
    END IF;

    -- [FIX 9] Commission déjà facturée → avoir ou facture complémentaire
    v_delta_ht := COALESCE(v_mission.montant_commission_ht, 0) - v_new_commission_ht;

    IF v_delta_ht = 0 THEN
      UPDATE public.missions SET commission_a_recalculer = FALSE
       WHERE id = v_mission.id;
      v_processed_unbilled := v_processed_unbilled + 1;
      CONTINUE;
    END IF;

    v_delta_tva := ROUND(abs(v_delta_ht) * 0.20, 2);
    v_delta_ttc := abs(v_delta_ht) + v_delta_tva;

    IF v_delta_ht > 0 THEN
      v_doc_number := public.next_avoir_commission_number(v_mission.etablissement_id);
      INSERT INTO public.factures (
        etablissement_id, numero_facture, type_document, facture_precedente_id,
        montant_ht, montant_tva, montant_ttc, nombre_missions,
        statut, date_emission, date_echeance, periode_debut, periode_fin
      ) VALUES (
        v_mission.etablissement_id, v_doc_number, 'AVOIR', v_mission.facture_id,
        v_delta_ht, v_delta_tva, v_delta_ttc, 1,
        'EMISE', now(), (now() + INTERVAL '30 days')::date,
        date_trunc('month', now())::date,
        (date_trunc('month', now()) + INTERVAL '1 month' - INTERVAL '1 day')::date
      );
      v_avoirs_emis := v_avoirs_emis + 1;
    ELSE
      v_doc_number := public.next_facture_complementaire_number(v_mission.etablissement_id);
      INSERT INTO public.factures (
        etablissement_id, numero_facture, type_document, facture_precedente_id,
        montant_ht, montant_tva, montant_ttc, nombre_missions,
        statut, date_emission, date_echeance, periode_debut, periode_fin
      ) VALUES (
        v_mission.etablissement_id, v_doc_number, 'FACTURE_COMPLEMENTAIRE',
        v_mission.facture_id,
        abs(v_delta_ht), v_delta_tva, v_delta_ttc, 1,
        'EMISE', now(), (now() + INTERVAL '30 days')::date,
        date_trunc('month', now())::date,
        (date_trunc('month', now()) + INTERVAL '1 month' - INTERVAL '1 day')::date
      );
      v_fc_emises := v_fc_emises + 1;
    END IF;

    UPDATE public.missions
       SET montant_commission_ht  = v_new_commission_ht,
           montant_commission_tva = v_new_commission_tva,
           montant_commission_ttc = v_new_commission_ttc,
           commission_a_recalculer = FALSE
     WHERE id = v_mission.id;
  END LOOP;

  RETURN jsonb_build_object(
    'processed_unbilled', v_processed_unbilled,
    'deferred_to_fix9_billed', 0,
    'avoirs_commission_emis', v_avoirs_emis,
    'factures_complementaires_emises', v_fc_emises
  );
END;
$$;

COMMENT ON FUNCTION public.fn_recalculer_commissions_post_litige() IS
  'CP-LITIGES-7a FIX 8+9 — recalcule les commissions Jolene post-litige. '
  'Non facturées : MAJ directe. Déjà facturées : AVOIR ou FACTURE_COMPLEMENTAIRE '
  'selon delta. Appelée AVANT fn_auto_facturation_mensuelle.';

COMMIT;
