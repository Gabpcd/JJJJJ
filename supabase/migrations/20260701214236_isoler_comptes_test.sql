-- Lot 6a.2 — Isolation des comptes/données de test (store-readiness).
-- Incident déclencheur : une mission "[pw-test:match]" OUVERTE (résidu d'un run
-- e2e dont le cleanup a échoué) était visible dans le deck de swipe prod, et le
-- classement public affichait le compte "Playwright" comme seule entrée.
-- Principe : flag est_compte_test + les surfaces publiques/découverte excluent
-- ces comptes, + un cron balaye les résidus de seeds e2e.

-- 1) Flag comptes de test -----------------------------------------------------

ALTER TABLE public.soignants
  ADD COLUMN IF NOT EXISTS est_compte_test boolean NOT NULL DEFAULT false;
ALTER TABLE public.etablissements
  ADD COLUMN IF NOT EXISTS est_compte_test boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.soignants.est_compte_test IS
  'Compte e2e Playwright ou compte d''audit interne — exclu des surfaces publiques et de la découverte.';
COMMENT ON COLUMN public.etablissements.est_compte_test IS
  'Établissement e2e Playwright ou d''audit interne — ses missions sont invisibles pour les vrais soignants.';

-- Backfill : comptes e2e (playwright-*@jolene.app) + comptes d'audit (@jolene-test.dev).
-- Les comptes de démo (@jolene-demo.dev) restent visibles : ils SONT le contenu de démo.
UPDATE public.soignants SET est_compte_test = true
WHERE email LIKE 'playwright-%@jolene.app' OR email LIKE '%@jolene-test.dev';

UPDATE public.etablissements SET est_compte_test = true
WHERE email_contact LIKE 'playwright-%@jolene.app' OR email_contact LIKE '%@jolene-test.dev';

-- 2) Classement public : exclure les comptes de test --------------------------

CREATE OR REPLACE FUNCTION public.fn_top_soignants(p_profession text DEFAULT NULL::text, p_limit integer DEFAULT 20)
 RETURNS TABLE(id uuid, prenom text, nom text, profession text, note_moyenne numeric, nb_evaluations integer, score_fiabilite integer, total_missions_terminees integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    RETURN QUERY
    SELECT s.id, s.prenom, s.nom, s.profession::TEXT, s.note_moyenne, s.nb_evaluations,
           ROUND(COALESCE(s.score_fiabilite, 0))::integer AS score_fiabilite,
           s.total_missions_terminees
    FROM soignants s
    WHERE s.supprime_le IS NULL
    AND s.est_compte_test = false
    AND fn_documents_ok_pour_mission(s.id, 'TOUS')
    AND (p_profession IS NULL OR s.profession::TEXT = p_profession)
    ORDER BY s.note_moyenne DESC NULLS LAST, s.score_fiabilite DESC, s.total_missions_terminees DESC
    LIMIT p_limit;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_top_soignants(text, integer) TO authenticated, service_role;

-- 3) Découverte missions : masquer les missions des étabs de test -------------
-- Policy RESTRICTIVE : ne restreint QUE les vrais soignants (les comptes de
-- test e2e continuent de voir leurs missions seedées ; étabs et admins
-- inchangés). Helpers SECURITY DEFINER pour ne pas dépendre des RLS de
-- soignants/etablissements dans l'évaluation de la policy.

CREATE OR REPLACE FUNCTION public.fn_est_etab_test(p_etab_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn_eet$
  SELECT EXISTS (SELECT 1 FROM etablissements e WHERE e.id = p_etab_id AND e.est_compte_test);
$fn_eet$;

CREATE OR REPLACE FUNCTION public.fn_suis_soignant_reel()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn_ssr$
  SELECT EXISTS (SELECT 1 FROM soignants s WHERE s.id = auth.uid() AND s.est_compte_test = false);
$fn_ssr$;

GRANT EXECUTE ON FUNCTION public.fn_est_etab_test(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_suis_soignant_reel() TO authenticated, service_role;

DROP POLICY IF EXISTS missions_masquer_etabs_test ON public.missions;
CREATE POLICY missions_masquer_etabs_test ON public.missions
AS RESTRICTIVE FOR SELECT TO authenticated
USING (
  NOT public.fn_est_etab_test(etablissement_id)
  OR NOT public.fn_suis_soignant_reel()
);

-- 4) Cron : balayer les résidus de seeds e2e ----------------------------------
-- Filet de sécurité si le cleanup afterEach d'un run Playwright échoue :
-- toute mission OUVERTE d'un étab de test créée il y a plus de 2 h est purgée
-- (enfants supprimés via le catalogue FK — une mission OUVERTE n'a ni bulletin
-- ni facture, donc pas de conflit avec les protections d'immutabilité).

CREATE OR REPLACE FUNCTION public.fn_cleanup_missions_test()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $fn_cmt$
DECLARE
  v_ids uuid[];
  r record;
BEGIN
  SELECT array_agg(m.id) INTO v_ids
  FROM missions m
  JOIN etablissements e ON e.id = m.etablissement_id
  WHERE e.est_compte_test
    AND m.statut = 'OUVERTE'
    AND m.cree_le < now() - interval '2 hours';

  IF v_ids IS NULL THEN RETURN 0; END IF;

  FOR r IN
    SELECT c.conrelid::regclass::text AS t, a.attname AS col
    FROM pg_constraint c
    JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY(c.conkey)
    WHERE c.confrelid = 'public.missions'::regclass AND c.contype = 'f'
  LOOP
    EXECUTE format('DELETE FROM %s WHERE %I = ANY($1)', r.t, r.col) USING v_ids;
  END LOOP;

  DELETE FROM missions WHERE id = ANY(v_ids);
  RETURN array_length(v_ids, 1);
END;
$fn_cmt$;

REVOKE EXECUTE ON FUNCTION public.fn_cleanup_missions_test() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_cleanup_missions_test() TO service_role;

SELECT cron.schedule(
  'cleanup-missions-test-horaire',
  '23 * * * *',
  'SELECT public.fn_cleanup_missions_test()'
);
