-- Fix bug 1: conformite_travail triggers fail because no INSERT RLS policy exists
-- Make the trigger functions SECURITY DEFINER so they bypass RLS (system-level compliance checks)

CREATE OR REPLACE FUNCTION public.dec_verifier_plafond_48h()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_debut_sem TIMESTAMPTZ; v_fin_sem TIMESTAMPTZ;
    v_heures_actuelles NUMERIC; v_heures_mission NUMERIC; v_total NUMERIC;
BEGIN
    IF NEW.soignant_assigne_id IS NULL THEN RETURN NEW; END IF;
    IF NEW.statut NOT IN ('ASSIGNEE', 'EN_COURS') THEN RETURN NEW; END IF;

    v_debut_sem := date_trunc('week', NEW.debut_le);
    v_fin_sem := v_debut_sem + INTERVAL '7 days';
    v_heures_mission := EXTRACT(EPOCH FROM (NEW.fin_le - NEW.debut_le)) / 3600.0;

    SELECT COALESCE(SUM(EXTRACT(EPOCH FROM (m.fin_le - m.debut_le)) / 3600.0), 0)
    INTO v_heures_actuelles
    FROM missions m
    WHERE m.soignant_assigne_id = NEW.soignant_assigne_id
      AND m.id != NEW.id
      AND m.debut_le >= v_debut_sem AND m.debut_le < v_fin_sem
      AND m.statut IN ('ASSIGNEE','EN_COURS','TERMINEE');

    v_total := v_heures_actuelles + v_heures_mission;

    IF v_total > 48.0 THEN
        INSERT INTO conformite_travail (soignant_id, mission_id, type_controle, resultat, details_violation)
        VALUES (NEW.soignant_assigne_id, NEW.id, 'PLAFOND_48H_HEBDO', 'VIOLATION_BLOQUEE',
            jsonb_build_object('heures_actuelles', ROUND(v_heures_actuelles, 2),
                'heures_mission', ROUND(v_heures_mission, 2), 'total', ROUND(v_total, 2),
                'plafond', 48, 'article', 'L3121-20'));
        RAISE EXCEPTION '[CODE DU TRAVAIL] Plafond hebdomadaire dépassé : %.1f heures prévues sur 48h maximum (Art. L3121-20). Assignation bloquée.', v_total;
    END IF;

    INSERT INTO conformite_travail (soignant_id, mission_id, type_controle, resultat, details_violation)
    VALUES (NEW.soignant_assigne_id, NEW.id, 'PLAFOND_48H_HEBDO', 'CONFORME',
        jsonb_build_object('total_heures', ROUND(v_total, 2)));
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.dec_verifier_repos_11h()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_fin_precedente TIMESTAMPTZ;
    v_debut_suivant TIMESTAMPTZ;
    v_ecart NUMERIC;
BEGIN
    IF NEW.soignant_assigne_id IS NULL THEN RETURN NEW; END IF;
    IF NEW.statut NOT IN ('ASSIGNEE', 'EN_COURS') THEN RETURN NEW; END IF;

    SELECT MAX(m.fin_le) INTO v_fin_precedente
    FROM missions m
    WHERE m.soignant_assigne_id = NEW.soignant_assigne_id
      AND m.id != NEW.id
      AND m.fin_le <= NEW.debut_le
      AND m.statut IN ('ASSIGNEE','EN_COURS','TERMINEE');

    IF v_fin_precedente IS NOT NULL THEN
        v_ecart := EXTRACT(EPOCH FROM (NEW.debut_le - v_fin_precedente)) / 3600.0;
        IF v_ecart < 11.0 THEN
            INSERT INTO conformite_travail (soignant_id, mission_id, type_controle, resultat, details_violation)
            VALUES (NEW.soignant_assigne_id, NEW.id, 'REPOS_11H', 'VIOLATION_BLOQUEE',
                jsonb_build_object('ecart_heures', ROUND(v_ecart, 2), 'minimum_requis', 11, 'sens', 'avant', 'article', 'L3131-1'));
            RAISE EXCEPTION '[CODE DU TRAVAIL] Repos insuffisant avant mission : %.1f heures au lieu de 11h minimum (Art. L3131-1). Assignation bloquée.', v_ecart;
        END IF;
    END IF;

    SELECT MIN(m.debut_le) INTO v_debut_suivant
    FROM missions m
    WHERE m.soignant_assigne_id = NEW.soignant_assigne_id
      AND m.id != NEW.id
      AND m.debut_le >= NEW.fin_le
      AND m.statut IN ('ASSIGNEE','EN_COURS','TERMINEE');

    IF v_debut_suivant IS NOT NULL THEN
        v_ecart := EXTRACT(EPOCH FROM (v_debut_suivant - NEW.fin_le)) / 3600.0;
        IF v_ecart < 11.0 THEN
            INSERT INTO conformite_travail (soignant_id, mission_id, type_controle, resultat, details_violation)
            VALUES (NEW.soignant_assigne_id, NEW.id, 'REPOS_11H', 'VIOLATION_BLOQUEE',
                jsonb_build_object('ecart_heures', ROUND(v_ecart, 2), 'minimum_requis', 11, 'sens', 'apres', 'article', 'L3131-1'));
            RAISE EXCEPTION '[CODE DU TRAVAIL] Repos insuffisant après mission : %.1f heures au lieu de 11h minimum (Art. L3131-1). Assignation bloquée.', v_ecart;
        END IF;
    END IF;

    INSERT INTO conformite_travail (soignant_id, mission_id, type_controle, resultat)
    VALUES (NEW.soignant_assigne_id, NEW.id, 'REPOS_11H', 'CONFORME');
    RETURN NEW;
END;
$function$;