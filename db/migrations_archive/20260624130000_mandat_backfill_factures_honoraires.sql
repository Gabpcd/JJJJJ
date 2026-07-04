-- Fix : génère (backfill) les factures d'honoraires des missions terminées qui
-- n'ont pas pu être facturées faute de mandat de facturation signé au moment de
-- la complétion / confirmation.
--
-- Bug découvert pendant l'audit E2E du cycle LIBÉRAL :
--   * fn_trg_auto_facture_honoraires (trigger TERMINEE, mode honoraires) ne génère
--     la facture QUE si le mandat est signé, et ne se déclenche qu'à la transition
--     vers TERMINEE — jamais réessayée.
--   * fn_confirmer_honoraires_retrocession / fn_auto_confirmer_honoraires (cron 48h)
--     marquent honoraires_confirmes_le = now() puis ne génèrent la facture QUE si le
--     mandat est signé. Une fois confirmé, le cron ne retraite plus la mission
--     (WHERE honoraires_confirmes_le IS NULL).
--   * fn_signer_mandat_facturation ne rattrapait RIEN.
-- Conséquence : un soignant libéral qui termine/confirme une mission AVANT de signer
-- son mandat n'était jamais facturé (aucun document émis), même après signature.
-- Aucun garde-fou côté UI n'empêche d'accepter/terminer une mission sans mandat signé.
--
-- Correctif : à la signature du mandat, on génère les factures manquantes pour les
-- missions terminées prêtes à facturer. fn_generer_facture_honoraires_mission est
-- entièrement auto-gardée (mandat signé requis, mission TERMINEE, idempotente si une
-- facture existe déjà) → l'appel est sûr et non destructif.

CREATE OR REPLACE FUNCTION public.fn_signer_mandat_facturation(p_version text, p_ip text DEFAULT NULL::text, p_user_agent text DEFAULT NULL::text, p_contenu_hash text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_user_id UUID := auth.uid();
    v_signature_id UUID;
    v_mission_id UUID;
    v_backfill INT := 0;
BEGIN
    IF v_user_id IS NULL THEN
        RETURN '{"error":"Non authentifié"}'::JSONB;
    END IF;

    -- Vérifier que c'est bien un soignant
    IF NOT EXISTS (SELECT 1 FROM soignants WHERE id = v_user_id AND supprime_le IS NULL) THEN
        RETURN '{"error":"Seuls les soignants peuvent signer ce mandat"}'::JSONB;
    END IF;

    -- Enregistrer la signature (audit)
    INSERT INTO mandats_facturation_signatures (soignant_id, version, ip_address, user_agent, contenu_hash)
    VALUES (v_user_id, p_version, p_ip, p_user_agent, p_contenu_hash)
    RETURNING id INTO v_signature_id;

    -- Mettre à jour le soignant
    UPDATE soignants SET
        mandat_facturation_signe = TRUE,
        mandat_facturation_signe_le = now(),
        mandat_facturation_version = p_version
    WHERE id = v_user_id;

    -- BACKFILL : rattraper les factures d'honoraires non générées faute de mandat.
    -- On reproduit les prédicats des deux générateurs existants :
    --   (A) honoraires "classiques" (non rétrocession) → généré par le trigger TERMINEE
    --       si mandat signé. Gardé sur type_contrat_applique = 'LIBERAL' pour ne PAS
    --       facturer en honoraires les missions SALARIÉES d'un soignant MIXTE.
    --   (B) rétrocession confirmée (honoraires_confirmes_le NOT NULL) → généré par
    --       confirm/cron si mandat signé. RETROCESSION est par nature libéral.
    -- fn_generer_facture_honoraires_mission est idempotente (no-op si facture existe).
    FOR v_mission_id IN
        SELECT m.id
        FROM missions m
        WHERE m.soignant_assigne_id = v_user_id
          AND m.statut = 'TERMINEE'
          AND COALESCE(m.net_a_payer, m.total_brut, 0) > 0
          AND NOT EXISTS (SELECT 1 FROM factures_honoraires fh WHERE fh.mission_id = m.id)
          AND (
                (m.mode_remuneration IS DISTINCT FROM 'RETROCESSION' AND m.type_contrat_applique = 'LIBERAL')
             OR (m.mode_remuneration = 'RETROCESSION' AND m.honoraires_confirmes_le IS NOT NULL)
          )
    LOOP
        PERFORM fn_generer_facture_honoraires_mission(v_mission_id);
        v_backfill := v_backfill + 1;
    END LOOP;

    RETURN jsonb_build_object(
        'success', true,
        'signature_id', v_signature_id,
        'version', p_version,
        'signed_at', now(),
        'factures_regenerees', v_backfill
    );
END;
$function$;
