-- PR 6 Sprint 3 — Bugfixes identifiés par l'audit E2E
--
-- Cf. docs/AUDIT_E2E_SPRINT3.md pour le contexte.
--
-- Tickets fixés :
--   1. Trigger notif étab dès signature soignant (étape 8 du workflow)
--      → email + push à l'étab quand le soignant vient de signer
--   2. Cron DPAE_RAPPEL J+1 pour les CDD non encore déclarés
--      → push de rappel quotidien à l'étab tant que dpae_effectuee = false
--   3. Cron détection no-show soignant T+30min
--      → push de rappel "Pointez votre arrivée"
--      (l'ouverture auto de litige reste manuelle pour éviter les faux positifs)

-- 1. Trigger signature soignant reçue → notif étab pour contre-signer
CREATE OR REPLACE FUNCTION public.dec_notif_signature_soignant_recue()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_lien text;
BEGIN
  -- Détecter la transition : signature_soignant passe de NULL/FALSE à TRUE
  -- alors que signature_etablissement est encore FALSE/NULL
  IF NEW.signature_soignant IS NOT TRUE THEN RETURN NEW; END IF;
  IF OLD.signature_soignant = TRUE THEN RETURN NEW; END IF;
  IF NEW.signature_etablissement IS TRUE THEN RETURN NEW; END IF;
  -- Skip si contrat déjà complet ou inactif
  IF NEW.statut IN ('SIGNE_COMPLET','ANNULE','EXPIRE','REFUSE') THEN RETURN NEW; END IF;

  v_lien := 'https://app.jolene.app/contrat/' || NEW.id::text;

  -- Email étab : "Le soignant a signé, c'est à votre tour"
  BEGIN
    PERFORM net.http_post(
      url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/send-email',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
      ),
      body := jsonb_build_object(
        'type', 'CONTRAT_A_SIGNER',
        'destinataire_id', NEW.etablissement_id,
        'data', jsonb_build_object(
          'numero_contrat', NEW.numero_contrat,
          'type_contrat', NEW.type_contrat,
          'lien', v_lien,
          'signataire_precedent', 'soignant'
        )
      )
    );
  EXCEPTION WHEN OTHERS THEN NULL; END;

  -- Push étab
  BEGIN
    PERFORM net.http_post(
      url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
      ),
      body := jsonb_build_object(
        'destinataire_id', NEW.etablissement_id,
        'type_evenement', 'CONTRAT_A_SIGNER',
        'titre', 'Le soignant a signé — à votre tour',
        'corps', 'Le contrat ' || COALESCE(NEW.numero_contrat, '') || ' attend votre signature.',
        'data', jsonb_build_object('contrat_id', NEW.id, 'lien', v_lien)
      )
    );
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_dec_notif_signature_soignant_recue ON public.contrats_mission;
CREATE TRIGGER trg_dec_notif_signature_soignant_recue
  AFTER UPDATE OF signature_soignant ON public.contrats_mission
  FOR EACH ROW EXECUTE FUNCTION public.dec_notif_signature_soignant_recue();

-- 2. Cron DPAE_RAPPEL J+1 pour CDD signés sans DPAE déclarée
CREATE OR REPLACE FUNCTION public.fn_rappel_dpae_quotidien()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_contrat RECORD;
  v_count int := 0;
BEGIN
  -- Sélection : contrats CDD signés complet, sans DPAE faite, datant de moins
  -- de 7 jours (au-delà, on arrête de spammer)
  FOR v_contrat IN
    SELECT cm.id, cm.numero_contrat, cm.etablissement_id, cm.soignant_id
    FROM public.contrats_mission cm
    WHERE cm.statut = 'SIGNE_COMPLET'
      AND cm.type_contrat IN ('CDD', 'CDDU', 'SALARIE')
      AND COALESCE(cm.dpae_effectuee, false) = false
      AND cm.signature_soignant_le > NOW() - INTERVAL '7 days'
      AND cm.signature_soignant_le < NOW() - INTERVAL '1 day'
  LOOP
    BEGIN
      PERFORM net.http_post(
        url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/send-push',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
        ),
        body := jsonb_build_object(
          'destinataire_id', v_contrat.etablissement_id,
          'type_evenement', 'DPAE_RAPPEL',
          'titre', 'Rappel DPAE',
          'corps', 'Contrat ' || COALESCE(v_contrat.numero_contrat, '') ||
                   ' : la DPAE URSSAF doit être déclarée avant la prise de poste.',
          'data', jsonb_build_object('contrat_id', v_contrat.id,
            'lien', 'https://app.jolene.app/contrat/' || v_contrat.id::text)
        )
      );
    EXCEPTION WHEN OTHERS THEN NULL; END;
    v_count := v_count + 1;
  END LOOP;

  IF v_count > 0 THEN
    INSERT INTO public.journaux_audit (
      acteur_id, type_acteur, action, type_ressource, id_ressource, details
    ) VALUES (
      '00000000-0000-0000-0000-000000000000', 'SYSTEME',
      'SYSTEM', 'cron', NULL,
      jsonb_build_object(
        'evenement', 'DPAE_RAPPEL_QUOTIDIEN',
        'count', v_count, 'exec_le', NOW()
      )
    );
  END IF;

  RETURN jsonb_build_object('success', true, 'count', v_count);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_rappel_dpae_quotidien() TO service_role;

