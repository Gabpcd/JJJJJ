-- CLEANUP (smoke test soignant Session A) — fn_mon_score() est du code mort :
-- aucune référence frontend, aucune edge function, aucun appelant DB interne. Et il
-- contient un bug latent (référence la table inexistante "notations", la vraie table
-- étant "notations_missions"). La page Score soignant utilise fn_mes_evenements_score
-- + fn_mon_breakdown_actuel, pas cette fonction. On la supprime.
DROP FUNCTION IF EXISTS public.fn_mon_score();
