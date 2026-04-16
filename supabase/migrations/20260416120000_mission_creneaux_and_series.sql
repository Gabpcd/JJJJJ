-- ============================================================
-- Sub-PR 1 / Checkpoint 1
-- CREATE TABLE mission_creneaux + mission_series
-- RLS, GRANTs, constraints, indexes
-- ============================================================

-- ──────────────────────────────────────────────────────────────
-- 1. Table mission_series (metadata for recurring mission groups)
-- ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.mission_series (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  etablissement_id    uuid NOT NULL REFERENCES public.etablissements(id),
  cree_par            uuid DEFAULT auth.uid(),  -- nullable: service_role inserts have no auth.uid()
  motif               text,
  nb_missions_prevues integer NOT NULL DEFAULT 1,
  cree_le             timestamptz NOT NULL DEFAULT now(),
  modifie_le          timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.mission_series IS
  'Groupe de missions récurrentes (série). Chaque mission de la série référence mission_series.id via missions.serie_id.';

-- Index
CREATE INDEX IF NOT EXISTS idx_ms_etablissement ON public.mission_series(etablissement_id);

-- RLS
ALTER TABLE public.mission_series ENABLE ROW LEVEL SECURITY;

CREATE POLICY ms_select ON public.mission_series FOR SELECT USING (
  est_admin()
  OR etablissement_id = mon_etablissement_id()
);

CREATE POLICY ms_insert ON public.mission_series FOR INSERT WITH CHECK (
  est_admin()
  OR etablissement_id = mon_etablissement_id()
);

-- UPDATE/DELETE : admin only
CREATE POLICY ms_update ON public.mission_series FOR UPDATE USING (est_admin());
CREATE POLICY ms_delete ON public.mission_series FOR DELETE USING (est_admin());

-- GRANTs (match missions table pattern)
GRANT SELECT, INSERT ON public.mission_series TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.mission_series TO service_role;

-- ──────────────────────────────────────────────────────────────
-- 2. FK missions.serie_id → mission_series.id
-- ──────────────────────────────────────────────────────────────
-- serie_id column already exists (uuid, nullable) but has no FK constraint.
-- Add the FK now. All existing values are NULL so no conflict.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'missions_serie_id_fkey'
      AND table_name = 'missions'
  ) THEN
    ALTER TABLE public.missions
      ADD CONSTRAINT missions_serie_id_fkey
      FOREIGN KEY (serie_id) REFERENCES public.mission_series(id)
      ON DELETE SET NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_missions_serie
  ON public.missions(serie_id) WHERE serie_id IS NOT NULL;

-- ──────────────────────────────────────────────────────────────
-- 3. Table mission_creneaux (time slots per mission)
-- ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.mission_creneaux (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  mission_id  uuid NOT NULL REFERENCES public.missions(id) ON DELETE CASCADE,
  debut       timestamptz NOT NULL,
  fin         timestamptz NOT NULL,
  est_pause   boolean NOT NULL DEFAULT false,
  type_pause  text,                         -- ex: 'repas_non_paye', 'pause_nuit_payee', 'transmission'
  ordre       smallint NOT NULL DEFAULT 1,
  cree_le     timestamptz NOT NULL DEFAULT now(),
  modifie_le  timestamptz NOT NULL DEFAULT now(),

  -- Fin must be after debut
  CONSTRAINT ck_creneau_coherent CHECK (fin > debut),
  -- Single créneau cannot exceed 24h
  CONSTRAINT ck_creneau_max_24h CHECK (EXTRACT(EPOCH FROM (fin - debut)) <= 86400),
  -- type_pause only meaningful when est_pause = true
  CONSTRAINT ck_type_pause_coherent CHECK (
    (est_pause = false AND type_pause IS NULL)
    OR est_pause = true
  ),
  -- Unique order per mission
  CONSTRAINT uq_mission_creneau_ordre UNIQUE (mission_id, ordre)
);

COMMENT ON TABLE public.mission_creneaux IS
  'Créneaux horaires par mission. Une mission a 1..6 créneaux. Les pauses entre créneaux sont implicites. est_pause=true pour les pauses comptées (garde nuit).';

