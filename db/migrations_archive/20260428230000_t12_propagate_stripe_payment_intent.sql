-- T12 — Câblage stripe_payment_intent_id sur factures_honoraires.
--
-- Contexte (cf. docs/tech-debt.md T12) :
-- factures_honoraires.stripe_payment_intent_id existe en colonne mais
-- n'était jamais peuplé. Conséquence : fn_admin_resoudre_litige cas AVOIR
-- (auto-stripe <120j) tombait toujours sur mode_remboursement=VIREMENT_MANUEL
-- car stripe_payment_intent_id NULL côté facture, même quand le paiement
-- avait été fait via Stripe Connect.
--
-- Solution choisie (option B simplifiée — trigger SQL, pas webhook) :
-- AFTER INSERT/UPDATE sur stripe_transfers, propager
-- stripe_payment_intent_id vers la FACTURE de la mission liée. Plus
-- robuste qu'un appel webhook (pas de fenêtre d'erreur réseau,
-- idempotent par WHERE conditionnel).
--
-- IMPORTANT : la jointure passe par mission_id (et non facture_id, qui
-- sur stripe_transfers pointe vers la table `factures` de commission
-- Jolene → étab, pas vers `factures_honoraires`). On propage uniquement
-- sur le type_document='FACTURE' (pas les AVOIR liés à la même mission).
--
-- L'immutabilité factures_honoraires post-EMISE NE bloque PAS
-- stripe_payment_intent_id (vérifié dans
-- fn_protect_facture_honoraire_immutability : seuls montant_*, numero,
-- identités, type_document et date_emission sont verrouillés).

CREATE OR REPLACE FUNCTION public.fn_propage_stripe_payment_intent_trg()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  IF NEW.mission_id IS NOT NULL AND NEW.stripe_payment_intent_id IS NOT NULL
     AND NEW.stripe_payment_intent_id <> '' THEN
    UPDATE public.factures_honoraires
    SET stripe_payment_intent_id = NEW.stripe_payment_intent_id
    WHERE mission_id = NEW.mission_id
      AND COALESCE(type_document, 'FACTURE') = 'FACTURE'
      AND (stripe_payment_intent_id IS NULL
           OR stripe_payment_intent_id <> NEW.stripe_payment_intent_id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_propage_stripe_payment_intent ON public.stripe_transfers;

CREATE TRIGGER trg_propage_stripe_payment_intent
  AFTER INSERT OR UPDATE OF stripe_payment_intent_id, mission_id
  ON public.stripe_transfers
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_propage_stripe_payment_intent_trg();

-- Backfill : pour les stripe_transfers déjà existants, propager vers
-- factures_honoraires les PI manquants.
UPDATE public.factures_honoraires fh
SET stripe_payment_intent_id = st.stripe_payment_intent_id
FROM public.stripe_transfers st
WHERE st.mission_id = fh.mission_id
  AND COALESCE(fh.type_document, 'FACTURE') = 'FACTURE'
  AND st.stripe_payment_intent_id IS NOT NULL
  AND st.stripe_payment_intent_id <> ''
  AND (fh.stripe_payment_intent_id IS NULL
       OR fh.stripe_payment_intent_id <> st.stripe_payment_intent_id);

NOTIFY pgrst, 'reload schema';
