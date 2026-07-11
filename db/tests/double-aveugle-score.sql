-- Preuve rejouable — Finding #3 : le double-aveugle filtre publie_le sur TOUTE
-- agrégation publique de notes. À exécuter tel quel (BEGIN … ROLLBACK, rien
-- persisté) contre la prod ou une branche. Attendu :
--   ancien_count=4, nouveau_count=3, ancienne_moy=4.00, nouvelle_moy=5.00
-- (3 notes publiées à 5★ + 1 NON publiée à 1★ : l'ancienne agrégation compte la
--  note non publiée et tire la moyenne à 4.00 ; la corrigée reste à 5.00.)
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

-- Garde : les 2 surfaces corrigées DOIVENT contenir le filtre publie_le.
SELECT
  (pg_get_functiondef('public.fn_calculer_score_fiabilite_v2'::regproc) LIKE '%publie_le IS NOT NULL%') AS score_fiabilite_filtre,
  (pg_get_functiondef('public.fn_mes_notations_recues_avec_stats'::regproc) LIKE '%publie_le IS NOT NULL%') AS mes_notations_filtre;
ROLLBACK;
