-- Rapprochement local transactionnel d'un paiement Connect dont la Charge et le
-- Transfer ont déjà été vérifiés auprès de Stripe par l'Edge Function. Un retry
-- de Checkout peut ainsi réparer toutes les écritures métier sans redébiter
-- l'établissement, même si les retries du webhook ont été épuisés.

CREATE UNIQUE INDEX IF NOT EXISTS uniq_paiements_soignant_stripe_transfer
  ON public.paiements_soignant (stripe_transfer_id)
  WHERE stripe_transfer_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.fn_stripe_connect_rapprocher_local(
  p_mission_id uuid,
  p_soignant_id uuid,
  p_etablissement_id uuid,
  p_facture_honoraires_id uuid,
  p_facture_commission_id uuid,
  p_stripe_checkout_session_id text,
  p_stripe_payment_intent_id text,
  p_stripe_charge_id text,
  p_stripe_transfer_id text,
  p_montant_soignant_cts integer,
  p_montant_commission_cts integer,
  p_montant_total_cts integer,
  p_rapproche_le timestamptz DEFAULT now()
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_mission public.missions%ROWTYPE;
  v_transfer public.stripe_transfers%ROWTYPE;
  v_honoraires public.factures_honoraires%ROWTYPE;
  v_commission public.factures%ROWTYPE;
  v_numero_commission text;
  v_rows integer;
BEGIN
  IF COALESCE(
       auth.jwt()->>'role',
       current_setting('request.jwt.claim.role', true),
       ''
     ) <> 'service_role'
     AND session_user NOT IN ('postgres', 'supabase_admin') THEN
    RAISE EXCEPTION 'Service role requis' USING ERRCODE = '42501';
  END IF;

  IF p_mission_id IS NULL OR p_soignant_id IS NULL OR p_etablissement_id IS NULL
     OR p_facture_honoraires_id IS NULL
     OR p_stripe_checkout_session_id !~ '^cs_[A-Za-z0-9_]+$'
     OR p_stripe_payment_intent_id !~ '^pi_[A-Za-z0-9]+$'
     OR p_stripe_charge_id !~ '^ch_[A-Za-z0-9]+'
     OR p_stripe_transfer_id !~ '^tr_[A-Za-z0-9]+$'
     OR p_montant_soignant_cts <= 0
     OR p_montant_commission_cts <= 0
     OR p_montant_total_cts <> p_montant_soignant_cts + p_montant_commission_cts THEN
    RAISE EXCEPTION 'Paramètres de rapprochement Connect invalides'
      USING ERRCODE = '22023';
  END IF;

  SELECT m.* INTO v_mission
  FROM public.missions m
  WHERE m.id = p_mission_id
  FOR UPDATE;
  IF NOT FOUND
     OR v_mission.etablissement_id <> p_etablissement_id
     OR v_mission.soignant_assigne_id <> p_soignant_id
     OR v_mission.statut <> 'TERMINEE'
     OR v_mission.type_contrat_applique <> 'LIBERAL'
     OR round(v_mission.net_a_payer * 100)::integer <> p_montant_soignant_cts
     OR round(v_mission.montant_commission_ttc * 100)::integer <> p_montant_commission_cts THEN
    RAISE EXCEPTION 'Mission Connect incohérente' USING ERRCODE = 'P0001';
  END IF;

  SELECT st.* INTO v_transfer
  FROM public.stripe_transfers st
  WHERE st.mission_id = p_mission_id
    AND st.stripe_checkout_session_id = p_stripe_checkout_session_id
  ORDER BY st.cree_le DESC
  LIMIT 1
  FOR UPDATE;
  IF NOT FOUND
     OR v_transfer.soignant_id <> p_soignant_id
     OR v_transfer.etablissement_id <> p_etablissement_id
     OR round(v_transfer.montant_soignant * 100)::integer <> p_montant_soignant_cts
     OR round(v_transfer.montant_commission * 100)::integer <> p_montant_commission_cts
     OR round(v_transfer.montant_total * 100)::integer <> p_montant_total_cts
     OR v_transfer.statut NOT IN ('EN_ATTENTE', 'ECHOUE', 'CHARGE_REUSSI', 'TRANSFERE', 'PAYE')
     OR (v_transfer.stripe_payment_intent_id IS NOT NULL
         AND v_transfer.stripe_payment_intent_id <> p_stripe_payment_intent_id)
     OR (v_transfer.stripe_transfer_id IS NOT NULL
         AND v_transfer.stripe_transfer_id <> p_stripe_transfer_id) THEN
    RAISE EXCEPTION 'Trace Connect incohérente' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.stripe_transfers
  SET statut = CASE
        WHEN statut = 'PAYE' THEN 'PAYE'
        ELSE 'TRANSFERE'
      END,
      stripe_payment_intent_id = p_stripe_payment_intent_id,
      stripe_charge_id = p_stripe_charge_id,
      stripe_transfer_id = p_stripe_transfer_id,
      transfere_le = COALESCE(transfere_le, p_rapproche_le, now()),
      erreur = NULL
  WHERE id = v_transfer.id;

  SELECT fh.* INTO v_honoraires
  FROM public.factures_honoraires fh
  WHERE fh.id = p_facture_honoraires_id
  FOR UPDATE;
  IF NOT FOUND
     OR v_honoraires.type_document <> 'FACTURE'
     OR v_honoraires.mission_id <> p_mission_id
     OR v_honoraires.soignant_id <> p_soignant_id
     OR v_honoraires.etablissement_id <> p_etablissement_id
     OR round(v_honoraires.montant_ttc * 100)::integer <> p_montant_soignant_cts
     OR v_honoraires.statut NOT IN ('EMISE', 'EN_RETARD', 'PAYEE')
     OR (v_honoraires.stripe_payment_intent_id IS NOT NULL
         AND v_honoraires.stripe_payment_intent_id <> p_stripe_payment_intent_id) THEN
    RAISE EXCEPTION 'Facture honoraires Connect incohérente' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.factures_honoraires
  SET statut = 'PAYEE',
      stripe_payment_intent_id = p_stripe_payment_intent_id,
      date_paiement = COALESCE(date_paiement, (COALESCE(p_rapproche_le, now()))::date),
      modifie_le = now()
  WHERE id = v_honoraires.id;

  IF p_facture_commission_id IS NOT NULL THEN
    SELECT f.* INTO v_commission
    FROM public.factures f
    WHERE f.id = p_facture_commission_id
    FOR UPDATE;
    IF NOT FOUND
       OR v_commission.type_document <> 'FACTURE'
       OR v_commission.mission_id <> p_mission_id
       OR v_commission.etablissement_id <> p_etablissement_id
       OR round(v_commission.montant_ttc * 100)::integer <> p_montant_commission_cts
       OR v_commission.statut NOT IN ('EMISE', 'EN_RETARD', 'PAYEE')
       OR (v_commission.stripe_payment_intent_id IS NOT NULL
           AND v_commission.stripe_payment_intent_id <> p_stripe_payment_intent_id) THEN
      RAISE EXCEPTION 'Facture commission Connect incohérente' USING ERRCODE = 'P0001';
    END IF;
    UPDATE public.factures
    SET statut = 'PAYEE',
        stripe_payment_intent_id = p_stripe_payment_intent_id,
        date_paiement = COALESCE(date_paiement, p_rapproche_le, now()),
        mode_paiement = 'STRIPE',
        modifie_le = now()
    WHERE id = v_commission.id;
  ELSE
    v_numero_commission := 'FACT-STRIPE-'
      || to_char(COALESCE(p_rapproche_le, now()), 'YYYY-MM-DD')
      || '-' || split_part(p_mission_id::text, '-', 1);
    INSERT INTO public.factures (
      etablissement_id, mission_id, numero_facture,
      montant_ht, montant_tva, montant_ttc, taux_tva, nombre_missions,
      statut, date_emission, date_paiement, mode_paiement,
      stripe_payment_intent_id, type_document
    ) VALUES (
      p_etablissement_id, p_mission_id, v_numero_commission,
      v_mission.montant_commission_ht,
      v_mission.montant_commission_tva,
      v_mission.montant_commission_ttc,
      20, 1,
      'PAYEE', COALESCE(p_rapproche_le, now()), COALESCE(p_rapproche_le, now()),
      'STRIPE', p_stripe_payment_intent_id, 'FACTURE'
    )
    ON CONFLICT (numero_facture) DO NOTHING;

    SELECT f.* INTO v_commission
    FROM public.factures f
    WHERE f.numero_facture = v_numero_commission
    FOR UPDATE;
    IF NOT FOUND
       OR v_commission.mission_id <> p_mission_id
       OR v_commission.etablissement_id <> p_etablissement_id
       OR v_commission.statut <> 'PAYEE'
       OR v_commission.stripe_payment_intent_id <> p_stripe_payment_intent_id
       OR round(v_commission.montant_ttc * 100)::integer <> p_montant_commission_cts THEN
      RAISE EXCEPTION 'Création facture commission Connect incohérente'
        USING ERRCODE = 'P0001';
    END IF;
  END IF;

  INSERT INTO public.paiements_soignant (
    mission_id, soignant_id, etablissement_id, montant_net, methode,
    reference_virement, date_paiement, statut,
    confirme_par_etablissement, confirme_par_etablissement_le,
    confirme_par_soignant, confirme_par_soignant_le, stripe_transfer_id
  ) VALUES (
    p_mission_id, p_soignant_id, p_etablissement_id,
    p_montant_soignant_cts::numeric / 100, 'NOTE_HONORAIRES',
    'STRIPE-' || p_stripe_transfer_id,
    (COALESCE(p_rapproche_le, now()))::date, 'CONFIRME',
    true, COALESCE(p_rapproche_le, now()),
    true, COALESCE(p_rapproche_le, now()), p_stripe_transfer_id
  )
  ON CONFLICT (stripe_transfer_id) WHERE stripe_transfer_id IS NOT NULL
  DO NOTHING;

  SELECT count(*) INTO v_rows
  FROM public.paiements_soignant ps
  WHERE ps.stripe_transfer_id = p_stripe_transfer_id
    AND ps.mission_id = p_mission_id
    AND ps.soignant_id = p_soignant_id
    AND ps.etablissement_id = p_etablissement_id
    AND round(ps.montant_net * 100)::integer = p_montant_soignant_cts
    AND ps.statut = 'CONFIRME';
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'Paiement soignant Connect incohérent' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.missions
  SET mode_paiement_soignant = 'STRIPE_CONNECT',
      commission_facturee = true,
      modifie_le = now()
  WHERE id = p_mission_id;

  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource,
    details, navigateur_acteur
  ) VALUES (
    p_soignant_id,
    'SYSTEME',
    'FINANCE_TRANSFER_CONNECT',
    'mission',
    p_mission_id,
    jsonb_build_object(
      'stripe_transfer_id', p_stripe_transfer_id,
      'stripe_charge_id', p_stripe_charge_id,
      'stripe_payment_intent_id', p_stripe_payment_intent_id,
      'stripe_session_id', p_stripe_checkout_session_id,
      'facture_honoraires_id', p_facture_honoraires_id,
      'facture_commission_id', v_commission.id,
      'montant_cents', p_montant_soignant_cts,
      'evenement', 'CONNECT_RAPPROCHEMENT_LOCAL_ATOMIQUE'
    ),
    'fn_stripe_connect_rapprocher_local'
  );

  RETURN jsonb_build_object(
    'success', true,
    'stripe_transfer_id', p_stripe_transfer_id,
    'facture_commission_id', v_commission.id
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_stripe_connect_rapprocher_local(
  uuid, uuid, uuid, uuid, uuid,
  text, text, text, text,
  integer, integer, integer, timestamptz
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_stripe_connect_rapprocher_local(
  uuid, uuid, uuid, uuid, uuid,
  text, text, text, text,
  integer, integer, integer, timestamptz
) TO service_role;
