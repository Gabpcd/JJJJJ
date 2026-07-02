-- §7.7 Lot 7a — régime fiscal du libéral (micro-BNC par défaut, « à confirmer »
-- tant que le soignant n'a pas répondu à la question). En micro-BNC il n'y a pas
-- de formulaire 2035 : les échéances fiscales affichent la 2042-C-PRO à la place.
ALTER TABLE public.soignants
  ADD COLUMN IF NOT EXISTS regime_fiscal text NOT NULL DEFAULT 'MICRO_BNC',
  ADD COLUMN IF NOT EXISTS regime_fiscal_confirme boolean NOT NULL DEFAULT false;

DO $do$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'soignants_regime_fiscal_check'
  ) THEN
    ALTER TABLE public.soignants
      ADD CONSTRAINT soignants_regime_fiscal_check
      CHECK (regime_fiscal IN ('MICRO_BNC', 'DECLARATION_CONTROLEE'));
  END IF;
END
$do$;
