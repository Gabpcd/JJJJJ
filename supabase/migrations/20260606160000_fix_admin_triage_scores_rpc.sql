-- FIX page admin /admin/scores (AdminScoreTriage) : la page interrogeait des tables
-- inexistantes (scores_soignants / scores_etablissements / profils). Les scores réels
-- vivent en colonnes : soignants.score_fiabilite et etablissements.score_qualite.
-- On expose une RPC admin unifiée, source de vérité unique, plutôt que des requêtes
-- frontend sur des tables fantômes.
CREATE OR REPLACE FUNCTION public.fn_admin_triage_scores()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v jsonb;
BEGIN
  IF NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Accès refusé — admin uniquement');
  END IF;

  SELECT jsonb_build_object('success', true, 'lignes', COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.score ASC), '[]'::jsonb))
  INTO v
  FROM (
    SELECT s.id AS user_id,
           'SOIGNANT' AS type,
           NULLIF(btrim(COALESCE(s.prenom, '') || ' ' || COALESCE(s.nom, '')), '') AS nom,
           COALESCE(s.email, '') AS email,
           COALESCE(s.score_fiabilite, 0)::numeric AS score
    FROM public.soignants s
    WHERE s.supprime_le IS NULL
    UNION ALL
    SELECT e.id,
           'ETAB',
           NULLIF(btrim(COALESCE(e.nom, '')), '') AS nom,
           COALESCE(e.email_contact, '') AS email,
           COALESCE(e.score_qualite, 0)::numeric AS score
    FROM public.etablissements e
    WHERE e.supprime_le IS NULL
  ) x;

  RETURN v;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_admin_triage_scores() TO authenticated;
