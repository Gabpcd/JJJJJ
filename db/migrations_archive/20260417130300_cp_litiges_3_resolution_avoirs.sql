-- ============================================================
-- CP-LITIGES-3 — Résolution admin étendue + système d'avoirs
-- ============================================================
-- Dépend de : CP-LITIGES-1 (20260417130000) + CP-LITIGES-2 (20260417130100)
--             + fixes CP2 (20260417130200).
--
-- Livre :
--   1. next_avoir_number(p_soignant_id) — séquence avoir par soignant
--      (modelée sur next_invoice_number, format AV-{SIRET}-{YYYY}-{NNNNN}).
--   2. Table stripe_refunds_queue — remboursements async à traiter par
--      edge function dédiée (process-stripe-refunds, CP4 ou ultérieur).
--   3. fn_admin_resoudre_litige étendue avec p_action_financiere :
--      - AUCUNE                — résolution admin sans ajustement.
--      - RECALCUL              — facture BROUILLON → recalcul direct.
--      - ANNULER_REEMETTRE     — facture EMISE non payée → annulation
--                                de la facture originale + INSERT nouvelle
--                                facture recalculée.
--      - AVOIR                 — facture PAYEE → INSERT avoir
--                                (type_document = 'AVOIR').
--      - AUTO (défaut)         — déduit automatiquement selon l'état.
--   4. fn_confirmer_remboursement_avoir(avoir_id, reference_virement) —
--      admin-only, finalise les avoirs en mode VIREMENT_MANUEL.
--   5. Flag régularisation URSSAF/Carpimko si ajustement sur facture
--      émise depuis > 90j (paramétrable via parametres_litiges).
--   6. Flag commission_a_recalculer systématique si montants modifiés.
--   7. Notifications (appels à send-email, templates créés en CP5).
--
-- Choix architecturaux :
--   - Les avoirs sont stockés dans factures_honoraires avec type_document=
--     'AVOIR' (pas de table séparée). Ils héritent ainsi de toute l'infra
--     (S3, Factur-X, Chorus, immutabilité, audit).
--   - Le PDF/XML Factur-X pour AVOIR est généré par l'edge function
--     generate-invoice étendue en CP-LITIGES-6. Ce CP3 se contente de créer
--     la ligne factures_honoraires avec flag pdf_a_regenerer (nouveau).
--   - La table stripe_refunds_queue est indépendante, alimentée par le
--     cas AVOIR quand mode_remboursement='AUTO_STRIPE'. Consommée par une
--     edge function ultérieure.
-- ============================================================

BEGIN;

-- ──────────────────────────────────────────────────────────────
-- 1. Colonnes additionnelles sur factures_honoraires
-- ──────────────────────────────────────────────────────────────
-- - pdf_a_regenerer : flag consommé par l'edge function generate-invoice
--   pour (re)générer PDF + XML Factur-X (cas ANNULER_REEMETTRE, AVOIR).
-- - stripe_payment_intent_id : placeholder pour le futur Stripe Connect
--   (Partie 2). Renseigné par le webhook Stripe au moment du paiement.
--   Permet la détection du délai 120j pour refund automatique.

ALTER TABLE public.factures_honoraires
  ADD COLUMN IF NOT EXISTS pdf_a_regenerer BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS stripe_payment_intent_id TEXT;

COMMENT ON COLUMN public.factures_honoraires.pdf_a_regenerer IS
  'TRUE si le PDF/XML doit être (re)généré par l''edge function generate-invoice. Remis à FALSE après succès.';

COMMENT ON COLUMN public.factures_honoraires.stripe_payment_intent_id IS
  'PaymentIntent Stripe Connect lié au paiement de la facture. Renseigné par le webhook Stripe (Partie 2). Utilisé pour détecter l''éligibilité au refund auto.';

