-- Sprint 17-A PR 4 — Étendre CHECK constraints externalisation_actions
--
-- Ajoute RECOMPENSE_PARRAINAGE_SOIGNANT au type_action CHECK
-- et parrainage_soignant au source CHECK.
-- Le handler est dans process-externalisation-actions/index.ts

-- 1) Drop et recréer le CHECK type_action (constraint inline sans nom)
DO $$
DECLARE
  v_constraint_name TEXT;
BEGIN
  SELECT conname INTO v_constraint_name
  FROM pg_constraint
  WHERE conrelid = 'public.externalisation_actions'::regclass
    AND contype = 'c'
    AND pg_get_constraintdef(oid) ILIKE '%type_action%'
  LIMIT 1;

  IF v_constraint_name IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.externalisation_actions DROP CONSTRAINT %I', v_constraint_name);
  END IF;
END $$;

ALTER TABLE public.externalisation_actions
  ADD CONSTRAINT externalisation_actions_type_action_check
  CHECK (type_action IN (
    'STRIPE_REFUND_PARTIEL', 'STRIPE_REFUND_TOTAL', 'STRIPE_PAYMENT', 'STRIPE_PAYOUT',
    'CHORUS_RECYCLER_FACTURE', 'CHORUS_RECYCLE_FACTURE',
    'DPAE_ANNULATION', 'DPAE_ANNULATION_NOTIF',
    'EMAIL_NOTIF', 'PUSH_NOTIF', 'AVOIR_PDF_GENERATION',
    'RECOMPENSE_PARRAINAGE_SOIGNANT'
  ));

-- 2) Drop et recréer le CHECK source
DO $$
DECLARE
  v_constraint_name TEXT;
BEGIN
  SELECT conname INTO v_constraint_name
  FROM pg_constraint
  WHERE conrelid = 'public.externalisation_actions'::regclass
    AND contype = 'c'
    AND pg_get_constraintdef(oid) ILIKE '%source%'
    AND pg_get_constraintdef(oid) NOT ILIKE '%source_id%'
  LIMIT 1;

  IF v_constraint_name IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.externalisation_actions DROP CONSTRAINT %I', v_constraint_name);
  END IF;
END $$;

ALTER TABLE public.externalisation_actions
  ADD CONSTRAINT externalisation_actions_source_check
  CHECK (source IN (
    'LITIGE_EXEC', 'ANNULATION_MISSION', 'AUTRE',
    'CRON_ANTI_TRICHE', 'CRON_ALERTES', 'parrainage_soignant'
  ));

NOTIFY pgrst, 'reload schema';
