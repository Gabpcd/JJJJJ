-- PR 1 Sprint 1 v2 — Refactor CDDU → CDD (hotfix audit action constraint)
--
-- Contexte : le terme CDDU (CDD d'usage, art. L1242-2 3°) est juridiquement
-- réservé aux secteurs autorisés (D1242-1 Code travail). Pour IDE/AS/AES/
-- etc. en EHPAD privé ou clinique privée, le CDDU est INVALIDE et
-- requalifiable en CDI (cf Conseil d'État 11/02/2025, arrêt Mediflash).
--
-- HISTORIQUE :
-- - 20260512_pr1_cddu_to_cdd.sql : rejeté par Supabase CLI (format YYYYMMDD)
-- - 20260512120000_pr1_cddu_to_cdd.sql : rolled back par CHECK constraint
--   journaux_audit_action_check (action 'REFACTOR_TERMINOLOGIE_CDDU_CDD'
--   pas dans la liste autorisée)
-- - Cette version v2 : action='SYSTEM' (existante dans la CHECK) et
--   contexte préservé dans details jsonb.

-- 1. Consolider CDDU_USAGE → CDDU avant le rename (0 row attendu)
UPDATE public.soignants
SET type_contrat = 'CDDU'::public.type_contrat
WHERE type_contrat = 'CDDU_USAGE'::public.type_contrat;

UPDATE public.contrats_mission
SET type_contrat = 'CDDU'::public.type_contrat
WHERE type_contrat = 'CDDU_USAGE'::public.type_contrat;

-- 2. Renommer la valeur enum CDDU → CDD (Postgres 14+)
ALTER TYPE public.type_contrat RENAME VALUE 'CDDU' TO 'CDD';

-- 3. Update jsonb arrays sur soignants.types_contrat_acceptes
UPDATE public.soignants
SET types_contrat_acceptes =
  REPLACE(REPLACE(types_contrat_acceptes::text, '"CDDU_USAGE"', '"CDD"'), '"CDDU"', '"CDD"')::jsonb
WHERE types_contrat_acceptes::text LIKE '%CDDU%';

-- 4. Update templates_contrat.type_contrat (colonne text, pas enum)
UPDATE public.templates_contrat
SET type_contrat = 'CDD',
    nom = REPLACE(REPLACE(nom, 'CDDU', 'CDD'), 'd''Usage (CDD)', '(CDD)'),
    contenu_html = REPLACE(REPLACE(contenu_html, 'CDDU', 'CDD'), 'CONTRAT DE TRAVAIL À DURÉE DÉTERMINÉE D''USAGE', 'CONTRAT DE TRAVAIL À DURÉE DÉTERMINÉE')
WHERE type_contrat IN ('CDDU', 'CDDU_USAGE');

-- 5. Audit trail avec action='SYSTEM' (valeur autorisée dans
-- journaux_audit_action_check). Le contexte custom est préservé dans
-- details jsonb pour traçabilité interne / conformité.
INSERT INTO public.journaux_audit (
  acteur_id, type_acteur, action, type_ressource, id_ressource, details
) VALUES (
  '00000000-0000-0000-0000-000000000000', 'SYSTEME',
  'SYSTEM', 'enum_type_contrat', NULL,
  jsonb_build_object(
    'evenement', 'REFACTOR_TERMINOLOGIE_CDDU_CDD',
    'pr', 'PR 1 Sprint 1 révisé (v2 hotfix audit action)',
    'date_iso', NOW()::text,
    'motif', 'Conformité art. D1242-1 Code travail — CDDU réservé aux secteurs autorisés',
    'reference', 'Conseil d''Etat 11/02/2025 (arrêt Mediflash)',
    'enum_value_renamed', 'CDDU → CDD',
    'cddu_usage_legacy_kept_dormant', true,
    'historique_tentatives', 'v0 (YYYYMMDD format) + v1 (action custom rejected) + v2 (this)'
  )
);

-- Note : la valeur enum 'CDDU_USAGE' reste dans le type pour éviter une
-- migration destructive. Aucune ligne ne devrait l'utiliser après ce script.
