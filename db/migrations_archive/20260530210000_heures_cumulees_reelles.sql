-- Aligner heures_cumulees (compteur fiabilité/badges + suivi_conversion_3200h)
-- sur les heures RÉELLEMENT pointées, comme fn_compteur_heures_soignant.
-- Avant : incrément = heures prévues (fin_le - debut_le). Après : somme des
-- presences.heures_reelles de la mission (repli prévu si pas de pointage).
CREATE OR REPLACE FUNCTION public.dec_mettre_a_jour_fiabilite()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_parrain_id UUID;
  v_nb_filleuls_valides INT;
  v_parrain_avait_badge BOOLEAN;
  v_filleul_prenom TEXT;
  v_heures_mission NUMERIC;
BEGIN
    IF NEW.soignant_assigne_id IS NULL THEN RETURN NEW; END IF;

    IF NEW.statut = 'TERMINEE' AND OLD.statut != 'TERMINEE' THEN
        -- Heures réellement pointées sur la mission (repli sur les heures prévues).
        v_heures_mission := COALESCE(
            (SELECT SUM(pr.heures_reelles) FROM public.presences pr
              WHERE pr.mission_id = NEW.id AND pr.heures_reelles IS NOT NULL),
            EXTRACT(EPOCH FROM (NEW.fin_le - NEW.debut_le)) / 3600.0
        );

        UPDATE soignants SET
            total_missions_terminees = total_missions_terminees + 1,
            heures_cumulees = heures_cumulees + v_heures_mission,
            eligible_conversion_3200h = (heures_cumulees + v_heures_mission) >= 3200,
            premiere_mission_le = COALESCE(premiere_mission_le, NOW()),
            derniere_activite_le = NOW(), modifie_le = NOW()
        WHERE id = NEW.soignant_assigne_id;

        UPDATE suivi_conversion_3200h SET
            heures_actuelles = (SELECT heures_cumulees FROM soignants WHERE id = NEW.soignant_assigne_id),
            jalon_800h_atteint  = heures_actuelles >= 800,
            jalon_1600h_atteint = heures_actuelles >= 1600,
            jalon_2400h_atteint = heures_actuelles >= 2400,
            jalon_3200h_atteint = heures_actuelles >= 3200,
            modifie_le = NOW()
        WHERE soignant_id = NEW.soignant_assigne_id;

        SELECT parraine_par, prenom INTO v_parrain_id, v_filleul_prenom
        FROM soignants WHERE id = NEW.soignant_assigne_id;

        IF v_parrain_id IS NOT NULL THEN
          SELECT COUNT(*) INTO v_nb_filleuls_valides
          FROM soignants
          WHERE parraine_par = v_parrain_id
            AND premiere_mission_le IS NOT NULL
            AND supprime_le IS NULL;

          IF v_nb_filleuls_valides >= 3 THEN
            SELECT badge_ambassadeur INTO v_parrain_avait_badge
            FROM soignants WHERE id = v_parrain_id;

            IF NOT COALESCE(v_parrain_avait_badge, false) THEN
              UPDATE soignants SET badge_ambassadeur = true, modifie_le = NOW()
              WHERE id = v_parrain_id;

              INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien)
              VALUES (
                v_parrain_id, 'SOIGNANT', 'PARRAINAGE',
                '🛡️ Badge Ambassadeur débloqué !',
                'Bravo ! ' || COALESCE(v_filleul_prenom, 'Votre filleul')
                  || ' vient de terminer sa 1ère mission. Vous avez 3 filleuls validés et obtenez le badge Ambassadeur, visible sur votre profil.',
                '/soignant/parrainage'
              );
            END IF;
          END IF;
        END IF;
    END IF;

    IF NEW.statut = 'ABSENCE' AND OLD.statut != 'ABSENCE' THEN
        UPDATE soignants SET total_absences = total_absences + 1, modifie_le = NOW()
        WHERE id = NEW.soignant_assigne_id;
    END IF;

    IF NEW.statut = 'ANNULEE_PAR_SOIGNANT' AND OLD.statut != 'ANNULEE_PAR_SOIGNANT' THEN
        UPDATE soignants SET total_missions_annulees = total_missions_annulees + 1, modifie_le = NOW()
        WHERE id = NEW.soignant_assigne_id;
    END IF;

    RETURN NEW;
END;
$function$;

NOTIFY pgrst, 'reload schema';
