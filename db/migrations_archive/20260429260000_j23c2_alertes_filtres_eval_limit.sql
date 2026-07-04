-- J2.3.C.2 — RPC fn_evaluer_alertes_filtres + ajout limite 20 filtres
-- + fn_compter_nouveaux_pour_filtre / fn_obtenir_apercu_filtre

-- 1. Modifier fn_creer_filtre_sauvegarde : ajouter check max 20 filtres
CREATE OR REPLACE FUNCTION public.fn_creer_filtre_sauvegarde(
  p_nom text,
  p_audience public.filtre_audience,
  p_filtres jsonb,
  p_alerte_active boolean DEFAULT false,
  p_frequence_alerte public.filtre_frequence_alerte DEFAULT 'QUOTIDIENNE'
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_id uuid;
  v_count integer;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('error','Non authentifié'); END IF;
  IF length(p_nom) = 0 OR length(p_nom) > 100 THEN
    RETURN jsonb_build_object('error','Nom invalide (1-100 caractères)');
  END IF;

  -- Limite : 20 filtres max par utilisateur
  SELECT count(*) INTO v_count FROM filtres_sauvegardes WHERE utilisateur_id = v_uid;
  IF v_count >= 20 THEN
    RETURN jsonb_build_object('error', 'Limite de 20 recherches sauvegardées atteinte. Supprimez-en une avant d''en créer une nouvelle.');
  END IF;

  INSERT INTO filtres_sauvegardes (utilisateur_id, nom, audience, filtres, alerte_active, frequence_alerte)
  VALUES (v_uid, p_nom, p_audience, COALESCE(p_filtres, '{}'::jsonb), p_alerte_active, p_frequence_alerte)
  RETURNING id INTO v_id;

  PERFORM fn_ecrire_audit_safe(
    p_acteur_id := v_uid, p_type_acteur := 'SOIGNANT',
    p_action := 'FILTRE_CREE', p_type_ressource := 'filtre_sauvegarde',
    p_id_ressource := v_id,
    p_details := jsonb_build_object('nom', p_nom, 'audience', p_audience::text, 'alerte_active', p_alerte_active, 'frequence', p_frequence_alerte::text)
  );

  IF p_alerte_active THEN
    PERFORM fn_ecrire_audit_safe(
      p_acteur_id := v_uid, p_type_acteur := 'SOIGNANT',
      p_action := 'ALERTE_ACTIVEE', p_type_ressource := 'filtre_sauvegarde',
      p_id_ressource := v_id,
      p_details := jsonb_build_object('frequence', p_frequence_alerte::text)
    );
  END IF;

  RETURN jsonb_build_object('success', true, 'id', v_id);
EXCEPTION
  WHEN unique_violation THEN
    RETURN jsonb_build_object('error', 'Un filtre avec ce nom existe déjà');
END;
$$;

-- 2. fn_compter_nouveaux_pour_filtre — helper count
CREATE OR REPLACE FUNCTION public.fn_compter_nouveaux_pour_filtre(
  p_filtre_id uuid,
  p_since timestamptz
) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions
STABLE AS $$
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
      AND (NOT v_urgentes_only OR COALESCE(m.urgente, false) = true);
  ELSIF v_filtre.audience = 'ETAB_RECHERCHE_SOIGNANTS' THEN
    v_profession := v_filtre.filtres->>'profession';
    SELECT count(*) INTO v_count FROM soignants s
    WHERE s.cree_le > p_since
      AND COALESCE(s.tous_documents_valides, false) = true
      AND (v_profession IS NULL OR v_profession = '' OR s.profession::text = v_profession);
  END IF;

  RETURN COALESCE(v_count, 0);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_compter_nouveaux_pour_filtre(uuid, timestamptz) TO service_role;

-- 3. fn_evaluer_alertes_filtres — boucle sur filtres éligibles + UPDATE state
CREATE OR REPLACE FUNCTION public.fn_evaluer_alertes_filtres(
  p_frequence text DEFAULT NULL
) RETURNS TABLE (
  filtre_id uuid,
  utilisateur_id uuid,
  audience public.filtre_audience,
  nom text,
  nb_nouveaux integer
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  r RECORD;
  v_count integer;
BEGIN
  FOR r IN
    SELECT * FROM filtres_sauvegardes
    WHERE alerte_active = true
      AND (
        (p_frequence IS NULL OR frequence_alerte::text = p_frequence)
        AND (
          (frequence_alerte = 'QUOTIDIENNE'   AND dernier_check_le < now() - interval '23 hours') OR
          (frequence_alerte = 'HEBDOMADAIRE'  AND dernier_check_le < now() - interval '6 days 23 hours') OR
          (frequence_alerte = 'IMMEDIATE'     AND dernier_check_le < now() - interval '55 minutes')
        )
      )
  LOOP
    v_count := fn_compter_nouveaux_pour_filtre(r.id, r.dernier_check_le);
    UPDATE filtres_sauvegardes
    SET dernier_check_le = now(),
        nb_resultats_dernier_check = v_count
    WHERE id = r.id;
    IF v_count > 0 THEN
      filtre_id := r.id;
      utilisateur_id := r.utilisateur_id;
      audience := r.audience;
      nom := r.nom;
      nb_nouveaux := v_count;
      RETURN NEXT;
    END IF;
  END LOOP;
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_evaluer_alertes_filtres(text) TO service_role;

-- 4. fn_obtenir_apercu_filtre — top N résultats pour preview email
CREATE OR REPLACE FUNCTION public.fn_obtenir_apercu_filtre(
  p_filtre_id uuid,
  p_since timestamptz,
  p_limit integer DEFAULT 5
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions
STABLE AS $$
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
      'urgente', COALESCE(m.urgente, false)
    ) ORDER BY m.cree_le DESC), '[]'::jsonb)
    INTO v_result
    FROM (
      SELECT * FROM missions m2
      WHERE m2.statut = 'OUVERTE' AND m2.cree_le > p_since
        AND (v_profession IS NULL OR v_profession = '' OR m2.profession_requise::text = v_profession)
        AND COALESCE(m2.taux_horaire_base, 0) >= v_taux_min
        AND (NOT v_urgentes_only OR COALESCE(m2.urgente, false) = true)
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
$$;
GRANT EXECUTE ON FUNCTION public.fn_obtenir_apercu_filtre(uuid, timestamptz, integer) TO service_role;

NOTIFY pgrst, 'reload schema';
