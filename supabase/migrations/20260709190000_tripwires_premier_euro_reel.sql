-- TRIPWIRES — le rail de paiement rapide (flag ⚡ = 1) est ouvert : les premiers
-- événements réels doivent être REGARDÉS, pas découverts. Alerte support à la
-- PREMIÈRE occurrence globale de : mandat SEPA posé, onboarding Connect complété,
-- PaymentIntent réel créé. Canal : edge function notify-support (→ support@jolene.app).
--
-- Gating : fn_param_num('alertes_tripwire_actives', 1). Par défaut ACTIF (prod).
-- Les environnements de test (recette escrow) le mettent à 0 (Setup 0) pour ne
-- pas spammer le support à chaque run. « Première occurrence » = NOT EXISTS d'une
-- autre ligne satisfaisant la condition → auto-limité, ne fire qu'une fois.

CREATE OR REPLACE FUNCTION public.fn_tripwire_alerte(p_sujet text, p_corps text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
BEGIN
  IF public.fn_param_num('alertes_tripwire_actives', 1) <> 1 THEN
    RETURN;
  END IF;
  BEGIN
    PERFORM net.http_post(
      url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/notify-support',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
      ),
      body := jsonb_build_object(
        'sujet', p_sujet,
        'corps', p_corps,
        'source', 'tripwire-paiement'
      )
    );
  EXCEPTION WHEN OTHERS THEN
    NULL; -- non bloquant : une alerte ratée ne casse jamais le flux métier.
  END;
END;
$fn$;

-- ── 1. Premier mandat SEPA posé (etablissements) ─────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_trg_tripwire_premier_mandat_sepa()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
BEGIN
  IF NEW.stripe_sepa_payment_method_id IS NOT NULL
     AND (TG_OP = 'INSERT' OR OLD.stripe_sepa_payment_method_id IS NULL)
     AND NOT EXISTS (SELECT 1 FROM etablissements
                     WHERE stripe_sepa_payment_method_id IS NOT NULL AND id <> NEW.id) THEN
    PERFORM public.fn_tripwire_alerte(
      '[TRIPWIRE] Premier mandat SEPA posé',
      'Le premier établissement vient de poser son mandat SEPA (paiement rapide ⚡). Établissement id: ' || NEW.id || '. Le rail d''encaissement est désormais actif — à surveiller.'
    );
  END IF;
  RETURN NEW;
END;
$fn$;
DROP TRIGGER IF EXISTS trg_tripwire_premier_mandat_sepa ON public.etablissements;
CREATE TRIGGER trg_tripwire_premier_mandat_sepa
  AFTER INSERT OR UPDATE OF stripe_sepa_payment_method_id ON public.etablissements
  FOR EACH ROW EXECUTE FUNCTION public.fn_trg_tripwire_premier_mandat_sepa();

-- ── 2. Premier onboarding Connect complété (stripe_connect_onboarding) ────────
CREATE OR REPLACE FUNCTION public.fn_trg_tripwire_premier_connect_complet()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
BEGIN
  IF NEW.statut = 'COMPLET'
     AND (TG_OP = 'INSERT' OR OLD.statut IS DISTINCT FROM 'COMPLET')
     AND NOT EXISTS (SELECT 1 FROM stripe_connect_onboarding
                     WHERE statut = 'COMPLET' AND soignant_id <> NEW.soignant_id) THEN
    PERFORM public.fn_tripwire_alerte(
      '[TRIPWIRE] Premier compte Connect complété',
      'Le premier soignant vient de compléter son onboarding Stripe Connect. Soignant id: ' || NEW.soignant_id || '. Il peut désormais recevoir des virements — à surveiller.'
    );
  END IF;
  RETURN NEW;
END;
$fn$;
DROP TRIGGER IF EXISTS trg_tripwire_premier_connect_complet ON public.stripe_connect_onboarding;
CREATE TRIGGER trg_tripwire_premier_connect_complet
  AFTER INSERT OR UPDATE OF statut ON public.stripe_connect_onboarding
  FOR EACH ROW EXECUTE FUNCTION public.fn_trg_tripwire_premier_connect_complet();

-- ── 3. Premier PaymentIntent réel créé (paiements_escrow) ─────────────────────
-- Les seeds E2E insèrent des escrows avec un PI factice `pi_pwtest_*` (spec
-- escrow-revenus-soignant, prod partagée) : on les EXCLUT entièrement — ni
-- déclencheurs, ni comptés comme « premier » — pour que le premier PaymentIntent
-- RÉEL reste le vrai signal.
CREATE OR REPLACE FUNCTION public.fn_trg_tripwire_premier_payment_intent()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
BEGIN
  IF NEW.stripe_payment_intent_id IS NOT NULL
     AND NEW.stripe_payment_intent_id NOT LIKE 'pi_pwtest%'
     AND (TG_OP = 'INSERT' OR OLD.stripe_payment_intent_id IS NULL)
     AND NOT EXISTS (SELECT 1 FROM paiements_escrow
                     WHERE stripe_payment_intent_id IS NOT NULL
                       AND stripe_payment_intent_id NOT LIKE 'pi_pwtest%' AND id <> NEW.id) THEN
    PERFORM public.fn_tripwire_alerte(
      '[TRIPWIRE] Premier PaymentIntent réel créé',
      'Le premier débit escrow réel vient d''être initié. Escrow id: ' || NEW.id || ', mission: ' || NEW.mission_id || ', PI: ' || NEW.stripe_payment_intent_id || '. Le premier euro réel circule — À REGARDER.'
    );
  END IF;
  RETURN NEW;
END;
$fn$;
DROP TRIGGER IF EXISTS trg_tripwire_premier_payment_intent ON public.paiements_escrow;
CREATE TRIGGER trg_tripwire_premier_payment_intent
  AFTER INSERT OR UPDATE OF stripe_payment_intent_id ON public.paiements_escrow
  FOR EACH ROW EXECUTE FUNCTION public.fn_trg_tripwire_premier_payment_intent();
