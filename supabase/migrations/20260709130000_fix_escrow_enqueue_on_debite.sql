-- Escrow 7b-D — enqueue de la release queue au passage DEBITE
-- (bug prod bloquant découvert par la recette Stripe, run #10 du 09/07/2026)
--
-- Le SEUL enqueue de escrow_release_queue était le trigger présences
-- (trg_escrow_release_on_validation), qui exige un escrow déjà DEBITE ou
-- DISPONIBLE. Or le cas COURANT en prod est inverse : l'établissement valide
-- les présences le jour de la mission, et le settlement SEPA (INITIE → DEBITE,
-- webhook payment_intent.succeeded) n'arrive qu'à J+2-5. À la transition
-- DEBITE, personne n'enfilait la queue → le payout n'était JAMAIS déclenché.
--
-- Fix : trigger miroir côté paiements_escrow — à la transition → DEBITE, si le
-- gate 7b-B est satisfait (au moins une présence validée, aucune présence
-- bloquante), on enfile. ON CONFLICT DO NOTHING : idempotent avec le trigger
-- présences quand la validation arrive après le DEBITE.

CREATE OR REPLACE FUNCTION public.fn_trg_escrow_enqueue_on_debite()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
BEGIN
  IF NEW.statut <> 'DEBITE' OR NEW.statut = OLD.statut THEN
    RETURN NEW;
  END IF;

  -- Gate 7b-B, miroir de fn_trg_escrow_release_check :
  -- au moins une présence validée…
  IF NOT EXISTS (
    SELECT 1 FROM presences p
    WHERE p.mission_id = NEW.mission_id
      AND COALESCE(p.valide_par_etablissement, false) = true
  ) THEN
    RETURN NEW; -- validation pas encore faite : le trigger présences prendra le relais
  END IF;

  -- … et aucune présence bloquante.
  IF EXISTS (
    SELECT 1 FROM presences p
    WHERE p.mission_id = NEW.mission_id
      AND COALESCE(p.valide_par_etablissement, false) = false
      AND (p.pointage_depart_le IS NOT NULL OR p.motif_litige IS NOT NULL)
  ) THEN
    RETURN NEW;
  END IF;

  INSERT INTO escrow_release_queue (paiement_escrow_id, mission_id)
  VALUES (NEW.id, NEW.mission_id)
  ON CONFLICT (paiement_escrow_id) DO NOTHING;

  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_escrow_enqueue_on_debite ON public.paiements_escrow;
CREATE TRIGGER trg_escrow_enqueue_on_debite
  AFTER UPDATE OF statut ON public.paiements_escrow
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_trg_escrow_enqueue_on_debite();
