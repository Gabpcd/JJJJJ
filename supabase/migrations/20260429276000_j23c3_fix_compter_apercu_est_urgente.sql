-- J2.3.C.3 — Fix RPC : `m.urgente` → `m.est_urgente` (la colonne s'appelle est_urgente).
-- Bug surfacé par tests E2E S6 (column m.urgente does not exist).

CREATE OR REPLACE FUNCTION public.fn_compter_nouveaux_pour_filtre(p_filtre_id uuid, p_since timestamp with time zone)
RETURNS integer
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_filtre RECORD;
  v_count integer := 0;
  v_profession text;
  v_taux_min numeric;
  v_urgentes_only boolean;
BEGIN
  SELECT * INTO v_filtre FROM filtres_sauvegardes WHERE id = p_filtre_id;
  IF NOT FOUND THEN RETURN 0; END IF;

  IF v_filtre.audience = 'SOIGNANT_RECHERCHE_MISSIONS' THEN
    v_profession := v_filtre.filtres->>'profession';
    v_taux_min := COALESCE((v_filtre.filtres->>'tauxMin')::numeric, 0);
    v_urgentes_only := COALESCE((v_filtre.filtres->>'urgentesOnly')::boolean, false);
    SELECT count(*) INTO v_count FROM missions m
    WHERE m.statut = 'OUVERTE'
      AND m.cree_le > p_since
      AND (v_profession IS NULL OR v_profession = '' OR m.profession_requise::text = v_profession)
      AND COALESCE(m.taux_horaire_base, 0) >= v_taux_min
      AND (NOT v_urgentes_only OR COALESCE(m.est_urgente, false) = true);
  ELSIF v_filtre.audience = 'ETAB_RECHERCHE_SOIGNANTS' THEN
    v_profession := v_filtre.filtres->>'profession';
    SELECT count(*) INTO v_count FROM soignants s
    WHERE s.cree_le > p_since
      AND COALESCE(s.tous_documents_valides, false) = true
      AND (v_profession IS NULL OR v_profession = '' OR s.profession::text = v_profession);
  END IF;

  RETURN COALESCE(v_count, 0);
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_obtenir_apercu_filtre(p_filtre_id uuid, p_since timestamp with time zone, p_limit integer DEFAULT 5)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_filtre RECORD;
  v_result jsonb;
  v_profession text;
  v_taux_min numeric;
  v_urgentes_only boolean;
BEGIN
  SELECT * INTO v_filtre FROM filtres_sauvegardes WHERE id = p_filtre_id;
  IF NOT FOUND THEN RETURN '[]'::jsonb; END IF;

  IF v_filtre.audience = 'SOIGNANT_RECHERCHE_MISSIONS' THEN
    v_profession := v_filtre.filtres->>'profession';
    v_taux_min := COALESCE((v_filtre.filtres->>'tauxMin')::numeric, 0);
    v_urgentes_only := COALESCE((v_filtre.filtres->>'urgentesOnly')::boolean, false);
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', m.id, 'intitule', m.intitule, 'profession', m.profession_requise::text,
      'etablissement', e.nom, 'ville', e.adresse_ville,
      'taux_horaire', m.taux_horaire_base,
      'debut_le', m.debut_le, 'fin_le', m.fin_le,
      'urgente', COALESCE(m.est_urgente, false)
    ) ORDER BY m.cree_le DESC), '[]'::jsonb)
    INTO v_result
    FROM (
      SELECT * FROM missions m2
      WHERE m2.statut = 'OUVERTE' AND m2.cree_le > p_since
        AND (v_profession IS NULL OR v_profession = '' OR m2.profession_requise::text = v_profession)
        AND COALESCE(m2.taux_horaire_base, 0) >= v_taux_min
        AND (NOT v_urgentes_only OR COALESCE(m2.est_urgente, false) = true)
      ORDER BY m2.cree_le DESC LIMIT p_limit
    ) m
    LEFT JOIN etablissements e ON e.id = m.etablissement_id;
  ELSIF v_filtre.audience = 'ETAB_RECHERCHE_SOIGNANTS' THEN
    v_profession := v_filtre.filtres->>'profession';
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', s.id, 'prenom', s.prenom,
      'nom_initiale', LEFT(s.nom, 1) || '.',
      'profession', s.profession::text,
      'note_moyenne', s.note_moyenne
    ) ORDER BY s.cree_le DESC), '[]'::jsonb)
    INTO v_result
    FROM (
      SELECT * FROM soignants s2
      WHERE s2.cree_le > p_since
        AND COALESCE(s2.tous_documents_valides, false) = true
        AND (v_profession IS NULL OR v_profession = '' OR s2.profession::text = v_profession)
      ORDER BY s2.cree_le DESC LIMIT p_limit
    ) s;
  ELSE
    v_result := '[]'::jsonb;
  END IF;

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$function$;
