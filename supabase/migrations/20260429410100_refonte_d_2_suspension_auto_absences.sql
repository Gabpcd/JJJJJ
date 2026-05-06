-- Refonte.D.2 — Suspension auto soignants après 3 absences sans prévenir sur 6 mois
--
-- Distinction ABSENCE vs absence sans prévenir : flag boolean missions.absence_sans_prevenir
-- (sans modifier l'enum statut_mission utilisé partout).
-- Compteur dénormalisé soignants.nb_absences_sans_prevenir_6_mois.
-- À 3 absences sans prévenir 6 mois → statut_compte = SUSPENDU + notif + email + audit.
-- + bloque fn_postuler_mission si statut_compte != ACTIF.

-- 1) Colonne flag mission
ALTER TABLE public.missions
  ADD COLUMN IF NOT EXISTS absence_sans_prevenir BOOLEAN NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_missions_absence_sans_prevenir
  ON public.missions (soignant_assigne_id, statut, absence_sans_prevenir)
  WHERE absence_sans_prevenir = true;

-- 2) Compteur soignants
ALTER TABLE public.soignants
  ADD COLUMN IF NOT EXISTS nb_absences_sans_prevenir_6_mois INT NOT NULL DEFAULT 0;

-- 3) Trigger compteur + suspension auto
CREATE OR REPLACE FUNCTION public.fn_trg_compteur_absences_sans_prevenir()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_nb_total INT;
  v_soignant_email TEXT;
  v_soignant_prenom TEXT;
  v_url TEXT;
  v_token TEXT;
BEGIN
  IF NEW.statut <> 'ABSENCE' THEN RETURN NEW; END IF;
  IF COALESCE(NEW.absence_sans_prevenir, false) = false THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' AND COALESCE(OLD.absence_sans_prevenir, false) = COALESCE(NEW.absence_sans_prevenir, false)
     AND OLD.statut = NEW.statut THEN RETURN NEW; END IF;

  IF NEW.soignant_assigne_id IS NULL THEN RETURN NEW; END IF;

  SELECT COUNT(*) INTO v_nb_total
  FROM missions
  WHERE soignant_assigne_id = NEW.soignant_assigne_id
    AND statut = 'ABSENCE' AND absence_sans_prevenir = true
    AND COALESCE(fin_le, debut_le) >= NOW() - INTERVAL '6 months';

  UPDATE soignants
  SET nb_absences_sans_prevenir_6_mois = v_nb_total, modifie_le = NOW()
  WHERE id = NEW.soignant_assigne_id;

  IF v_nb_total >= 3 THEN
    SELECT email, prenom INTO v_soignant_email, v_soignant_prenom
    FROM soignants WHERE id = NEW.soignant_assigne_id;

    UPDATE soignants
    SET statut_compte = 'SUSPENDU',
        suspension_raison = 'Suspension auto : 3 absences sans prévenir sur 6 mois',
        suspension_le = NOW(), modifie_le = NOW()
    WHERE id = NEW.soignant_assigne_id AND statut_compte = 'ACTIF';

    IF FOUND THEN
      INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien)
      VALUES (
        NEW.soignant_assigne_id, 'SOIGNANT', 'SYSTEM',
        '🚫 Compte suspendu',
        'Votre compte est suspendu suite à 3 absences sans prévenir sur 6 mois. Pour faire un recours, écrivez à bonjour@jolene.app.',
        '/soignant/profil'
      );

      PERFORM public.fn_ecrire_audit_safe(
        p_acteur_id := NEW.soignant_assigne_id, p_type_acteur := 'SYSTEME',
        p_action := 'COMPTE_SUSPENDU', p_type_ressource := 'soignant', p_id_ressource := NEW.soignant_assigne_id,
        p_details := jsonb_build_object('raison', 'auto_3_absences_sans_prevenir_6m', 'mission_declencheur', NEW.id, 'nb_absences', v_nb_total)
      );

      BEGIN
        v_url := public.fn_lire_secret_cron('supabase_url');
        v_token := public.fn_lire_secret_cron('service_role_key');
        IF v_url IS NOT NULL AND v_token IS NOT NULL THEN
          PERFORM net.http_post(
            url := v_url || '/functions/v1/send-email',
            headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_token),
            body := jsonb_build_object(
              'type', 'COMPTE_SUSPENDU',
              'destinataire_id', NEW.soignant_assigne_id,
              'data', jsonb_build_object('prenom', v_soignant_prenom, 'raison', 'absences_sans_prevenir', 'nb_absences', v_nb_total)
            )
          );
        END IF;
      EXCEPTION WHEN OTHERS THEN NULL;
      END;
    END IF;
  END IF;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_compteur_absences_sans_prevenir ON public.missions;
CREATE TRIGGER trg_compteur_absences_sans_prevenir
  AFTER INSERT OR UPDATE OF statut, absence_sans_prevenir ON public.missions
  FOR EACH ROW EXECUTE FUNCTION public.fn_trg_compteur_absences_sans_prevenir();

