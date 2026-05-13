-- PR 7 Sprint 3.5 — Réclamations score côté user (RPCs)
--
-- RPC fn_creer_reclamation_score : un soignant ou un étab dépose une
-- réclamation contre un événement de score qui les pénalise.
-- RPC fn_mes_reclamations : liste des réclamations de l'utilisateur courant.

-- ============================================================
-- 1. fn_creer_reclamation_score : ouvrir une réclamation
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_creer_reclamation_score(
  p_evenement_id uuid,
  p_evenement_type text,  -- 'SOIGNANT' ou 'ETAB'
  p_motif_categorie text,
  p_texte_libre text,
  p_justificatif_storage_path text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_event RECORD;
  v_proprio_id uuid;
  v_reclamation_id uuid;
  v_existante RECORD;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;

  IF p_evenement_type NOT IN ('SOIGNANT', 'ETAB') THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'TYPE_INVALIDE',
                                'error', 'evenement_type doit être SOIGNANT ou ETAB');
  END IF;

  IF p_motif_categorie NOT IN ('URGENCE_MEDICALE','DEUIL','FORCE_MAJEURE',
                                'ERREUR_JOLENE','CONTEXTE_PARTICULIER','AUTRE') THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'MOTIF_INVALIDE',
                                'error', 'Motif catégorie invalide');
  END IF;

  IF p_texte_libre IS NULL OR length(trim(p_texte_libre)) < 20 THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'TEXTE_REQUIS',
                                'error', 'Texte libre obligatoire (min 20 caractères)');
  END IF;

  -- Charger l'événement + check propriété + contestable
  IF p_evenement_type = 'SOIGNANT' THEN
    SELECT id, soignant_id, contestable, decision_admin, reclamation_id
    INTO v_event FROM public.evenements_score_soignant WHERE id = p_evenement_id;
    v_proprio_id := v_event.soignant_id;
  ELSE
    SELECT id, etablissement_id AS proprio_id, contestable, decision_admin, reclamation_id
    INTO v_event FROM public.evenements_score_etab WHERE id = p_evenement_id;
    v_proprio_id := v_event.proprio_id;
  END IF;

  IF v_event.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'EVENT_INTROUVABLE',
                                'error', 'Événement de score introuvable');
  END IF;

  -- Auth : seul le propriétaire peut réclamer
  IF p_evenement_type = 'SOIGNANT' AND v_proprio_id != v_uid THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE',
                                'error', 'Vous n''êtes pas concerné par cet événement');
  END IF;
  IF p_evenement_type = 'ETAB' AND v_proprio_id != mon_etablissement_id() THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE',
                                'error', 'Vous n''êtes pas concerné par cet événement');
  END IF;

  IF NOT v_event.contestable THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_CONTESTABLE',
                                'error', 'Cet événement n''est pas contestable');
  END IF;

  IF v_event.decision_admin IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'DEJA_TRAITE',
                                'error', 'Cet événement a déjà été traité par un admin');
  END IF;

  IF v_event.reclamation_id IS NOT NULL THEN
    SELECT id, statut INTO v_existante FROM public.reclamations_score WHERE id = v_event.reclamation_id;
    IF v_existante.statut = 'PENDING' THEN
      RETURN jsonb_build_object('success', false, 'error_code', 'RECLAMATION_EN_COURS',
                                  'error', 'Une réclamation est déjà ouverte pour cet événement',
                                  'reclamation_id', v_existante.id);
    END IF;
  END IF;

  -- Créer la réclamation
  INSERT INTO public.reclamations_score (
    evenement_type, evenement_soignant_id, evenement_etab_id,
    contesteur_id, motif_categorie, texte_libre, justificatif_storage_path
  ) VALUES (
    p_evenement_type,
    CASE WHEN p_evenement_type = 'SOIGNANT' THEN p_evenement_id ELSE NULL END,
    CASE WHEN p_evenement_type = 'ETAB' THEN p_evenement_id ELSE NULL END,
    v_uid, p_motif_categorie, trim(p_texte_libre), p_justificatif_storage_path
  ) RETURNING id INTO v_reclamation_id;

  -- Lier l'event à la réclamation
  IF p_evenement_type = 'SOIGNANT' THEN
    UPDATE public.evenements_score_soignant SET reclamation_id = v_reclamation_id WHERE id = p_evenement_id;
  ELSE
    UPDATE public.evenements_score_etab SET reclamation_id = v_reclamation_id WHERE id = p_evenement_id;
  END IF;

  -- Notification admin via externalisation
  INSERT INTO public.externalisation_actions (type_action, payload, source, source_id)
  VALUES ('EMAIL_NOTIF', jsonb_build_object(
    'destinataire_role', 'ADMIN',
    'type', 'RECLAMATION_SCORE_NOUVELLE',
    'data', jsonb_build_object(
      'reclamation_id', v_reclamation_id,
      'evenement_type', p_evenement_type,
      'motif_categorie', p_motif_categorie,
      'contesteur_id', v_uid
    )
  ), 'AUTRE', v_reclamation_id);

  -- Audit
  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    v_uid, 'SOIGNANT', 'SYSTEM', 'reclamation_score', v_reclamation_id,
    jsonb_build_object('evenement', 'RECLAMATION_SCORE_CREEE',
                        'event_score_id', p_evenement_id,
                        'event_type', p_evenement_type,
                        'motif_categorie', p_motif_categorie,
                        'justificatif', p_justificatif_storage_path IS NOT NULL)
  );

  RETURN jsonb_build_object('success', true, 'reclamation_id', v_reclamation_id, 'statut', 'PENDING');
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_creer_reclamation_score(uuid, text, text, text, text) TO authenticated;

-- ============================================================
-- 2. fn_mes_reclamations : liste réclamations utilisateur courant
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_mes_reclamations(p_statut text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_result jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', r.id,
    'evenement_type', r.evenement_type,
    'evenement_id', COALESCE(r.evenement_soignant_id, r.evenement_etab_id),
    'motif_categorie', r.motif_categorie,
    'texte_libre', r.texte_libre,
    'justificatif_storage_path', r.justificatif_storage_path,
    'statut', r.statut,
    'decision_admin', r.decision_admin,
    'motif_admin', r.motif_admin,
    'traitee_le', r.traitee_le,
    'cree_le', r.cree_le
  ) ORDER BY r.cree_le DESC), '[]'::jsonb) INTO v_result
  FROM public.reclamations_score r
  WHERE r.contesteur_id = v_uid
    AND (p_statut IS NULL OR r.statut = p_statut);

  RETURN jsonb_build_object('success', true, 'reclamations', v_result);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_mes_reclamations(text) TO authenticated;

-- Audit
INSERT INTO public.journaux_audit (
  acteur_id, type_acteur, action, type_ressource, id_ressource, details
) VALUES (
  '00000000-0000-0000-0000-000000000000', 'SYSTEME',
  'SYSTEM', 'fonction', NULL,
  jsonb_build_object(
    'evenement', 'SPRINT35_PR7_RECLAMATIONS_USER_INSTALLED',
    'pr', 'PR 7 Sprint 3.5',
    'rpcs', ARRAY['fn_creer_reclamation_score', 'fn_mes_reclamations']
  )
);
