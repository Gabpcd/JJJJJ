-- Navigation libre des comptes inscrits. Aucun rôle métier, candidature ou
-- droit sur un établissement n'est créé avant la complétion du dossier.
CREATE OR REPLACE FUNCTION public.fn_explorer_missions_inscription(p_mission_id uuid DEFAULT NULL, p_offset integer DEFAULT 0, p_limit integer DEFAULT 100)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public
AS $body$
DECLARE v_resultat jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT public.fn_compte_auth_actif()
    OR NOT EXISTS (SELECT 1 FROM public.parcours_inscription
      WHERE user_id=auth.uid() AND type_compte='SOIGNANT') THEN
    RAISE EXCEPTION 'Espace soignant requis.' USING ERRCODE='42501';
  END IF;
  SELECT COALESCE(jsonb_agg(offre ORDER BY debut_le,id),'[]'::jsonb) INTO v_resultat
  FROM (
    SELECT m.id,m.debut_le,
      public.fn_mission_publique(m.id) || jsonb_build_object(
        'statut','OUVERTE','soignant_assigne_id',NULL,
        'etablissement_id',m.etablissement_id,'nb_creneaux',m.nb_creneaux,
        'mode_remuneration',m.mode_remuneration,'retrocession_pct',m.retrocession_pct,
        'specialite_medicale_requise',m.specialite_medicale_requise,'accepte_non_specialises',m.accepte_non_specialises,
        'niveau_urgence',m.niveau_urgence,
        'duree_heures',m.duree_heures,'mode_attribution',m.mode_attribution,
        'total_brut',m.total_brut,'net_a_payer',m.net_a_payer,'net_estime',m.net_estime,
        'taux_rist_plafonne',m.taux_rist_plafonne,'rist_plafond_applique',m.rist_plafond_applique,
        'etablissements',jsonb_build_object('id',e.id,'nom',e.nom,'type',e.type,
          'adresse_ville',e.adresse_ville,'adresse_code_postal',e.adresse_code_postal,
          'adresse_lat',e.adresse_lat,'adresse_lng',e.adresse_lng,'logo_url',e.logo_url),
        'creneaux',COALESCE((SELECT jsonb_agg(jsonb_build_object(
          'id',c.id,'mission_id',c.mission_id,'debut',c.debut,'fin',c.fin,
          'est_pause',c.est_pause,'type_creneau',c.type_creneau) ORDER BY c.debut,c.id)
          FROM public.mission_creneaux c WHERE c.mission_id=m.id
            AND c.type_creneau='PREVISIONNEL' AND c.est_pause IS FALSE),'[]'::jsonb)
      ) AS offre
    FROM public.missions m JOIN public.etablissements e ON e.id=m.etablissement_id
    WHERE (p_mission_id IS NULL OR m.id=p_mission_id)
      AND m.statut='OUVERTE' AND m.debut_le>now() AND m.soignant_assigne_id IS NULL
      AND public.fn_mission_publique(m.id) IS NOT NULL
      AND NOT private.fn_mission_lie_compte_test(m.id)
    ORDER BY m.debut_le,m.id LIMIT LEAST(GREATEST(COALESCE(p_limit,100),1),100) OFFSET GREATEST(COALESCE(p_offset,0),0)
  ) offres;
  RETURN v_resultat;
