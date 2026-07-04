-- PR 1 Sprint 1 v3 — Refactor CDDU → CDD (5e essai, validé par TEST en
-- transaction MCP rollback)
--
-- Contexte : CDDU réservé aux secteurs autorisés (art. D1242-1). En santé,
-- INVALIDE pour IDE/AS/AES en EHPAD/clinique privée (Conseil d'État
-- 11/02/2025 arrêt Mediflash). Terme correct : CDD.
--
-- HISTORIQUE (4 deploy échoués avant) :
-- - v0 (YYYYMMDD format) : rejet CLI
-- - v1 (action custom) : rollback CHECK journaux_audit_action_check
-- - v2 (cast enum sur text) : ERROR 42883 operator does not exist
-- - v2b (CHECK cotisations) : ERROR 23514 check constraint
-- - v2c (jsonb cast sur text) : ERROR 22P02 invalid JSON
-- - v3 (this) : test rollback MCP réussi, enum CDD + tous formats text
--   migrés correctement
--
-- Schéma vérifié live :
--   ENUM type_contrat : soignants, rist_plafonds
--   TEXT type_contrat : contrats_mission, cotisations_sociales,
--                       templates_contrat
--   types_contrat_acceptes : text (formats variés : CSV ou JSON array)
--   CHECK cotisations_sociales_type_contrat_check : accepte SEULEMENT
--     ('CDDU', 'REMPLACEMENT_LIBERAL') → à étendre
--   CHECK contrats_mission_type_contrat_check : accepte déjà 'CDD'

-- 1. ALTER TYPE RENAME : renomme la valeur enum CDDU → CDD.
ALTER TYPE public.type_contrat RENAME VALUE 'CDDU' TO 'CDD';

-- 2. Update colonnes TEXT.
-- 2.1 contrats_mission (CHECK contient déjà 'CDD', OK)
UPDATE public.contrats_mission
SET type_contrat = 'CDD'
WHERE type_contrat IN ('CDDU', 'CDDU_USAGE');

-- 2.2 cotisations_sociales : étendre la CHECK avant l'UPDATE.
ALTER TABLE public.cotisations_sociales
  DROP CONSTRAINT cotisations_sociales_type_contrat_check;

UPDATE public.cotisations_sociales
SET type_contrat = 'CDD'
WHERE type_contrat IN ('CDDU', 'CDDU_USAGE');

ALTER TABLE public.cotisations_sociales
  ADD CONSTRAINT cotisations_sociales_type_contrat_check
  CHECK (type_contrat = ANY (ARRAY['CDD'::text, 'CDDU'::text, 'REMPLACEMENT_LIBERAL'::text]));

-- 2.3 templates_contrat (pas de CHECK constraint)
UPDATE public.templates_contrat
SET type_contrat = 'CDD',
    nom = REPLACE(REPLACE(nom, 'CDDU', 'CDD'), 'd''Usage (CDD)', '(CDD)'),
    contenu_html = REPLACE(REPLACE(contenu_html, 'CDDU', 'CDD'), 'CONTRAT DE TRAVAIL À DURÉE DÉTERMINÉE D''USAGE', 'CONTRAT DE TRAVAIL À DURÉE DÉTERMINÉE')
WHERE type_contrat IN ('CDDU', 'CDDU_USAGE');

-- 3. Update soignants.types_contrat_acceptes (colonne TEXT, pas jsonb,
-- formats variés CSV ou JSON-array string).
-- Ordre des REPLACE : CDDU_USAGE avant CDDU pour éviter écrasement
-- partiel.
UPDATE public.soignants
SET types_contrat_acceptes =
  REPLACE(
    REPLACE(
      REPLACE(
        REPLACE(types_contrat_acceptes, '"CDDU_USAGE"', '"CDD"'),
        'CDDU_USAGE', 'CDD'),
      '"CDDU"', '"CDD"'),
    'CDDU', 'CDD')
WHERE types_contrat_acceptes LIKE '%CDDU%';

-- 4. Audit trail avec action='SYSTEM' (valeur autorisée)
INSERT INTO public.journaux_audit (
  acteur_id, type_acteur, action, type_ressource, id_ressource, details
) VALUES (
  '00000000-0000-0000-0000-000000000000', 'SYSTEME',
  'SYSTEM', 'enum_type_contrat', NULL,
  jsonb_build_object(
    'evenement', 'REFACTOR_TERMINOLOGIE_CDDU_CDD',
    'pr', 'PR 1 Sprint 1 v3 (validé MCP rollback)',
    'date_iso', NOW()::text,
    'motif', 'Conformité art. D1242-1 Code travail',
    'reference', 'Conseil d''Etat 11/02/2025 (arrêt Mediflash)',
    'enum_value_renamed', 'CDDU → CDD',
    'tables_text_migrees', ARRAY['contrats_mission','cotisations_sociales','templates_contrat'],
    'check_constraint_etendue', 'cotisations_sociales_type_contrat_check',
    'historique_tentatives', '4 échecs avant (format / CHECK action / cast enum sur text / CHECK cotisations / jsonb cast sur text)'
  )
);
