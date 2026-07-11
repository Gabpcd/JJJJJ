-- Preuve rejouable — Finding #3 : le double-aveugle filtre publie_le sur TOUTE
-- surface publique (score, liste/stats, RLS). À exécuter tel quel (BEGIN … ROLLBACK,
-- rien persisté) contre la prod ou une branche.
--
-- Diligence (addendum 5) : la table notations_missions n'a qu'un trigger
-- (trg_recalcul_score_v2_notations) SANS effet hors-transaction (pas de pg_net /
-- NOTIFY) — un INSERT en tx annulée est donc sûr, aucun worker externe n'est
-- réveillé. Vérifier cette propriété avant de rejouer sur une autre table.

-- ── Preuve 1 : sémantique du filtre (note non publiée à 1★ ne tire pas la moyenne).
-- Attendu : ancien_count=4, nouveau_count=3, ancienne_moy=4.00, nouvelle_moy=5.00.
BEGIN;
WITH synth(c1,c2,c3,c4,cree_le,masque,publie_le) AS (VALUES
  (5,5,5,5, now(), false, now()),
  (5,5,5,5, now(), false, now()),
  (5,5,5,5, now(), false, now()),
  (1,1,1,1, now(), false, NULL::timestamptz)
)
SELECT
  count(*) FILTER (WHERE masque=false)                           AS ancien_count,
  count(*) FILTER (WHERE masque=false AND publie_le IS NOT NULL) AS nouveau_count,
  round(avg((c1+c2+c3+c4)/4.0) FILTER (WHERE masque=false),2)                           AS ancienne_moy,
  round(avg((c1+c2+c3+c4)/4.0) FILTER (WHERE masque=false AND publie_le IS NOT NULL),2) AS nouvelle_moy
FROM synth;
ROLLBACK;

-- ── Preuve 2 (test-GARDE, addendum 2) : énumère TOUS les lecteurs pg_proc de
-- notations_missions qui agrègent du ETAB_VERS_SOIGNANT vers un score/note public
-- SANS filtre publie_le. Attendu APRÈS DÉPLOIEMENT : 0 ligne. Toute nouvelle
-- surface qui oublie le filtre (ou ne lit pas la vue evaluations_publiees)
-- réapparaît ici et fait échouer la garde.
SELECT p.proname AS surface_publique_sans_filtre
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND pg_get_functiondef(p.oid) LIKE '%ETAB_VERS_SOIGNANT%'
  AND (pg_get_functiondef(p.oid) LIKE '%notations_missions%')
  AND (pg_get_functiondef(p.oid) LIKE '%score_fiabilite%'
       OR pg_get_functiondef(p.oid) LIKE '%note_moyenne%'
       OR pg_get_functiondef(p.oid) LIKE '%note_moyenne_globale%')
  AND pg_get_functiondef(p.oid) NOT LIKE '%publie_le%'
  AND pg_get_functiondef(p.oid) NOT LIKE '%evaluations_publiees%'
  AND p.proname <> 'fn_admin_masquer_notation';  -- action admin de masquage, pas une agrégation d'affichage

-- ── Preuve 3 : garde-fichier — les 2 fonctions corrigées + la policy RLS
-- portent bien le filtre. Attendu après déploiement : tout à true.
SELECT
  (pg_get_functiondef('public.fn_calculer_score_fiabilite_v2'::regproc) LIKE '%publie_le IS NOT NULL%')       AS score_fiabilite_filtre,
  (pg_get_functiondef('public.fn_mes_notations_recues_avec_stats'::regproc) LIKE '%publie_le IS NOT NULL%')   AS mes_notations_filtre,
  (SELECT bool_and(pg_get_expr(polqual, polrelid) LIKE '%publie_le IS NOT NULL%')
     FROM pg_policy WHERE polname='pol_notations_select' AND polrelid='public.notations_missions'::regclass)  AS rls_select_filtre;
