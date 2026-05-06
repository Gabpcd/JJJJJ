-- ============================================================
-- CP-LITIGES-6 — Support PDF/Factur-X/Chorus pour les avoirs
-- ============================================================
-- Dépend de : CP-LITIGES-1 à 5.
--
-- Ajouts DDL :
--   - factures_honoraires.chorus_avoir_reference_invoice TEXT
--     Référence au numero_facture d'origine requise par Chorus Pro
--     pour les avoirs (métadonnée d'accompagnement).
--   - fn_lister_factures_a_regenerer() — RPC utilisée par le cron pour
--     récupérer les factures/avoirs avec pdf_a_regenerer=TRUE.
--
-- Déclenchement de la regen :
--   - Option A (non implémentée ici) : appel direct pg_net.http_post
--     depuis fn_admin_resoudre_litige.
--   - Option B (retenue pour CP6) : extension du cron quotidien
--     litige-escalation-cron qui scanne pdf_a_regenerer=TRUE et invoke
--     generate-invoice pour chaque ligne.
--   → Inconvénient : délai jusqu'à 24h entre résolution admin et
--     disponibilité du PDF. Tech-debt ticket T14 ouvert pour passer
--     à Option A en Sub-PR 3.
-- ============================================================

BEGIN;

-- ──────────────────────────────────────────────────────────────
-- 1. Colonne chorus_avoir_reference_invoice
-- ──────────────────────────────────────────────────────────────

ALTER TABLE public.factures_honoraires
  ADD COLUMN IF NOT EXISTS chorus_avoir_reference_invoice TEXT;

COMMENT ON COLUMN public.factures_honoraires.chorus_avoir_reference_invoice IS
  'Pour un AVOIR : numero_facture de la facture d''origine (requis par Chorus Pro en métadonnée). Alimenté par generate-invoice au moment de la regénération.';

-- ──────────────────────────────────────────────────────────────
-- 2. fn_lister_factures_a_regenerer — pour le cron de regen
-- ──────────────────────────────────────────────────────────────
-- Retourne les IDs des factures/avoirs avec pdf_a_regenerer=TRUE,
-- triées par ancienneté (les plus anciennes en tête).

CREATE OR REPLACE FUNCTION public.fn_lister_factures_a_regenerer(
  p_limit INTEGER DEFAULT 50
)
RETURNS TABLE (
  id UUID,
  numero_facture TEXT,
  type_document public.type_document_facture,
  soignant_id UUID,
  cree_le TIMESTAMPTZ
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT f.id, f.numero_facture, f.type_document, f.soignant_id, f.cree_le
    FROM public.factures_honoraires f
   WHERE f.pdf_a_regenerer = TRUE
     AND f.statut IN ('BROUILLON', 'EMISE')
   ORDER BY f.cree_le ASC
   LIMIT p_limit;
$$;

COMMENT ON FUNCTION public.fn_lister_factures_a_regenerer(INTEGER) IS
  'Liste les factures/avoirs en attente de regénération PDF/XML. Consommée par le cron litige-escalation-cron.';

GRANT EXECUTE ON FUNCTION public.fn_lister_factures_a_regenerer(INTEGER) TO service_role;

COMMIT;
