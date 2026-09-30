-- Retiré : aucune mutation par préfixe ni compte fixe.
-- Voir docs/tests-charge.md ; F reste suspendu.
DO $retired_load_seed$
BEGIN
  RAISE EXCEPTION 'Banc historique F retiré : utiliser uniquement un lot isolé revu.';
END $retired_load_seed$;
