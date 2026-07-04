-- AUDIT INFRA J2.3.B.AUDIT — Fix crons cassés + fn_recalculer_palier_commission
--
-- 1. Bug fn_recalculer_palier_commission (cron job 6) :
--    "ERROR: cannot ALTER TABLE etablissements because it is being used by
--    active queries in this session". La fn utilisait ALTER TABLE DISABLE
--    TRIGGER pour bypasser fn_protect_etablissement_commercial pendant
--    l'UPDATE, mais ça échoue quand on est dans une boucle qui scanne la
--    même table (fn_recalculer_tous_paliers). Fix : remplacer le DISABLE
--    TRIGGER par set_config('app.internal_operation', 'true', true) — qui
--    est déjà supporté par le trigger comme bypass.
--
-- 2. Cron jobs (cron.schedule + cron.unschedule appliqué directement via
--    MCP execute_sql, pas via cette migration — pg_cron n'est pas idempotent
--    via DDL sur supabase_migrations). Cette migration documente seulement
--    l'état attendu.
--
--    - job 4 email-cron-daily : refait pour utiliser le secret du vault
--      directement (au lieu de current_setting('app.settings.service_role_key')
--      qui est vide → 401).
--    - job 5 alerte-cddu-repetitif : unschedulé (la fn fn_alerte_cddu_repetitif()
--      n'existe pas en prod ; à recréer puis re-scheduler quand prête).
--    - job 15 litige-escalation-cron : refait. L'ancien était cassé :
--      `jsonb_build_object('Key', 'Authorization', 'Value', 'Bearer ...')`
--      produit `{"Key":"Authorization","Value":"Bearer ..."}` au lieu de
--      `{"Authorization":"Bearer ..."}`. + secret hardcodé. Fix : vault.
--    - job 19 weekly_invoicing : refait. L'ancien avait `headers:=jsonb_build_object()`
--      (vide) + `timeout_milliseconds:=1000` (1 s — trop court). Fix :
--      auth depuis vault + 120 s timeout.

CREATE OR REPLACE FUNCTION public.fn_recalculer_palier_commission(p_etablissement_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_count INTEGER; v_groupe_id UUID; v_palier RECORD;
    v_ancien_taux NUMERIC; v_nouveau_taux NUMERIC; v_remise_groupe NUMERIC := 0;
BEGIN
    SELECT COALESCE(taux_commission_negocie, 15.00) INTO v_ancien_taux FROM etablissements WHERE id = p_etablissement_id;
    SELECT groupe_sante_id INTO v_groupe_id FROM etablissements WHERE id = p_etablissement_id;

    IF v_groupe_id IS NOT NULL THEN
        SELECT COALESCE(remise_groupe_pourcent, 0) INTO v_remise_groupe FROM groupes_sante WHERE id = v_groupe_id;
        SELECT COUNT(*) INTO v_count FROM missions m JOIN etablissements e ON e.id = m.etablissement_id
        WHERE e.groupe_sante_id = v_groupe_id AND m.statut = 'TERMINEE'
          AND m.fin_le >= date_trunc('month', NOW()) - INTERVAL '1 month' AND m.fin_le < date_trunc('month', NOW());
    ELSE
        SELECT COUNT(*) INTO v_count FROM missions m
        WHERE m.etablissement_id = p_etablissement_id AND m.statut = 'TERMINEE'
          AND m.fin_le >= date_trunc('month', NOW()) - INTERVAL '1 month' AND m.fin_le < date_trunc('month', NOW());
    END IF;

    SELECT * INTO v_palier FROM paliers_commission
    WHERE est_actif = TRUE AND missions_min <= v_count AND (missions_max IS NULL OR missions_max >= v_count)
    ORDER BY ordre DESC LIMIT 1;

    IF FOUND AND v_palier.id IS NOT NULL THEN
        v_nouveau_taux := GREATEST(5.00, v_palier.taux_commission - v_remise_groupe);

        -- Bypass trigger fn_protect_etablissement_commercial via session GUC
        -- (compatible avec appel en boucle sur etablissements, contrairement
        -- à ALTER TABLE DISABLE TRIGGER qui locke la table).
        PERFORM set_config('app.internal_operation', 'true', true);

        UPDATE etablissements SET taux_commission_negocie = v_nouveau_taux, palier_commission_id = v_palier.id,
            missions_mois_precedent = v_count, palier_recalcule_le = CURRENT_DATE, modifie_le = NOW()
        WHERE id = p_etablissement_id;

        IF v_groupe_id IS NOT NULL THEN
            UPDATE etablissements SET taux_commission_negocie = v_nouveau_taux, palier_commission_id = v_palier.id,
                missions_mois_precedent = v_count, palier_recalcule_le = CURRENT_DATE, modifie_le = NOW()
            WHERE groupe_sante_id = v_groupe_id;
        END IF;

        PERFORM set_config('app.internal_operation', 'false', true);
    END IF;

    RETURN jsonb_build_object('etablissement_id', p_etablissement_id, 'missions_mois_precedent', v_count,
        'ancien_taux', v_ancien_taux, 'nouveau_taux', COALESCE(v_nouveau_taux, v_ancien_taux),
        'palier', COALESCE(v_palier.nom, 'Découverte'), 'remise_groupe', v_remise_groupe, 'groupe_cumul', v_groupe_id IS NOT NULL);
END;
$function$;
