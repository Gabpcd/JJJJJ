-- Fix : aligner net_a_payer / total_brut / majorations sur les HEURES TRAVAILLÉES
-- (créneaux hors pauses) au lieu du span continu [debut_le, fin_le].
--
-- Bug découvert pendant l'audit facturation salarié : dec_calculer_finance_mission
-- appelait fn_calculer_remuneration_mission(debut_le, fin_le, ...) qui parcourt le
-- span CONTINU heure par heure — il comptait les pauses comme du temps payé et
-- ignorait totalement les créneaux. Résultat, deux bases d'heures divergentes :
--   - net_a_payer / total_brut = span continu (pauses INCLUSES) → commission + facture
--     honoraires FINALE libéral
--   - duree_heures / bulletin de paie = somme créneaux NOT est_pause (pauses EXCLUES)
-- Ex. mission 09:00-18:00 avec 1h de pause : bulletin paie 8h (240€) mais net_a_payer
-- = 9h (270€) → commission et facture finale surfacturent l'heure de pause.
--
-- Correctif : dec_calculer_finance_mission calcule désormais par créneau non-pause
-- (EFFECTIF fermés si présents, sinon PREVISIONNEL — même logique que duree_heures via
-- fn_sync_mission_creneaux), en réutilisant fn_calculer_remuneration_mission par créneau
-- (préserve la ventilation nuit/dimanche/férié + majorations). Fallback sur le span
-- quand aucun créneau (INSERT initial avant création des créneaux).
--
-- Effet : net_a_payer == base bulletin == base commission == facture finale, toutes sur
-- les heures travaillées hors pauses.
--
-- NB inconsistance résiduelle FLAGGÉE (hors scope, décision produit) : fn_calculer_montant_periode
-- (hebdo) et fn_verifier_pre_facturation utilisent GREATEST(prévisionnel, effectif) — un
-- plancher prévisionnel. Ici on s'aligne sur duree_heures = COALESCE(effectif, prévisionnel)
-- (= heures travaillées). Si un plancher prévisionnel est voulu, le traiter séparément.

CREATE OR REPLACE FUNCTION public.dec_calculer_finance_mission()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_taux_effectif NUMERIC;
    v_calcul JSONB;
    v_c RECORD;
    v_use_effectif BOOLEAN;
    v_has_creneaux BOOLEAN;
    v_h_nuit NUMERIC := 0; v_h_dim NUMERIC := 0; v_h_fer NUMERIC := 0;
    v_m_nuit NUMERIC := 0; v_m_dim NUMERIC := 0; v_m_fer NUMERIC := 0;
    v_brut NUMERIC := 0;
    v_ifm NUMERIC := 0; v_icp NUMERIC := 0; v_taux_ifm NUMERIC := 0; v_taux_icp NUMERIC := 0;
