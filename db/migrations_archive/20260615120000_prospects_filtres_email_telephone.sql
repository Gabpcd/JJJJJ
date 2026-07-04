-- Filtres « avec email » / « avec téléphone » sur la prospection étabs + soignants.
-- Params optionnels ajoutés EN FIN de signature (rétro-compat : anciens appels OK).

CREATE OR REPLACE FUNCTION public.fn_admin_chercher_prospects(
  p_type text DEFAULT NULL::text,
  p_departement text DEFAULT NULL::text,
  p_q text DEFAULT NULL::text,
  p_favoris boolean DEFAULT false,
  p_page integer DEFAULT 1,
  p_avec_email boolean DEFAULT false,
  p_avec_tel boolean DEFAULT false
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_total bigint;
  v_resultats jsonb;
  v_par_page int := 30;
  v_offset int := (greatest(p_page,1)-1) * 30;
BEGIN
  IF NOT public.est_admin() THEN RAISE EXCEPTION 'Accès admin requis'; END IF;

  SELECT count(*) INTO v_total
  FROM prospects_etablissements p
  WHERE (p_type IS NULL OR p_type = '' OR p.type_jolene = p_type)
    AND (p_departement IS NULL OR p_departement = '' OR p.departement = upper(p_departement))
    AND (NOT p_favoris OR p.favori)
    AND (NOT p_avec_email OR (p.email IS NOT NULL AND p.email <> ''))
    AND (NOT p_avec_tel OR (p.telephone IS NOT NULL AND p.telephone <> ''))
    AND (p_q IS NULL OR p_q = '' OR p.nom ILIKE '%'||p_q||'%' OR p.ville ILIKE '%'||p_q||'%');

  SELECT coalesce(jsonb_agg(row_to_json(t)::jsonb), '[]'::jsonb) INTO v_resultats
  FROM (
    SELECT p.finess, p.siret, p.nom, p.type_jolene, p.categorie_lib, p.telephone,
           p.email, p.adresse, p.code_postal, p.ville, p.departement, p.favori
    FROM prospects_etablissements p
    WHERE (p_type IS NULL OR p_type = '' OR p.type_jolene = p_type)
      AND (p_departement IS NULL OR p_departement = '' OR p.departement = upper(p_departement))
      AND (NOT p_favoris OR p.favori)
      AND (NOT p_avec_email OR (p.email IS NOT NULL AND p.email <> ''))
      AND (NOT p_avec_tel OR (p.telephone IS NOT NULL AND p.telephone <> ''))
      AND (p_q IS NULL OR p_q = '' OR p.nom ILIKE '%'||p_q||'%' OR p.ville ILIKE '%'||p_q||'%')
    ORDER BY p.favori DESC, p.nom
    LIMIT v_par_page OFFSET v_offset
  ) t;

  RETURN jsonb_build_object(
    'total', v_total,
    'page', greatest(p_page,1),
    'total_pages', ceil(v_total::numeric / v_par_page),
    'resultats', v_resultats
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_admin_chercher_prospects_soignants(
  p_profession text DEFAULT NULL::text,
  p_departement text DEFAULT NULL::text,
  p_q text DEFAULT NULL::text,
  p_favoris boolean DEFAULT false,
  p_page integer DEFAULT 1,
  p_avec_email boolean DEFAULT false,
  p_avec_tel boolean DEFAULT false
)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_total bigint; v_res jsonb; v_page int := GREATEST(p_page, 1);
BEGIN
  IF NOT public.est_admin() THEN RETURN jsonb_build_object('error', 'Accès refusé'); END IF;
  SELECT count(*) INTO v_total FROM prospects_soignants p
   WHERE (p_profession IS NULL OR p.profession = p_profession)
     AND (p_departement IS NULL OR p.departement = lpad(p_departement, 2, '0'))
     AND (NOT p_favoris OR p.favori)
     AND (NOT p_avec_email OR (p.email IS NOT NULL AND p.email <> ''))
     AND (NOT p_avec_tel OR (p.telephone IS NOT NULL AND p.telephone <> ''))
     AND (p_q IS NULL OR p.nom ILIKE '%' || p_q || '%' OR p.ville ILIKE '%' || p_q || '%' OR p.enseigne ILIKE '%' || p_q || '%');
  SELECT coalesce(jsonb_agg(row_to_json(t)::jsonb), '[]'::jsonb) INTO v_res FROM (
    SELECT p.* FROM prospects_soignants p
     WHERE (p_profession IS NULL OR p.profession = p_profession)
       AND (p_departement IS NULL OR p.departement = lpad(p_departement, 2, '0'))
       AND (NOT p_favoris OR p.favori)
       AND (NOT p_avec_email OR (p.email IS NOT NULL AND p.email <> ''))
       AND (NOT p_avec_tel OR (p.telephone IS NOT NULL AND p.telephone <> ''))
       AND (p_q IS NULL OR p.nom ILIKE '%' || p_q || '%' OR p.ville ILIKE '%' || p_q || '%' OR p.enseigne ILIKE '%' || p_q || '%')
     ORDER BY p.favori DESC, p.departement, p.ville, p.nom
     LIMIT 30 OFFSET (v_page - 1) * 30
  ) t;
  RETURN jsonb_build_object('total', v_total, 'page', v_page,
    'total_pages', CEIL(v_total / 30.0), 'resultats', v_res);
END;
$function$;
