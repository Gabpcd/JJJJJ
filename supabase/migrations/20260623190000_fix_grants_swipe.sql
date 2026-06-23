-- Fix : "permission denied for table super_swipes_quota" / "swipes" (logs prod).
--
-- Cause : les deux tables ont la RLS activée + des policies correctes (SELECT/INSERT
-- sur ses propres lignes), MAIS le rôle `authenticated` n'avait AUCUN GRANT au niveau
-- table. En Postgres il faut LES DEUX (GRANT + policy) : le GRANT manquant fait échouer
-- la requête AVANT l'évaluation RLS → "permission denied for table".
--
-- Impact : le frontend swipe (VueSwipeMissions, SwipeMissions) lit super_swipes_quota
-- en direct pour afficher le quota de super-likes → cassé. Les policies row-level
-- restent la seule barrière d'accès (chaque user ne voit/écrit que ses lignes).

GRANT SELECT ON public.super_swipes_quota TO authenticated;
GRANT SELECT, INSERT ON public.swipes TO authenticated;
