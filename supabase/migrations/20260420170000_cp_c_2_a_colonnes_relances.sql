-- ============================================================
-- CP-C-2 A — Colonnes relances + backfill anti-spam
-- ============================================================
-- Contexte : implémenter relances J+7 / J+21 pour commission
-- Jolene (table factures) et paiement soignant non déclaré
-- (table missions, Option A).
-- Backfill anti-spam : SET relance_1_le=NOW() sur 185 missions
-- + 4 factures existantes >7j pour éviter envoi massif, et
-- SET relance_2_le=NOW() sur >21j pour éviter J+21 dans 2
-- semaines (précision validée Gabrielle).
-- Tickets résolus : E6 (dead column exploitée), préparation E2/E11.
-- ============================================================

-- A. Factures commission : colonnes relances + blocage
ALTER TABLE public.factures
  ADD COLUMN IF NOT EXISTS relance_1_le TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS relance_2_le TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS bloque_le    TIMESTAMPTZ;

-- Index perf cron : scans répétés sur statut IN ('EMISE','EN_RETARD')
CREATE INDEX IF NOT EXISTS idx_factures_statut_emission
  ON public.factures(statut, date_emission)
  WHERE statut IN ('EMISE', 'EN_RETARD');

-- B. Missions : colonnes relance paiement (Option A validée)
ALTER TABLE public.missions
  ADD COLUMN IF NOT EXISTS relance_paiement_1_le TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS relance_paiement_2_le TIMESTAMPTZ;

-- Index perf cron : scan missions TERMINEE SALARIE
CREATE INDEX IF NOT EXISTS idx_missions_terminee_salarie
  ON public.missions(fin_le, statut, type_contrat_applique)
  WHERE statut = 'TERMINEE';

-- C. Backfill anti-spam (missions)
-- J+7 : marquer relance_1_le sur toutes les missions éligibles
UPDATE public.missions
SET relance_paiement_1_le = NOW()
WHERE statut = 'TERMINEE'
  AND type_contrat_applique = 'SALARIE'
  AND fin_le < NOW() - INTERVAL '7 days'
  AND relance_paiement_1_le IS NULL
  AND NOT EXISTS (
    SELECT 1 FROM public.paiements_soignant ps
    WHERE ps.mission_id = missions.id
    AND ps.statut IN ('DECLARE', 'CONFIRME')
  );

-- J+21 : marquer relance_2_le sur >21j (évite J+21 dans 2 semaines)
UPDATE public.missions
SET relance_paiement_2_le = NOW()
WHERE statut = 'TERMINEE'
  AND type_contrat_applique = 'SALARIE'
  AND fin_le < NOW() - INTERVAL '21 days'
  AND relance_paiement_2_le IS NULL
  AND NOT EXISTS (
    SELECT 1 FROM public.paiements_soignant ps
    WHERE ps.mission_id = missions.id
    AND ps.statut IN ('DECLARE', 'CONFIRME')
  );

-- D. Backfill anti-spam (factures commission)
UPDATE public.factures
SET relance_1_le = NOW()
WHERE statut IN ('EMISE', 'EN_RETARD')
  AND date_emission < NOW() - INTERVAL '7 days'
  AND relance_1_le IS NULL;

UPDATE public.factures
SET relance_2_le = NOW()
WHERE statut IN ('EMISE', 'EN_RETARD')
  AND date_emission < NOW() - INTERVAL '21 days'
  AND relance_2_le IS NULL;

COMMENT ON COLUMN public.factures.relance_1_le IS 'CP-C-2 : J+7 post date_emission, relance email RAPPEL_PAIEMENT_J7';
COMMENT ON COLUMN public.factures.relance_2_le IS 'CP-C-2 : J+21 post date_emission, relance email PAIEMENT_RETARD_J21';
COMMENT ON COLUMN public.factures.bloque_le IS 'CP-C-3 : J+45, blocage auto publication étab';
COMMENT ON COLUMN public.missions.relance_paiement_1_le IS 'CP-C-2 : J+7 post fin_le pour mission SALARIE non payée, relance étab';
COMMENT ON COLUMN public.missions.relance_paiement_2_le IS 'CP-C-2 : J+21 post fin_le, 2ème relance plus pressante';
