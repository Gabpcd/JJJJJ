-- Escrow 7b-D — PR 4 : remboursements en destination charge.
-- INACTIF sans escrow (aucun paiements_escrow tant que le flag ⚡ = 0).
--
-- Décisions (docs/ESCROW_7BD_MAPPING.md §6) :
--   A5 : AVANT release (fonds encore sur le solde connecté) → reverse_transfer:true
--        (reprend au soignant). APRÈS release (payout parti, statut PAYE) →
--        remboursement ABSORBÉ par Jolene (avoir AUTO_STRIPE, pas de reversal,
--        jamais de solde négatif imposé à une soignante ayant travaillé — sauf
--        fraude, décision admin manuelle hors de ce chemin).
--   A6 : refund_application_fee — annulation TOTALE avant début → commission
--        remboursée à 100 % ; réduction partielle → prorata sur la part non due.
--   Base de montant : la part SOIGNANT réellement transférée (honoraires_cents),
--        pas l'écart HT du litige (correction du bug identifié à la cartographie).

-- ── 1. Colonnes escrow sur la file de remboursement ────────────────────────

ALTER TABLE stripe_refunds_queue
  ADD COLUMN IF NOT EXISTS paiement_escrow_id uuid REFERENCES paiements_escrow(id),
  ADD COLUMN IF NOT EXISTS reverse_transfer boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS refund_application_fee_cts integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS absorbe_plateforme boolean NOT NULL DEFAULT false;

-- ── 2. Enfilement d'un remboursement escrow (décide A5/A6) ──────────────────
-- Appelé par le circuit litige/annulation quand la mission est en escrow.
-- p_montant_honoraires_cts = part soignant à reprendre (<= honoraires_cents).
-- p_annulation_totale = annulation avant début (→ commission remboursée 100 %).

CREATE OR REPLACE FUNCTION public.fn_escrow_rembourser(
  p_paiement_escrow_id uuid,
  p_montant_honoraires_cts integer,
  p_annulation_totale boolean DEFAULT false,
  p_motif text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $esc_ref$
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
$esc_ref$;

REVOKE EXECUTE ON FUNCTION public.fn_escrow_rembourser(uuid, integer, boolean, text) FROM PUBLIC, anon, authenticated;

-- Autoriser l'action d'audit ESCROW_REMBOURSEMENT_ENFILE (fn_ecrire_audit_safe
-- avale sinon). Extension idempotente de la CHECK.
DO $audit$
DECLARE
  v_src text;
  v_inject text := ', ''ESCROW_REMBOURSEMENT_ENFILE''::text, ''ESCROW_REMBOURSE''::text';
BEGIN
  SELECT pg_get_constraintdef(c.oid) INTO v_src
  FROM pg_constraint c
  JOIN pg_class cl ON cl.oid = c.conrelid
  JOIN pg_namespace n ON n.oid = cl.relnamespace
  WHERE n.nspname = 'public' AND cl.relname = 'journaux_audit'
    AND c.conname = 'journaux_audit_action_check';

  IF v_src IS NOT NULL AND position('ESCROW_REMBOURSEMENT_ENFILE' IN v_src) = 0 THEN
    v_src := replace(v_src, '])))', v_inject || '])))');
    EXECUTE 'ALTER TABLE journaux_audit DROP CONSTRAINT journaux_audit_action_check';
    EXECUTE 'ALTER TABLE journaux_audit ADD CONSTRAINT journaux_audit_action_check ' || v_src;
  END IF;
END
$audit$;
