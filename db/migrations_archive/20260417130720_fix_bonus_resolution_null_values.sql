-- ============================================================
-- FIX BONUS — fn_admin_resoudre_litige : NULL handling p_ajuster_*
-- ============================================================
-- Bug découvert via CP8a T5 : si l'admin appelle la RPC avec
-- p_ajuster_taux=NULL (ou p_ajuster_heures=NULL) en voulant ne modifier
-- qu'une seule des deux dimensions, le calcul actuel retombait sur
-- v_facture.montant_ht (pas de changement), produisant v_diff=0 puis
-- l'erreur "AVOIR non applicable" — alors que l'admin avait bien
-- modifié un paramètre.
--
-- Correction :
--   1) Avant chaque branche RECALCUL/ANNULER_REEMETTRE/AVOIR, on
--      construit un (v_heures_final, v_taux_final) via COALESCE :
--        v_taux_final   = COALESCE(p_ajuster_taux, mission.taux_horaire_base)
--        v_heures_final = COALESCE(p_ajuster_heures,
--                                  presence.heures_reelles,
--                                  facture.montant_ht / NULLIF(v_taux_final, 0))
--      → l'admin peut ajuster une seule dimension, l'autre est figée
--        sur la valeur de référence courante.
--   2) Pour AVOIR : si v_diff=0 (aucun changement effectif) → success
--      avec action_financiere='AUCUNE' (au lieu d'une erreur). Si
--      v_diff<0 (montant ↑) → erreur explicite invitant à utiliser
--      ANNULER_REEMETTRE (le futur FACTURE_COMPLEMENTAIRE est tracé
--      dans /docs/sub-pr-2-quater-recap.md, hors scope V1).
--
-- Le reste de la fonction (audit, push email FIX 19, regen PDF FIX 18,
-- gel facture, flags URSSAF/commission) est inchangé.
-- ============================================================

BEGIN;

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
  v_nouveau_numero_facture TEXT;
  v_avoir_id UUID;
  v_avoir_numero TEXT;
  v_diff NUMERIC;
  v_mode_remboursement public.mode_remboursement_avoir;
  v_delai_stripe_j INT;
  v_delai_urssaf_j INT;
  v_age_facture_j INT;
  v_regul_sociale BOOLEAN := FALSE;
  v_regen_request_ids BIGINT[] := ARRAY[]::BIGINT[];
  v_etab_user_id UUID;
  v_soignant_id UUID;
  v_email_data JSONB;
  -- [FIX bonus null values]
  v_taux_ref NUMERIC;
  v_heures_ref NUMERIC;
  v_taux_final NUMERIC;
  v_heures_final NUMERIC;
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

  -- [FIX bonus null values] Lookup des références taux/heures pour
  -- permettre à l'admin d'ajuster une seule dimension à la fois.
  IF v_facture IS NOT NULL THEN
    SELECT m.taux_horaire_base INTO v_taux_ref
      FROM public.missions m
     WHERE m.id = v_facture.mission_id;

    SELECT p.heures_reelles INTO v_heures_ref
      FROM public.presences p
     WHERE p.mission_id = v_facture.mission_id
       AND p.valide_par_etablissement = TRUE
     ORDER BY p.valide_le DESC NULLS LAST
     LIMIT 1;

    v_taux_final   := COALESCE(p_ajuster_taux, v_taux_ref);
    v_heures_final := COALESCE(
      p_ajuster_heures,
      v_heures_ref,
      CASE WHEN v_taux_final IS NOT NULL AND v_taux_final <> 0
           THEN v_facture.montant_ht / v_taux_final
           ELSE NULL END
    );
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
    IF v_heures_final IS NOT NULL AND v_taux_final IS NOT NULL THEN
      v_nouveau_montant_ht := v_heures_final * v_taux_final;
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

    v_regen_request_ids := v_regen_request_ids
      || COALESCE(public.fn_trigger_regen_pdf_immediate(v_facture.id), 0);

  ELSIF v_action = 'ANNULER_REEMETTRE' AND v_facture IS NOT NULL THEN
    IF v_heures_final IS NOT NULL AND v_taux_final IS NOT NULL THEN
      v_nouveau_montant_ht := v_heures_final * v_taux_final;
    ELSE
      v_nouveau_montant_ht := v_facture.montant_ht;
    END IF;

    UPDATE public.factures_honoraires
       SET statut = 'ANNULEE',
           statut_litige = 'LITIGE_RESOLU_AJUSTE'
     WHERE id = v_facture.id;

    v_nouveau_numero_facture := public.next_invoice_number(v_facture.soignant_id);

    INSERT INTO public.factures_honoraires (
      soignant_id, etablissement_id, mission_id,
      numero_facture, montant_ht, montant_tva, montant_ttc,
      taux_tva, exoneration_tva, date_emission, date_echeance,
      statut, mandat_version, type_document, facture_precedente_id,
      statut_litige, litige_id, pdf_a_regenerer
    ) VALUES (
      v_facture.soignant_id, v_facture.etablissement_id, v_facture.mission_id,
      v_nouveau_numero_facture,
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

    v_regen_request_ids := v_regen_request_ids
      || COALESCE(public.fn_trigger_regen_pdf_immediate(v_nouvelle_facture_id), 0);

  ELSIF v_action = 'AVOIR' AND v_facture IS NOT NULL THEN
    IF v_heures_final IS NOT NULL AND v_taux_final IS NOT NULL THEN
      v_nouveau_montant_ht := v_heures_final * v_taux_final;
    ELSE
      v_nouveau_montant_ht := v_facture.montant_ht;
    END IF;
    v_diff := v_facture.montant_ht - v_nouveau_montant_ht;

    -- [FIX bonus null values] Distinction des trois cas v_diff
    IF v_diff = 0 THEN
      -- Aucun changement effectif : on bascule en AUCUNE et on ne crée
      -- aucun avoir. Le litige sera marqué résolu côté statut.
      v_action := 'AUCUNE';
    ELSIF v_diff < 0 THEN
      -- Augmentation : AVOIR n'est pas applicable. L'admin doit
      -- explicitement choisir ANNULER_REEMETTRE pour émettre une
      -- nouvelle facture. FACTURE_COMPLEMENTAIRE auto = TODO Sub-PR 3.
      RETURN jsonb_build_object(
        'error',
        'Le nouveau montant (' || v_nouveau_montant_ht || ' €) est supérieur à l''original (' ||
        v_facture.montant_ht || ' €). AVOIR non applicable. Utilisez p_action_financiere=ANNULER_REEMETTRE.'
      );
    ELSE
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

      v_regen_request_ids := v_regen_request_ids
        || COALESCE(public.fn_trigger_regen_pdf_immediate(v_avoir_id), 0);
    END IF;
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

  PERFORM public.fn_ecrire_audit(
    v_user_id, 'ADMIN', 'LITIGE_RESOLUTION',
    'litige', p_litige_id, NULL,
    jsonb_build_object(
      'action_financiere', v_action,
      'en_faveur_de', p_en_faveur_de,
      'ajuster_heures', p_ajuster_heures,
      'ajuster_taux', p_ajuster_taux,
      'heures_final', v_heures_final,
      'taux_final', v_taux_final,
      'facture_id', v_facture.id,
      'nouvelle_facture_id', v_nouvelle_facture_id,
      'avoir_id', v_avoir_id,
      'mode_remboursement', v_mode_remboursement,
      'regularisation_sociale_requise', v_regul_sociale,
      'regen_pdf_request_ids', to_jsonb(v_regen_request_ids)
    ),
    NULL, NULL
  );

  IF v_action IN ('RECALCUL', 'ANNULER_REEMETTRE', 'AVOIR') AND v_litige IS NOT NULL THEN
    v_soignant_id := v_litige.soignant_id;

    v_etab_user_id := v_litige.etablissement_id;

    v_email_data := jsonb_build_object(
      'action_financiere', v_action,
      'en_faveur_de', p_en_faveur_de,
      'resolution', trim(p_resolution),
      'numero_facture', v_facture.numero_facture,
      'numero_ancienne', CASE WHEN v_action = 'ANNULER_REEMETTRE' THEN v_facture.numero_facture ELSE NULL END,
      'numero_nouvelle', v_nouveau_numero_facture,
      'numero_avoir', v_avoir_numero,
      'montant_avant', v_facture.montant_ht,
      'montant_apres', v_nouveau_montant_ht
    );

    IF v_soignant_id IS NOT NULL THEN
      PERFORM public.fn_litige_push_notification(
        v_soignant_id,
        'SOIGNANT',
        'LITIGE_RESOLU_AJUSTE',
        'Litige résolu — ajustement appliqué',
        CASE v_action
          WHEN 'AVOIR'             THEN 'Un avoir ' || COALESCE(v_avoir_numero, '') || ' a été émis suite à la résolution du litige.'
          WHEN 'RECALCUL'          THEN 'Votre facture ' || COALESCE(v_facture.numero_facture, '') || ' a été recalculée.'
          WHEN 'ANNULER_REEMETTRE' THEN 'Une nouvelle facture ' || COALESCE(v_nouveau_numero_facture, '') || ' remplace ' || COALESCE(v_facture.numero_facture, '') || '.'
          ELSE                          'Le litige a été résolu avec impact financier.'
        END,
        p_litige_id,
        v_email_data
      );
    END IF;

    IF v_etab_user_id IS NOT NULL THEN
      PERFORM public.fn_litige_push_notification(
        v_etab_user_id,
        'ETABLISSEMENT',
        'LITIGE_RESOLU_AJUSTE',
        'Litige résolu — ajustement appliqué',
        CASE v_action
          WHEN 'AVOIR'             THEN 'Un avoir ' || COALESCE(v_avoir_numero, '') || ' a été émis pour cette mission.'
          WHEN 'RECALCUL'          THEN 'La facture ' || COALESCE(v_facture.numero_facture, '') || ' a été recalculée.'
          WHEN 'ANNULER_REEMETTRE' THEN 'Une nouvelle facture ' || COALESCE(v_nouveau_numero_facture, '') || ' remplace ' || COALESCE(v_facture.numero_facture, '') || '.'
          ELSE                          'Le litige a été résolu avec impact financier.'
        END,
        p_litige_id,
        v_email_data
      );
    END IF;

    IF v_action = 'AVOIR' AND v_avoir_id IS NOT NULL AND v_soignant_id IS NOT NULL THEN
      PERFORM public.fn_litige_push_notification(
        v_soignant_id,
        'SOIGNANT',
        'AVOIR_EMIS',
        'Avoir ' || COALESCE(v_avoir_numero, '') || ' émis',
        'Un avoir a été émis suite à la résolution du litige. Le PDF est attaché à cet email.',
        p_litige_id,
        jsonb_build_object(
          'avoir_id', v_avoir_id,
          'numero_avoir', v_avoir_numero,
          'numero_facture_origine', v_facture.numero_facture,
          'montant_avoir', v_diff,
          'mode_remboursement_texte', CASE v_mode_remboursement::text
            WHEN 'AUTO_STRIPE'      THEN 'Remboursement Stripe automatique (2 à 5 jours ouvrés)'
            WHEN 'VIREMENT_MANUEL'  THEN 'Virement manuel sous 7 jours ouvrés'
            ELSE                         'Mode de remboursement à confirmer'
          END
        )
      );
    END IF;
  END IF;

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
    'regen_pdf_request_ids', to_jsonb(v_regen_request_ids),
    'heures_final', v_heures_final,
    'taux_final', v_taux_final
  );
END;
$$;

COMMENT ON FUNCTION public.fn_admin_resoudre_litige(UUID, TEXT, TEXT, NUMERIC, NUMERIC, TEXT) IS
  'Admin-only. Résout un litige avec propagation financière : RECALCUL (BROUILLON), '
  'ANNULER_REEMETTRE (EMISE), AVOIR (PAYEE). FIX 18 : regen PDF immédiat pg_net. '
  'FIX 19 : push email LITIGE_RESOLU_AJUSTE + AVOIR_EMIS. '
  'FIX bonus null : p_ajuster_heures/taux NULL → fallback sur '
  'mission.taux_horaire_base / presence.heures_reelles ; v_diff=0 → AUCUNE ; '
  'v_diff<0 → erreur invitant à ANNULER_REEMETTRE.';

COMMIT;
