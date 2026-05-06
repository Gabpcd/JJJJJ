-- Refonte.D.3 — Email J+1 post-mission notation
-- Table idempotence + RPC scan + intégration cron daily

-- 1) Table idempotence
CREATE TABLE IF NOT EXISTS public.notifications_notation_j1 (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  mission_id UUID NOT NULL REFERENCES public.missions(id) ON DELETE CASCADE,
  sens public.sens_notation NOT NULL,
  destinataire_id UUID NOT NULL,
  envoye_le TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (mission_id, sens)
);

CREATE INDEX IF NOT EXISTS idx_notif_notation_j1_dest ON public.notifications_notation_j1 (destinataire_id, envoye_le DESC);

ALTER TABLE public.notifications_notation_j1 ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_notif_notation_j1_select ON public.notifications_notation_j1;
CREATE POLICY pol_notif_notation_j1_select ON public.notifications_notation_j1 FOR SELECT
  USING (destinataire_id = auth.uid() OR destinataire_id = mon_etablissement_id() OR (SELECT est_admin()));

GRANT SELECT ON public.notifications_notation_j1 TO authenticated;
GRANT ALL ON public.notifications_notation_j1 TO service_role;

-- 2) RPC fn_envoyer_rappels_notation_j1 : appelée par cron daily
-- À brancher dans email-cron-daily : SELECT public.fn_envoyer_rappels_notation_j1();
-- Templates RAPPEL_NOTATION_ETAB + RAPPEL_NOTATION_SOIGNANT à ajouter dans send-email function (action Gabrielle).
CREATE OR REPLACE FUNCTION public.fn_envoyer_rappels_notation_j1()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_url TEXT;
  v_token TEXT;
  v_mission RECORD;
  v_count_etab INT := 0;
  v_count_soignant INT := 0;
  v_send_email_called BOOLEAN;
BEGIN
  IF NOT (est_admin() OR COALESCE(current_setting('request.jwt.claim.role', true), '') = 'service_role') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Accès refusé');
  END IF;

  BEGIN
    v_url := public.fn_lire_secret_cron('supabase_url');
    v_token := public.fn_lire_secret_cron('service_role_key');
  EXCEPTION WHEN OTHERS THEN
    v_url := NULL; v_token := NULL;
  END;

  FOR v_mission IN
    SELECT m.id, m.intitule, m.fin_le, m.etablissement_id, m.soignant_assigne_id
    FROM missions m
    WHERE m.statut = 'TERMINEE'
      AND m.fin_le >= NOW() - INTERVAL '48 hours'
      AND m.fin_le < NOW() - INTERVAL '24 hours'
      AND m.soignant_assigne_id IS NOT NULL
  LOOP
    -- Côté étab
    IF NOT EXISTS (SELECT 1 FROM notifications_notation_j1 WHERE mission_id = v_mission.id AND sens = 'ETAB_VERS_SOIGNANT')
       AND NOT EXISTS (SELECT 1 FROM notations_missions WHERE mission_id = v_mission.id AND sens = 'ETAB_VERS_SOIGNANT')
       AND public.fn_doit_notifier(v_mission.etablissement_id, 'NOTATION_RAPPEL'::type_evenement_notification, 'EMAIL'::canal_notification) THEN
      v_send_email_called := false;
      IF v_url IS NOT NULL AND v_token IS NOT NULL THEN
        BEGIN
          PERFORM net.http_post(
            url := v_url || '/functions/v1/send-email',
            headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_token),
            body := jsonb_build_object(
              'type', 'RAPPEL_NOTATION_ETAB',
              'destinataire_id', v_mission.etablissement_id,
              'data', jsonb_build_object('mission_id', v_mission.id, 'mission_intitule', v_mission.intitule, 'fin_le', v_mission.fin_le)
            )
          );
          v_send_email_called := true;
        EXCEPTION WHEN OTHERS THEN NULL; END;
      END IF;

      INSERT INTO notifications_notation_j1 (mission_id, sens, destinataire_id)
      VALUES (v_mission.id, 'ETAB_VERS_SOIGNANT', v_mission.etablissement_id)
      ON CONFLICT (mission_id, sens) DO NOTHING;

      PERFORM public.fn_ecrire_audit_safe(
        p_acteur_id := v_mission.etablissement_id, p_type_acteur := 'SYSTEME',
        p_action := 'RAPPEL_NOTATION_J1_ENVOYE', p_type_ressource := 'mission', p_id_ressource := v_mission.id,
        p_details := jsonb_build_object('sens', 'ETAB_VERS_SOIGNANT', 'send_email_called', v_send_email_called)
      );
      v_count_etab := v_count_etab + 1;
    END IF;

    -- Côté soignant
    IF NOT EXISTS (SELECT 1 FROM notifications_notation_j1 WHERE mission_id = v_mission.id AND sens = 'SOIGNANT_VERS_ETAB')
       AND NOT EXISTS (SELECT 1 FROM notations_missions WHERE mission_id = v_mission.id AND sens = 'SOIGNANT_VERS_ETAB')
       AND public.fn_doit_notifier(v_mission.soignant_assigne_id, 'NOTATION_RAPPEL'::type_evenement_notification, 'EMAIL'::canal_notification) THEN
      v_send_email_called := false;
      IF v_url IS NOT NULL AND v_token IS NOT NULL THEN
        BEGIN
          PERFORM net.http_post(
            url := v_url || '/functions/v1/send-email',
            headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_token),
            body := jsonb_build_object(
              'type', 'RAPPEL_NOTATION_SOIGNANT',
              'destinataire_id', v_mission.soignant_assigne_id,
              'data', jsonb_build_object('mission_id', v_mission.id, 'mission_intitule', v_mission.intitule, 'fin_le', v_mission.fin_le)
            )
          );
          v_send_email_called := true;
        EXCEPTION WHEN OTHERS THEN NULL; END;
      END IF;

      INSERT INTO notifications_notation_j1 (mission_id, sens, destinataire_id)
      VALUES (v_mission.id, 'SOIGNANT_VERS_ETAB', v_mission.soignant_assigne_id)
      ON CONFLICT (mission_id, sens) DO NOTHING;

      PERFORM public.fn_ecrire_audit_safe(
        p_acteur_id := v_mission.soignant_assigne_id, p_type_acteur := 'SYSTEME',
        p_action := 'RAPPEL_NOTATION_J1_ENVOYE', p_type_ressource := 'mission', p_id_ressource := v_mission.id,
        p_details := jsonb_build_object('sens', 'SOIGNANT_VERS_ETAB', 'send_email_called', v_send_email_called)
      );
      v_count_soignant := v_count_soignant + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object('success', true, 'count_etab', v_count_etab, 'count_soignant', v_count_soignant);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_envoyer_rappels_notation_j1() TO service_role;

NOTIFY pgrst, 'reload schema';
