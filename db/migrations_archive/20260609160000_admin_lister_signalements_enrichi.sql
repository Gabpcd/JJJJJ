-- Enrichit fn_admin_lister_signalements : retourne aussi les noms du signaleur et de
-- la cible (pour l'onglet admin « Signalements »), résolus selon leur type.

CREATE OR REPLACE FUNCTION public.fn_admin_lister_signalements(p_statut text DEFAULT NULL)
RETURNS TABLE (
  id uuid,
  signaleur_id uuid,
  signaleur_type text,
  signaleur_nom text,
  cible_id uuid,
  cible_type text,
  cible_nom text,
  categorie text,
  motif text,
  mission_id uuid,
  statut text,
  resolution text,
  traite_le timestamptz,
  cree_le timestamptz
)
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT
    s.id, s.signaleur_id, s.signaleur_type,
    CASE WHEN s.signaleur_type = 'SOIGNANT'
      THEN (SELECT trim(coalesce(so.prenom,'') || ' ' || coalesce(so.nom,'')) FROM soignants so WHERE so.id = s.signaleur_id)
      ELSE (SELECT et.nom FROM etablissements et WHERE et.id = s.signaleur_id)
    END AS signaleur_nom,
    s.cible_id, s.cible_type,
    CASE WHEN s.cible_type = 'SOIGNANT'
      THEN (SELECT trim(coalesce(so.prenom,'') || ' ' || coalesce(so.nom,'')) FROM soignants so WHERE so.id = s.cible_id)
      ELSE (SELECT et.nom FROM etablissements et WHERE et.id = s.cible_id)
    END AS cible_nom,
    s.categorie, s.motif, s.mission_id, s.statut, s.resolution, s.traite_le, s.cree_le
  FROM public.signalements s
  WHERE public.est_admin()
    AND (p_statut IS NULL OR s.statut = p_statut)
  ORDER BY
    CASE s.statut WHEN 'OUVERT' THEN 0 WHEN 'EN_COURS' THEN 1 ELSE 2 END,
    s.cree_le DESC;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_admin_lister_signalements(text) TO authenticated;
