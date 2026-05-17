-- Sprint 15 PR 5 — Hardening search_path immutable (4 fonctions)
--
-- Fix advisor `function_search_path_mutable` Supabase pour 4 fonctions
-- qui n'avaient pas SET search_path :
--   - fn_trg_articles_aide_updated_at (trigger updated_at simple)
--   - fn_trg_pn_updated_at (trigger updated_at simple — preferences_notifications)
--   - fn_evaluer_coherence_pointage (IMMUTABLE pure jsonb assembly)
--   - fn_mission_est_de_nuit (IMMUTABLE pure boolean compute)
--
-- Pattern Jolene standard : SET search_path TO 'public'.
-- Aucune dépendance d'extension non-public utilisée par ces 4 fonctions.

CREATE OR REPLACE FUNCTION public.fn_trg_articles_aide_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $body$
BEGIN
  NEW.mis_a_jour_le := now();
  RETURN NEW;
END;
$body$;

CREATE OR REPLACE FUNCTION public.fn_trg_pn_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $body$
BEGIN
  NEW.mis_a_jour_le := now();
  RETURN NEW;
END;
$body$;

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
SET search_path TO 'public'
AS $body$
DECLARE
  v_incidents jsonb := '[]'::jsonb;
BEGIN
  IF p_pointage_arrivee IS NOT NULL AND p_pointage_arrivee < p_mission_debut - INTERVAL '1 hour' THEN
    v_incidents := v_incidents || jsonb_build_object(
      'code', 'ARRIVEE_TROP_PRECOCE',
      'severite', 'WARNING',
      'message', 'Arrivée pointée plus d''1h avant le début prévu',
      'ecart_min', EXTRACT(EPOCH FROM (p_mission_debut - p_pointage_arrivee))/60
    );
  END IF;

  IF p_pointage_arrivee IS NOT NULL AND p_pointage_arrivee > p_mission_fin THEN
    v_incidents := v_incidents || jsonb_build_object(
      'code', 'ARRIVEE_APRES_FIN',
      'severite', 'CRITICAL',
      'message', 'Arrivée pointée après l''heure de fin de mission',
      'ecart_min', EXTRACT(EPOCH FROM (p_pointage_arrivee - p_mission_fin))/60
    );
  END IF;

  IF p_pointage_arrivee IS NOT NULL AND p_pointage_depart IS NOT NULL
     AND p_pointage_depart < p_pointage_arrivee THEN
    v_incidents := v_incidents || jsonb_build_object(
      'code', 'DEPART_AVANT_ARRIVEE',
      'severite', 'CRITICAL',
      'message', 'Heure de départ antérieure à l''arrivée'
    );
  END IF;

  IF p_pointage_depart IS NOT NULL AND p_pointage_depart < p_mission_fin - INTERVAL '4 hours' THEN
    v_incidents := v_incidents || jsonb_build_object(
      'code', 'DEPART_TRES_ANTICIPE',
      'severite', 'WARNING',
      'message', 'Départ pointé plus de 4h avant la fin prévue',
      'ecart_min', EXTRACT(EPOCH FROM (p_mission_fin - p_pointage_depart))/60
    );
  END IF;

  IF p_pointage_depart IS NOT NULL AND p_pointage_depart > p_mission_fin + INTERVAL '4 hours' THEN
    v_incidents := v_incidents || jsonb_build_object(
      'code', 'DEPART_TRES_TARDIF',
      'severite', 'WARNING',
      'message', 'Départ pointé plus de 4h après la fin prévue',
      'ecart_min', EXTRACT(EPOCH FROM (p_pointage_depart - p_mission_fin))/60
    );
  END IF;

  IF p_duree_nette_min IS NOT NULL THEN
    IF p_duree_nette_min <= 0 THEN
      v_incidents := v_incidents || jsonb_build_object(
        'code', 'DUREE_NULLE',
        'severite', 'CRITICAL',
        'message', 'Durée nette de mission <= 0 minutes'
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

CREATE OR REPLACE FUNCTION public.fn_mission_est_de_nuit(
  p_debut timestamptz,
  p_fin timestamptz
)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO 'public'
AS $body$
DECLARE
  v_heures_nuit numeric := 0;
  v_curseur timestamptz;
  v_curseur_fin timestamptz;
  v_h_debut int;
BEGIN
  v_curseur := p_debut;
  WHILE v_curseur < p_fin LOOP
    v_curseur_fin := LEAST(v_curseur + INTERVAL '30 minutes', p_fin);
    v_h_debut := EXTRACT(HOUR FROM v_curseur)::int;
    IF v_h_debut >= 21 OR v_h_debut < 6 THEN
      v_heures_nuit := v_heures_nuit + EXTRACT(EPOCH FROM (v_curseur_fin - v_curseur)) / 3600.0;
    END IF;
    v_curseur := v_curseur_fin;
  END LOOP;
  RETURN v_heures_nuit >= 3.0;
END;
$body$;