END;
$body$;
REVOKE ALL ON FUNCTION public.fn_explorer_missions_inscription(uuid,integer,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.fn_explorer_missions_inscription(uuid,integer,integer) TO authenticated,service_role;

INSERT INTO private.security_definer_inventory(signature,categorie,definition_md5,justification,recense_le)
SELECT p.oid::regprocedure::text,'RPC_UTILISATEUR_AUTH_INTERNE',md5(p.prosrc),
  'Exploration de missions publiques : compte actif et parcours soignant propriétaire ; aucune candidature ni donnée privée.',now()
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname='fn_explorer_missions_inscription'
ON CONFLICT(signature) DO UPDATE SET definition_md5=EXCLUDED.definition_md5,justification=EXCLUDED.justification,recense_le=EXCLUDED.recense_le;
-- Extension du brouillon privé ; les droits de publication restent inchangés.
CREATE OR REPLACE FUNCTION public.fn_enregistrer_parcours_inscription(p_donnees jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
DECLARE v_parcours public.parcours_inscription;
BEGIN
  IF auth.uid() IS NULL OR NOT public.fn_compte_auth_actif() THEN
    RAISE EXCEPTION 'Session invalide.' USING ERRCODE = '42501';
  END IF;
  IF p_donnees IS NULL OR jsonb_typeof(p_donnees) <> 'object' OR octet_length(p_donnees::text) > 32768 THEN
    RAISE EXCEPTION 'Brouillon invalide.' USING ERRCODE = '22023';
  END IF;
  -- Aucun mot de passe, jeton, pièce ni état de vérification dans le brouillon.
  IF EXISTS (SELECT 1 FROM jsonb_object_keys(p_donnees) k WHERE k NOT IN (
    'profession','prenom','nom','telephone','dateNaissance','typesContrat','rpps','rayon',
    'estSalarieEtablissement','estEtudiant','scolariteFormation','scolariteAnnee',
    'siret','finess','type','rue','ville','codePostal','departement','emailContact',
    'telephoneContact','numeroLicence','missionProfession','missionVille','missionDate',
    'missionDebut','missionFin','missionChoisie','brouillonMission','missionFormulaire'
  )) THEN RAISE EXCEPTION 'Champ non autorisé dans le brouillon.' USING ERRCODE = '22023'; END IF;
  IF p_donnees ? 'missionFormulaire' AND (
    jsonb_typeof(p_donnees->'missionFormulaire') <> 'object'
    OR EXISTS (SELECT 1 FROM jsonb_object_keys(p_donnees->'missionFormulaire') k
      WHERE k NOT IN ('intitule','description','profession','specialite','service',
        'tauxHoraire','estUrgente','niveauUrgence','modeAttribution','contratPreference','creneaux'))
  ) THEN RAISE EXCEPTION 'Brouillon de mission invalide.' USING ERRCODE='22023'; END IF;
  UPDATE public.parcours_inscription SET donnees = donnees || p_donnees, modifie_le = now()
    WHERE user_id = auth.uid() RETURNING * INTO v_parcours;
  IF NOT FOUND THEN RAISE EXCEPTION 'Inscription introuvable.' USING ERRCODE = 'P0002'; END IF;
  RETURN to_jsonb(v_parcours);
END;
$function$;

UPDATE private.security_definer_inventory i SET definition_md5=md5(p.prosrc),recense_le=now()
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname='fn_enregistrer_parcours_inscription'
AND i.signature=p.oid::regprocedure::text;


-- Favoris atomiques par compte : deux clics / appareils ne s'écrasent pas.
CREATE OR REPLACE FUNCTION public.fn_modifier_favori_inscription(p_mission_id uuid, p_actif boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public
AS $favoris$
DECLARE v_ids jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT public.fn_compte_auth_actif() THEN
    RAISE EXCEPTION 'Session invalide.' USING ERRCODE='42501';
  END IF;
  SELECT COALESCE(donnees->'missionsSauvegardees','[]'::jsonb) INTO v_ids
  FROM public.parcours_inscription WHERE user_id=auth.uid() AND type_compte='SOIGNANT' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Espace soignant requis.' USING ERRCODE='42501'; END IF;
  IF p_mission_id IS NULL OR p_actif IS NULL THEN
    RAISE EXCEPTION 'Favori invalide.' USING ERRCODE='22023';
  END IF;
  IF p_actif AND NOT (v_ids ? p_mission_id::text) THEN
    IF public.fn_mission_publique(p_mission_id) IS NULL THEN
      RAISE EXCEPTION 'Cette mission n’est plus disponible.' USING ERRCODE='22023';
    END IF;
    IF jsonb_array_length(v_ids) >= 200 THEN
      RAISE EXCEPTION 'Retirez un favori avant d’en ajouter un autre.' USING ERRCODE='22023';
    END IF;
    v_ids := v_ids || jsonb_build_array(p_mission_id::text);
  ELSIF NOT p_actif THEN
    v_ids := v_ids - p_mission_id::text;
  END IF;
  UPDATE public.parcours_inscription SET donnees=jsonb_set(donnees,'{missionsSauvegardees}',v_ids),modifie_le=now()
  WHERE user_id=auth.uid();
END;
$favoris$;
REVOKE ALL ON FUNCTION public.fn_modifier_favori_inscription(uuid,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.fn_modifier_favori_inscription(uuid,boolean) TO authenticated,service_role;
INSERT INTO private.security_definer_inventory(signature,categorie,definition_md5,justification,recense_le)
SELECT p.oid::regprocedure::text,'RPC_UTILISATEUR_AUTH_INTERNE',md5(p.prosrc),
  'Favoris privés du compte actif : parcours propriétaire verrouillé, ajout limité aux missions publiques.',now()
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname='fn_modifier_favori_inscription'
ON CONFLICT(signature) DO UPDATE SET definition_md5=EXCLUDED.definition_md5,justification=EXCLUDED.justification,recense_le=EXCLUDED.recense_le;
