-- ============================================================
-- CP-LITIGES-7a FIX 18 — Regen PDF immédiat via pg_net
-- ============================================================
-- Avant : PDF/XML des factures ajustées + avoirs régénérés par le cron
-- quotidien litige-escalation-cron (scan pdf_a_regenerer=TRUE). Délai
-- jusqu'à 24h entre résolution admin et disponibilité du PDF (ticket T14).
--
-- Fix : pg_net.http_post (fire-and-forget) depuis fn_admin_resoudre_litige
-- vers l'edge function generate-invoice, pour les 3 cas RECALCUL /
-- ANNULER_REEMETTRE / AVOIR. Cron conservé comme filet de sécurité
-- (fn_lister_factures_a_regenerer ne ramène plus que les factures dont
-- modifie_le < NOW() - 1h, pour laisser pg_net tenter en premier).
--
-- Prérequis :
--   1. Extension pg_net : déjà installée (v0.19.5, vérifié).
--   2. Param generate_invoice_url : seedé ici via parametres_litiges.
--   3. Secret service_role_key : à créer dans Supabase Vault par Gabrielle
--      (cf docs/cron-litiges.md). Si absent, la fn helper retourne NULL
--      et le cron prend le relais sans erreur.
-- ============================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- ── 1. Seed URL generate-invoice ───────────────────────────

INSERT INTO public.parametres_litiges (cle, valeur, description)
VALUES (
  'generate_invoice_url',
  'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/generate-invoice',
  'URL de l''edge function generate-invoice (FIX 18, pg_net async).'
)
ON CONFLICT (cle) DO NOTHING;

-- ── 2. Helper : pg_net fire-and-forget ──────────────────────

CREATE OR REPLACE FUNCTION public.fn_trigger_regen_pdf_immediate(
  p_facture_id UUID
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_url TEXT;
  v_key TEXT;
  v_request_id BIGINT;
BEGIN
  IF p_facture_id IS NULL THEN RETURN NULL; END IF;

  SELECT valeur INTO v_url
    FROM public.parametres_litiges WHERE cle = 'generate_invoice_url';
  IF v_url IS NULL OR length(v_url) = 0 THEN
    RETURN NULL;
  END IF;

  BEGIN
    SELECT decrypted_secret INTO v_key
      FROM vault.decrypted_secrets
     WHERE name = 'service_role_key'
     LIMIT 1;
  EXCEPTION WHEN OTHERS THEN
    v_key := NULL;
  END;
  IF v_key IS NULL OR length(v_key) = 0 THEN
    RETURN NULL;
  END IF;

  SELECT net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_key
    ),
    body := jsonb_build_object(
      'facture_id', p_facture_id,
      'service_role_reason', 'admin_resoudre_litige_immediate'
    )
  ) INTO v_request_id;

  RETURN v_request_id;
END;
$$;

COMMENT ON FUNCTION public.fn_trigger_regen_pdf_immediate(UUID) IS
  'CP-LITIGES-7a FIX 18 — déclenche regen PDF immédiat via pg_net. '
  'Retourne net.http_post request_id ou NULL si URL/secret manquant.';

GRANT EXECUTE ON FUNCTION public.fn_trigger_regen_pdf_immediate(UUID) TO service_role;

-- ── 3. Extension fn_admin_resoudre_litige avec appels pg_net ───

