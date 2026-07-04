-- PR 8 Sprint 3.5 — Réclamations admin : décision + propagation auto
--
-- RPC fn_admin_traiter_reclamation : admin Jolene tranche (MAINTENIR /
-- REDUIRE / ANNULER) avec motif obligatoire. Propage la décision sur
-- l'événement de score → recalcul automatique du score.
--
-- RPC fn_admin_lister_reclamations : liste paginée filtrable pour
-- /admin/reclamations-score.

-- ============================================================
-- 1. fn_admin_traiter_reclamation : décision admin + propagation
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_admin_traiter_reclamation(
  p_reclamation_id uuid,
  p_decision text,          -- 'MAINTENIR' | 'REDUIRE' | 'ANNULER'
  p_points_corriges int,    -- requis si REDUIRE
  p_motif_admin text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_rec RECORD;
  v_event_id uuid;
  v_event_type text;
  v_proprio_id uuid;
  v_score jsonb;
BEGIN
  IF v_uid IS NULL OR NOT est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_ADMIN');
  END IF;

  IF p_decision NOT IN ('MAINTENIR', 'REDUIRE', 'ANNULER') THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'DECISION_INVALIDE',
                                'error', 'Décision doit être MAINTENIR, REDUIRE ou ANNULER');
  END IF;

  IF p_motif_admin IS NULL OR length(trim(p_motif_admin)) < 10 THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'MOTIF_ADMIN_REQUIS',
                                'error', 'Motif admin obligatoire (min 10 caractères)');
  END IF;

  IF p_decision = 'REDUIRE' AND (p_points_corriges IS NULL OR p_points_corriges >= 0) THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'POINTS_CORRIGES_INVALIDE',
                                'error', 'REDUIRE requiert points_corriges < 0 (ex: -5 au lieu de -10)');
  END IF;

  SELECT * INTO v_rec FROM public.reclamations_score WHERE id = p_reclamation_id;
  IF v_rec IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'RECLAMATION_INTROUVABLE');
  END IF;

  IF v_rec.statut != 'PENDING' THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'DEJA_TRAITEE',
                                'error', 'Réclamation déjà traitée (statut : ' || v_rec.statut || ')');
  END IF;

  v_event_type := v_rec.evenement_type;
  v_event_id := COALESCE(v_rec.evenement_soignant_id, v_rec.evenement_etab_id);

  -- Mettre à jour la réclamation
  UPDATE public.reclamations_score SET
    statut = 'TREATED',
    decision_admin = p_decision,
    motif_admin = trim(p_motif_admin),
    traitee_par_admin_id = v_uid,
    traitee_le = NOW(),
    modifiee_le = NOW()
  WHERE id = p_reclamation_id;

  -- Propager la décision sur l'événement
  IF v_event_type = 'SOIGNANT' THEN
    UPDATE public.evenements_score_soignant SET
      decision_admin = p_decision,
      points_corriges = CASE WHEN p_decision = 'REDUIRE' THEN p_points_corriges ELSE NULL END,
      motif_admin = trim(p_motif_admin),
      traite_par_admin_id = v_uid,
      traite_le = NOW()
    WHERE id = v_event_id
    RETURNING soignant_id INTO v_proprio_id;

    -- Recalcul score auto
    v_score := public.fn_calculer_score_soignant(v_proprio_id);
  ELSE
    UPDATE public.evenements_score_etab SET
      decision_admin = p_decision,
      points_corriges = CASE WHEN p_decision = 'REDUIRE' THEN p_points_corriges ELSE NULL END,
      motif_admin = trim(p_motif_admin),
      traite_par_admin_id = v_uid,
      traite_le = NOW()
    WHERE id = v_event_id
    RETURNING etablissement_id INTO v_proprio_id;

    v_score := public.fn_calculer_score_etab(v_proprio_id);
  END IF;

  -- Notification user (email + push) avec décision et motif
  INSERT INTO public.externalisation_actions (type_action, payload, source, source_id)
  VALUES
    ('EMAIL_NOTIF', jsonb_build_object(
      'destinataire_id', v_rec.contesteur_id,
      'type', 'RECLAMATION_SCORE_DECISION',
      'data', jsonb_build_object(
        'reclamation_id', p_reclamation_id,
        'decision', p_decision,
        'motif_admin', p_motif_admin,
        'points_corriges', p_points_corriges,
        'nouveau_score', (v_score->>'score_total')::int
      )
    ), 'AUTRE', p_reclamation_id),
    ('PUSH_NOTIF', jsonb_build_object(
      'destinataire_id', v_rec.contesteur_id,
      'type_evenement', 'RECLAMATION_SCORE_DECISION',
      'titre', CASE p_decision
        WHEN 'ANNULER' THEN 'Réclamation acceptée ✅'
        WHEN 'REDUIRE' THEN 'Réclamation partiellement acceptée'
        ELSE 'Réclamation examinée'
      END,
      'corps', 'Votre score a été mis à jour. Consultez votre profil pour le détail.'
    ), 'AUTRE', p_reclamation_id);

  -- Audit
  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    v_uid, 'ADMIN_PLATEFORME', 'ADMIN_ACTION', 'reclamation_score', p_reclamation_id,
    jsonb_build_object(
      'evenement', 'RECLAMATION_SCORE_TRAITEE',
      'decision', p_decision,
      'points_corriges', p_points_corriges,
      'motif_admin', p_motif_admin,
      'event_id', v_event_id, 'event_type', v_event_type,
      'nouveau_score', v_score
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'reclamation_id', p_reclamation_id,
    'decision', p_decision,
    'event_id', v_event_id,
    'nouveau_score', v_score
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_admin_traiter_reclamation(uuid, text, int, text) TO authenticated;

-- ============================================================
-- 2. fn_admin_lister_reclamations : liste pour /admin/reclamations-score
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_admin_lister_reclamations(
  p_statut text DEFAULT 'PENDING',
  p_limit int DEFAULT 50
)
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
  IF v_uid IS NULL OR NOT est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Admin requis');
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', r.id,
    'evenement_type', r.evenement_type,
    'evenement_id', COALESCE(r.evenement_soignant_id, r.evenement_etab_id),
    'event_type_evenement',
      COALESCE((SELECT type_evenement FROM public.evenements_score_soignant WHERE id = r.evenement_soignant_id),
                (SELECT type_evenement FROM public.evenements_score_etab WHERE id = r.evenement_etab_id)),
    'event_points',
      COALESCE((SELECT points FROM public.evenements_score_soignant WHERE id = r.evenement_soignant_id),
                (SELECT points FROM public.evenements_score_etab WHERE id = r.evenement_etab_id)),
    'event_motif',
      COALESCE((SELECT motif FROM public.evenements_score_soignant WHERE id = r.evenement_soignant_id),
                (SELECT motif FROM public.evenements_score_etab WHERE id = r.evenement_etab_id)),
    'event_cree_le',
      COALESCE((SELECT cree_le FROM public.evenements_score_soignant WHERE id = r.evenement_soignant_id),
                (SELECT cree_le FROM public.evenements_score_etab WHERE id = r.evenement_etab_id)),
    'contesteur_id', r.contesteur_id,
    'motif_categorie', r.motif_categorie,
    'texte_libre', r.texte_libre,
    'justificatif_storage_path', r.justificatif_storage_path,
    'statut', r.statut,
    'decision_admin', r.decision_admin,
    'motif_admin', r.motif_admin,
    'cree_le', r.cree_le,
    'jours_attente', EXTRACT(EPOCH FROM (NOW() - r.cree_le)) / 86400
  ) ORDER BY r.cree_le ASC), '[]'::jsonb) INTO v_result
  FROM public.reclamations_score r
  WHERE (p_statut IS NULL OR p_statut = 'TOUS' OR r.statut = p_statut)
  LIMIT p_limit;

  RETURN jsonb_build_object('success', true, 'reclamations', v_result);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_admin_lister_reclamations(text, int) TO authenticated;

-- Audit
INSERT INTO public.journaux_audit (
  acteur_id, type_acteur, action, type_ressource, id_ressource, details
) VALUES (
  '00000000-0000-0000-0000-000000000000', 'SYSTEME',
  'SYSTEM', 'fonction', NULL,
  jsonb_build_object(
    'evenement', 'SPRINT35_PR8_RECLAMATIONS_ADMIN_INSTALLED',
    'pr', 'PR 8 Sprint 3.5',
    'rpcs', ARRAY['fn_admin_traiter_reclamation', 'fn_admin_lister_reclamations'],
    'workflow', 'admin tranche → propagation auto event score → recalcul score → notif user'
  )
);
