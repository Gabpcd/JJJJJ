-- Définition LIVE relue le 29/09/2026, md5(prosrc) 5b60c98f33c87ae592b43f2a95dedbfb.
-- Les remboursements SEPA renvoyés par Stripe peuvent porter le préfixe pyr_.
-- Conserver les gardes service, identité de queue, montant, état et idempotence.
CREATE OR REPLACE FUNCTION public.fn_stripe_refund_rapprocher(p_queue_id uuid, p_stripe_refund_id text, p_resultat text, p_detail text DEFAULT NULL::text, p_finalise_le timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_queue public.stripe_refunds_queue%ROWTYPE;
  v_avoir public.factures_honoraires%ROWTYPE;
  v_escrow public.paiements_escrow%ROWTYPE;
  v_rows integer;
  v_legacy_escrow boolean := false;
BEGIN
  IF COALESCE(
       auth.jwt()->>'role',
       current_setting('request.jwt.claim.role', true),
       ''
     ) <> 'service_role'
     AND session_user NOT IN ('postgres', 'supabase_admin') THEN
    RAISE EXCEPTION 'Service role requis' USING ERRCODE = '42501';
  END IF;

  IF p_queue_id IS NULL
     OR p_resultat NOT IN ('SUCCEEDED', 'FAILED', 'CANCELED') THEN
    RAISE EXCEPTION 'Rapprochement refund invalide' USING ERRCODE = '22023';
  END IF;

  -- Un refund effectivement créé porte toujours son identifiant Stripe. Un
  -- échec de validation/création peut être terminal avant que Stripe n'ait
  -- créé le moindre objet ; NULL reste alors une provenance explicite.
  IF p_resultat IN ('SUCCEEDED', 'CANCELED')
     AND (p_stripe_refund_id IS NULL
          OR p_stripe_refund_id !~ '^(re|pyr)_[A-Za-z0-9]+$') THEN
    RAISE EXCEPTION 'Identifiant Stripe refund requis' USING ERRCODE = '22023';
  END IF;
  IF p_stripe_refund_id IS NOT NULL
     AND p_stripe_refund_id !~ '^(re|pyr)_[A-Za-z0-9]+$' THEN
    RAISE EXCEPTION 'Identifiant Stripe refund invalide' USING ERRCODE = '22023';
  END IF;

  SELECT q.*
    INTO v_queue
    FROM public.stripe_refunds_queue q
   WHERE q.id = p_queue_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Queue refund introuvable' USING ERRCODE = 'P0001';
  END IF;

  IF v_queue.stripe_refund_id IS NOT NULL
     AND v_queue.stripe_refund_id <> p_stripe_refund_id THEN
    RAISE EXCEPTION 'Refund Stripe différent déjà lié à la queue'
      USING ERRCODE = 'P0001';
  END IF;

  IF p_resultat = 'SUCCEEDED' AND v_queue.statut = 'TRAITE' THEN
    IF v_queue.stripe_refund_id = p_stripe_refund_id THEN
      RETURN jsonb_build_object('success', true, 'already_processed', true);
    END IF;
    RAISE EXCEPTION 'Queue traitée sans le refund attendu' USING ERRCODE = 'P0001';
  END IF;

  IF p_resultat IN ('FAILED', 'CANCELED') AND v_queue.statut = 'ECHEC' THEN
    IF v_queue.stripe_refund_id IS NOT DISTINCT FROM p_stripe_refund_id THEN
      RETURN jsonb_build_object('success', true, 'already_processed', true);
    END IF;
    RAISE EXCEPTION 'Queue en échec sans le refund attendu' USING ERRCODE = 'P0001';
  END IF;

  IF v_queue.statut NOT IN ('EN_ATTENTE', 'EN_COURS') THEN
    RAISE EXCEPTION 'Transition refund interdite depuis %', v_queue.statut
      USING ERRCODE = 'P0001';
  END IF;

  IF p_resultat = 'SUCCEEDED' THEN
    IF v_queue.avoir_id IS NOT NULL THEN
      SELECT fh.*
        INTO v_avoir
        FROM public.factures_honoraires fh
       WHERE fh.id = v_queue.avoir_id
         AND fh.type_document = 'AVOIR'
       FOR UPDATE;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'Avoir de la queue introuvable' USING ERRCODE = 'P0001';
      END IF;
      IF round(abs(v_avoir.montant_ttc) * 100)::integer <> v_queue.montant_cts THEN
        RAISE EXCEPTION 'Montant de l''avoir incohérent avec la queue'
          USING ERRCODE = 'P0001';
      END IF;

      IF v_avoir.statut = 'REMBOURSE' THEN
        IF v_avoir.reference_remboursement IS DISTINCT FROM p_stripe_refund_id THEN
          RAISE EXCEPTION 'Avoir déjà rapproché avec une autre référence'
            USING ERRCODE = 'P0001';
        END IF;
      ELSE
        UPDATE public.factures_honoraires
           SET statut = 'REMBOURSE',
               date_remboursement = COALESCE(p_finalise_le, now()),
               reference_remboursement = p_stripe_refund_id
         WHERE id = v_avoir.id
           AND statut IN ('EMISE', 'EN_RETARD');
        GET DIAGNOSTICS v_rows = ROW_COUNT;
        IF v_rows <> 1 THEN
          RAISE EXCEPTION 'État de l''avoir non remboursable: %', v_avoir.statut
            USING ERRCODE = 'P0001';
        END IF;
      END IF;
    END IF;

    IF v_queue.paiement_escrow_id IS NOT NULL THEN
      SELECT pe.*
        INTO v_escrow
        FROM public.paiements_escrow pe
       WHERE pe.id = v_queue.paiement_escrow_id
       FOR UPDATE;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'Escrow de la queue introuvable' USING ERRCODE = 'P0001';
      END IF;

      IF v_escrow.statut = 'REMBOURSE' THEN
        -- Compatibilité défensive pour une éventuelle ligne créée avant cette
        -- migration. La production était vide lors de l'audit pré-déploiement.
        v_legacy_escrow := true;
      ELSIF v_escrow.statut = 'REMBOURSE_EN_COURS' THEN
        UPDATE public.paiements_escrow
           SET statut = 'REMBOURSE',
               erreur = NULL,
               modifie_le = now()
         WHERE id = v_escrow.id
           AND statut = 'REMBOURSE_EN_COURS';
        GET DIAGNOSTICS v_rows = ROW_COUNT;
        IF v_rows <> 1 THEN
          RAISE EXCEPTION 'Finalisation escrow concurrente refusée';
        END IF;
      ELSE
        RAISE EXCEPTION 'État escrow incompatible avec refund réussi: %',
          v_escrow.statut USING ERRCODE = 'P0001';
      END IF;

      UPDATE public.escrow_exposition_releases
         SET statut = 'REGLE'
       WHERE paiement_escrow_id = v_escrow.id
         AND statut = 'ACTIF';
    END IF;

    UPDATE public.stripe_refunds_queue
       SET statut = 'TRAITE',
           stripe_refund_id = p_stripe_refund_id,
           traite_le = COALESCE(p_finalise_le, now()),
           dernier_essai_le = now(),
           erreur = NULL
     WHERE id = v_queue.id
       AND statut IN ('EN_ATTENTE', 'EN_COURS');
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    IF v_rows <> 1 THEN
      RAISE EXCEPTION 'Finalisation queue concurrente refusée';
    END IF;

    INSERT INTO public.journaux_audit (
      acteur_id, type_acteur, action, type_ressource, id_ressource,
      details, navigateur_acteur
    ) VALUES (
      '00000000-0000-0000-0000-000000000000'::uuid,
      'SYSTEME',
      CASE
        WHEN v_queue.avoir_id IS NOT NULL THEN 'AVOIR_REMBOURSEMENT_CONFIRME'
        WHEN v_queue.paiement_escrow_id IS NOT NULL THEN 'ESCROW_REMBOURSE'
        ELSE 'FINANCE_CHARGE_REFUNDED'
      END,
      CASE
        WHEN v_queue.avoir_id IS NOT NULL THEN 'facture_honoraires'
        WHEN v_queue.paiement_escrow_id IS NOT NULL THEN 'paiement_escrow'
        ELSE 'stripe_refunds_queue'
      END,
      COALESCE(v_queue.avoir_id, v_queue.paiement_escrow_id, v_queue.id),
      jsonb_build_object(
        'queue_id', v_queue.id,
        'stripe_refund_id', p_stripe_refund_id,
        'stripe_payment_intent_id', v_queue.stripe_payment_intent_id,
        'montant_cts', v_queue.montant_cts
      ),
      'fn_stripe_refund_rapprocher'
    );

    RETURN jsonb_build_object(
      'success', true,
      'resultat', 'SUCCEEDED',
      'legacy_escrow', v_legacy_escrow
    );
  END IF;

  -- failed/canceled : le remboursement n'a pas eu lieu. Restaurer l'escrow
  -- exactement dans son état antérieur ; ne jamais solder son exposition.
  IF v_queue.paiement_escrow_id IS NOT NULL THEN
    SELECT pe.*
      INTO v_escrow
      FROM public.paiements_escrow pe
     WHERE pe.id = v_queue.paiement_escrow_id
     FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Escrow de la queue introuvable' USING ERRCODE = 'P0001';
    END IF;

    IF v_escrow.statut = 'REMBOURSE_EN_COURS' THEN
      IF v_queue.escrow_statut_avant_remboursement NOT IN (
        'DEBITE', 'DISPONIBLE', 'PAYE'
      ) THEN
        RAISE EXCEPTION 'État escrow antérieur absent ou invalide'
          USING ERRCODE = 'P0001';
      END IF;
      UPDATE public.paiements_escrow
         SET statut = v_queue.escrow_statut_avant_remboursement,
             erreur = left(COALESCE(p_detail, p_resultat), 500),
             modifie_le = now()
       WHERE id = v_escrow.id
         AND statut = 'REMBOURSE_EN_COURS';
      GET DIAGNOSTICS v_rows = ROW_COUNT;
      IF v_rows <> 1 THEN
        RAISE EXCEPTION 'Restauration escrow concurrente refusée';
      END IF;
    ELSIF v_escrow.statut <> 'REMBOURSE' THEN
      RAISE EXCEPTION 'État escrow incompatible avec refund échoué: %',
        v_escrow.statut USING ERRCODE = 'P0001';
    END IF;
  END IF;

  UPDATE public.stripe_refunds_queue
     SET statut = 'ECHEC',
         stripe_refund_id = COALESCE(p_stripe_refund_id, stripe_refund_id),
         dernier_essai_le = now(),
         erreur = left(COALESCE(p_detail, p_resultat), 500)
   WHERE id = v_queue.id
     AND statut IN ('EN_ATTENTE', 'EN_COURS');
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'Échec queue concurrent refusé';
  END IF;

  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource,
    details, navigateur_acteur
  ) VALUES (
    '00000000-0000-0000-0000-000000000000'::uuid,
    'SYSTEME',
    'ADMIN_ACTION',
    'stripe_refunds_queue',
    v_queue.id,
    jsonb_build_object(
      'evenement', 'FINANCE_REFUND_TERMINE_SANS_SUCCES',
      'queue_id', v_queue.id,
      'stripe_refund_id', p_stripe_refund_id,
      'resultat', p_resultat,
      'detail', p_detail
    ),
    'fn_stripe_refund_rapprocher'
  );

  RETURN jsonb_build_object('success', true, 'resultat', p_resultat);
END;
$function$;

UPDATE private.security_definer_inventory
SET definition_md5=md5((SELECT prosrc FROM pg_proc WHERE oid='public.fn_stripe_refund_rapprocher(uuid,text,text,text,timestamptz)'::regprocedure)),recense_le=now()
WHERE signature='fn_stripe_refund_rapprocher(uuid,text,text,text,timestamp with time zone)';
