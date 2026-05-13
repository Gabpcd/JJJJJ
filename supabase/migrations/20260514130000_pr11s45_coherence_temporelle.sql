-- ============================================================================
-- Sprint 4.5 PR 11 — Cohérence temporelle des pointages
-- ============================================================================
-- Détecte les incohérences entre horaires de mission et horaires de pointage :
--   1. Arrivée hors fenêtre [debut-1h, fin]
--   2. Départ avant arrivée (impossible)
--   3. Départ très anticipé (>4h avant fin de mission)
--   4. Départ très tardif (>4h après fin de mission)
--   5. Durée nette aberrante (≤0 ou >24h)
--   6. Pointage solo (arrivée sans départ) après fin mission + 6h
-- Crée des alertes_systeme pour suivi admin (pas d'action auto).
-- ============================================================================

-- 1. Marqueurs sur presences (qu'on n'alerte qu'une fois par incident)
ALTER TABLE public.presences
  ADD COLUMN IF NOT EXISTS coherence_verifiee_le timestamptz,
  ADD COLUMN IF NOT EXISTS coherence_incidents jsonb DEFAULT '[]'::jsonb;

CREATE INDEX IF NOT EXISTS idx_presences_coherence_pending
  ON public.presences(pointage_arrivee_le)
  WHERE coherence_verifiee_le IS NULL;

-- 2. Helper IMMUTABLE pour évaluer la cohérence d'une presence
CREATE OR REPLACE FUNCTION public.fn_evaluer_coherence_pointage(
  p_pointage_arrivee timestamptz,
  p_pointage_depart timestamptz,
  p_mission_debut timestamptz,
  p_mission_fin timestamptz,
  p_duree_nette_min numeric
)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
AS $body$
DECLARE
  v_incidents jsonb := '[]'::jsonb;
BEGIN
  -- 1. Arrivée trop précoce (>1h avant début mission)
  IF p_pointage_arrivee IS NOT NULL AND p_pointage_arrivee < p_mission_debut - INTERVAL '1 hour' THEN
    v_incidents := v_incidents || jsonb_build_object(
      'code', 'ARRIVEE_TROP_PRECOCE',
      'severite', 'WARNING',
      'message', 'Arrivée pointée plus d''1h avant le début prévu',
      'ecart_min', EXTRACT(EPOCH FROM (p_mission_debut - p_pointage_arrivee))/60
    );
  END IF;

  -- 2. Arrivée après fin mission
  IF p_pointage_arrivee IS NOT NULL AND p_pointage_arrivee > p_mission_fin THEN
    v_incidents := v_incidents || jsonb_build_object(
      'code', 'ARRIVEE_APRES_FIN',
      'severite', 'CRITICAL',
      'message', 'Arrivée pointée après l''heure de fin de mission',
      'ecart_min', EXTRACT(EPOCH FROM (p_pointage_arrivee - p_mission_fin))/60
    );
  END IF;

  -- 3. Départ avant arrivée
  IF p_pointage_arrivee IS NOT NULL AND p_pointage_depart IS NOT NULL
     AND p_pointage_depart < p_pointage_arrivee THEN
    v_incidents := v_incidents || jsonb_build_object(
      'code', 'DEPART_AVANT_ARRIVEE',
      'severite', 'CRITICAL',
      'message', 'Heure de départ antérieure à l''arrivée'
    );
  END IF;

  -- 4. Départ très anticipé (>4h avant fin mission)
  IF p_pointage_depart IS NOT NULL AND p_pointage_depart < p_mission_fin - INTERVAL '4 hours' THEN
    v_incidents := v_incidents || jsonb_build_object(
      'code', 'DEPART_TRES_ANTICIPE',
      'severite', 'WARNING',
      'message', 'Départ pointé plus de 4h avant la fin prévue',
      'ecart_min', EXTRACT(EPOCH FROM (p_mission_fin - p_pointage_depart))/60
    );
  END IF;

  -- 5. Départ très tardif (>4h après fin mission)
  IF p_pointage_depart IS NOT NULL AND p_pointage_depart > p_mission_fin + INTERVAL '4 hours' THEN
    v_incidents := v_incidents || jsonb_build_object(
      'code', 'DEPART_TRES_TARDIF',
      'severite', 'WARNING',
      'message', 'Départ pointé plus de 4h après la fin prévue',
      'ecart_min', EXTRACT(EPOCH FROM (p_pointage_depart - p_mission_fin))/60
    );
  END IF;

  -- 6. Durée nette aberrante
  IF p_duree_nette_min IS NOT NULL THEN
    IF p_duree_nette_min <= 0 THEN
      v_incidents := v_incidents || jsonb_build_object(
        'code', 'DUREE_NULLE',
        'severite', 'CRITICAL',
        'message', 'Durée nette de mission ≤ 0 minutes'
      );
    ELSIF p_duree_nette_min > 1440 THEN
      v_incidents := v_incidents || jsonb_build_object(
        'code', 'DUREE_EXCESSIVE',
        'severite', 'WARNING',
        'message', 'Durée nette de mission > 24h',
        'duree_min', p_duree_nette_min
      );
    END IF;
  END IF;

  RETURN v_incidents;
END;
$body$;

-- 3. Worker : vérifie les presences et crée des alertes pour les incidents
CREATE OR REPLACE FUNCTION public.fn_verifier_pointages_incoherents()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $body$
DECLARE
  v_presence record;
  v_mission record;
  v_incidents jsonb;
  v_incident jsonb;
  v_severite_max text;
  v_count_verifiees integer := 0;
  v_count_alertes integer := 0;
BEGIN
  -- Vérifie les presences :
  --  - pas encore vérifiées (coherence_verifiee_le IS NULL)
  --  - dont la mission est terminée depuis au moins 1h (ou pointage arrivée >2h sans départ)
  FOR v_presence IN
    SELECT p.*
    FROM public.presences p
    JOIN public.missions m ON m.id = p.mission_id
    WHERE p.coherence_verifiee_le IS NULL
      AND (
        (p.pointage_depart_le IS NOT NULL AND m.fin_le < now() - INTERVAL '1 hour')
        OR (p.pointage_arrivee_le IS NOT NULL AND p.pointage_depart_le IS NULL AND m.fin_le < now() - INTERVAL '6 hours')
      )
    LIMIT 500
  LOOP
    SELECT * INTO v_mission FROM public.missions WHERE id = v_presence.mission_id;
    CONTINUE WHEN v_mission IS NULL;

    v_incidents := public.fn_evaluer_coherence_pointage(
      v_presence.pointage_arrivee_le,
      v_presence.pointage_depart_le,
      v_mission.debut_le,
      v_mission.fin_le,
      v_presence.duree_nette_min
    );

    -- Cas spécial : arrivée sans départ après fin mission + 6h
    IF v_presence.pointage_arrivee_le IS NOT NULL
       AND v_presence.pointage_depart_le IS NULL
       AND v_mission.fin_le < now() - INTERVAL '6 hours' THEN
      v_incidents := v_incidents || jsonb_build_object(
        'code', 'DEPART_MANQUANT',
        'severite', 'CRITICAL',
        'message', 'Arrivée pointée mais aucun départ enregistré'
      );
    END IF;

    -- Calcule sévérité max
    v_severite_max := NULL;
    FOR v_incident IN SELECT * FROM jsonb_array_elements(v_incidents)
    LOOP
      IF v_incident->>'severite' = 'CRITICAL' THEN
        v_severite_max := 'CRITICAL';
        EXIT;
      ELSIF v_incident->>'severite' = 'WARNING' AND v_severite_max IS NULL THEN
        v_severite_max := 'WARNING';
      END IF;
    END LOOP;

    -- Marque la presence comme vérifiée
    UPDATE public.presences
    SET coherence_verifiee_le = now(),
        coherence_incidents = v_incidents
    WHERE id = v_presence.id;
    v_count_verifiees := v_count_verifiees + 1;

    -- Crée une alerte_systeme si incident détecté
    IF jsonb_array_length(v_incidents) > 0 THEN
      INSERT INTO public.alertes_systeme (
        type_alerte, severite, source, message, details
      ) VALUES (
        'POINTAGE_INCOHERENT',
        COALESCE(v_severite_max, 'WARNING'),
        'cron:jolene_verifier_pointages_incoherents',
        format('Incident pointage mission %s (soignant %s)', v_mission.id, v_presence.soignant_id),
        jsonb_build_object(
          'mission_id', v_mission.id,
          'presence_id', v_presence.id,
          'soignant_id', v_presence.soignant_id,
          'etablissement_id', v_mission.etablissement_id,
          'mission_debut', v_mission.debut_le,
          'mission_fin', v_mission.fin_le,
          'pointage_arrivee', v_presence.pointage_arrivee_le,
          'pointage_depart', v_presence.pointage_depart_le,
          'duree_nette_min', v_presence.duree_nette_min,
          'incidents', v_incidents
        )
      );
      v_count_alertes := v_count_alertes + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'verifiees', v_count_verifiees,
    'alertes', v_count_alertes,
    'horodatage', now()
  );
END;
$body$;

GRANT EXECUTE ON FUNCTION public.fn_verifier_pointages_incoherents() TO service_role;

-- 4. pg_cron : toutes les 30 min
DO $body$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('jolene_verifier_pointages_incoherents') WHERE EXISTS (
      SELECT 1 FROM cron.job WHERE jobname = 'jolene_verifier_pointages_incoherents'
    );
    PERFORM cron.schedule(
      'jolene_verifier_pointages_incoherents',
      '*/30 * * * *',
      'SELECT public.fn_verifier_pointages_incoherents()'
    );
  END IF;
END;
$body$;

-- 5. Audit migration
INSERT INTO public.journaux_audit (
  acteur_id, type_acteur, action, type_ressource, id_ressource, details
) VALUES (
  '00000000-0000-0000-0000-000000000000', 'SYSTEME',
  'SYSTEM', 'fonction', NULL,
  jsonb_build_object(
    'evenement', 'SPRINT45_PR11_COHERENCE_TEMPORELLE_INSTALLED',
    'pr', 'PR 11 Sprint 4.5',
    'rpcs', jsonb_build_array('fn_evaluer_coherence_pointage', 'fn_verifier_pointages_incoherents'),
    'colonnes_ajoutees', jsonb_build_array('presences.coherence_verifiee_le', 'presences.coherence_incidents'),
    'cron', 'jolene_verifier_pointages_incoherents */30 min'
  )
);
