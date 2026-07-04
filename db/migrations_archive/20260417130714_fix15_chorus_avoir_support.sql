-- ============================================================
-- CP-LITIGES-7a FIX 15 — submit-to-chorus support AVOIR
-- ============================================================
-- Pré-requis : CP6 (chorus_avoir_reference_invoice sur factures_honoraires).
--
-- Scope :
--   1. DDL : ajout type_document + avoir_reference_invoice sur chorus_submissions.
--   2. L'edge function submit-to-chorus/index.ts est modifiée séparément
--      (pas de SQL pour la logique edge function).
-- ============================================================

BEGIN;

-- ── 1. Colonne type_document sur chorus_submissions ────────────

ALTER TABLE public.chorus_submissions
  ADD COLUMN IF NOT EXISTS type_document TEXT NOT NULL DEFAULT 'FACTURE';

ALTER TABLE public.chorus_submissions
  DROP CONSTRAINT IF EXISTS chorus_submissions_type_document_check;
ALTER TABLE public.chorus_submissions
  ADD CONSTRAINT chorus_submissions_type_document_check
  CHECK (type_document IN ('FACTURE', 'AVOIR'));

COMMENT ON COLUMN public.chorus_submissions.type_document IS
  'FACTURE ou AVOIR — distingue le type de dépôt Chorus Pro (BT-3=380 ou 381).';

-- ── 2. Colonne avoir_reference_invoice ─────────────────────────

ALTER TABLE public.chorus_submissions
  ADD COLUMN IF NOT EXISTS avoir_reference_invoice TEXT;

COMMENT ON COLUMN public.chorus_submissions.avoir_reference_invoice IS
  'Pour AVOIR : numero_facture d''origine déposée sur Chorus (requis par PISTE). Copie de factures_honoraires.chorus_avoir_reference_invoice.';

-- ── 3. Index partiel pour les soumissions AVOIR ────────────────

CREATE INDEX IF NOT EXISTS idx_chorus_sub_avoir
  ON public.chorus_submissions(type_document)
  WHERE type_document = 'AVOIR';

COMMIT;
