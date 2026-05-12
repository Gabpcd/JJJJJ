-- PR 1 — Refactor CDDU → CDD
--
-- Contexte : le terme CDDU (CDD d'usage, art. L1242-2 3°) est juridiquement
-- réservé aux secteurs autorisés (D1242-1 Code travail). En santé, seule la
-- médecine en centre de santé en zone sous-dotée est éligible. Pour IDE/AS/
-- AES/etc. en EHPAD privé ou clinique privée, le CDDU est INVALIDE et
-- requalifiable en CDI au premier contrôle URSSAF (cf Conseil d'État
-- 11/02/2025, arrêt Mediflash).
--
-- Le terme correct est CDD (CDD de remplacement L1242-2 1° ou CDD
-- accroissement temporaire L1242-2 2°).
--
-- Stratégie de migration :
-- 1. ALTER TYPE type_contrat RENAME VALUE 'CDDU' TO 'CDD' (Postgres 12+)
-- 2. CDDU_USAGE legacy reste dans l'enum mais 0 row l'utilise (vérifié pré-merge).
--    Pas de DROP VALUE possible en Postgres sans recréer l'enum entièrement.
--    On UPDATE les éventuelles lignes CDDU_USAGE → CDD avant le rename.
-- 3. Update jsonb arrays types_contrat_acceptes pour remplacer "CDDU" → "CDD"
-- 4. Update templates_contrat.type_contrat (text column, pas enum) : 'CDDU' → 'CDD'
-- 5. Update les contraintes / triggers qui référenceraient 'CDDU' en string

BEGIN;

-- 1. Consolider CDDU_USAGE → CDDU avant le rename (0 row attendu)
UPDATE public.soignants SET type_contrat = 'CDDU'::public.type_contrat
WHERE type_contrat = 'CDDU_USAGE'::public.type_contrat;

UPDATE public.contrats_mission SET type_contrat = 'CDDU'::public.type_contrat
WHERE type_contrat = 'CDDU_USAGE'::public.type_contrat;

COMMIT;

-- 2. Renommer la valeur enum CDDU → CDD (must run outside a transaction
-- block in some Postgres versions, but PG 17 supports it in tx).
ALTER TYPE public.type_contrat RENAME VALUE 'CDDU' TO 'CDD';

BEGIN;

-- 3. Update jsonb arrays sur soignants.types_contrat_acceptes
-- Le champ est stocké soit comme jsonb array ("[\"CDDU\",\"LIBERAL\"]") soit
-- comme texte simple ("CDDU,LIBERAL"). On gère les deux.
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

-- 5. Audit trail
INSERT INTO public.journaux_audit (
  acteur_id, type_acteur, action, type_ressource, id_ressource, details
) VALUES (
  '00000000-0000-0000-0000-000000000000', 'SYSTEME',
  'REFACTOR_TERMINOLOGIE_CDDU_CDD', 'enum_type_contrat', NULL,
  jsonb_build_object(
    'pr', 'PR 1 Sprint 1 révisé',
    'date_iso', NOW()::text,
    'motif', 'Conformité art. D1242-1 Code travail — CDDU réservé aux secteurs autorisés',
    'reference', 'Conseil d''Etat 11/02/2025 (arrêt Mediflash)',
    'enum_value_renamed', 'CDDU → CDD',
    'cddu_usage_legacy_kept_dormant', true
  )
);

COMMIT;

-- Note : la valeur enum 'CDDU_USAGE' reste dans le type pour éviter une
-- migration destructive. Aucune ligne ne devrait l'utiliser après ce script.
-- Une migration de nettoyage Sprint 2 pourra recréer l'enum proprement
-- (DROP + CREATE) après une période de quarantaine.
