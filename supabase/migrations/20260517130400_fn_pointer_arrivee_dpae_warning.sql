-- Sprint 15 PR 4 — Avertissement DPAE non régularisée au pointage
--
-- fn_pointer_arrivee : ajoute un champ `warnings` dans la réponse
-- (sans bloquer le pointage) si le contrat est de type CDD/CDDU/SALARIE
-- et que dpae_numero IS NULL.
--
-- Le soignant peut continuer à pointer (cas urgent, mission déjà commencée)
-- mais voit un avertissement clair. L'UI affichera le warning côté soignant
-- ET notifiera l'établissement via push pour régularisation.
--
-- Préserve toute la logique existante : géofence, code de secours, méthode
-- pointage, mise à jour statut mission EN_COURS.

CREATE OR REPLACE FUNCTION public.fn_pointer_arrivee(
  p_mission_id uuid,
  p_lat numeric DEFAULT NULL,
  p_lng numeric DEFAULT NULL,
  p_precision numeric DEFAULT NULL,
  p_terminal_id text DEFAULT NULL,
  p_modele text DEFAULT NULL,
  p_code_arrivee text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $body$
DECLARE
  v_mission RECORD;
  v_contrat RECORD;
  v_etab RECORD;
  v_distance_m numeric;
  v_perimetre_ok boolean;
  v_methode text;
  v_warnings jsonb := '[]'::jsonb;
BEGIN
  SELECT * INTO v_mission FROM missions WHERE id = p_mission_id;
  IF v_mission IS NULL THEN RETURN '{"error":"Mission introuvable"}'::JSONB; END IF;
  IF v_mission.soignant_assigne_id != auth.uid() THEN RETURN '{"error":"Accès refusé"}'::JSONB; END IF;
  IF v_mission.statut NOT IN ('ASSIGNEE', 'EN_COURS') THEN RETURN '{"error":"Mission non active"}'::JSONB; END IF;

  SELECT * INTO v_contrat FROM contrats_mission WHERE mission_id = p_mission_id AND statut = 'SIGNE_COMPLET';
  IF v_contrat IS NULL THEN RETURN '{"error":"Le contrat doit être signé avant le pointage."}'::JSONB; END IF;

  IF EXISTS (SELECT 1 FROM presences WHERE mission_id = p_mission_id AND soignant_id = auth.uid()) THEN
    RETURN '{"error":"Vous avez déjà pointé votre arrivée."}'::JSONB;
  END IF;

  SELECT adresse_lat, adresse_lng, COALESCE(tolerance_pointage_m, 500) AS tolerance_m
    INTO v_etab FROM etablissements WHERE id = v_mission.etablissement_id;

  IF p_code_arrivee IS NOT NULL THEN
    IF p_code_arrivee != v_mission.code_arrivee THEN
      RETURN jsonb_build_object('success', false, 'error_code', 'CODE_INCORRECT', 'error', 'Code de pointage incorrect.');
    END IF;
    v_methode := 'CODE';
    v_perimetre_ok := true;
    v_distance_m := NULL;
  ELSE
    IF p_lat IS NULL OR p_lng IS NULL THEN
      RETURN jsonb_build_object('success', false, 'error_code', 'GPS_MANQUANT',
        'error', 'Coordonnées GPS requises (ou utilisez le code de secours).');
    END IF;
    IF v_etab.adresse_lat IS NULL OR v_etab.adresse_lng IS NULL THEN
      v_distance_m := NULL;
      v_perimetre_ok := false;
    ELSE
      v_distance_m := public.fn_haversine_distance_m(p_lat, p_lng, v_etab.adresse_lat::numeric, v_etab.adresse_lng::numeric);
      v_perimetre_ok := v_distance_m <= v_etab.tolerance_m;
      IF NOT v_perimetre_ok THEN
        RETURN jsonb_build_object('success', false, 'error_code', 'HORS_PERIMETRE',
          'error', 'Vous êtes à ' || v_distance_m::int || 'm de l''établissement (tolérance ' || v_etab.tolerance_m || 'm). Utilisez le code fourni par l''établissement.',
          'distance_m', v_distance_m, 'tolerance_m', v_etab.tolerance_m);
      END IF;
    END IF;
    v_methode := 'GPS';
  END IF;

  -- Avertissement DPAE non régularisée pour contrat salarié (non-bloquant)
  IF v_contrat.type_contrat IN ('CDD', 'CDDU', 'SALARIE')
     AND COALESCE(v_contrat.dpae_numero, '') = '' THEN
    v_warnings := v_warnings || jsonb_build_object(
      'code', 'DPAE_NON_REGULARISEE',
      'message', 'Votre DPAE URSSAF n''est pas encore enregistrée dans Jolene. L''établissement doit régulariser la déclaration auprès de l''URSSAF et saisir le numéro dans la plateforme.',
      'severite', 'warning'
    );

    -- Push notification à l'établissement pour régularisation (best-effort)
    BEGIN
      PERFORM net.http_post(
        url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/send-push',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
        ),
        body := jsonb_build_object(
          'destinataire_id', v_mission.etablissement_id,
          'type_evenement', 'DPAE_NON_REGULARISEE_POINTAGE',
          'titre', '⚠️ DPAE à régulariser',
          'corps', 'Le soignant vient de pointer sur le contrat ' || COALESCE(v_contrat.numero_contrat, '') || ' mais le numéro URSSAF n''est pas saisi. À régulariser sous 24h.',
          'data', jsonb_build_object('contrat_id', v_contrat.id::text, 'mission_id', p_mission_id::text)
        )
      );
    EXCEPTION WHEN OTHERS THEN NULL; END;
  END IF;

  INSERT INTO presences (
    mission_id, soignant_id, pointage_arrivee_le,
    arrivee_lat, arrivee_lng, arrivee_precision_gps_m,
    arrivee_id_terminal, arrivee_modele_terminal,
    methode_pointage_arrivee, distance_etablissement_m, perimetre_gps_valide
  ) VALUES (
    p_mission_id, auth.uid(), NOW(), p_lat, p_lng, p_precision,
    p_terminal_id, p_modele, v_methode, v_distance_m, v_perimetre_ok
  );

  UPDATE missions SET statut = 'EN_COURS', modifie_le = NOW()
   WHERE id = p_mission_id AND statut = 'ASSIGNEE';

  RETURN jsonb_build_object(
    'success', true,
    'methode', v_methode,
    'distance_m', v_distance_m,
    'perimetre_valide', v_perimetre_ok,
    'warnings', v_warnings
  );
END;
$body$;