-- ──────────────────────────────────────────────────────────────
-- 2. Table stripe_refunds_queue (remboursements async)
-- ──────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.stripe_refunds_queue (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  avoir_id UUID NOT NULL REFERENCES public.factures_honoraires(id) ON DELETE RESTRICT,
  facture_origine_id UUID NOT NULL REFERENCES public.factures_honoraires(id) ON DELETE RESTRICT,
  stripe_payment_intent_id TEXT NOT NULL,
  montant_cts INTEGER NOT NULL CHECK (montant_cts > 0),
  statut TEXT NOT NULL DEFAULT 'EN_ATTENTE'
    CHECK (statut IN ('EN_ATTENTE', 'EN_COURS', 'TRAITE', 'ECHEC')),
  stripe_refund_id TEXT,
  erreur TEXT,
  tentatives INTEGER NOT NULL DEFAULT 0,
  cree_le TIMESTAMPTZ NOT NULL DEFAULT now(),
  traite_le TIMESTAMPTZ,
  dernier_essai_le TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_stripe_refunds_queue_statut
  ON public.stripe_refunds_queue(statut, cree_le)
  WHERE statut IN ('EN_ATTENTE', 'EN_COURS');

COMMENT ON TABLE public.stripe_refunds_queue IS
  'File des remboursements Stripe Connect à traiter async. Consommée par edge function process-stripe-refunds (à créer).';

ALTER TABLE public.stripe_refunds_queue ENABLE ROW LEVEL SECURITY;

CREATE POLICY pol_stripe_refunds_admin_all
  ON public.stripe_refunds_queue
  FOR ALL
  TO authenticated
  USING (public.est_admin())
  WITH CHECK (public.est_admin());

GRANT SELECT, INSERT, UPDATE ON public.stripe_refunds_queue TO authenticated;
GRANT ALL ON public.stripe_refunds_queue TO service_role;

-- ──────────────────────────────────────────────────────────────
-- 3. next_avoir_number(p_soignant_id) — séquence dédiée avoirs
-- ──────────────────────────────────────────────────────────────
-- Format : AV-{SIRET_8_PREMIERS}-{ANNEE}-{SEQ_5_CHIFFRES}
-- Exemple : AV-12345678-2026-00001
-- Séquence totalement séparée de next_invoice_number (compte les lignes
-- type_document='AVOIR' uniquement).
-- Advisory lock par soignant pour la concurrence.

CREATE OR REPLACE FUNCTION public.next_avoir_number(p_soignant_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_siret TEXT;
  v_year TEXT;
  v_last_seq INTEGER;
  v_next_seq INTEGER;
  v_lock_key BIGINT;
  v_result TEXT;
BEGIN
  -- Advisory lock distinct de next_invoice_number (préfixe 'AV' dans hash input).
  v_lock_key := ('x' || left(md5('AV:' || p_soignant_id::text), 15))::bit(64)::bigint;
  PERFORM pg_advisory_xact_lock(v_lock_key);

  SELECT COALESCE(LEFT(siret_liberal, 8), LEFT(p_soignant_id::text, 8))
    INTO v_siret
    FROM public.soignants WHERE id = p_soignant_id;
  IF v_siret IS NULL THEN
    v_siret := LEFT(p_soignant_id::text, 8);
  END IF;

  v_year := TO_CHAR(CURRENT_DATE, 'YYYY');

  -- Dernier SEQ parmi les AVOIR de ce soignant (toutes années confondues)
  SELECT MAX(
    NULLIF(SPLIT_PART(numero_facture, '-', 4), '')::INTEGER
  ) INTO v_last_seq
    FROM public.factures_honoraires
   WHERE soignant_id = p_soignant_id
     AND type_document = 'AVOIR'
     AND numero_facture LIKE 'AV-%';

  v_next_seq := COALESCE(v_last_seq, 0) + 1;
  v_result := 'AV-' || v_siret || '-' || v_year || '-' || LPAD(v_next_seq::TEXT, 5, '0');
  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.next_avoir_number(UUID) IS
  'Séquence avoir par soignant, distincte de next_invoice_number. Format AV-{SIRET}-{YYYY}-{NNNNN}.';

GRANT EXECUTE ON FUNCTION public.next_avoir_number(UUID) TO authenticated, service_role;

-- ──────────────────────────────────────────────────────────────
-- 4. fn_admin_resoudre_litige étendue
-- ──────────────────────────────────────────────────────────────
-- Signature canonique (6 args) — rétrocompat avec l'ancienne 5-arg
-- assurée via DEFAULT sur p_action_financiere. L'ancienne version
-- existait déjà (référencée dans types.ts), nous la remplaçons par
-- cette version étendue, toujours rétrocompatible.
--
-- Logique p_action_financiere :
--   - 'AUTO' (défaut)       : déduit selon statut facture (BROUILLON →
--                             RECALCUL, EMISE → ANNULER_REEMETTRE,
--                             PAYEE → AVOIR, sinon AUCUNE).
--   - 'AUCUNE'              : pas d'impact financier (validation sans
--                             ajustement).
--   - 'RECALCUL'            : UPDATE directement la facture BROUILLON.
--   - 'ANNULER_REEMETTRE'   : annulation + nouvelle facture.
--   - 'AVOIR'               : INSERT avoir (refund Stripe si <120j).

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
  v_montant_ajuste NUMERIC;
  v_diff NUMERIC;
  v_mode_remboursement public.mode_remboursement_avoir;
  v_delai_stripe_j INT;
  v_delai_urssaf_j INT;
  v_age_facture_j INT;
  v_regul_sociale BOOLEAN := FALSE;
BEGIN
  -- 1. Auth
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

  -- 2. Récupération litige + facture liée (via litige.facture_id)
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
    -- Cas litige PRESENCE sans facture : première facture NORMAL de la mission
    SELECT * INTO v_facture FROM public.factures_honoraires
     WHERE mission_id = v_litige.mission_id
       AND statut_litige = 'EN_ATTENTE_LITIGE'
     ORDER BY date_emission ASC NULLS LAST LIMIT 1;
  END IF;

  -- 3. Déduction action_financiere = AUTO
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

  -- 4. Cas d'impact financier
  IF v_action = 'RECALCUL' AND v_facture IS NOT NULL THEN
    v_montant_ajuste := COALESCE(p_ajuster_heures, v_facture.montant_ht / NULLIF(v_facture.taux_tva, 0))
                        * COALESCE(p_ajuster_taux, v_facture.taux_tva);
    -- Simplification : on applique directement heures * taux comme montant_ht si fournis.
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

  ELSIF v_action = 'ANNULER_REEMETTRE' AND v_facture IS NOT NULL THEN
    IF p_ajuster_heures IS NOT NULL AND p_ajuster_taux IS NOT NULL THEN
      v_nouveau_montant_ht := p_ajuster_heures * p_ajuster_taux;
    ELSE
      v_nouveau_montant_ht := v_facture.montant_ht;
    END IF;

    -- Annulation de l'ancienne (via statut dédié, bypass immutabilité par admin)
    UPDATE public.factures_honoraires
       SET statut = 'ANNULEE',
           statut_litige = 'LITIGE_RESOLU_AJUSTE'
     WHERE id = v_facture.id;

    -- Nouvelle facture avec montants recalculés, chaînée à l'ancienne
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

    -- Détermination mode_remboursement
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

    -- Marque facture originale comme ajustée
    UPDATE public.factures_honoraires
       SET statut_litige = 'LITIGE_RESOLU_AJUSTE'
     WHERE id = v_facture.id;

    -- Si Stripe auto-refund, enqueue
    IF v_mode_remboursement = 'AUTO_STRIPE' THEN
      INSERT INTO public.stripe_refunds_queue (
        avoir_id, facture_origine_id, stripe_payment_intent_id, montant_cts
      ) VALUES (
        v_avoir_id, v_facture.id, v_facture.stripe_payment_intent_id,
        (v_diff * 100)::INTEGER
      );
    END IF;
  END IF;

  -- 5. Flag régularisation URSSAF/Carpimko si ajustement sur facture > 90j
  IF v_facture IS NOT NULL
     AND v_action IN ('ANNULER_REEMETTRE', 'AVOIR')
     AND p_ajuster_heures IS NOT NULL
  THEN
    SELECT valeur::INT INTO v_delai_urssaf_j
      FROM public.parametres_litiges WHERE cle = 'delai_notif_urssaf_mois';
    v_delai_urssaf_j := COALESCE(v_delai_urssaf_j, 3) * 30;  -- mois → jours approx.

    v_age_facture_j := EXTRACT(DAY FROM NOW() - v_facture.date_emission)::INT;
    IF v_age_facture_j > v_delai_urssaf_j THEN
      UPDATE public.missions
         SET regularisation_sociale_requise = TRUE
       WHERE id = v_facture.mission_id;
      v_regul_sociale := TRUE;
    END IF;
  END IF;

  -- 6. Flag commission_a_recalculer si impact financier
  IF v_action IN ('RECALCUL', 'ANNULER_REEMETTRE', 'AVOIR') THEN
    UPDATE public.missions
       SET commission_a_recalculer = TRUE
     WHERE id = v_litige.mission_id;
  END IF;

  -- 7. Transition statut litige (déclenche trg_litige_gel_degel_facture
  --    pour passer statut_litige à LITIGE_RESOLU_CONFIRME ; on surcharge
  --    ensuite à LITIGE_RESOLU_AJUSTE si impact financier).
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

  -- 8. Audit RGPD
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
      'regularisation_sociale_requise', v_regul_sociale
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
    'regularisation_sociale_requise', v_regul_sociale
  );
