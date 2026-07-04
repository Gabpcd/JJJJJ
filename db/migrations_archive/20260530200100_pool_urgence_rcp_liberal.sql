-- Cohérence RCP : l'acceptation rapide d'une mission urgente en LIBÉRAL doit
-- aussi vérifier la RCP (un libéral ne peut exercer sans). Les missions urgentes
-- salariées (ou TOUS) restent accessibles sans RCP (cf. règle par type de contrat
-- effectif, migration 20260530200000).
CREATE OR REPLACE FUNCTION public.fn_accepter_mission_urgence(p_mission_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_soignant RECORD;
  v_mission RECORD;
  v_existing UUID;
  v_candidature_id UUID;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;

  SELECT * INTO v_soignant FROM soignants WHERE id = v_uid AND supprime_le IS NULL;
  IF v_soignant IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Profil soignant introuvable');
  END IF;

  SELECT * INTO v_mission FROM missions WHERE id = p_mission_id;
  IF v_mission IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Mission introuvable');
  END IF;
  IF v_mission.statut <> 'OUVERTE' OR COALESCE(v_mission.est_urgente, false) = false THEN
    RETURN jsonb_build_object('success', false, 'error', 'Mission non disponible (non-urgente ou non-ouverte)');
  END IF;

  IF NOT public.fn_soignant_compatible_mission(
    v_soignant.profession, v_soignant.specialite_medicale,
    v_mission.profession_requise, v_mission.specialite_medicale_requise,
    COALESCE(v_mission.accepte_non_specialises, true)
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Profession ou spécialité incompatible');
  END IF;

  IF COALESCE(v_soignant.tous_documents_valides, false) = false THEN
    RETURN jsonb_build_object('success', false, 'error', 'Vos documents ne sont pas tous validés');
  END IF;

  -- RCP obligatoire si la mission urgente est explicitement LIBÉRALE.
  IF v_mission.type_contrat_recherche = 'LIBERAL' THEN
    IF NOT EXISTS (
      SELECT 1 FROM documents_soignants
      WHERE soignant_id = v_uid AND type_document = 'RCP_ASSURANCE'
      AND statut_verification = 'VERIFIE' AND supprime_le IS NULL
      AND (valide_jusqua IS NULL OR valide_jusqua > CURRENT_DATE)
    ) THEN
      RETURN jsonb_build_object('success', false, 'error', 'Assurance RCP obligatoire pour une mission urgente en libéral.');
    END IF;
  END IF;

  SELECT id INTO v_existing FROM candidatures
  WHERE mission_id = p_mission_id AND soignant_id = v_uid
  LIMIT 1;
  IF v_existing IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Vous avez déjà candidaté à cette mission');
  END IF;

  INSERT INTO candidatures (mission_id, soignant_id, statut, message, cree_le)
  VALUES (
    p_mission_id, v_uid, 'EN_ATTENTE_VALIDATION_ETAB',
    'Acceptation rapide via pool urgence',
    NOW()
  )
  RETURNING id INTO v_candidature_id;

  INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien, type_ressource, id_ressource)
  VALUES (
    v_mission.etablissement_id, 'ETABLISSEMENT', 'POOL_URGENCE_ACCEPTATION',
    '🚨 Acceptation rapide pool urgence',
    v_soignant.prenom || ' ' || LEFT(v_soignant.nom, 1) || '. (' || v_soignant.profession::text
      || ') a accepté votre mission urgente. Validez ou refusez sous 1h.',
    '/etablissement/missions/' || p_mission_id::text,
    'candidature', v_candidature_id
  );

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid,
    p_type_acteur := 'SOIGNANT',
    p_action := 'POOL_URGENCE_ACCEPTATION_RAPIDE',
    p_type_ressource := 'candidature',
    p_id_ressource := v_candidature_id,
    p_details := jsonb_build_object('mission_id', p_mission_id)
  );

  RETURN jsonb_build_object(
    'success', true,
    'candidature_id', v_candidature_id,
    'message', 'Acceptation enregistrée. Attente validation établissement.'
  );
END;
$function$;

NOTIFY pgrst, 'reload schema';
