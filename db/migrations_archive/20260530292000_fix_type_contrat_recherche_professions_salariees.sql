-- BUG : dec_valider_type_contrat_mission levait une exception dès que
-- type_contrat_recherche IN ('LIBERAL','TOUS') pour une profession non-libérale
-- (AS, AES, PREPARATEUR_PHARMA). Or fn_creer_mission insère TOUJOURS avec le
-- défaut 'TOUS' (la préférence n'est posée qu'APRÈS via fn_modifier_type_contrat).
-- Conséquence : impossible de créer la moindre mission pour ces 3 professions
-- (aide-soignant inclus — un des profils les plus demandés). fn_creer_mission
-- renvoyait {success:false, error:"...ne peut pas exercer en libéral"}.
-- Fix : pour une profession non-libérale,
--   * 'TOUS'    -> auto-restreint à 'SALARIE' (pas d'erreur, comportement attendu)
--   * 'LIBERAL' -> erreur explicite conservée (demande libérale impossible)
CREATE OR REPLACE FUNCTION public.dec_valider_type_contrat_mission()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NEW.type_contrat_recherche = 'LIBERAL' THEN
        IF NOT fn_profession_peut_etre_liberal(NEW.profession_requise::TEXT) THEN
            RAISE EXCEPTION 'La profession % ne peut pas exercer en libéral. Seul le type "Salarié" est autorisé pour cette profession.', NEW.profession_requise;
        END IF;
    ELSIF NEW.type_contrat_recherche = 'TOUS' THEN
        -- Profession salariée uniquement : 'TOUS' se réduit de fait à 'SALARIE'
        IF NOT fn_profession_peut_etre_liberal(NEW.profession_requise::TEXT) THEN
            NEW.type_contrat_recherche := 'SALARIE';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;
