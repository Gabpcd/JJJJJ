-- BUG P0 : l'écran Classement soignant affichait l'erreur Postgres brute
-- « structure of query does not match function result type ».
--
-- Cause : fn_top_soignants déclare score_fiabilite en `integer` dans son RETURNS
-- TABLE, alors que la colonne soignants.score_fiabilite est `numeric`. PostgreSQL
-- refuse le RETURN QUERY car le type de la colonne projetée ne correspond pas au
-- type déclaré. Fix : caster score_fiabilite en integer dans le SELECT (un score
-- de fiabilité /100 s'affiche en entier). Aucun autre changement de signature.

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
    AND s.tous_documents_valides = TRUE
    AND (p_profession IS NULL OR s.profession::TEXT = p_profession)
    ORDER BY s.note_moyenne DESC NULLS LAST, s.score_fiabilite DESC, s.total_missions_terminees DESC
    LIMIT p_limit;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_top_soignants(text, integer) TO authenticated, service_role;
