-- ============================================================
-- CP-LITIGES-7a FIX 4 — Cohérence clé rate_limit_litiges_par_heure
-- ============================================================
-- Audit préalable (résultat) :
--
-- Occurrences de 'rate_limit_litiges_par_24h' :
--   - docs/tech-debt.md:270,273              — doc historique (OK)
--   - 20260417130000_cp_litiges_1_ddl.sql:168 — seed initial (renommé par
--     CP2-fixes via UPDATE)
--   - 20260417130100_cp_litiges_2_triggers_rpcs.sql:465 — lecture dans la
--     v1 de fn_ouvrir_litige_rate_limited (3-arg), ENTIÈREMENT remplacée
--     par CREATE OR REPLACE dans CP2-fixes → donc vestige historique du
--     fichier, pas de bug runtime.
--   - 20260417130200_cp_litiges_2_fixes.sql:7,8,25,28 — commentaires +
--     UPDATE de renommage (OK).
--
-- Occurrences de 'rate_limit_litiges_par_heure' :
--   - 20260417130200_cp_litiges_2_fixes.sql:25,99 — seed renommé + lecture
--     dans la v2 corrigée de fn_ouvrir_litige_rate_limited (OK).
--
-- Conclusion : à runtime après CP2-fixes, le seed et la fonction 3-arg
-- utilisent tous deux 'rate_limit_litiges_par_heure'. Ce FIX livre :
--   A) Un INSERT idempotent pour garantir la présence du seed sous la
--      nouvelle clé (filet de sécurité en cas d'environnement où CP2-fixes
--      n'aurait pas trouvé de ligne à UPDATE-renommer).
--   B) Une suppression défensive de toute ligne résiduelle sous l'ancienne
--      clé 'rate_limit_litiges_par_24h' (si elle réapparaît via rollback
--      partiel, seed manuel, etc.).
--
-- Ce FIX ne modifie aucune fonction. Les tests associés vérifient qu'aucun
-- pg_proc.prosrc ne lit l'ancienne clé.
-- ============================================================

BEGIN;

-- [A] INSERT idempotent : garantit la présence de la nouvelle clé.
INSERT INTO public.parametres_litiges (cle, valeur, description)
VALUES (
  'rate_limit_litiges_par_heure',
  '3',
  'Rate limit : 3 litiges par heure par entité (aligné sur le code de fn_ouvrir_litige_rate_limited). [CP-LITIGES-7a FIX 4 — idempotence seed]'
)
ON CONFLICT (cle) DO NOTHING;

-- [B] Nettoyage défensif : supprime toute ligne résiduelle sous l'ancienne
-- clé. Safe car CP2-fixes a déjà fait le UPDATE de renommage — si une ligne
-- sous l'ancienne clé existe encore, c'est un doublon à purger.
DELETE FROM public.parametres_litiges
 WHERE cle = 'rate_limit_litiges_par_24h';

COMMIT;
