-- VERROU (principe « gap verrouillé ») — fn_escrow_rembourser refuse tout
-- remboursement PARTIEL AVANT release. Gap documenté §9.4 :
-- un remboursement partiel pré-release (statut DEBITE/DISPONIBLE/RELEASE_PLANIFIE)
-- reprend une part des honoraires sur le solde connecté MAIS le payout n'a
-- jamais lieu (escrow → REMBOURSE → release skippé) → le reliquat
-- (honoraires − repris) reste bloqué sur le solde Stripe connecté, jamais
-- reversé au soignant. Tant que le flux reliquat cible (TODO Lot 13) n'est pas
-- livré, ce cas est rendu IMPOSSIBLE à déclencher silencieusement : exception
-- claire renvoyant à la spec.
--
-- Autorisés (inchangés) : annulation TOTALE (pré ou post-release), et
-- remboursement partiel POST-versement (statut PAYE → absorption plateforme, le
-- soignant a déjà touché 100 %).
--
-- TODO(Lot 13) — flux reliquat cible pour lever ce verrou :
--   1. Nouvel état paiements_escrow 'REMBOURSE_PARTIEL' + colonne
--      montant_rembourse_cents (traçabilité du repris).
--   2. Après reprise partielle pré-release : re-enfiler un release du solde
--      restant (honoraires − repris) → payout du reliquat au soignant.
--   3. UI : état « Versé partiellement (X € sur Y) — résolution du litige du JJ/MM »
--      (aujourd'hui non affiché, cf. SPEC §1 note + §9.4).

CREATE OR REPLACE FUNCTION public.fn_escrow_rembourser(p_paiement_escrow_id uuid, p_montant_honoraires_cts integer, p_annulation_totale boolean DEFAULT false, p_motif text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_row            paiements_escrow%ROWTYPE;
  v_absorbe        boolean;
  v_reverse        boolean;
  v_fee_cts        integer;
  v_montant_total  integer;
BEGIN
  SELECT * INTO v_row FROM paiements_escrow WHERE id = p_paiement_escrow_id;
  IF v_row.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'ESCROW_INCONNU');
  END IF;

  IF p_montant_honoraires_cts <= 0 OR p_montant_honoraires_cts > v_row.honoraires_cents THEN
    RETURN jsonb_build_object('success', false, 'error', 'MONTANT_INVALIDE');
  END IF;

  IF v_row.stripe_payment_intent_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'PAS_DE_DEBIT');
  END IF;

  -- VERROU gap §9.4 : partiel pré-release interdit (reliquat non versable).
  IF NOT p_annulation_totale
     AND p_montant_honoraires_cts < v_row.honoraires_cents
     AND v_row.statut IN ('DEBITE', 'DISPONIBLE', 'RELEASE_PLANIFIE') THEN
    RAISE EXCEPTION 'Résolution partielle indisponible avant release, reliquat non versable — cf. docs/SPEC_ESCROW_REVENUS_SOIGNANT.md §9.4, TODO Lot 13'
      USING ERRCODE = 'P0001';
  END IF;

  -- A5 : après release (PAYE) → absorption plateforme, pas de reverse_transfer.
  v_absorbe := (v_row.statut = 'PAYE');
  v_reverse := (NOT v_absorbe) AND (v_row.statut IN ('DEBITE', 'DISPONIBLE', 'RELEASE_PLANIFIE'));

  -- A6 : commission remboursée à 100 % si annulation totale, sinon prorata sur
  -- la part d'honoraires effectivement reprise.
  IF p_annulation_totale THEN
    v_fee_cts := v_row.commission_cents;
  ELSE
    v_fee_cts := ROUND(v_row.commission_cents::numeric
                       * p_montant_honoraires_cts / v_row.honoraires_cents)::integer;
  END IF;

  -- Montant total remboursé à l'établissement = honoraires repris + commission.
  v_montant_total := p_montant_honoraires_cts + v_fee_cts;

  INSERT INTO stripe_refunds_queue (
    avoir_id, facture_origine_id, stripe_payment_intent_id, montant_cts, statut,
    paiement_escrow_id, reverse_transfer, refund_application_fee_cts, absorbe_plateforme
  ) VALUES (
    NULL, NULL, v_row.stripe_payment_intent_id, v_montant_total, 'EN_ATTENTE',
    p_paiement_escrow_id, v_reverse, v_fee_cts, v_absorbe
  );

  UPDATE paiements_escrow
  SET statut = 'REMBOURSE', modifie_le = now()
  WHERE id = p_paiement_escrow_id;

  -- Décrémente l'exposition A2 : le release est réglé (remboursé).
  UPDATE escrow_exposition_releases
  SET statut = 'REGLE'
  WHERE paiement_escrow_id = p_paiement_escrow_id AND statut = 'ACTIF';

  PERFORM public.fn_ecrire_audit_safe(
    '00000000-0000-0000-0000-000000000000'::uuid, 'SYSTEME',
    'ESCROW_REMBOURSEMENT_ENFILE', 'mission', v_row.mission_id, NULL,
    jsonb_build_object(
      'paiement_escrow_id', p_paiement_escrow_id,
      'montant_honoraires_cts', p_montant_honoraires_cts,
      'refund_application_fee_cts', v_fee_cts,
      'montant_total_cts', v_montant_total,
      'reverse_transfer', v_reverse,
      'absorbe_plateforme', v_absorbe,
      'annulation_totale', p_annulation_totale,
      'motif', p_motif
    ), NULL, 'fn_escrow_rembourser'
  );

  RETURN jsonb_build_object(
    'success', true,
    'reverse_transfer', v_reverse,
    'absorbe_plateforme', v_absorbe,
    'refund_application_fee_cts', v_fee_cts,
    'montant_total_cts', v_montant_total
  );
END;
$function$;
