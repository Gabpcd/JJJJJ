-- ============================================================
-- CP-LITIGES-7a FIX 11 — presences.litige_auto_cree_le (structure)
-- ============================================================
-- Ajoute une colonne timestamp sur public.presences qui mémorise l'instant
-- auquel fn_auto_creation_litiges_presence a déjà généré un litige
-- automatique pour cette présence (ABSENCE_SOIGNANT / DEPART_ANTICIPE /
-- RETARD_IMPORTANT).
--
-- Objectif : rendre la fonction d'auto-création IDEMPOTENTE — si
-- litige_auto_cree_le IS NOT NULL, on ne recrée pas de litige à chaque
-- UPDATE de la présence (anti-boucle).
--
-- Ce FIX livre uniquement la STRUCTURE. La consommation côté RPC
-- (fn_auto_creation_litiges_presence : check litige_auto_cree_le IS NULL
-- avant INSERT + UPDATE de la colonne après création réussie) est livrée
-- dans un FIX suivant.
-- ============================================================

BEGIN;

ALTER TABLE public.presences
  ADD COLUMN IF NOT EXISTS litige_auto_cree_le TIMESTAMPTZ;

COMMENT ON COLUMN public.presences.litige_auto_cree_le IS
  'CP-LITIGES-7a FIX 11 — timestamp de création du litige automatique '
  'associé à cette présence (ABSENCE / DEPART_ANTICIPE / RETARD_IMPORTANT). '
  'NULL = pas encore traité. Utilisé par fn_auto_creation_litiges_presence '
  'comme verrou d''idempotence (anti-boucle sur UPDATE).';

COMMIT;
