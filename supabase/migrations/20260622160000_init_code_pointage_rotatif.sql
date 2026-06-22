-- Pointage rotatif (PR 1/N) — activation de l'état de départ du système ②.
--
-- Contexte : deux systèmes de pointage coexistent (cf. docs/POINTAGE_DIAGNOSTIC.md).
--   ① ancien (presences + fn_pointer_arrivee/depart) — branché au frontend, mono-jour.
--   ② rotatif (fn_scanner_code_pointage + scans_pointage + créneaux EFFECTIF) —
--      codes qui se régénèrent à chaque scan, gère pauses + multi-jours, alimente la paie.
--
-- Le système ② était complet côté backend mais dormant : `code_pointage_actif`
-- (le code de départ que fn_scanner_code_pointage matche) n'était JAMAIS initialisé.
-- nb_scans (défaut 0) et prochain_type_scan (défaut 'OUVERTURE') l'étaient déjà.
--
-- Ce correctif initialise `code_pointage_actif` à la création de la mission.
-- 100% additif : le système ① (code_arrivee/code_depart) reste intact, aucune
-- régression — le frontend continue d'utiliser ① tant qu'il n'est pas rebranché (PR suivantes).

CREATE OR REPLACE FUNCTION public.dec_generer_codes_pointage()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
    -- Système ① (codes statiques arrivée/départ) — conservé tel quel.
    NEW.code_arrivee := LPAD(FLOOR(RANDOM() * 999999)::TEXT, 6, '0');
    NEW.code_depart := LPAD(FLOOR(RANDOM() * 999999)::TEXT, 6, '0');
    WHILE NEW.code_depart = NEW.code_arrivee LOOP
        NEW.code_depart := LPAD(FLOOR(RANDOM() * 999999)::TEXT, 6, '0');
    END LOOP;

    -- Système ② (rotatif) — code de départ. fn_scanner_code_pointage le régénère
    -- à chaque scan. On n'écrase pas une valeur déjà présente.
    IF NEW.code_pointage_actif IS NULL THEN
        NEW.code_pointage_actif := LPAD(FLOOR(RANDOM() * 1000000)::TEXT, 6, '0');
    END IF;

    RETURN NEW;
END;
$function$;

-- Backfill : missions déjà actives sans code rotatif (créées avant ce correctif).
UPDATE public.missions
SET code_pointage_actif = LPAD(FLOOR(RANDOM() * 1000000)::TEXT, 6, '0')
WHERE code_pointage_actif IS NULL
  AND statut IN ('ASSIGNEE', 'EN_COURS');