-- Indexes
CREATE INDEX IF NOT EXISTS idx_mc_mission ON public.mission_creneaux(mission_id);

-- ──────────────────────────────────────────────────────────────
-- 4. Max 6 créneaux: denormalized column + CHECK on missions
-- ──────────────────────────────────────────────────────────────
-- Using a denormalized column instead of a trigger to avoid race conditions.
-- nb_creneaux is maintained by the sync trigger (see CP2 migration).
-- TODO CP2 : missions.nb_creneaux doit être maintenu par fn_sync_mission_creneaux()
--   AFTER INSERT/UPDATE/DELETE sur mission_creneaux.
--   Sans cette maintenance, le CHECK constraint nb_creneaux BETWEEN 0 AND 6 ne protège rien.
--   Test attendu : INSERT créneau → nb_creneaux++, DELETE créneau → nb_creneaux--.
ALTER TABLE public.missions
  ADD COLUMN IF NOT EXISTS nb_creneaux smallint NOT NULL DEFAULT 0
  CONSTRAINT ck_max_6_creneaux CHECK (nb_creneaux >= 0 AND nb_creneaux <= 6);

-- ──────────────────────────────────────────────────────────────
-- 5. Trigger: no overlapping créneaux within same mission
-- ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_no_overlap_creneaux()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM mission_creneaux
    WHERE mission_id = NEW.mission_id
      AND id != COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid)
      AND NEW.debut < fin
      AND NEW.fin > debut
  ) THEN
    RAISE EXCEPTION 'Chevauchement de créneaux dans la même mission'
      USING ERRCODE = 'exclusion_violation';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_no_overlap_creneaux
  BEFORE INSERT OR UPDATE ON public.mission_creneaux
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_no_overlap_creneaux();

-- ──────────────────────────────────────────────────────────────
-- 6. RLS on mission_creneaux
-- ──────────────────────────────────────────────────────────────
ALTER TABLE public.mission_creneaux ENABLE ROW LEVEL SECURITY;

-- SELECT: same visibility as the parent mission
CREATE POLICY mc_select ON public.mission_creneaux FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM missions m
    WHERE m.id = mission_id
      AND (
        est_admin()
        OR m.etablissement_id = mon_etablissement_id()
        OR m.soignant_assigne_id = auth.uid()
        OR (est_soignant() AND m.statut = 'OUVERTE'::statut_mission)
      )
  )
);

-- INSERT: establishment that owns the mission, or admin
CREATE POLICY mc_insert ON public.mission_creneaux FOR INSERT WITH CHECK (
  EXISTS (
    SELECT 1 FROM missions m
    WHERE m.id = mission_id
      AND (est_admin() OR m.etablissement_id = mon_etablissement_id())
  )
);

-- UPDATE: establishment owner or admin
CREATE POLICY mc_update ON public.mission_creneaux FOR UPDATE USING (
  EXISTS (
    SELECT 1 FROM missions m
    WHERE m.id = mission_id
      AND (est_admin() OR m.etablissement_id = mon_etablissement_id())
  )
);

-- DELETE: admin only (client shouldn't delete créneaux directly)
CREATE POLICY mc_delete ON public.mission_creneaux FOR DELETE USING (
  est_admin()
);

-- ──────────────────────────────────────────────────────────────
-- 7. GRANTs on mission_creneaux (match missions table)
-- ──────────────────────────────────────────────────────────────
GRANT SELECT, INSERT, UPDATE, DELETE ON public.mission_creneaux TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.mission_creneaux TO service_role;

-- ──────────────────────────────────────────────────────────────
-- 8. COMMENT on shifts table (DEPRECATED marker)
-- ──────────────────────────────────────────────────────────────
COMMENT ON TABLE public.shifts IS
  'DEPRECATED 2026-04-16 — Module planning futur, non utilisé actuellement. Voir /docs/modules-futurs.md';
COMMENT ON TABLE public.shift_affectations IS
  'DEPRECATED 2026-04-16 — Lié à shifts, non utilisé. Voir /docs/modules-futurs.md';
