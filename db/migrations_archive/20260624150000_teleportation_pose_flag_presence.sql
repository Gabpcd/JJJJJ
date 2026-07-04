-- Fix anti-fraude : le détecteur de téléportation pose désormais le flag
-- presences.alerte_teleportation = true sur la présence suspecte.
--
-- Gap découvert pendant l'audit (re-challenge rigoureux) : tout le mécanisme de
-- blocage anti-téléportation existait et était câblé sur presences.alerte_teleportation :
--   - fn_valider_presences_72h_auto / fn_auto_valider_presences_72h (auto 72h) : gate
--   - fn_valider_presences_lot (validation établissement en lot) : gate
--   - fn_valider_presence (validation unitaire) : PAS de gate → override manuel possible
-- ... MAIS fn_detecter_teleportations ne posait JAMAIS le flag : il loggeait seulement
-- un événement TELEPORTATION_DETECTED dans journaux_audit + notifiait les admins.
--
-- Conséquence : une présence avec téléportation GPS détectée (>200 km/h) s'auto-validait
-- quand même après 72h (et était payée) si l'admin ne contestait pas manuellement à temps.
-- Détection et blocage étaient déconnectés → tout le système anti-fraude présence dormant.
--
-- Correctif : poser alerte_teleportation = true sur la présence destination lors de la
-- détection. Cela active le blocage déjà construit :
--   - auto-validation 72h : bloquée
--   - validation établissement en lot : bloquée
--   - validation unitaire manuelle (fn_valider_presence) : toujours possible (override
--     humain après revue de l'alerte — c'est le « human in the loop » voulu)

CREATE OR REPLACE FUNCTION public.fn_detecter_teleportations()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_alertes_count int := 0;
  v_rec RECORD;
  v_vitesse jsonb;
  v_admin_ids uuid[];
BEGIN
  FOR v_rec IN
    WITH pointages_recents AS (
      SELECT
        p.soignant_id,
        p.pointage_arrivee_le AS ts,
        p.arrivee_lat AS lat, p.arrivee_lng AS lng,
        p.mission_id, p.id AS presence_id,
        'arrivee' AS type_p
      FROM public.presences p
      WHERE p.pointage_arrivee_le > NOW() - INTERVAL '24 hours'
        AND p.arrivee_lat IS NOT NULL AND p.arrivee_lng IS NOT NULL
      UNION ALL
      SELECT
        p.soignant_id,
        p.pointage_depart_le AS ts,
        p.depart_lat AS lat, p.depart_lng AS lng,
        p.mission_id, p.id AS presence_id,
        'depart' AS type_p
      FROM public.presences p
      WHERE p.pointage_depart_le > NOW() - INTERVAL '24 hours'
        AND p.depart_lat IS NOT NULL AND p.depart_lng IS NOT NULL
    ),
    paires AS (
      SELECT
        a.soignant_id,
        a.ts AS ts1, a.lat AS lat1, a.lng AS lng1, a.mission_id AS mission1, a.type_p AS type1,
        LEAD(a.ts) OVER (PARTITION BY a.soignant_id ORDER BY a.ts) AS ts2,
        LEAD(a.lat) OVER (PARTITION BY a.soignant_id ORDER BY a.ts) AS lat2,
        LEAD(a.lng) OVER (PARTITION BY a.soignant_id ORDER BY a.ts) AS lng2,
        LEAD(a.mission_id) OVER (PARTITION BY a.soignant_id ORDER BY a.ts) AS mission2,
        LEAD(a.type_p) OVER (PARTITION BY a.soignant_id ORDER BY a.ts) AS type2,
        LEAD(a.presence_id) OVER (PARTITION BY a.soignant_id ORDER BY a.ts) AS presence2
      FROM pointages_recents a
    )
    SELECT * FROM paires
    WHERE ts2 IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM public.journaux_audit ja
        WHERE ja.action = 'SYSTEM'
          AND ja.details->>'evenement' = 'TELEPORTATION_DETECTED'
          AND ja.details->>'presence_id_destination' = paires.presence2::text
      )
  LOOP
    v_vitesse := public.fn_vitesse_entre_pointages(
      v_rec.lat1, v_rec.lng1, v_rec.ts1,
      v_rec.lat2, v_rec.lng2, v_rec.ts2
    );

    IF (v_vitesse->>'calculable')::boolean AND (v_vitesse->>'teleportation')::boolean THEN
      INSERT INTO public.journaux_audit (
        acteur_id, type_acteur, action, type_ressource, id_ressource, details
      ) VALUES (
        v_rec.soignant_id, 'SOIGNANT', 'SYSTEM', 'presence', v_rec.presence2,
        jsonb_build_object(
          'evenement', 'TELEPORTATION_DETECTED',
          'niveau', 'ALERTE',
          'soignant_id', v_rec.soignant_id,
          'mission_id_source', v_rec.mission1,
          'mission_id_destination', v_rec.mission2,
          'type_pointage_source', v_rec.type1,
          'type_pointage_destination', v_rec.type2,
          'presence_id_destination', v_rec.presence2,
          'ts_source', v_rec.ts1,
          'ts_destination', v_rec.ts2,
          'distance_m', v_vitesse->>'distance_m',
          'duree_h', v_vitesse->>'duree_h',
          'vitesse_kmh', v_vitesse->>'vitesse_kmh'
        )
      );

      -- ACTIVATION DU BLOCAGE : poser le flag sur la présence destination.
      -- Bloque l'auto-validation 72h + la validation établissement en lot ;
      -- la validation unitaire manuelle reste possible (override humain).
      UPDATE public.presences
        SET alerte_teleportation = true, modifie_le = now()
        WHERE id = v_rec.presence2;

      v_alertes_count := v_alertes_count + 1;
    END IF;
  END LOOP;

  IF v_alertes_count > 0 THEN
    v_admin_ids := ARRAY(SELECT id FROM public.fn_list_admin_user_ids());
    IF array_length(v_admin_ids, 1) > 0 THEN
      INSERT INTO public.externalisation_actions (type_action, payload, source, source_id)
      SELECT 'EMAIL_NOTIF', jsonb_build_object(
        'destinataire_id', uid,
        'type', 'ALERTE_TELEPORTATION',
        'data', jsonb_build_object(
          'count', v_alertes_count,
          'lien_admin', 'https://app.jolene.app/admin/journaux-audit?evenement=TELEPORTATION_DETECTED'
        )
      ), 'CRON_ANTI_TRICHE', NULL FROM unnest(v_admin_ids) AS uid;
      INSERT INTO public.externalisation_actions (type_action, payload, source, source_id)
      SELECT 'PUSH_NOTIF', jsonb_build_object(
        'destinataire_id', uid, 'type_evenement', 'ALERTE_ADMIN',
        'titre', '⚠️ ' || v_alertes_count || ' téléportation' || CASE WHEN v_alertes_count > 1 THEN 's' ELSE '' END || ' détectée' || CASE WHEN v_alertes_count > 1 THEN 's' ELSE '' END,
        'corps', 'Vitesse > 200 km/h entre pointages. Vérification requise.',
        'lien', '/admin/journaux-audit'
      ), 'CRON_ANTI_TRICHE', NULL FROM unnest(v_admin_ids) AS uid;
    END IF;
  END IF;

  RETURN jsonb_build_object('success', true, 'alertes_count', v_alertes_count);
END;
$function$;
