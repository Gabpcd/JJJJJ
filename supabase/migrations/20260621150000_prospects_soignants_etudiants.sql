-- Prospection étudiants : segment dédié dans prospects_soignants (est_etudiant + ecole + formation)
-- et filtre p_etudiants dans fn_admin_chercher_prospects_soignants. Appliquée prod via MCP puis enregistrée.
ALTER TABLE public.prospects_soignants
  ADD COLUMN IF NOT EXISTS est_etudiant boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS ecole text,
  ADD COLUMN IF NOT EXISTS formation text;
CREATE INDEX IF NOT EXISTS idx_prospects_soignants_etudiant ON public.prospects_soignants (est_etudiant) WHERE est_etudiant;

DROP FUNCTION IF EXISTS public.fn_admin_chercher_prospects_soignants(text, text, text, boolean, integer, boolean, boolean);

CREATE OR REPLACE FUNCTION public.fn_admin_chercher_prospects_soignants(
  p_profession text DEFAULT NULL, p_departement text DEFAULT NULL, p_q text DEFAULT NULL,
  p_favoris boolean DEFAULT false, p_page integer DEFAULT 1,
  p_avec_email boolean DEFAULT false, p_avec_tel boolean DEFAULT false,
  p_etudiants boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE v_total bigint; v_res jsonb; v_page int := GREATEST(p_page, 1);
BEGIN
  IF NOT public.est_admin() THEN RETURN jsonb_build_object('error', 'Accès refusé'); END IF;
  SELECT count(*) INTO v_total FROM prospects_soignants p
   WHERE (p_profession IS NULL OR p.profession = p_profession)
     AND (p_departement IS NULL OR p.departement = lpad(p_departement, 2, '0'))
     AND (NOT p_favoris OR p.favori)
     AND (NOT p_avec_email OR (p.email IS NOT NULL AND p.email <> ''))
     AND (NOT p_avec_tel OR (p.telephone IS NOT NULL AND p.telephone <> ''))
     AND (NOT p_etudiants OR p.est_etudiant)
     AND (p_q IS NULL OR p.nom ILIKE '%' || p_q || '%' OR p.ville ILIKE '%' || p_q || '%' OR p.enseigne ILIKE '%' || p_q || '%');
  SELECT coalesce(jsonb_agg(row_to_json(t)::jsonb), '[]'::jsonb) INTO v_res FROM (
    SELECT p.* FROM prospects_soignants p
     WHERE (p_profession IS NULL OR p.profession = p_profession)
       AND (p_departement IS NULL OR p.departement = lpad(p_departement, 2, '0'))
       AND (NOT p_favoris OR p.favori)
       AND (NOT p_avec_email OR (p.email IS NOT NULL AND p.email <> ''))
       AND (NOT p_avec_tel OR (p.telephone IS NOT NULL AND p.telephone <> ''))
       AND (NOT p_etudiants OR p.est_etudiant)
       AND (p_q IS NULL OR p.nom ILIKE '%' || p_q || '%' OR p.ville ILIKE '%' || p_q || '%' OR p.enseigne ILIKE '%' || p_q || '%')
     ORDER BY p.favori DESC, p.departement, p.ville, p.nom
     LIMIT 30 OFFSET (v_page - 1) * 30
  ) t;
  RETURN jsonb_build_object('total', v_total, 'page', v_page, 'total_pages', CEIL(v_total / 30.0), 'resultats', v_res);
END;
$function$;
GRANT EXECUTE ON FUNCTION public.fn_admin_chercher_prospects_soignants(text, text, text, boolean, integer, boolean, boolean, boolean) TO authenticated;
