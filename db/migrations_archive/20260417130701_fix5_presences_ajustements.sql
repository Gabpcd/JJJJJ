-- ============================================================
-- CP-LITIGES-7a FIX 5 — Traçabilité ajustements presences (structure)
-- ============================================================
-- Ajoute deux colonnes sur public.presences pour tracer les ajustements
-- d'heures décidés par admin lors de la résolution d'un litige via
-- fn_admin_resoudre_litige (action RECALCUL / ANNULER_REEMETTRE / AVOIR).
--
--   - heures_ajustees_litige : override admin (nullable, pas de CHECK > 0
--     pour laisser la liberté de corriger vers 0h en cas d'absence).
--   - ajustement_litige_id   : FK vers litiges(id) pour audit inverse.
--
-- Ce FIX livre uniquement la STRUCTURE. La consommation côté RPC
-- (fn_calculer_financier_mission, fn_verifier_pre_facturation,
-- fn_admin_resoudre_litige pour alimenter les colonnes) est livrée
-- dans un FIX suivant (CP-LITIGES-7a FIX 5 consommation).
--
-- Cf. /docs/tech-debt.md CP-LITIGES-7a pour le plan de découpage.
-- ============================================================

BEGIN;

ALTER TABLE public.presences
  ADD COLUMN IF NOT EXISTS heures_ajustees_litige NUMERIC(6,2),
  ADD COLUMN IF NOT EXISTS ajustement_litige_id   UUID
    REFERENCES public.litiges(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.presences.heures_ajustees_litige IS
  'CP-LITIGES-7a FIX 5 — override admin des heures pour cette présence '
  'suite à résolution de litige (NULL = pas d''ajustement, heures_reelles '
  'fait foi). Consommé via COALESCE(heures_ajustees_litige, heures_reelles) '
  'dans les calculs financiers (FIX 5 consommation, à venir).';

COMMENT ON COLUMN public.presences.ajustement_litige_id IS
  'CP-LITIGES-7a FIX 5 — litige à l''origine de l''ajustement (audit '
  'inverse presence→litige). ON DELETE SET NULL : la présence survit à '
  'la purge du litige, seule la traçabilité est perdue.';

-- Index partiel sur les présences effectivement ajustées (minorité).
CREATE INDEX IF NOT EXISTS idx_presences_ajustement_litige_id
  ON public.presences (ajustement_litige_id)
  WHERE ajustement_litige_id IS NOT NULL;

COMMIT;