CREATE OR REPLACE FUNCTION public.fn_admin_resoudre_litige(
  p_litige_id UUID,
  p_resolution TEXT,
  p_en_faveur_de TEXT DEFAULT NULL,
  p_ajuster_heures NUMERIC DEFAULT NULL,
  p_ajuster_taux NUMERIC DEFAULT NULL,
  p_action_financiere TEXT DEFAULT 'AUTO'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_litige RECORD;
  v_facture RECORD;
  v_action TEXT;
  v_nouveau_statut TEXT;
  v_nouveau_montant_ht NUMERIC;
  v_nouvelle_facture_id UUID;
  v_avoir_id UUID;
  v_avoir_numero TEXT;
  v_diff NUMERIC;
  v_mode_remboursement public.mode_remboursement_avoir;
  v_delai_stripe_j INT;
  v_delai_urssaf_j INT;
  v_age_facture_j INT;
  v_regul_sociale BOOLEAN := FALSE;
  v_regen_request_ids BIGINT[] := ARRAY[]::BIGINT[];
BEGIN
  IF v_user_id IS NULL OR NOT public.est_admin() THEN
    RETURN jsonb_build_object('error', 'Admin requis pour cette opération.');
  END IF;
  IF length(trim(COALESCE(p_resolution, ''))) < 10 THEN
    RETURN jsonb_build_object('error', 'Le texte de résolution doit contenir au moins 10 caractères.');
  END IF;
  IF p_en_faveur_de IS NOT NULL AND p_en_faveur_de NOT IN ('SOIGNANT', 'ETABLISSEMENT') THEN
    RETURN jsonb_build_object('error', 'p_en_faveur_de doit être SOIGNANT ou ETABLISSEMENT.');
  END IF;
  IF p_action_financiere NOT IN ('AUTO', 'AUCUNE', 'RECALCUL', 'ANNULER_REEMETTRE', 'AVOIR') THEN
    RETURN jsonb_build_object('error', 'p_action_financiere invalide.');
  END IF;

  SELECT * INTO v_litige FROM public.litiges WHERE id = p_litige_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Litige introuvable.');
  END IF;
  IF v_litige.statut IN ('RESOLU', 'RESOLU_SOIGNANT', 'RESOLU_ETABLISSEMENT',
                         'RESOLU_ADMIN', 'FERME', 'CLOTURE') THEN
    RETURN jsonb_build_object('error', 'Ce litige est déjà résolu.');
  END IF;

  IF v_litige.facture_id IS NOT NULL THEN
    SELECT * INTO v_facture FROM public.factures_honoraires WHERE id = v_litige.facture_id;
  ELSE
    SELECT * INTO v_facture FROM public.factures_honoraires
     WHERE mission_id = v_litige.mission_id
       AND statut_litige = 'EN_ATTENTE_LITIGE'
     ORDER BY date_emission ASC NULLS LAST LIMIT 1;
  END IF;

  IF p_action_financiere = 'AUTO' THEN
    IF v_facture IS NULL OR (p_ajuster_heures IS NULL AND p_ajuster_taux IS NULL) THEN
      v_action := 'AUCUNE';
    ELSIF v_facture.statut = 'BROUILLON' THEN
      v_action := 'RECALCUL';
    ELSIF v_facture.statut = 'EMISE' THEN
      v_action := 'ANNULER_REEMETTRE';
    ELSIF v_facture.statut = 'PAYEE' THEN
      v_action := 'AVOIR';
    ELSE
      v_action := 'AUCUNE';
    END IF;
  ELSE
    v_action := p_action_financiere;
  END IF;

  IF v_action = 'RECALCUL' AND v_facture IS NOT NULL THEN
    IF p_ajuster_heures IS NOT NULL AND p_ajuster_taux IS NOT NULL THEN
      v_nouveau_montant_ht := p_ajuster_heures * p_ajuster_taux;
    ELSE
      v_nouveau_montant_ht := v_facture.montant_ht;
    END IF;

    UPDATE public.factures_honoraires
       SET montant_ht = v_nouveau_montant_ht,
           montant_ttc = v_nouveau_montant_ht * (1 + COALESCE(taux_tva, 0) / 100),
           montant_tva = v_nouveau_montant_ht * COALESCE(taux_tva, 0) / 100,
           statut_litige = 'LITIGE_RESOLU_AJUSTE',
           pdf_a_regenerer = TRUE
     WHERE id = v_facture.id;

    -- [FIX 18] Regen immédiat pg_net
    v_regen_request_ids := v_regen_request_ids
      || COALESCE(public.fn_trigger_regen_pdf_immediate(v_facture.id), 0);

  ELSIF v_action = 'ANNULER_REEMETTRE' AND v_facture IS NOT NULL THEN
    IF p_ajuster_heures IS NOT NULL AND p_ajuster_taux IS NOT NULL THEN
      v_nouveau_montant_ht := p_ajuster_heures * p_ajuster_taux;
    ELSE
      v_nouveau_montant_ht := v_facture.montant_ht;
    END IF;

    UPDATE public.factures_honoraires
       SET statut = 'ANNULEE',
           statut_litige = 'LITIGE_RESOLU_AJUSTE'
     WHERE id = v_facture.id;

    INSERT INTO public.factures_honoraires (
      soignant_id, etablissement_id, mission_id,
      numero_facture, montant_ht, montant_tva, montant_ttc,
      taux_tva, exoneration_tva, date_emission, date_echeance,
      statut, mandat_version, type_document, facture_precedente_id,
      statut_litige, litige_id, pdf_a_regenerer
    ) VALUES (
      v_facture.soignant_id, v_facture.etablissement_id, v_facture.mission_id,
      public.next_invoice_number(v_facture.soignant_id),
      v_nouveau_montant_ht,
      v_nouveau_montant_ht * COALESCE(v_facture.taux_tva, 0) / 100,
      v_nouveau_montant_ht * (1 + COALESCE(v_facture.taux_tva, 0) / 100),
      v_facture.taux_tva, v_facture.exoneration_tva,
      CURRENT_DATE, CURRENT_DATE + INTERVAL '30 days',
      'BROUILLON', v_facture.mandat_version,
      'FACTURE', v_facture.id,
      'LITIGE_RESOLU_AJUSTE', p_litige_id, TRUE
    )
    RETURNING id INTO v_nouvelle_facture_id;

    -- [FIX 18] Regen immédiat pg_net
    v_regen_request_ids := v_regen_request_ids
      || COALESCE(public.fn_trigger_regen_pdf_immediate(v_nouvelle_facture_id), 0);

  ELSIF v_action = 'AVOIR' AND v_facture IS NOT NULL THEN
    IF p_ajuster_heures IS NOT NULL AND p_ajuster_taux IS NOT NULL THEN
      v_nouveau_montant_ht := p_ajuster_heures * p_ajuster_taux;
    ELSE
      v_nouveau_montant_ht := v_facture.montant_ht;
    END IF;
    v_diff := v_facture.montant_ht - v_nouveau_montant_ht;
    IF v_diff <= 0 THEN
      RETURN jsonb_build_object('error', 'AVOIR non applicable : le nouveau montant doit être inférieur à l''original.');
    END IF;

    SELECT valeur::INT INTO v_delai_stripe_j
      FROM public.parametres_litiges WHERE cle = 'delai_stripe_refund_auto_j';

    IF v_facture.stripe_payment_intent_id IS NOT NULL
       AND v_facture.date_paiement IS NOT NULL
       AND v_facture.date_paiement > CURRENT_DATE - make_interval(days => v_delai_stripe_j) THEN
      v_mode_remboursement := 'AUTO_STRIPE';
    ELSE
      v_mode_remboursement := 'VIREMENT_MANUEL';
    END IF;

    v_avoir_numero := public.next_avoir_number(v_facture.soignant_id);

    INSERT INTO public.factures_honoraires (
      soignant_id, etablissement_id, mission_id,
      numero_facture, montant_ht, montant_tva, montant_ttc,
      taux_tva, exoneration_tva, date_emission, date_echeance,
      statut, mandat_version, type_document, facture_precedente_id,
      statut_litige, litige_id, mode_remboursement, pdf_a_regenerer
    ) VALUES (
      v_facture.soignant_id, v_facture.etablissement_id, v_facture.mission_id,
      v_avoir_numero,
      v_diff,
      v_diff * COALESCE(v_facture.taux_tva, 0) / 100,
      v_diff * (1 + COALESCE(v_facture.taux_tva, 0) / 100),
      v_facture.taux_tva, v_facture.exoneration_tva,
      CURRENT_DATE, CURRENT_DATE,
      'EMISE', v_facture.mandat_version,
      'AVOIR', v_facture.id,
      'LITIGE_RESOLU_AJUSTE', p_litige_id, v_mode_remboursement, TRUE
    )
    RETURNING id INTO v_avoir_id;

    UPDATE public.factures_honoraires
       SET statut_litige = 'LITIGE_RESOLU_AJUSTE'
     WHERE id = v_facture.id;

    IF v_mode_remboursement = 'AUTO_STRIPE' THEN
      INSERT INTO public.stripe_refunds_queue (
        avoir_id, facture_origine_id, stripe_payment_intent_id, montant_cts
      ) VALUES (
        v_avoir_id, v_facture.id, v_facture.stripe_payment_intent_id,
        (v_diff * 100)::INTEGER
      );
    END IF;

    -- [FIX 18] Regen immédiat pg_net
    v_regen_request_ids := v_regen_request_ids
      || COALESCE(public.fn_trigger_regen_pdf_immediate(v_avoir_id), 0);
  END IF;

  IF v_facture IS NOT NULL
     AND v_action IN ('ANNULER_REEMETTRE', 'AVOIR')
     AND p_ajuster_heures IS NOT NULL
  THEN
    SELECT valeur::INT INTO v_delai_urssaf_j
      FROM public.parametres_litiges WHERE cle = 'delai_notif_urssaf_mois';
    v_delai_urssaf_j := COALESCE(v_delai_urssaf_j, 3) * 30;

    v_age_facture_j := EXTRACT(DAY FROM NOW() - v_facture.date_emission)::INT;
    IF v_age_facture_j > v_delai_urssaf_j THEN
      UPDATE public.missions
         SET regularisation_sociale_requise = TRUE
       WHERE id = v_facture.mission_id;
      v_regul_sociale := TRUE;
    END IF;
  END IF;

  IF v_action IN ('RECALCUL', 'ANNULER_REEMETTRE', 'AVOIR') THEN
    UPDATE public.missions
       SET commission_a_recalculer = TRUE
     WHERE id = v_litige.mission_id;
  END IF;

  v_nouveau_statut := CASE
    WHEN p_en_faveur_de = 'SOIGNANT'       THEN 'RESOLU_SOIGNANT'
    WHEN p_en_faveur_de = 'ETABLISSEMENT'  THEN 'RESOLU_ETABLISSEMENT'
    ELSE 'RESOLU_ADMIN'
  END;

  UPDATE public.litiges
     SET statut = v_nouveau_statut,
         resolution = trim(p_resolution),
         resolu_par = v_user_id,
         resolu_le = NOW()
   WHERE id = p_litige_id;

  -- [FIX 18] Audit enrichi : regen_pdf_request_ids
  PERFORM public.fn_ecrire_audit(
    v_user_id, 'ADMIN', 'LITIGE_RESOLUTION',
    'litige', p_litige_id, NULL,
    jsonb_build_object(
      'action_financiere', v_action,
      'en_faveur_de', p_en_faveur_de,
      'ajuster_heures', p_ajuster_heures,
      'ajuster_taux', p_ajuster_taux,
      'facture_id', v_facture.id,
      'nouvelle_facture_id', v_nouvelle_facture_id,
      'avoir_id', v_avoir_id,
      'mode_remboursement', v_mode_remboursement,
      'regularisation_sociale_requise', v_regul_sociale,
      'regen_pdf_request_ids', to_jsonb(v_regen_request_ids)
    ),
    NULL, NULL
  );

  RETURN jsonb_build_object(
    'success', TRUE,
    'action_financiere', v_action,
    'statut', v_nouveau_statut,
    'facture_id', v_facture.id,
    'nouvelle_facture_id', v_nouvelle_facture_id,
    'avoir_id', v_avoir_id,
    'avoir_numero', v_avoir_numero,
    'mode_remboursement', v_mode_remboursement,
    'regularisation_sociale_requise', v_regul_sociale,
    'regen_pdf_request_ids', to_jsonb(v_regen_request_ids)
  );
END;
$$;

-- ── 4. fn_lister_factures_a_regenerer : filtre 1h (filet sécurité) ──

CREATE OR REPLACE FUNCTION public.fn_lister_factures_a_regenerer(
  p_limit INTEGER DEFAULT 50
)
RETURNS TABLE (
  id UUID,
  numero_facture TEXT,
  type_document public.type_document_facture,
  soignant_id UUID,
  cree_le TIMESTAMPTZ
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT f.id, f.numero_facture, f.type_document, f.soignant_id, f.cree_le
    FROM public.factures_honoraires f
   WHERE f.pdf_a_regenerer = TRUE
     AND f.statut IN ('BROUILLON', 'EMISE')
     AND f.modifie_le < NOW() - INTERVAL '1 hour'
   ORDER BY f.cree_le ASC
   LIMIT p_limit;
$$;

COMMENT ON FUNCTION public.fn_lister_factures_a_regenerer(INTEGER) IS
  'CP-LITIGES-7a FIX 18 — liste les factures/avoirs dont la regen pg_net '
  'a probablement échoué (modifie_le > 1h). Filet de sécurité du cron.';

COMMIT;