END;
$$;

COMMENT ON FUNCTION public.fn_admin_resoudre_litige(UUID, TEXT, TEXT, NUMERIC, NUMERIC, TEXT) IS
  'Admin-only. Résout un litige avec propagation financière : RECALCUL (BROUILLON), ANNULER_REEMETTRE (EMISE), AVOIR (PAYEE). Flag régul URSSAF si facture > 90j. Audit RGPD LITIGE_RESOLUTION.';

GRANT EXECUTE ON FUNCTION public.fn_admin_resoudre_litige(UUID, TEXT, TEXT, NUMERIC, NUMERIC, TEXT)
  TO authenticated, service_role;

-- ──────────────────────────────────────────────────────────────
-- 5. fn_confirmer_remboursement_avoir(avoir_id, reference_virement)
-- ──────────────────────────────────────────────────────────────
-- Admin-only. Finalise un avoir en mode VIREMENT_MANUEL après virement
-- effectué côté banque. Met à jour date_remboursement +
-- reference_remboursement, passe statut à REMBOURSE, audit RGPD.

CREATE OR REPLACE FUNCTION public.fn_confirmer_remboursement_avoir(
  p_avoir_id UUID,
  p_reference_virement TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_avoir RECORD;
BEGIN
  IF v_user_id IS NULL OR NOT public.est_admin() THEN
    RETURN jsonb_build_object('error', 'Admin requis.');
  END IF;
  IF length(trim(COALESCE(p_reference_virement, ''))) < 4 THEN
    RETURN jsonb_build_object('error', 'Référence virement requise (min 4 caractères).');
  END IF;

  SELECT * INTO v_avoir FROM public.factures_honoraires WHERE id = p_avoir_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Avoir introuvable.');
  END IF;
  IF v_avoir.type_document <> 'AVOIR' THEN
    RETURN jsonb_build_object('error', 'Ce document n''est pas un avoir.');
  END IF;
  IF v_avoir.mode_remboursement <> 'VIREMENT_MANUEL' THEN
    RETURN jsonb_build_object('error', 'Mode de remboursement incompatible (attendu : VIREMENT_MANUEL).');
  END IF;
  IF v_avoir.date_remboursement IS NOT NULL THEN
    RETURN jsonb_build_object('error', 'Remboursement déjà confirmé.');
  END IF;

  UPDATE public.factures_honoraires
     SET statut = 'REMBOURSE',
         date_remboursement = NOW(),
         reference_remboursement = trim(p_reference_virement)
   WHERE id = p_avoir_id;

  PERFORM public.fn_ecrire_audit(
    v_user_id, 'ADMIN', 'AVOIR_REMBOURSEMENT_CONFIRME',
    'facture_honoraire', p_avoir_id, NULL,
    jsonb_build_object(
      'numero_avoir', v_avoir.numero_facture,
      'montant_ht', v_avoir.montant_ht,
      'reference_virement', trim(p_reference_virement),
      'mode_remboursement', 'VIREMENT_MANUEL'
    ),
    NULL, NULL
  );

  RETURN jsonb_build_object(
    'success', TRUE,
    'avoir_id', p_avoir_id,
    'statut', 'REMBOURSE',
    'date_remboursement', NOW()
  );
END;
$$;

COMMENT ON FUNCTION public.fn_confirmer_remboursement_avoir(UUID, TEXT) IS
  'Admin-only. Confirme le remboursement manuel d''un avoir (mode VIREMENT_MANUEL) après virement bancaire effectué.';

GRANT EXECUTE ON FUNCTION public.fn_confirmer_remboursement_avoir(UUID, TEXT)
  TO authenticated, service_role;

COMMIT;

-- ============================================================
-- Notes d'implémentation (hors SQL) :
--
--   - Templates email (CP5) à déclencher :
--     * LITIGE_RESOLU_AJUSTE (E4) — soignant + étab, à chaque résolution
--       avec impact financier.
--     * AVOIR_EMIS (E5) — soignant + étab, si cas AVOIR.
--     * REMBOURSEMENT_CONFIRME (E6) — soignant, si fn_confirmer_remboursement
--       _avoir ou webhook Stripe.
--     * REGULARISATION_SOCIALE_REQUISE — soignant, si flag positionné.
--     Pour CP3 : on ne fait pas d'appel send-email ici, les notifications
--     seront câblées dans CP5 avec le rendu des templates.
--
--   - Edge function process-stripe-refunds (à créer) :
--     Consomme stripe_refunds_queue avec statut='EN_ATTENTE',
--     appelle Stripe refunds.create, met à jour statut → TRAITE/ECHEC,
--     stocke stripe_refund_id. Sur webhook charge.refunded, met à jour
--     factures_honoraires.date_remboursement + statut='REMBOURSE'.
--
--   - PDF AVOIR : la colonne pdf_a_regenerer=TRUE est consommée par
--     generate-invoice (édition CP6) qui détecte type_document='AVOIR'
--     et applique le template dédié (rouge, mention "Avoir émis sur
--     facture n° {numero_precedent}", Factur-X BT-3=381 + BT-25).
-- ============================================================