-- 4) RPC admin marquer absence sans prévenir
CREATE OR REPLACE FUNCTION public.fn_admin_marquer_absence_sans_prevenir(p_mission_id UUID, p_motif TEXT DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE v_uid UUID := auth.uid(); v_mission RECORD;
BEGIN
  IF NOT est_admin() THEN RETURN jsonb_build_object('success', false, 'error', 'Accès admin uniquement'); END IF;

  SELECT id, statut, soignant_assigne_id INTO v_mission FROM missions WHERE id = p_mission_id;
  IF v_mission IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'Mission introuvable'); END IF;
  IF v_mission.statut <> 'ABSENCE' THEN RETURN jsonb_build_object('success', false, 'error', 'Mission doit être en statut ABSENCE'); END IF;

  UPDATE missions SET absence_sans_prevenir = true, modifie_le = NOW() WHERE id = p_mission_id;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid, p_type_acteur := 'ADMIN_PLATEFORME',
    p_action := 'ADMIN_ACTION', p_type_ressource := 'mission', p_id_ressource := p_mission_id,
    p_details := jsonb_build_object('action', 'absence_sans_prevenir_marquee', 'motif', p_motif, 'soignant_id', v_mission.soignant_assigne_id)
  );

  RETURN jsonb_build_object('success', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_admin_marquer_absence_sans_prevenir(UUID, TEXT) TO authenticated;

-- 5) RPC admin lever suspension
CREATE OR REPLACE FUNCTION public.fn_admin_lever_suspension(p_soignant_id UUID, p_raison TEXT)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE v_uid UUID := auth.uid(); v_soignant RECORD; v_url TEXT; v_token TEXT;
BEGIN
  IF NOT est_admin() THEN RETURN jsonb_build_object('success', false, 'error', 'Accès admin uniquement'); END IF;
  IF p_raison IS NULL OR LENGTH(TRIM(p_raison)) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Raison requise');
  END IF;

  SELECT id, prenom, statut_compte INTO v_soignant FROM soignants WHERE id = p_soignant_id;
  IF v_soignant IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'Soignant introuvable'); END IF;
  IF v_soignant.statut_compte = 'ACTIF' THEN RETURN jsonb_build_object('success', false, 'error', 'Compte déjà actif'); END IF;

  UPDATE soignants SET
    statut_compte = 'ACTIF', suspension_raison = NULL, suspension_le = NULL,
    nb_absences_sans_prevenir_6_mois = 0, modifie_le = NOW()
  WHERE id = p_soignant_id;

  INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien)
  VALUES (
    p_soignant_id, 'SOIGNANT', 'SYSTEM',
    '✅ Compte réactivé',
    'Votre compte est réactivé. Vous pouvez à nouveau candidater aux missions. Raison : ' || p_raison,
    '/soignant/tableau-de-bord'
  );

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid, p_type_acteur := 'ADMIN_PLATEFORME',
    p_action := 'COMPTE_LEVEE_SUSPENSION', p_type_ressource := 'soignant', p_id_ressource := p_soignant_id,
    p_details := jsonb_build_object('raison', p_raison)
  );

  BEGIN
    v_url := public.fn_lire_secret_cron('supabase_url');
    v_token := public.fn_lire_secret_cron('service_role_key');
    IF v_url IS NOT NULL AND v_token IS NOT NULL THEN
      PERFORM net.http_post(
        url := v_url || '/functions/v1/send-email',
        headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_token),
        body := jsonb_build_object(
          'type', 'COMPTE_REACTIVE', 'destinataire_id', p_soignant_id,
          'data', jsonb_build_object('prenom', v_soignant.prenom, 'raison', p_raison)
        )
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN jsonb_build_object('success', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_admin_lever_suspension(UUID, TEXT) TO authenticated;

-- 6) Patch fn_postuler_mission : bloque si statut_compte != ACTIF
CREATE OR REPLACE FUNCTION public.fn_postuler_mission(p_mission_id uuid, p_message text DEFAULT NULL::text, p_choix_contrat text DEFAULT NULL::text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
    v_mission RECORD; v_soignant RECORD; v_rcp_valide BOOLEAN; v_choix_final TEXT;
    v_compatible BOOLEAN; v_specialite_label TEXT;
BEGIN
    SELECT * INTO v_mission FROM missions WHERE id = p_mission_id;
    IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Mission introuvable'); END IF;
    IF v_mission.statut != 'OUVERTE' THEN RETURN jsonb_build_object('error', 'Cette mission n''est plus disponible'); END IF;
    IF v_mission.mode_attribution != 'CANDIDATURE' THEN RETURN jsonb_build_object('error', 'Cette mission n''accepte pas les candidatures'); END IF;

    SELECT * INTO v_soignant FROM soignants WHERE id = auth.uid();
    IF v_soignant IS NULL THEN RETURN jsonb_build_object('error', 'Profil soignant introuvable'); END IF;

    -- J5 Refonte.D.2 : blocage si compte non-actif
    IF COALESCE(v_soignant.statut_compte::text, 'ACTIF') <> 'ACTIF' THEN
      RETURN jsonb_build_object('error',
        'Votre compte est ' || v_soignant.statut_compte::text || '. Vous ne pouvez plus candidater. Pour faire un recours, écrivez à bonjour@jolene.app.');
    END IF;

    v_compatible := fn_soignant_compatible_mission(v_soignant.profession, v_soignant.specialite_medicale,
      v_mission.profession_requise, v_mission.specialite_medicale_requise, v_mission.accepte_non_specialises);

    IF NOT v_compatible THEN
      IF v_mission.profession_requise = 'MEDECIN' AND v_mission.specialite_medicale_requise IS NOT NULL
         AND v_soignant.profession = 'MEDECIN' THEN
        SELECT label INTO v_specialite_label FROM specialites_medicales WHERE code = v_mission.specialite_medicale_requise;
        RETURN jsonb_build_object('error', 'Cette mission requiert la spécialité ' ||
          COALESCE(v_specialite_label, v_mission.specialite_medicale_requise) || '.');
      ELSIF v_mission.profession_requise IN ('IBODE', 'IADE') AND v_soignant.profession = 'IDE'
            AND COALESCE(v_mission.accepte_non_specialises, true) = false THEN
        RETURN jsonb_build_object('error', 'Cette mission ' || v_mission.profession_requise::text || ' n''accepte pas les IDE non spécialisés.');
      ELSE
        RETURN jsonb_build_object('error', 'Votre profession ne correspond pas à la mission requise (' || v_mission.profession_requise::text || ').');
      END IF;
    END IF;

    IF fn_est_exclu(auth.uid(), v_mission.etablissement_id) THEN RETURN jsonb_build_object('error', 'Accès refusé.'); END IF;
    IF v_mission.type_contrat_recherche = 'SALARIE' AND COALESCE(v_soignant.type_exercice, 'SALARIE') NOT IN ('SALARIE', 'MIXTE') THEN
        RETURN jsonb_build_object('error', 'Cette mission est réservée aux salariés.'); END IF;
    IF v_mission.type_contrat_recherche = 'LIBERAL' AND COALESCE(v_soignant.type_exercice, 'SALARIE') NOT IN ('LIBERAL', 'MIXTE') THEN
        RETURN jsonb_build_object('error', 'Cette mission est réservée aux libéraux.'); END IF;

    IF v_soignant.type_exercice = 'MIXTE' AND v_mission.type_contrat_recherche = 'TOUS' THEN
        IF p_choix_contrat IS NULL OR p_choix_contrat NOT IN ('SALARIE', 'LIBERAL') THEN
            RETURN jsonb_build_object('error', 'Veuillez choisir votre mode de contrat.', 'choix_requis', TRUE,
                'options', jsonb_build_array(
                    jsonb_build_object('value', 'SALARIE', 'label', 'Salarié (CDDU)'),
                    jsonb_build_object('value', 'LIBERAL', 'label', 'Libéral (note d''honoraires)')));
        END IF;
    END IF;

    SELECT EXISTS(SELECT 1 FROM documents_soignants WHERE soignant_id = auth.uid() AND type_document = 'RCP_ASSURANCE'
        AND statut_verification = 'VERIFIE' AND supprime_le IS NULL
        AND (valide_jusqua IS NULL OR valide_jusqua > CURRENT_DATE)) INTO v_rcp_valide;
    IF NOT v_rcp_valide THEN
        RETURN jsonb_build_object('error', 'Assurance Responsabilité Civile Professionnelle (RCP) manquante ou expirée. Veuillez la téléverser dans vos documents.');
    END IF;

    IF EXTRACT(EPOCH FROM (v_mission.debut_le - NOW())) / 86400 < 7 THEN
        IF v_soignant.tous_documents_valides IS NOT TRUE THEN
            RETURN jsonb_build_object('error', 'Documents obligatoires non validés (mission < 7 jours).'); END IF;
    END IF;

    IF EXISTS (SELECT 1 FROM candidatures WHERE mission_id = p_mission_id AND soignant_id = auth.uid()) THEN
        RETURN jsonb_build_object('error', 'Vous avez déjà postulé à cette mission'); END IF;

    IF v_mission.type_contrat_recherche = 'SALARIE' THEN v_choix_final := 'SALARIE';
    ELSIF v_mission.type_contrat_recherche = 'LIBERAL' THEN v_choix_final := 'LIBERAL';
    ELSIF v_soignant.type_exercice = 'MIXTE' THEN v_choix_final := p_choix_contrat;
    ELSE v_choix_final := COALESCE(v_soignant.type_exercice, 'SALARIE'); END IF;

    INSERT INTO candidatures (mission_id, soignant_id, message, statut, type_contrat_choisi)
    VALUES (p_mission_id, auth.uid(), fn_html_escape(p_message), 'EN_ATTENTE', v_choix_final);

    RETURN jsonb_build_object('success', TRUE, 'choix_contrat', v_choix_final);
END;
$function$;

NOTIFY pgrst, 'reload schema';
