-- AUDIT sécurité (jugement, non détectable par advisors) — autorisation interne des
-- fonctions SECURITY DEFINER sur données sensibles. Corrige 2 fuites IDOR + durcit
-- 7 helpers internes (défense en profondeur).
--
-- 1) fn_soignants_urgence : RETOURNE noms + TÉLÉPHONES de soignants pour une mission,
--    SANS vérifier que l'appelant possède la mission → n'importe quel utilisateur
--    authentifié pouvait dumper des coordonnées (fuite PII / RGPD). Ajout d'un garde
--    de propriété établissement.
-- 2) fn_soignant_dpae_complet : expose les métadonnées d'identité (champs DPAE remplis)
--    d'un soignant arbitraire. Seul appelant légitime = le soignant sur son propre
--    profil. Ajout garde auth.uid()/admin. (0 appelant interne — vérifié.)
-- 3) Helpers purement internes (générateurs de numéros légaux + calculs de score/montant)
--    exposés à 'authenticated' sans raison. Aucun appel frontend, tous les appelants
--    internes sont SECURITY DEFINER (s'exécutent en tant que postgres). Révocation +
--    grant service_role explicite. Empêche notamment le "burning" de numéros de facture
--    (numérotation séquentielle légale).

-- ── 1) fn_soignants_urgence : garde de propriété ────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_soignants_urgence(p_mission_id uuid)
 RETURNS TABLE(soignant_id uuid, id uuid, prenom text, nom text, score_fiabilite integer, distance_km numeric, urgence_rayon_km integer, telephone text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_mission RECORD;
BEGIN
    SELECT m.id, m.profession_requise, e.id AS etablissement_id, e.adresse_lat AS etab_lat, e.adresse_lng AS etab_lng
    INTO v_mission FROM missions m JOIN etablissements e ON e.id = m.etablissement_id WHERE m.id = p_mission_id;
    IF NOT FOUND THEN RETURN; END IF;

    -- GARDE : seul l'établissement propriétaire de la mission (ou un admin) peut obtenir
    -- la liste des soignants disponibles avec leurs coordonnées.
    -- COALESCE indispensable : mon_etablissement_id() est NULL pour un non-établissement,
    -- et `etab_id = NULL` vaut NULL → sans COALESCE, `IF NOT (false OR NULL)` = `IF NULL`
    -- ne déclenche PAS le RETURN (la fuite persisterait). Vérifié en test.
    IF NOT (est_admin() OR COALESCE(v_mission.etablissement_id = mon_etablissement_id(), false)) THEN
        RETURN;
    END IF;

    RETURN QUERY
    SELECT
        s.id AS soignant_id,
        s.id,
        s.prenom::TEXT, s.nom::TEXT,
        COALESCE(s.score_fiabilite, 0)::INTEGER,
        CASE WHEN s.adresse_lat IS NOT NULL AND v_mission.etab_lat IS NOT NULL THEN
            ROUND((6371 * ACOS(LEAST(1.0, GREATEST(-1.0,
                COS(RADIANS(v_mission.etab_lat)) * COS(RADIANS(s.adresse_lat)) *
                COS(RADIANS(s.adresse_lng) - RADIANS(v_mission.etab_lng)) +
                SIN(RADIANS(v_mission.etab_lat)) * SIN(RADIANS(s.adresse_lat))
            ))))::NUMERIC, 1)
        ELSE NULL END,
        COALESCE(s.urgence_rayon_km, 15)::INTEGER,
        s.telephone::TEXT
    FROM soignants s
    WHERE COALESCE(s.disponible_urgence, FALSE) = TRUE
      AND s.supprime_le IS NULL
      AND s.tous_documents_valides = TRUE
      AND s.profession = v_mission.profession_requise
      AND NOT fn_est_exclu(s.id, v_mission.etablissement_id)
      AND NOT EXISTS (SELECT 1 FROM missions m WHERE m.soignant_assigne_id = s.id AND m.statut = 'EN_COURS' AND NOW() BETWEEN m.debut_le AND m.fin_le)
      AND (
          s.adresse_lat IS NULL OR v_mission.etab_lat IS NULL
          OR (6371 * ACOS(LEAST(1.0, GREATEST(-1.0,
              COS(RADIANS(v_mission.etab_lat)) * COS(RADIANS(s.adresse_lat)) *
              COS(RADIANS(s.adresse_lng) - RADIANS(v_mission.etab_lng)) +
              SIN(RADIANS(v_mission.etab_lat)) * SIN(RADIANS(s.adresse_lat))
          )))) <= COALESCE(s.urgence_rayon_km, 15)
      )
    ORDER BY s.score_fiabilite DESC NULLS LAST, distance_km NULLS LAST;
END;
$function$;

-- ── 2) fn_soignant_dpae_complet : garde appelant ────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_soignant_dpae_complet(p_soignant_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_s RECORD;
  v_manquants text[] := ARRAY[]::text[];
BEGIN
  -- GARDE : seul le soignant concerné (ou un admin) peut interroger sa complétude DPAE.
  IF NOT (p_soignant_id = auth.uid() OR est_admin()) THEN
    RETURN jsonb_build_object('complet', false, 'manquants', ARRAY['non_autorise']);
  END IF;

  SELECT sexe, lieu_naissance_commune, lieu_naissance_departement,
         pays_naissance, nationalite,
         COALESCE(numero_securite_sociale, numero_secu) AS nir,
         date_naissance, adresse_rue, adresse_ville
  INTO v_s
  FROM public.soignants WHERE id = p_soignant_id;

  IF v_s IS NULL THEN
    RETURN jsonb_build_object('complet', false, 'manquants', ARRAY['profil_introuvable']);
  END IF;

  IF v_s.sexe IS NULL THEN v_manquants := array_append(v_manquants, 'sexe'); END IF;
  IF v_s.date_naissance IS NULL THEN v_manquants := array_append(v_manquants, 'date_naissance'); END IF;
  IF v_s.pays_naissance IS NULL THEN v_manquants := array_append(v_manquants, 'pays_naissance'); END IF;
  IF v_s.nationalite IS NULL THEN v_manquants := array_append(v_manquants, 'nationalite'); END IF;
  IF COALESCE(v_s.pays_naissance, 'France') = 'France' THEN
    IF v_s.lieu_naissance_commune IS NULL THEN v_manquants := array_append(v_manquants, 'lieu_naissance_commune'); END IF;
    IF v_s.lieu_naissance_departement IS NULL THEN v_manquants := array_append(v_manquants, 'lieu_naissance_departement'); END IF;
  END IF;
  IF v_s.nir IS NULL OR v_s.nir = '' THEN v_manquants := array_append(v_manquants, 'numero_securite_sociale'); END IF;
  IF v_s.adresse_rue IS NULL OR v_s.adresse_rue = '' THEN v_manquants := array_append(v_manquants, 'adresse'); END IF;

  RETURN jsonb_build_object(
    'complet', array_length(v_manquants, 1) IS NULL,
    'manquants', v_manquants
  );
END;
$function$;

-- ── 3) Durcissement des helpers internes (révocation accès client) ──────────────
REVOKE EXECUTE ON FUNCTION public.next_invoice_number(uuid) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.next_invoice_number(uuid) TO service_role;
REVOKE EXECUTE ON FUNCTION public.next_avoir_number(uuid) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.next_avoir_number(uuid) TO service_role;
REVOKE EXECUTE ON FUNCTION public.fn_calculer_montant_periode(uuid, date, date) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.fn_calculer_montant_periode(uuid, date, date) TO service_role;
REVOKE EXECUTE ON FUNCTION public.fn_calculer_score_soignant(uuid) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.fn_calculer_score_soignant(uuid) TO service_role;
REVOKE EXECUTE ON FUNCTION public.fn_calculer_score_etab(uuid) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.fn_calculer_score_etab(uuid) TO service_role;
REVOKE EXECUTE ON FUNCTION public.fn_calculer_score_matching(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.fn_calculer_score_matching(uuid, uuid) TO service_role;
REVOKE EXECUTE ON FUNCTION public.fn_calculer_taux_free_transition_safe(uuid) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.fn_calculer_taux_free_transition_safe(uuid) TO service_role;
