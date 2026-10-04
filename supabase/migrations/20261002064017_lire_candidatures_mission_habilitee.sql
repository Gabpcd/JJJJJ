-- Lecture bornée pour les membres habilités des établissements secondaires.
-- Helpers et ACL rapprochés des catalogues staging/production du 02/10/2026.
-- Ne modifie aucune policy, aucun scope global ni aucune RPC de décision.
CREATE FUNCTION public.fn_lire_candidatures_mission_habilitee(p_mission_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_mission public.missions%ROWTYPE; v_nom text;
BEGIN
  IF auth.uid() IS NULL OR public.fn_compte_auth_actif() IS NOT TRUE
    OR NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id=auth.uid()
      AND u.email_confirmed_at IS NOT NULL)
  THEN RAISE EXCEPTION 'Mission indisponible ou accès refusé' USING ERRCODE='42501'; END IF;

  SELECT m.* INTO v_mission FROM public.missions m
  JOIN public.etablissements e ON e.id=m.etablissement_id AND e.supprime_le IS NULL
  WHERE m.id=p_mission_id;
  IF NOT FOUND
    OR public.fn_role_etablissement_courant(v_mission.etablissement_id)
      IS NULL
    OR public.fn_a_permission_etablissement('candidatures',v_mission.etablissement_id) IS NOT TRUE
  THEN RAISE EXCEPTION 'Mission indisponible ou accès refusé' USING ERRCODE='42501'; END IF;

  -- Une adhésion active au bon établissement est nécessaire ; ni métadonnée
  -- éditable, ni simple appartenance au groupe de santé ne suffit.
  -- Le repli propriétaire historique ne réactive pas une adhésion révoquée.
  IF NOT EXISTS (SELECT 1 FROM public.membres_etablissement me
      WHERE me.user_id=auth.uid() AND me.etablissement_id=v_mission.etablissement_id
        AND me.actif IS TRUE AND me.role IN ('PROPRIETAIRE','ADMIN_GROUPE','RH'))
    AND NOT (auth.uid()=v_mission.etablissement_id
      AND NOT EXISTS (SELECT 1 FROM public.membres_etablissement me
        WHERE me.user_id=auth.uid() AND me.etablissement_id=v_mission.etablissement_id))
  THEN RAISE EXCEPTION 'Mission indisponible ou accès refusé' USING ERRCODE='42501'; END IF;

  SELECT e.nom INTO v_nom FROM public.etablissements e WHERE e.id=v_mission.etablissement_id;
  RETURN jsonb_build_object(
    'mission',jsonb_build_object('id',v_mission.id,'intitule',v_mission.intitule,
      'etablissement_id',v_mission.etablissement_id,'etablissement_nom',v_nom,
      'statut',v_mission.statut,'mode_attribution',v_mission.mode_attribution,
      'nb_creneaux',v_mission.nb_creneaux,'profession_requise',v_mission.profession_requise,
      'specialite_medicale_requise',v_mission.specialite_medicale_requise),
    'creneaux',COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'id',mc.id,'mission_id',mc.mission_id,'debut',mc.debut,'fin',mc.fin,
      'est_pause',mc.est_pause,'type_creneau',mc.type_creneau) ORDER BY mc.debut,mc.id)
      FROM public.mission_creneaux mc WHERE mc.mission_id=v_mission.id
        AND mc.type_creneau='PREVISIONNEL' AND mc.est_pause IS FALSE),'[]'::jsonb),
    'candidatures',COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'id',c.id,'soignant_id',c.soignant_id,'message',c.message,'statut',c.statut,'cree_le',c.cree_le,
      'soignant',jsonb_build_object('id',s.id,'prenom',s.prenom,
        'nom',left(COALESCE(s.nom,''),1)||'.','nom_anonymise',true,
        'profession',s.profession,'specialite_medicale',s.specialite_medicale,
        'type_exercice',s.type_exercice,'est_etudiant',s.est_etudiant,
        'score_fiabilite',s.score_fiabilite,'total_missions_terminees',s.total_missions_terminees,
        'note_moyenne',s.note_moyenne,'nb_evaluations',s.nb_evaluations,
        'etudiant_details',s.etudiant_details,'tous_documents_valides',s.tous_documents_valides))
      ORDER BY c.cree_le,c.id)
      FROM public.candidatures c JOIN public.soignants s ON s.id=c.soignant_id
      WHERE c.mission_id=v_mission.id AND s.supprime_le IS NULL
        AND private.fn_comptes_meme_cohorte_test(s.id,v_mission.etablissement_id) IS TRUE),'[]'::jsonb));
END;
$function$;
ALTER FUNCTION public.fn_lire_candidatures_mission_habilitee(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_lire_candidatures_mission_habilitee(uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.fn_lire_candidatures_mission_habilitee(uuid) TO authenticated;
-- Format et convention de hash confirmés dans les deux catalogues LIVE à 06:09 UTC.
INSERT INTO private.security_definer_inventory(signature,categorie,definition_md5,justification,recense_le)
SELECT 'fn_lire_candidatures_mission_habilitee(uuid)','RPC_UTILISATEUR_AUTH_INTERNE',md5(p.prosrc),
  'Lecture candidature et planning bornée à la mission : compte actif confirmé, adhésion habilitée sur son établissement, cohorte TEST ; aucun élargissement des policies ni des décisions.',now()
FROM pg_catalog.pg_proc p
WHERE p.oid='public.fn_lire_candidatures_mission_habilitee(uuid)'::regprocedure
ON CONFLICT(signature) DO UPDATE SET categorie=EXCLUDED.categorie,definition_md5=EXCLUDED.definition_md5,
  justification=EXCLUDED.justification,recense_le=EXCLUDED.recense_le;
