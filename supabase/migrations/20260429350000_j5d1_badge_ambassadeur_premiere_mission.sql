-- J5.D.1 — Étend dec_mettre_a_jour_fiabilite :
--   * Set premiere_mission_le quand 1ère TERMINEE (utile pour comptage filleuls validés)
--   * Déclenche badge_ambassadeur=true sur le parrain quand 3 filleuls ont leur premiere_mission_le
--   * Notification PARRAINAGE au parrain au déblocage du badge
--
-- L'avantage RÉEL câblé pour un parrainage = +50h cumulées parrain+filleul à l'application
-- du code (fn_appliquer_parrainage existante). La mention "accès prioritaire missions urgentes
-- 15min avant" présente dans la page parrainage avant J5.D.1 était une fonctionnalité fantôme
-- (jamais implémentée backend) — retirée dans la PageParrainage.tsx du même commit.

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
BEGIN
    IF NEW.soignant_assigne_id IS NULL THEN RETURN NEW; END IF;

    IF NEW.statut = 'TERMINEE' AND OLD.statut != 'TERMINEE' THEN
        UPDATE soignants SET
            total_missions_terminees = total_missions_terminees + 1,
            heures_cumulees = heures_cumulees +
                EXTRACT(EPOCH FROM (NEW.fin_le - NEW.debut_le)) / 3600.0,
            eligible_conversion_3200h = (
                heures_cumulees + EXTRACT(EPOCH FROM (NEW.fin_le - NEW.debut_le)) / 3600.0
            ) >= 3200,
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

        -- J5.D.1 : check badge Ambassadeur si ce soignant a un parrain
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

    UPDATE soignants SET
        score_fiabilite = GREATEST(0, LEAST(100,
            50.0
            + (total_missions_terminees * 2.0)
            - (total_missions_annulees * 8.0)
            - (total_absences * 25.0)
            - (total_retards_pointage * 3.0)
            - (COALESCE(total_litiges_perdus, 0) * 10.0)
            + CASE WHEN total_missions_terminees > 20 THEN 10.0 ELSE 0 END
            + CASE WHEN total_absences = 0 AND total_missions_terminees > 5 THEN 5.0 ELSE 0 END
            + CASE WHEN prevoyance_inscrit THEN 3.0 ELSE 0 END
        ))
    WHERE id = NEW.soignant_assigne_id;

    RETURN NEW;
END;
$function$;

NOTIFY pgrst, 'reload schema';
