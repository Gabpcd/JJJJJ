-- AUDIT FONCTIONNEL — FIX BUG CRITIQUE #2 (RGPD)
-- fn_supprimer_mon_compte et fn_supprimer_mon_compte_etablissement n'anonymisent pas
-- notations_missions. Quand un compte est supprimé (supprime_le set), les notations
-- dont il est notateur restent visibles avec notateur_id non anonymisé → faille RGPD.
--
-- Solution : trigger AFTER UPDATE sur soignants/etablissements qui détecte le passage
-- supprime_le NULL → NOT NULL et anonymise les notations.

CREATE OR REPLACE FUNCTION public.fn_trg_anonymiser_notations_suppression()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  -- Anonymise quand supprime_le passe de NULL à NOT NULL
  IF OLD.supprime_le IS NULL AND NEW.supprime_le IS NOT NULL THEN
    UPDATE notations_missions SET
      notateur_id = NULL,
      notateur_anonymise = true
    WHERE notateur_id = NEW.id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_anonymiser_notations_soignant_supprime ON public.soignants;
CREATE TRIGGER trg_anonymiser_notations_soignant_supprime
  AFTER UPDATE OF supprime_le ON public.soignants
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_trg_anonymiser_notations_suppression();

DROP TRIGGER IF EXISTS trg_anonymiser_notations_etab_supprime ON public.etablissements;
CREATE TRIGGER trg_anonymiser_notations_etab_supprime
  AFTER UPDATE OF supprime_le ON public.etablissements
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_trg_anonymiser_notations_suppression();

-- Backfill : anonymiser les notations existantes des comptes déjà supprimés
UPDATE notations_missions n
SET notateur_id = NULL, notateur_anonymise = true
WHERE notateur_id IN (
  SELECT id FROM soignants WHERE supprime_le IS NOT NULL
  UNION
  SELECT id FROM etablissements WHERE supprime_le IS NOT NULL
)
AND COALESCE(notateur_anonymise, false) = false;

NOTIFY pgrst, 'reload schema';
