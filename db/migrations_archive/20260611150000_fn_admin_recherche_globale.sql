-- Session D-2 : recherche globale admin (⌘K) — utilisateurs, missions, factures.
-- Une seule RPC pour le palette de commandes : retourne au plus 5 résultats
-- par catégorie. Même garde que fn_rechercher_utilisateurs : est_admin(),
-- résultat vide sinon (pas d'exception, la palette reste silencieuse).

CREATE OR REPLACE FUNCTION public.fn_admin_recherche_globale(p_query text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $body$
DECLARE
  v_q text := LOWER(TRIM(COALESCE(p_query, '')));
  v_vide jsonb := jsonb_build_object(
    'utilisateurs', '[]'::jsonb,
    'missions', '[]'::jsonb,
    'factures', '[]'::jsonb
  );
  v_utilisateurs jsonb;
  v_missions jsonb;
  v_factures jsonb;
BEGIN
  IF NOT est_admin() THEN RETURN v_vide; END IF;
  IF length(v_q) < 2 THEN RETURN v_vide; END IF;

  -- Utilisateurs : soignants (nom, prénom, email, téléphone) + établissements (nom)
  SELECT COALESCE(jsonb_agg(x.r), '[]'::jsonb) INTO v_utilisateurs FROM (
    SELECT jsonb_build_object(
      'id', u.id,
      'type', CASE
        WHEN s.id IS NOT NULL THEN 'soignant'
        WHEN e.id IS NOT NULL THEN 'etablissement'
        ELSE 'inconnu'
      END,
      'nom', COALESCE(s.nom, e.nom, ''),
      'prenom', COALESCE(s.prenom, ''),
      'email', u.email,
      'profession', s.profession,
      'ville', COALESCE(s.adresse_ville, e.adresse_ville)
    ) AS r
    FROM auth.users u
    LEFT JOIN soignants s ON s.id = u.id
    LEFT JOIN etablissements e ON e.id = u.id
    WHERE LOWER(u.email) LIKE v_q || '%'
       OR LOWER(COALESCE(s.prenom, '') || ' ' || COALESCE(s.nom, '')) LIKE '%' || v_q || '%'
       OR LOWER(COALESCE(s.nom, '') || ' ' || COALESCE(s.prenom, '')) LIKE '%' || v_q || '%'
       OR LOWER(COALESCE(e.nom, '')) LIKE '%' || v_q || '%'
       OR COALESCE(s.telephone, '') LIKE v_q || '%'
    LIMIT 5
  ) x;

  -- Missions : intitulé, service, n° de note d'honoraires, début d'UUID, nom d'établissement
  SELECT COALESCE(jsonb_agg(x.r), '[]'::jsonb) INTO v_missions FROM (
    SELECT jsonb_build_object(
      'id', m.id,
      'intitule', m.intitule,
      'statut', m.statut,
      'etablissement', e.nom,
      'debut_le', m.debut_le,
      'profession', m.profession_requise
    ) AS r
    FROM missions m
    JOIN etablissements e ON e.id = m.etablissement_id
    WHERE LOWER(COALESCE(m.intitule, '')) LIKE '%' || v_q || '%'
       OR LOWER(COALESCE(m.service, '')) LIKE '%' || v_q || '%'
       OR LOWER(COALESCE(m.numero_note_honoraires, '')) LIKE v_q || '%'
       OR m.id::text LIKE v_q || '%'
       OR LOWER(e.nom) LIKE '%' || v_q || '%'
    ORDER BY m.debut_le DESC
    LIMIT 5
  ) x;

  -- Factures : numéro, début d'UUID, nom d'établissement
  SELECT COALESCE(jsonb_agg(x.r), '[]'::jsonb) INTO v_factures FROM (
    SELECT jsonb_build_object(
      'id', f.id,
      'numero', f.numero_facture,
      'statut', f.statut,
      'etablissement', e.nom,
      'montant_ttc', f.montant_ttc,
      'date_emission', f.date_emission,
      'type_document', f.type_document
    ) AS r
    FROM factures f
    JOIN etablissements e ON e.id = f.etablissement_id
    WHERE LOWER(COALESCE(f.numero_facture, '')) LIKE '%' || v_q || '%'
       OR f.id::text LIKE v_q || '%'
       OR LOWER(e.nom) LIKE '%' || v_q || '%'
    ORDER BY f.date_emission DESC NULLS LAST
    LIMIT 5
  ) x;

  RETURN jsonb_build_object(
    'utilisateurs', v_utilisateurs,
    'missions', v_missions,
    'factures', v_factures
  );
END;
$body$;

GRANT EXECUTE ON FUNCTION public.fn_admin_recherche_globale(text) TO authenticated;
