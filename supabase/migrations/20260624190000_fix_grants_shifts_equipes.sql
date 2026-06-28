-- Fix : "permission denied for table shifts / equipes / shift_affectations".
--
-- Même bug que les swipes (PR #674) : les 3 tables ont la RLS activée + une policy
-- ALL correcte pour `authenticated` (etablissement_id = mon_etablissement_id() OR est_admin()),
-- MAIS aucun GRANT au niveau table. En Postgres il faut LES DEUX (GRANT + policy) :
-- le GRANT manquant fait échouer la requête AVANT l'évaluation RLS.
--
-- Impact : la page établissement GestionShifts.tsx (gestion des équipes et des shifts /
-- planning) lit/écrit directement ces tables → 100% cassée (permission denied) pour tout
-- établissement. Découvert pendant l'audit sécurité RLS/GRANT exhaustif.
--
-- Les policies row-level restent la seule barrière d'accès (chaque établissement ne
-- voit/modifie que ses propres équipes/shifts/affectations).

GRANT SELECT, INSERT, UPDATE, DELETE ON public.shifts TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.equipes TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.shift_affectations TO authenticated;

-- Idem pour equivalences_scolarite : policy ALL `est_admin()` mais aucun GRANT →
-- le composant admin EditeurEquivalencesScolarite.tsx (insert/delete/list) était cassé.
GRANT SELECT, INSERT, UPDATE, DELETE ON public.equivalences_scolarite TO authenticated;
