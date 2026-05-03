-- Refonte.E.3 — Cleanup scoring v1 inline dans dec_mettre_a_jour_fiabilite
--
-- Contexte : Le trigger dec_mission_maj_fiabilite (sur missions) appelle
-- dec_mettre_a_jour_fiabilite qui :
--   1) Maintient les compteurs total_missions_terminees, heures_cumulees,
--      total_absences, total_missions_annulees (UTILE — utilisé par v2)
--   2) Calcule un score_fiabilite v1 par formule heuristique
--      (50 + bonus - malus) puis l'écrit dans soignants.score_fiabilite
--      (OBSOLÈTE — écrasé par v2 via trg_recalcul_score_v2_missions)
--
-- Le calcul v1 est :
--   - Coûteux pour rien (UPDATE supplémentaire)
--   - Confusant (logique parallèle à v2)
--   - Risque race condition si v1 s'exécute APRÈS v2 (selon ordre triggers)
--
-- Solution : conserver la fonction (maintien compteurs + badge ambassadeur)
-- mais retirer le calcul v1. v2 prend complètement le relais.

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

        -- J5.D.1 : badge Ambassadeur si ce soignant a un parrain et 3 filleuls validés
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

    -- Refonte.E.3 : retiré du trigger v1 le UPDATE soignants.score_fiabilite (formule heuristique 50 + bonus - malus).
    -- Le score est désormais calculé exclusivement par fn_calculer_score_fiabilite_v2 via trg_recalcul_score_v2_missions
    -- (et trg_recalcul_score_v2_notations / trg_recalcul_score_v2_litiges sur les autres tables).
    -- La fonction conserve le maintien des compteurs (total_missions_terminees, heures_cumulees, etc.)
    -- et la logique badge Ambassadeur, qui restent utilisés par v2.

    RETURN NEW;
END;
$function$;

NOTIFY pgrst, 'reload schema';
