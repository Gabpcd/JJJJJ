-- Lot 13 — Validation des présences : audit côté SQL, notification soignant,
-- tolérance GPS réelle dans l'antifraude, CHECK notifications réaligné.
--
-- Constats (09/07/2026, définitions LIVE via pg_get_functiondef — règle 9.0) :
--   1. fn_valider_presence / fn_valider_presences_lot n'écrivaient AUCUN audit
--      côté SQL (seulement côté client → absent pour tout chemin non-UI).
--   2. Aucune notification au soignant à la validation de sa présence.
--   3. notifications_type_check ne contenait PAS 'CONTESTATION_PRESENCE',
--      pourtant utilisé par PanneauContestation → la notif de contestation
--      échouait EN SILENCE en prod (pattern incident Sprint 17 : CHECK
--      désynchronisé du code).
--   4. dec_antifraude_presence : périmètre 500 m CODÉ EN DUR, ignorant
--      etablissements.tolerance_pointage_m (le réglage Urbain/Rural/Campus
--      n'avait aucun effet sur les alertes HORS_PERIMETRE).

-- ── 1. CHECK notifications : + CONTESTATION_PRESENCE + PRESENCE_VALIDEE ──────
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check CHECK (type = ANY (ARRAY[
  'CANDIDATURE_ACCEPTEE','CANDIDATURE_REFUSEE','CANDIDATURE_PROPOSEE','CANDIDATURE_RECUE',
  'MISSION_ACCEPTEE','MISSION_ANNULEE','MISSION_TERMINEE','MISSION_URGENTE','MISSION_NON_POURVUE',
  'MISSION_ASSIGNEE','MISSION_A_POURVOIR','CONTRAT_A_SIGNER','CONTRAT_SIGNE','FACTURE_EMISE',
  'FACTURE_PAYEE','DOCUMENT_EXPIRANT','RAPPEL_DOCUMENTS','DOCUMENT_VERIFIE','DOCUMENT_REJETE',
  'MESSAGE_RECU','MESSAGE_ADMIN','POINTAGE_ARRIVEE','POINTAGE_DEPART','EVALUATION_RECUE',
  'PARRAINAGE','CREDIT_PARRAINAGE','PARRAINAGE_PRIME_VERSEE','RAPPEL_MISSION','RAPPEL_CANDIDATURES',
  'POOL_URGENCE','POOL_URGENCE_ACCEPTATION','SYSTEM','LITIGE_OUVERT','LITIGE_REPONSE','LITIGE_RESOLU',
  'LITIGE_MEDIATION','LITIGE_RESOLU_AJUSTE','LITIGE_ESCALADE_ADMIN','LITIGE_MEDIATION_PRIORITAIRE',
  'LITIGE_RAPPEL_J1','LITIGE_RAPPEL_J3','LITIGE_RAPPEL_J5','CHORUS_DEPOSEE','CHORUS_MISE_A_DISPOSITION',
  'CHORUS_PAIEMENT_EN_COURS','CHORUS_PAIEMENT_COMPTABILISE','CHORUS_REJETEE','FAVORI_NOUVELLE_MISSION',
  'AVOIR_EMIS','COMMISSION_AJUSTEE','REMBOURSEMENT_MANUEL_A_FAIRE','REMBOURSEMENT_CONFIRME',
  'MATCHING_SUPER_LIKE','FAVORI_MISSION_EXPIRE','RAPPEL_VALIDATION_PRESENCE',
  'CONTESTATION_PRESENCE','PRESENCE_VALIDEE'
]::text[]));

-- ── 2. fn_valider_presence : audit SQL + notification soignant ───────────────
-- Base = définition LIVE (09/07/2026). Ajouts : fn_ecrire_audit + notif.
CREATE OR REPLACE FUNCTION public.fn_valider_presence(p_presence_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_etab_id uuid;
  v_presence record;
BEGIN
  v_etab_id := mon_etablissement_id();
  IF v_etab_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non autorisé');
  END IF;

  SELECT p.* INTO v_presence
  FROM presences p
  JOIN missions m ON m.id = p.mission_id
  WHERE p.id = p_presence_id
    AND m.etablissement_id = v_etab_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Présence introuvable');
  END IF;

  IF v_presence.valide_par_etablissement = true THEN
    RETURN jsonb_build_object('success', false, 'error', 'Déjà validée');
  END IF;

  UPDATE presences
  SET valide_par_etablissement = true,
      valide_le = now(),
      modifie_le = now()
  WHERE id = p_presence_id;

  -- Lot 13 : la transition est auditée CÔTÉ SQL (l'audit client seul manquait
  -- tout chemin non-UI) et le soignant est notifié (déclencheur du paiement).
  PERFORM fn_ecrire_audit(
    v_etab_id, 'ETABLISSEMENT', 'PRESENCE_VALIDATION', 'presence',
    p_presence_id, NULL,
    jsonb_build_object('mission_id', v_presence.mission_id, 'soignant_id', v_presence.soignant_id)
  );
  BEGIN
    PERFORM fn_creer_notification(
      p_destinataire_id   := v_presence.soignant_id,
      p_type_destinataire := 'SOIGNANT',
      p_type              := 'PRESENCE_VALIDEE',
      p_titre             := 'Présence validée',
      p_corps             := 'Vos heures ont été validées par l''établissement. Le paiement suit son cours.',
      p_lien              := '/soignant/presences',
      p_type_ressource    := 'presence',
      p_id_ressource      := p_presence_id
    );
  EXCEPTION WHEN OTHERS THEN
    NULL; -- une notif ratée ne doit jamais annuler une validation.
  END;

  RETURN jsonb_build_object('success', true);
END;
$function$;

-- ── 3. fn_valider_presences_lot : audit SQL + notifications soignants ────────
-- Base = définition LIVE (09/07/2026). Ajouts : collecte des lignes validées,
-- audit + une notification par présence validée.
CREATE OR REPLACE FUNCTION public.fn_valider_presences_lot(p_ids uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_etab_id uuid;
  v_count integer;
  v_row record;
BEGIN
  v_etab_id := mon_etablissement_id();
  IF v_etab_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non autorisé');
  END IF;

  CREATE TEMP TABLE IF NOT EXISTS _validees_lot (presence_id uuid, mission_id uuid, soignant_id uuid) ON COMMIT DROP;
  DELETE FROM _validees_lot;

  WITH maj AS (
    UPDATE presences p
    SET valide_par_etablissement = true,
        valide_le = now(),
        modifie_le = now()
    FROM missions m
    WHERE p.id = ANY(p_ids)
      AND p.mission_id = m.id
      AND m.etablissement_id = v_etab_id
      AND p.valide_par_etablissement = false
      AND p.perimetre_gps_valide = true
      AND (p.alerte_teleportation = false OR p.alerte_teleportation IS NULL)
    RETURNING p.id, p.mission_id, p.soignant_id
  )
  INSERT INTO _validees_lot SELECT id, mission_id, soignant_id FROM maj;

  SELECT count(*) INTO v_count FROM _validees_lot;

  IF v_count > 0 THEN
    PERFORM fn_ecrire_audit(
      v_etab_id, 'ETABLISSEMENT', 'PRESENCE_VALIDATION_LOT', 'presence',
      NULL, NULL,
      jsonb_build_object('nb_validees', v_count, 'presence_ids', (SELECT jsonb_agg(presence_id) FROM _validees_lot))
    );
    FOR v_row IN SELECT * FROM _validees_lot LOOP
      BEGIN
        PERFORM fn_creer_notification(
          p_destinataire_id   := v_row.soignant_id,
          p_type_destinataire := 'SOIGNANT',
          p_type              := 'PRESENCE_VALIDEE',
          p_titre             := 'Présence validée',
          p_corps             := 'Vos heures ont été validées par l''établissement. Le paiement suit son cours.',
          p_lien              := '/soignant/presences',
          p_type_ressource    := 'presence',
          p_id_ressource      := v_row.presence_id
        );
      EXCEPTION WHEN OTHERS THEN
        NULL;
      END;
    END LOOP;
  END IF;

  RETURN jsonb_build_object('success', true, 'nb_validees', v_count);
END;
$function$;

-- ── 4. dec_antifraude_presence : tolérance réelle de l'établissement ─────────
-- Base = définition LIVE (09/07/2026). Seul changement : le périmètre 500 m
-- codé en dur devient COALESCE(tolerance_pointage_m, 500) — le réglage
-- Urbain 100 / Rural 200 / Campus 500 s'applique enfin aux alertes.
CREATE OR REPLACE FUNCTION public.dec_antifraude_presence()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_teleport JSONB;
    v_etab RECORD;
    v_dist NUMERIC;
BEGIN
    IF NEW.pointage_arrivee_le IS NOT NULL AND NEW.arrivee_lat IS NOT NULL THEN
        -- Détection téléportation
        v_teleport := fn_detecter_teleportation(
            NEW.soignant_id, NEW.arrivee_lat, NEW.arrivee_lng, NEW.pointage_arrivee_le
        );
        IF (v_teleport->>'suspect')::BOOLEAN THEN
            NEW.alerte_teleportation := TRUE;
            NEW.alertes_fraude := NEW.alertes_fraude || jsonb_build_array(v_teleport);

            INSERT INTO file_revue_manuelle (type_entite, id_entite, service_en_echec, motif_echec, donnees_originales, priorite)
            VALUES ('ALERTE_FRAUDE', NEW.id, 'GEOLOCALISATION', 'Téléportation détectée', v_teleport, 5);

            PERFORM fn_ecrire_audit(
                NEW.soignant_id, 'SYSTEME', 'PRESENCE_ALERTE_FRAUDE',
                'presence', NEW.id, NULL, v_teleport
            );
        END IF;

        -- Vérification périmètre GPS — tolérance RÉGLÉE par l'établissement
        SELECT e.adresse_lat, e.adresse_lng, COALESCE(e.tolerance_pointage_m, 500) AS tolerance
        INTO v_etab
        FROM missions m JOIN etablissements e ON e.id = m.etablissement_id
        WHERE m.id = NEW.mission_id;

        IF v_etab.adresse_lat IS NOT NULL THEN
            v_dist := 6371000 * acos(LEAST(1.0,
                cos(radians(v_etab.adresse_lat)) * cos(radians(NEW.arrivee_lat))
                * cos(radians(NEW.arrivee_lng) - radians(v_etab.adresse_lng))
                + sin(radians(v_etab.adresse_lat)) * sin(radians(NEW.arrivee_lat))
            ));
            NEW.distance_etablissement_m := ROUND(v_dist, 2);
            NEW.perimetre_gps_valide := (v_dist <= v_etab.tolerance);

            IF NOT NEW.perimetre_gps_valide THEN
                NEW.alertes_fraude := NEW.alertes_fraude || jsonb_build_array(jsonb_build_object(
                    'type_alerte', 'HORS_PERIMETRE',
                    'distance_m', ROUND(v_dist, 2),
                    'distance_max_m', v_etab.tolerance
                ));
            END IF;
        END IF;

        -- Lot 13 (recours) : une anomalie n'est JAMAIS un rejet silencieux — le
        -- soignant est prévenu et peut expliquer/contester depuis ses présences.
        IF NEW.alerte_teleportation OR (NEW.perimetre_gps_valide IS FALSE) THEN
            BEGIN
                PERFORM fn_creer_notification(
                    p_destinataire_id   := NEW.soignant_id,
                    p_type_destinataire := 'SOIGNANT',
                    p_type              := 'SYSTEM',
                    p_titre             := 'Anomalie GPS sur votre pointage',
                    p_corps             := 'Un écart GPS a été détecté sur votre pointage. Votre présence reste enregistrée — vous pouvez apporter une explication depuis vos présences.',
                    p_lien              := '/soignant/presences',
                    p_type_ressource    := 'presence',
                    p_id_ressource      := NEW.id
                );
            EXCEPTION WHEN OTHERS THEN
                NULL; -- la notif ne doit jamais bloquer le pointage.
            END;
        END IF;
    END IF;

    -- Retard de pointage (> 15 min)
    IF NEW.pointage_arrivee_le IS NOT NULL THEN
        DECLARE v_debut_mission TIMESTAMPTZ;
        BEGIN
            SELECT m.debut_le INTO v_debut_mission FROM missions m WHERE m.id = NEW.mission_id;
            IF NEW.pointage_arrivee_le > v_debut_mission + INTERVAL '15 minutes' THEN
                UPDATE soignants SET
                    total_retards_pointage = total_retards_pointage + 1, modifie_le = NOW()
                WHERE id = NEW.soignant_id;
            END IF;
        END;
    END IF;

    RETURN NEW;
END;
$function$;