BEGIN
    v_taux_effectif := COALESCE(NEW.taux_rist_plafonne, NEW.taux_horaire_base);

    -- Créneaux travaillés (hors pause) disponibles ? EFFECTIF fermés prioritaires.
    SELECT EXISTS(SELECT 1 FROM mission_creneaux WHERE mission_id = NEW.id AND NOT est_pause
                  AND type_creneau = 'EFFECTIF' AND fin IS NOT NULL)
      INTO v_use_effectif;
    SELECT EXISTS(SELECT 1 FROM mission_creneaux WHERE mission_id = NEW.id AND NOT est_pause
                  AND fin IS NOT NULL
                  AND (type_creneau = 'EFFECTIF' OR type_creneau = 'PREVISIONNEL'))
      INTO v_has_creneaux;

    IF v_has_creneaux THEN
        FOR v_c IN
            SELECT debut, fin FROM mission_creneaux
            WHERE mission_id = NEW.id AND NOT est_pause AND fin IS NOT NULL
              AND type_creneau = CASE WHEN v_use_effectif THEN 'EFFECTIF' ELSE 'PREVISIONNEL' END
            ORDER BY debut
        LOOP
            v_calcul := fn_calculer_remuneration_mission(
                v_c.debut, v_c.fin, v_taux_effectif, NEW.etablissement_id, NEW.soignant_assigne_id);
            v_h_nuit := v_h_nuit + (v_calcul->>'heures_nuit')::NUMERIC;
            v_h_dim  := v_h_dim  + (v_calcul->>'heures_dimanche')::NUMERIC;
            v_h_fer  := v_h_fer  + (v_calcul->>'heures_ferie')::NUMERIC;
            v_m_nuit := v_m_nuit + (v_calcul->>'montant_majoration_nuit')::NUMERIC;
            v_m_dim  := v_m_dim  + (v_calcul->>'montant_majoration_dimanche')::NUMERIC;
            v_m_fer  := v_m_fer  + (v_calcul->>'montant_majoration_ferie')::NUMERIC;
            v_brut   := v_brut   + (v_calcul->>'total_brut')::NUMERIC;
            v_taux_ifm := (v_calcul->>'taux_ifm')::NUMERIC;
            v_taux_icp := (v_calcul->>'taux_icp')::NUMERIC;
        END LOOP;

        -- IFM/ICP sur le brut travaillé total (linéaire : identique à la somme par créneau).
        v_ifm := ROUND(v_brut * v_taux_ifm, 2);
        v_icp := ROUND((v_brut + v_ifm) * v_taux_icp, 2);

        NEW.heures_nuit                := ROUND(v_h_nuit, 2);
        NEW.heures_dimanche            := ROUND(v_h_dim, 2);
        NEW.heures_ferie               := ROUND(v_h_fer, 2);
        NEW.montant_majoration_nuit    := ROUND(v_m_nuit, 2);
        NEW.montant_majoration_dimanche:= ROUND(v_m_dim, 2);
        NEW.montant_majoration_ferie   := ROUND(v_m_fer, 2);
        NEW.total_brut                 := ROUND(v_brut, 2);
        NEW.taux_ifm                   := v_taux_ifm;
        NEW.montant_ifm                := v_ifm;
        NEW.taux_icp                   := v_taux_icp;
        NEW.montant_icp                := v_icp;
        NEW.net_a_payer                := ROUND(v_brut + v_ifm + v_icp, 2);
    ELSE
        -- Fallback : aucun créneau (INSERT initial) → span [debut_le, fin_le].
        v_calcul := fn_calculer_remuneration_mission(
            NEW.debut_le, NEW.fin_le, v_taux_effectif, NEW.etablissement_id, NEW.soignant_assigne_id);
        NEW.heures_nuit                := (v_calcul->>'heures_nuit')::NUMERIC;
        NEW.heures_dimanche            := (v_calcul->>'heures_dimanche')::NUMERIC;
        NEW.heures_ferie               := (v_calcul->>'heures_ferie')::NUMERIC;
        NEW.montant_majoration_nuit    := (v_calcul->>'montant_majoration_nuit')::NUMERIC;
        NEW.montant_majoration_dimanche:= (v_calcul->>'montant_majoration_dimanche')::NUMERIC;
        NEW.montant_majoration_ferie   := (v_calcul->>'montant_majoration_ferie')::NUMERIC;
        NEW.total_brut                 := (v_calcul->>'total_brut')::NUMERIC;
        NEW.taux_ifm                   := (v_calcul->>'taux_ifm')::NUMERIC;
        NEW.montant_ifm                := (v_calcul->>'montant_ifm')::NUMERIC;
        NEW.taux_icp                   := (v_calcul->>'taux_icp')::NUMERIC;
        NEW.montant_icp                := (v_calcul->>'montant_icp')::NUMERIC;
        NEW.net_a_payer                := (v_calcul->>'net_a_payer')::NUMERIC;
    END IF;

    RETURN NEW;
END;
$function$;
