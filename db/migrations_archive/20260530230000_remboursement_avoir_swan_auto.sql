-- Remboursement des avoirs par virement SEPA SWAN automatique (comme le parrainage),
-- avec fallback admin. Quand un avoir passe en VIREMENT_MANUEL :
--   - IBAN présent  → enfile une action REMBOURSEMENT_AVOIR_SWAN (cron */5min →
--     process-externalisation-actions → SWAN SCT). Admin notifié (awareness).
--   - IBAN absent    → admin notifié pour virement manuel (fn_confirmer_remboursement_avoir).
-- Si SWAN échoue, l'avoir reste non remboursé (visible AvoirsList + Externalisations) :
-- le fallback manuel admin reste disponible.

-- 1) Étendre les CHECK externalisation_actions
ALTER TABLE public.externalisation_actions DROP CONSTRAINT IF EXISTS externalisation_actions_type_action_check;
ALTER TABLE public.externalisation_actions
  ADD CONSTRAINT externalisation_actions_type_action_check
  CHECK (type_action IN (
    'STRIPE_REFUND_PARTIEL', 'STRIPE_REFUND_TOTAL', 'STRIPE_PAYMENT', 'STRIPE_PAYOUT',
    'CHORUS_RECYCLER_FACTURE', 'CHORUS_RECYCLE_FACTURE',
    'DPAE_ANNULATION', 'DPAE_ANNULATION_NOTIF',
    'EMAIL_NOTIF', 'PUSH_NOTIF', 'AVOIR_PDF_GENERATION',
    'RECOMPENSE_PARRAINAGE_SOIGNANT', 'REMBOURSEMENT_AVOIR_SWAN'
  ));

ALTER TABLE public.externalisation_actions DROP CONSTRAINT IF EXISTS externalisation_actions_source_check;
ALTER TABLE public.externalisation_actions
  ADD CONSTRAINT externalisation_actions_source_check
  CHECK (source IN (
    'LITIGE_EXEC', 'ANNULATION_MISSION', 'AUTRE', 'CRON_ANTI_TRICHE',
    'CRON_ALERTES', 'parrainage_soignant', 'remboursement_avoir'
  ));

-- 2) Trigger : SWAN auto si IBAN, sinon manuel ; admin toujours notifié (awareness)
CREATE OR REPLACE FUNCTION public.fn_trg_notif_admin_remboursement_manuel()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_admin_id UUID;
  v_soignant RECORD;
  v_montant NUMERIC;
  v_a_iban BOOLEAN;
BEGIN
  IF NEW.type_document <> 'AVOIR' OR NEW.mode_remboursement <> 'VIREMENT_MANUEL'
     OR NEW.date_remboursement IS NOT NULL THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE' AND OLD.mode_remboursement = 'VIREMENT_MANUEL'
     AND OLD.type_document = 'AVOIR' THEN
    RETURN NEW; -- déjà traité
  END IF;

  SELECT prenom, nom, iban_virement INTO v_soignant
  FROM public.soignants WHERE id = NEW.soignant_id;
  v_a_iban := v_soignant.iban_virement IS NOT NULL AND length(trim(v_soignant.iban_virement)) > 0;
  v_montant := COALESCE(NEW.montant_ttc, NEW.montant_ht, 0);

  -- Virement SEPA SWAN automatique si IBAN renseigné
  IF v_a_iban THEN
    INSERT INTO public.externalisation_actions (type_action, payload, source, source_id)
    VALUES (
      'REMBOURSEMENT_AVOIR_SWAN',
      jsonb_build_object('avoir_id', NEW.id, 'soignant_id', NEW.soignant_id, 'montant', v_montant),
      'remboursement_avoir', NEW.id
    );
  END IF;

  -- Admin toujours informé du remboursement + montant
  FOR v_admin_id IN SELECT public.fn_list_admin_user_ids() LOOP
    INSERT INTO public.notifications (destinataire_id, type_destinataire, type, titre, corps, lien, type_ressource, id_ressource)
    VALUES (
      v_admin_id, 'ADMIN_PLATEFORME', 'REMBOURSEMENT_MANUEL_A_FAIRE',
      CASE WHEN v_a_iban THEN '💸 Remboursement (virement SEPA auto)' ELSE '💸 Remboursement par virement à effectuer' END,
      'Avoir ' || COALESCE(NEW.numero_facture, '') || ' — ' ||
        to_char(v_montant, 'FM999G999D00') || ' € pour ' ||
        COALESCE(v_soignant.prenom, '') || ' ' || COALESCE(v_soignant.nom, '') ||
        CASE WHEN v_a_iban
             THEN ' : virement SEPA SWAN automatique initié.'
             ELSE ' : IBAN MANQUANT — virement manuel requis (relancer le soignant). Admin > Litiges > Avoirs.' END,
      '/admin/litiges',
      'facture_honoraire', NEW.id
    );
  END LOOP;

  RETURN NEW;
END;
$function$;

NOTIFY pgrst, 'reload schema';
