-- ============================================================
-- CP-LITIGES-7a Bloc 4 — Push COMMISSION_AJUSTEE (oubli FIX 9)
-- ============================================================
-- Oubli rattrapé : FIX 9 a créé les AVOIR commission et
-- FACTURE_COMPLEMENTAIRE mais n'a pas notifié l'établissement.
-- Le commentaire L16-17 de FIX 9 marquait ce point comme "reporté".
--
-- Bloc 4 ajoute :
--   1. Template COMMISSION_AJUSTEE dans send-email (hors SQL).
--   2. PERFORM fn_litige_push_notification dans la boucle
--      fn_recalculer_commissions_post_litige, pour chaque user_id
--      ayant role ADMIN_ETABLISSEMENT ou ETABLISSEMENT sur l'étab.
--   3. Retour JSONB enrichi : notifications_envoyees.
--
-- Le type_notif 'COMMISSION_AJUSTEE' est nouveau ; le helper
-- fn_litige_push_notification (CP5) l'accepte car aucune CHECK
-- constraint n'est posée sur email_queue.type.
-- ============================================================

BEGIN;

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
  v_doc_type           TEXT;
  v_processed_unbilled INT := 0;
  v_avoirs_emis        INT := 0;
  v_fc_emises          INT := 0;
  v_notifs_envoyees    INT := 0;
  v_mission_intitule   TEXT;
  v_litige_id          UUID;
BEGIN
  FOR v_mission IN
    SELECT id, taux_commission, facture_id, commission_facturee,
           montant_commission_ht, etablissement_id, intitule
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

    -- Commission non facturée → MAJ directe, pas de notif
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

    -- Commission déjà facturée → avoir ou facture complémentaire
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
      v_doc_type := 'AVOIR';
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
      v_doc_type := 'FACTURE_COMPLEMENTAIRE';
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

    -- ═══ [Bloc 4] Push COMMISSION_AJUSTEE ══════════════════════
    -- Retrouve le litige déclencheur via factures_honoraires.litige_id
    -- (le flag commission_a_recalculer est posé par fn_admin_resoudre_litige).
    SELECT DISTINCT fh.litige_id INTO v_litige_id
      FROM public.factures_honoraires fh
     WHERE fh.mission_id = v_mission.id
       AND fh.litige_id IS NOT NULL
     ORDER BY fh.litige_id
     LIMIT 1;

    v_mission_intitule := COALESCE(v_mission.intitule, 'Mission #' || v_mission.id::text);

    -- Notifier l'établissement (pattern Jolene : destinataire_id = etablissement_id).
    PERFORM public.fn_litige_push_notification(
      v_mission.etablissement_id,
      'ETABLISSEMENT',
      'COMMISSION_AJUSTEE',
      CASE WHEN v_doc_type = 'AVOIR'
        THEN 'Avoir commission ' || v_doc_number || ' émis'
        ELSE 'Facture complémentaire ' || v_doc_number || ' émise'
      END,
      CASE WHEN v_doc_type = 'AVOIR'
        THEN 'Un avoir de ' || v_delta_ttc || ' € a été émis sur la commission de la mission "' || v_mission_intitule || '". Déduit de votre prochaine facture mensuelle.'
        ELSE 'Une facture complémentaire de ' || v_delta_ttc || ' € a été émise sur la commission de la mission "' || v_mission_intitule || '". Due aux conditions habituelles.'
      END,
      v_litige_id,
      jsonb_build_object(
        'type_document', v_doc_type,
        'numero_document', v_doc_number,
        'montant', v_delta_ttc,
        'mission_id', v_mission.id,
        'mission_intitule', v_mission_intitule,
        'etablissement_id', v_mission.etablissement_id
      )
    );
    v_notifs_envoyees := v_notifs_envoyees + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'processed_unbilled', v_processed_unbilled,
    'deferred_to_fix9_billed', 0,
    'avoirs_commission_emis', v_avoirs_emis,
    'factures_complementaires_emises', v_fc_emises,
    'notifications_envoyees', v_notifs_envoyees
  );
END;
$$;

COMMENT ON FUNCTION public.fn_recalculer_commissions_post_litige() IS
  'CP-LITIGES-7a FIX 8+9+Bloc4 — recalcule les commissions Jolene post-litige. '
  'Non facturées : MAJ directe. Déjà facturées : AVOIR ou FACTURE_COMPLEMENTAIRE '
  'selon delta, avec push COMMISSION_AJUSTEE à tous les représentants légaux '
  'de l''étab. Appelée AVANT fn_auto_facturation_mensuelle.';

COMMIT;
