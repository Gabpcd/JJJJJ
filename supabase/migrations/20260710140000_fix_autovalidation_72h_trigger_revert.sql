-- Fix (audit 10/07/2026, incident latent) : l'auto-validation 72h des présences
-- était NEUTRALISÉE par un trigger de protection.
--
-- Mécanique du bug (définitions LIVE) :
--   fn_valider_presences_72h_auto (cron jolene_valider_presences_72h) fait
--   UPDATE presences SET valide_auto_72h_le=NOW(), valide_par_etablissement=true.
--   Le trigger BEFORE UPDATE dec_proteger_presence_soignant reverte
--   valide_par_etablissement dès que « NOT est_admin() AND NOT
--   est_admin_etablissement() » — or en contexte cron auth.uid() est NULL donc
--   est_admin()=false → la condition est vraie → valide_par_etablissement est
--   remis à OLD (false). MAIS valide_auto_72h_le n'est PAS dans la liste de
--   revert → il reste posé → la présence est exclue des passages suivants
--   (WHERE valide_auto_72h_le IS NULL). Résultat : présence coincée
--   (auto-timestamp posé, flag de validation false), escrow/paie jamais
--   débloqués par le filet 72h.
--
-- Impact prod au moment du fix : NUL (0 présence éligible en pré-lancement,
-- les étabs valident à la main). Bug LATENT du filet de sécurité.
--
-- Fix : exempter le contexte système (auth.uid() IS NULL = cron/backend/
-- service_role) du verrou soignant. Aligné sur le trigger jumeau
-- fn_protect_presence_integrity qui ne bloque que « OLD.soignant_id = auth.uid() »
-- (donc jamais le cron). Un soignant est TOUJOURS authentifié (auth.uid = son
-- id) → toujours bloqué : l'anti-tamper reste strictement intact.
--
-- Vérifié sur prod (transactions annulées, triggers réels) :
--   AVANT : cron valide=false (bug), soignant tamper bloqué=false.
--   APRÈS : cron valide=true (réparé), soignant tamper toujours bloqué=false.
-- Appliqué en prod par SQL direct le 10/07 (vérif triggers réels), recapturé ici.
CREATE OR REPLACE FUNCTION public.dec_proteger_presence_soignant()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
    IF auth.uid() IS NOT NULL AND NOT est_admin() AND NOT est_admin_etablissement() THEN
        NEW.valide_par_etablissement := OLD.valide_par_etablissement;
        NEW.valide_le := OLD.valide_le;
        NEW.alerte_teleportation := OLD.alerte_teleportation;
        NEW.alertes_fraude := OLD.alertes_fraude;
        NEW.perimetre_gps_valide := OLD.perimetre_gps_valide;
        NEW.distance_etablissement_m := OLD.distance_etablissement_m;
        NEW.motif_litige := OLD.motif_litige;
        NEW.heures_reelles := OLD.heures_reelles;
        NEW.duree_brute_min := OLD.duree_brute_min;
        NEW.duree_nette_min := OLD.duree_nette_min;
        NEW.retard_min := OLD.retard_min;
        NEW.depart_anticipe_min := OLD.depart_anticipe_min;
        NEW.mission_id := OLD.mission_id;
        NEW.soignant_id := OLD.soignant_id;
    END IF;
    RETURN NEW;
END;
$function$;
