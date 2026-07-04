-- PR 6 Sprint 3.5 — Score révisé soignant + nouveau score étab
--
-- Refactor fn_calculer_score_soignant pour intégrer evenements_score_soignant
-- (12 derniers mois, hors événements ANNULES par admin).
-- Création fn_calculer_score_etab parallèle.
--
-- Formules :
--   Score soignant total = note_moyenne_pts (max 40) + comportement_pts (max 40)
--                          + anciennete_pts (max 20). Plafonné 100, plancher 0.
--   Score étab total = note_moyenne_pts (max 40) + comportement_pts (max 40)
--                       + delai_paiement_pts (max 20). Plafonné 100, plancher 0.

-- ============================================================
-- 1. Score soignant révisé v3 (intègre evenements_score_soignant)
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_calculer_score_soignant(p_soignant_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_soignant RECORD;
  v_note_moyenne numeric;
  v_note_count int;
  v_note_pts int := 0;
  v_evt_penalites int;
  v_evt_bonus int;
  v_comportement_pts int;
  v_mois_inscription int;
  v_anciennete_pts int;
  v_score_total int;
BEGIN
  SELECT id, cree_le INTO v_soignant FROM public.soignants WHERE id = p_soignant_id;
  IF v_soignant IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Soignant introuvable');
  END IF;

  -- Composante 1 : note moyenne (40 pts max) — basée sur notes reçues
  SELECT AVG(note), COUNT(*) INTO v_note_moyenne, v_note_count
  FROM public.notations
  WHERE cible_id = p_soignant_id AND cible_type = 'SOIGNANT'
    AND masquee_par_admin IS NOT TRUE
    AND cree_le > NOW() - INTERVAL '12 months';
  IF v_note_count IS NULL OR v_note_count = 0 THEN
    v_note_pts := 28;  -- valeur par défaut neutre (3.5/5 × 8)
  ELSE
    v_note_pts := LEAST(40, GREATEST(0, ROUND(COALESCE(v_note_moyenne, 0) * 8)));
  END IF;

  -- Composante 2 : comportement contractuel (40 pts max)
  -- Base 40 — somme des points pénalités (négatifs) - somme bonus (positifs)
  -- Sur 12 derniers mois, en excluant les events ANNULES par admin
  SELECT
    COALESCE(SUM(CASE
      WHEN decision_admin = 'ANNULER' THEN 0
      WHEN decision_admin = 'REDUIRE' THEN COALESCE(points_corriges, points)
      ELSE points
    END), 0) INTO v_evt_penalites
  FROM public.evenements_score_soignant
  WHERE soignant_id = p_soignant_id
    AND points < 0
    AND cree_le > NOW() - INTERVAL '12 months';

  SELECT
    COALESCE(SUM(CASE
      WHEN decision_admin = 'ANNULER' THEN 0
      WHEN decision_admin = 'REDUIRE' THEN COALESCE(points_corriges, points)
      ELSE points
    END), 0) INTO v_evt_bonus
  FROM public.evenements_score_soignant
  WHERE soignant_id = p_soignant_id
    AND points > 0
    AND cree_le > NOW() - INTERVAL '12 months';

  v_comportement_pts := GREATEST(0, LEAST(40, 40 + v_evt_penalites + v_evt_bonus));

  -- Composante 3 : ancienneté (20 pts max, 1 pt par mois)
  v_mois_inscription := EXTRACT(EPOCH FROM (NOW() - v_soignant.cree_le)) / (30.44 * 86400);
  v_anciennete_pts := LEAST(20, GREATEST(0, v_mois_inscription));

  v_score_total := LEAST(100, GREATEST(0, v_note_pts + v_comportement_pts + v_anciennete_pts));

  RETURN jsonb_build_object(
    'success', true,
    'score_total', v_score_total,
    'composantes', jsonb_build_object(
      'note_moyenne_pts', v_note_pts,
      'note_moyenne_valeur', COALESCE(v_note_moyenne, 0),
      'note_count', COALESCE(v_note_count, 0),
      'comportement_pts', v_comportement_pts,
      'comportement_penalites', v_evt_penalites,
      'comportement_bonus', v_evt_bonus,
      'anciennete_pts', v_anciennete_pts,
      'anciennete_mois', v_mois_inscription
    ),
    'calcul_le', NOW()
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_calculer_score_soignant(uuid) TO authenticated;

-- ============================================================
-- 2. Score étab (création)
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_calculer_score_etab(p_etablissement_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_etab RECORD;
  v_note_moyenne numeric;
  v_note_count int;
  v_note_pts int := 0;
  v_evt_penalites int;
  v_evt_bonus int;
  v_comportement_pts int;
  v_delai_moyen_jours numeric;
  v_delai_paiement_pts int;
  v_score_total int;
BEGIN
  SELECT id, cree_le INTO v_etab FROM public.etablissements WHERE id = p_etablissement_id;
  IF v_etab IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Établissement introuvable');
  END IF;

  -- Composante 1 : note moyenne donnée par les soignants (40 pts max)
  SELECT AVG(note), COUNT(*) INTO v_note_moyenne, v_note_count
  FROM public.notations
  WHERE cible_id = p_etablissement_id AND cible_type = 'ETABLISSEMENT'
    AND masquee_par_admin IS NOT TRUE
    AND cree_le > NOW() - INTERVAL '12 months';
  IF v_note_count IS NULL OR v_note_count = 0 THEN
    v_note_pts := 28;
  ELSE
    v_note_pts := LEAST(40, GREATEST(0, ROUND(COALESCE(v_note_moyenne, 0) * 8)));
  END IF;

  -- Composante 2 : comportement contractuel (40 pts max)
  SELECT
    COALESCE(SUM(CASE
      WHEN decision_admin = 'ANNULER' THEN 0
      WHEN decision_admin = 'REDUIRE' THEN COALESCE(points_corriges, points)
      ELSE points
    END), 0) INTO v_evt_penalites
  FROM public.evenements_score_etab
  WHERE etablissement_id = p_etablissement_id
    AND points < 0
    AND cree_le > NOW() - INTERVAL '12 months';

  SELECT
    COALESCE(SUM(CASE
      WHEN decision_admin = 'ANNULER' THEN 0
      WHEN decision_admin = 'REDUIRE' THEN COALESCE(points_corriges, points)
      ELSE points
    END), 0) INTO v_evt_bonus
  FROM public.evenements_score_etab
  WHERE etablissement_id = p_etablissement_id
    AND points > 0
    AND cree_le > NOW() - INTERVAL '12 months';

  v_comportement_pts := GREATEST(0, LEAST(40, 40 + v_evt_penalites + v_evt_bonus));

  -- Composante 3 : délai moyen de paiement (20 pts max)
  -- Sur les 12 derniers mois, écart entre date_emission et date_paiement
  SELECT AVG(EXTRACT(EPOCH FROM (date_paiement - date_emission)) / 86400)
  INTO v_delai_moyen_jours
  FROM public.factures
  WHERE etablissement_id = p_etablissement_id
    AND date_paiement IS NOT NULL
    AND date_emission IS NOT NULL
    AND date_emission > NOW() - INTERVAL '12 months';

  v_delai_paiement_pts := CASE
    WHEN v_delai_moyen_jours IS NULL THEN 15  -- défaut neutre si pas de data
    WHEN v_delai_moyen_jours <= 7 THEN 20
    WHEN v_delai_moyen_jours <= 15 THEN 15
    WHEN v_delai_moyen_jours <= 30 THEN 10
    ELSE 5
  END;

  v_score_total := LEAST(100, GREATEST(0, v_note_pts + v_comportement_pts + v_delai_paiement_pts));

  RETURN jsonb_build_object(
    'success', true,
    'score_total', v_score_total,
    'composantes', jsonb_build_object(
      'note_moyenne_pts', v_note_pts,
      'note_moyenne_valeur', COALESCE(v_note_moyenne, 0),
      'note_count', COALESCE(v_note_count, 0),
      'comportement_pts', v_comportement_pts,
      'comportement_penalites', v_evt_penalites,
      'comportement_bonus', v_evt_bonus,
      'delai_paiement_pts', v_delai_paiement_pts,
      'delai_paiement_jours_moy', v_delai_moyen_jours
    ),
    'calcul_le', NOW()
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_calculer_score_etab(uuid) TO authenticated;

-- ============================================================
-- 3. RPC publique fn_mon_score (raccourci UI)
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_mon_score()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_etab_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;
  IF EXISTS (SELECT 1 FROM public.soignants WHERE id = v_uid) THEN
    RETURN public.fn_calculer_score_soignant(v_uid);
  END IF;
  v_etab_id := mon_etablissement_id();
  IF v_etab_id IS NOT NULL THEN
    RETURN public.fn_calculer_score_etab(v_etab_id);
  END IF;
  RETURN jsonb_build_object('success', false, 'error', 'Profil non identifié');
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_mon_score() TO authenticated;

-- ============================================================
-- 4. RPC liste événements score impactants récents
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_mes_evenements_score(p_limit int DEFAULT 20)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_etab_id uuid;
  v_events jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;

  IF EXISTS (SELECT 1 FROM public.soignants WHERE id = v_uid) THEN
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', id, 'type_evenement', type_evenement, 'points', points,
      'points_corriges', points_corriges, 'motif', motif,
      'contestable', contestable AND decision_admin IS NULL AND reclamation_id IS NULL,
      'decision_admin', decision_admin, 'cree_le', cree_le,
      'mission_id', mission_id
    ) ORDER BY cree_le DESC), '[]'::jsonb)
    INTO v_events
    FROM (
      SELECT * FROM public.evenements_score_soignant
      WHERE soignant_id = v_uid
        AND cree_le > NOW() - INTERVAL '12 months'
      ORDER BY cree_le DESC LIMIT p_limit
    ) t;
    RETURN jsonb_build_object('success', true, 'type', 'SOIGNANT', 'events', v_events);
  END IF;

  v_etab_id := mon_etablissement_id();
  IF v_etab_id IS NOT NULL THEN
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', id, 'type_evenement', type_evenement, 'points', points,
      'points_corriges', points_corriges, 'motif', motif,
      'contestable', contestable AND decision_admin IS NULL AND reclamation_id IS NULL,
      'decision_admin', decision_admin, 'cree_le', cree_le,
      'mission_id', mission_id
    ) ORDER BY cree_le DESC), '[]'::jsonb)
    INTO v_events
    FROM (
      SELECT * FROM public.evenements_score_etab
      WHERE etablissement_id = v_etab_id
        AND cree_le > NOW() - INTERVAL '12 months'
      ORDER BY cree_le DESC LIMIT p_limit
    ) t;
    RETURN jsonb_build_object('success', true, 'type', 'ETAB', 'events', v_events);
  END IF;

  RETURN jsonb_build_object('success', false, 'error', 'Profil non identifié');
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_mes_evenements_score(int) TO authenticated;

-- Audit
INSERT INTO public.journaux_audit (
  acteur_id, type_acteur, action, type_ressource, id_ressource, details
) VALUES (
  '00000000-0000-0000-0000-000000000000', 'SYSTEME',
  'SYSTEM', 'fonction', NULL,
  jsonb_build_object(
    'evenement', 'SPRINT35_PR6_SCORES_REVISES_INSTALLED',
    'pr', 'PR 6 Sprint 3.5',
    'rpcs', ARRAY['fn_calculer_score_soignant (v3 intègre evenements)',
                   'fn_calculer_score_etab (création)',
                   'fn_mon_score', 'fn_mes_evenements_score'],
    'formule_soignant', '40 (note moyenne ×8) + 40 (comportement: base 40 + Σ events 12m) + 20 (ancienneté: 1pt/mois)',
    'formule_etab', '40 (note moyenne ×8) + 40 (comportement) + 20 (délai paiement)',
    'note', 'Events avec decision_admin=ANNULER neutralisés. REDUIRE → points_corriges utilisé.'
  )
);
