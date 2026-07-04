-- ============================================================
-- Bug 5 — BUG-UI-EVAL-1 : bandeau évaluation s'affiche après
-- évaluation déjà faite (côté étab)
-- ============================================================
-- Cause racine : `fn_evaluer_soignant` stocke `evaluateur_id =
-- mon_etablissement_id()` (l'id de l'étab, pas l'auth.uid() de
-- l'admin). Or `pol_eval_select` autorise uniquement
-- `evaluateur_id = auth.uid()` en SELECT. Conséquence :
--
--   - Single-etab (auth.uid() == etablissement.id) : OK
--   - Groupe_sante admin (auth.uid() != etablissement.id) :
--     l'évaluation existante est invisible → le frontend croit
--     qu'elle n'a pas été faite et rouvre le modal.
--
-- Fix : étendre `pol_eval_select` pour autoriser
-- `evaluateur_id = mon_etablissement_id()` afin que tout admin
-- d'un étab voie les évaluations émises par son étab.
-- ============================================================

DROP POLICY IF EXISTS pol_eval_select ON public.evaluations;

CREATE POLICY pol_eval_select
    ON public.evaluations
    FOR SELECT
    USING (
        (SELECT est_admin())
        OR evaluateur_id = (SELECT auth.uid())
        OR evaluateur_id = (SELECT mon_etablissement_id())
        OR (evalue_id = (SELECT auth.uid()) AND visible = TRUE)
    );