-- 3. Cron détection no-show soignant T+30min (rappel push, pas litige auto)
CREATE OR REPLACE FUNCTION public.fn_rappel_pointage_arrivee()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_mission RECORD;
  v_count int := 0;
BEGIN
  -- Sélection : missions assignées ou EN_COURS avec debut_le passé de 30min à 2h
  -- et SANS presence enregistrée
  FOR v_mission IN
    SELECT m.id, m.intitule, m.soignant_assigne_id
    FROM public.missions m
    WHERE m.statut IN ('ASSIGNEE','EN_COURS')
      AND m.debut_le > NOW() - INTERVAL '2 hours'
      AND m.debut_le < NOW() - INTERVAL '30 minutes'
      AND m.soignant_assigne_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM public.presences p
        WHERE p.mission_id = m.id AND p.soignant_id = m.soignant_assigne_id
      )
  LOOP
    BEGIN
      PERFORM net.http_post(
        url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/send-push',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
        ),
        body := jsonb_build_object(
          'destinataire_id', v_mission.soignant_assigne_id,
          'type_evenement', 'POINTAGE_MANQUANT',
          'titre', 'Pointez votre arrivée 📍',
          'corps', 'Mission ' || COALESCE(v_mission.intitule, '') ||
                   ' : pensez à pointer votre arrivée dans l''application.',
          'data', jsonb_build_object('mission_id', v_mission.id,
            'lien', 'https://app.jolene.app/soignant/missions/' || v_mission.id::text)
        )
      );
    EXCEPTION WHEN OTHERS THEN NULL; END;
    v_count := v_count + 1;
  END LOOP;

  RETURN jsonb_build_object('success', true, 'count', v_count);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_rappel_pointage_arrivee() TO service_role;

-- 4. Schedule des 2 crons via pg_cron.
-- Dollar-quoting : DO block en $body$ + strings cron.schedule en simple quote
-- pour éviter le parser conflit qui faisait échouer supabase db push.
DO $body$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('jolene_rappel_dpae_quotidien')
      WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'jolene_rappel_dpae_quotidien');
    PERFORM cron.schedule('jolene_rappel_dpae_quotidien',
      '0 9 * * *',  -- chaque jour à 09:00
      'SELECT public.fn_rappel_dpae_quotidien()');

    PERFORM cron.unschedule('jolene_rappel_pointage')
      WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'jolene_rappel_pointage');
    PERFORM cron.schedule('jolene_rappel_pointage',
      '*/15 * * * *',  -- toutes les 15 min
      'SELECT public.fn_rappel_pointage_arrivee()');
  END IF;
END $body$;

-- 5. Audit
INSERT INTO public.journaux_audit (
  acteur_id, type_acteur, action, type_ressource, id_ressource, details
) VALUES (
  '00000000-0000-0000-0000-000000000000', 'SYSTEME',
  'SYSTEM', 'fonction', NULL,
  jsonb_build_object(
    'evenement', 'SPRINT3_PR6_BUGFIXES_AUDIT_INSTALLED',
    'pr', 'PR 6 Sprint 3',
    'fixes', ARRAY[
      'Trigger signature_soignant_recue → email + push étab',
      'Cron daily fn_rappel_dpae_quotidien (CDD signés sans DPAE J+1 à J+7)',
      'Cron 15min fn_rappel_pointage_arrivee (no-show T+30min à T+2h)'
    ]
  )
);
