-- Fix : fn_generer_facture_honoraires_mission omettait periode_debut/periode_fin
-- (colonnes NOT NULL sans défaut sur factures_honoraires) → la génération de
-- la facture d'honoraires libérale échouait (23502) et faisait échouer le
-- passage de la mission en TERMINEE (trigger fn_trg_auto_facture_honoraires).
-- Bornes = debut_le / fin_le de la mission. Renseigne aussi semaine/année ISO.

CREATE OR REPLACE FUNCTION public.fn_generer_facture_honoraires_mission(p_mission_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_mission RECORD;
    v_soignant RECORD;
    v_numero TEXT;
    v_facture_id UUID;
    v_existing_id UUID;
    v_periode_debut DATE;
    v_periode_fin DATE;
BEGIN
    SELECT m.*, e.nom AS etab_nom
    INTO v_mission
    FROM missions m
    JOIN etablissements e ON e.id = m.etablissement_id
    WHERE m.id = p_mission_id AND m.statut = 'TERMINEE';

    IF v_mission IS NULL THEN
        RETURN '{"error":"Mission introuvable ou non terminée"}'::JSONB;
    END IF;

    IF v_mission.soignant_assigne_id IS NULL THEN
        RETURN '{"error":"Aucun soignant assigné"}'::JSONB;
    END IF;

    SELECT * INTO v_soignant FROM soignants WHERE id = v_mission.soignant_assigne_id;
    IF v_soignant IS NULL THEN
        RETURN '{"error":"Soignant introuvable"}'::JSONB;
    END IF;

    IF NOT COALESCE(v_soignant.mandat_facturation_signe, FALSE) THEN
        RETURN '{"error":"Le soignant n''a pas encore signé le mandat de facturation"}'::JSONB;
    END IF;

    SELECT id INTO v_existing_id FROM factures_honoraires WHERE mission_id = p_mission_id LIMIT 1;
    IF v_existing_id IS NOT NULL THEN
        RETURN jsonb_build_object('success', true, 'facture_id', v_existing_id, 'message', 'Facture déjà existante');
    END IF;

    v_numero := 'FH-' || to_char(now(), 'YYYY-MM') || '-' || lpad(
        (COALESCE((SELECT COUNT(*) FROM factures_honoraires WHERE date_emission >= date_trunc('month', now())), 0) + 1)::TEXT,
        4, '0'
    );

    -- Période de la facture = bornes de la mission (NOT NULL en base)
    v_periode_debut := COALESCE(v_mission.debut_le::date, CURRENT_DATE);
    v_periode_fin := COALESCE(v_mission.fin_le::date, v_mission.debut_le::date, CURRENT_DATE);

    INSERT INTO factures_honoraires (
        numero_facture, soignant_id, etablissement_id, mission_id,
        montant_ht, montant_tva, montant_ttc, taux_tva, exoneration_tva,
        date_emission, date_echeance, statut, mandat_version,
        periode_debut, periode_fin,
        numero_semaine_iso, annee_iso
    ) VALUES (
        v_numero,
        v_mission.soignant_assigne_id,
        v_mission.etablissement_id,
        p_mission_id,
        COALESCE(v_mission.net_a_payer, v_mission.total_brut, 0),
        0,
        COALESCE(v_mission.net_a_payer, v_mission.total_brut, 0),
        0,
        TRUE,
        CURRENT_DATE,
        CURRENT_DATE + INTERVAL '30 days',
        'EMISE',
        v_soignant.mandat_facturation_version,
        v_periode_debut,
        v_periode_fin,
        EXTRACT(WEEK FROM v_periode_debut)::smallint,
        EXTRACT(ISOYEAR FROM v_periode_debut)::smallint
    ) RETURNING id INTO v_facture_id;

    RETURN jsonb_build_object('success', true, 'facture_id', v_facture_id, 'numero', v_numero);
END;
$function$;
