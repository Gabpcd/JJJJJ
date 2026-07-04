-- ============================================================
-- CP-C-4 A — Ajout valeur EXPIREE à enum statut_mission
-- ============================================================
-- NOTE : ALTER TYPE ADD VALUE doit être seul dans sa transaction
-- avant d'être utilisé (enum value commit avant usage).
-- fn_auto_transitions_missions refondue dans migration suivante.
-- ============================================================

ALTER TYPE public.statut_mission ADD VALUE IF NOT EXISTS 'EXPIREE';
