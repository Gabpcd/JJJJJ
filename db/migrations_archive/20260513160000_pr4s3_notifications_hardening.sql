-- PR 4 Sprint 3 — Hardening notifications push (production-grade)
--
-- Audit Sprint 3 a révélé :
--   1. tokens_push pas nettoyés au logout → orphelins + fuites privées
--   2. fn_nettoyer_tokens_push existe mais pas schedulée via pg_cron
--   3. Pas de RPC sécurisée pour delete les tokens d'un user spécifique
--   4. Triggers DB auto-push manquants sur événements critiques
--      (CONTRAT_A_SIGNER notamment — l'email part déjà via PR 7 S1
--       mais pas le push)
--
-- Fixes :
--   - RPC fn_supprimer_mes_tokens_push pour cleanup au logout
--   - Cron pg_cron quotidien sur fn_nettoyer_tokens_push (tokens 90j+)
--   - Trigger AFTER INSERT contrats_mission → push CONTRAT_A_SIGNER
--     (complément du trigger email PR 7 S1)
--   - Trigger AFTER UPDATE contrats_mission statut → SIGNE_COMPLET
--     → push CONTRAT_SIGNE aux 2 parties

-- 1. RPC : suppression des tokens push du user courant (logout, etc.)
CREATE OR REPLACE FUNCTION public.fn_supprimer_mes_tokens_push()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_count int;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;

  DELETE FROM public.tokens_push WHERE utilisateur_id = v_uid;
  GET DIAGNOSTICS v_count = ROW_COUNT;

  RETURN jsonb_build_object('success', true, 'tokens_supprimes', v_count);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_supprimer_mes_tokens_push() TO authenticated;

-- 2. Cron quotidien pour purger les tokens inactifs > 90 jours.
-- Dollar-quoting : DO block en $body$ pour ne pas conflicter avec les
-- strings de cron.schedule (cf. PR 3 Sprint 3 fix).
DO $body$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('jolene_nettoyer_tokens_push')
      WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'jolene_nettoyer_tokens_push');

    PERFORM cron.schedule(
      'jolene_nettoyer_tokens_push',
      '30 3 * * *',  -- chaque jour à 03:30
      'SELECT public.fn_nettoyer_tokens_push()'
    );
  END IF;
END $body$;

-- 3. Trigger AFTER INSERT contrats_mission → push CONTRAT_A_SIGNER au soignant
CREATE OR REPLACE FUNCTION public.dec_push_contrat_a_signer()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.statut NOT IN ('EN_ATTENTE_SIGNATURES', 'EN_ATTENTE_SIGNATURE') THEN
    RETURN NEW;
  END IF;

  -- Best-effort : push via send-push edge function
  BEGIN
    PERFORM net.http_post(
      url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
      ),
      body := jsonb_build_object(
        'destinataire_id', NEW.soignant_id,
        'type_evenement', 'CONTRAT_A_SIGNER',
        'titre', 'Contrat à signer',
        'corps', 'Vous avez un nouveau contrat ' || COALESCE(NEW.numero_contrat, '') || ' à signer.',
        'data', jsonb_build_object(
          'contrat_id', NEW.id,
          'lien', 'https://app.jolene.app/contrat/' || NEW.id::text
        )
      )
    );
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_dec_push_contrat_a_signer ON public.contrats_mission;
CREATE TRIGGER trg_dec_push_contrat_a_signer
  AFTER INSERT ON public.contrats_mission
  FOR EACH ROW EXECUTE FUNCTION public.dec_push_contrat_a_signer();

-- 4. Trigger AFTER UPDATE statut → SIGNE_COMPLET → push aux 2 parties
CREATE OR REPLACE FUNCTION public.dec_push_contrat_signe_complet()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF OLD.statut = 'SIGNE_COMPLET' OR NEW.statut != 'SIGNE_COMPLET' THEN
    RETURN NEW;
  END IF;

  -- Push soignant
  BEGIN
    PERFORM net.http_post(
      url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
      ),
      body := jsonb_build_object(
        'destinataire_id', NEW.soignant_id,
        'type_evenement', 'CONTRAT_SIGNE',
        'titre', 'Contrat signé ✅',
        'corps', 'Mission confirmée : contrat ' || COALESCE(NEW.numero_contrat, '') || ' signé par les 2 parties.',
        'data', jsonb_build_object(
          'contrat_id', NEW.id,
          'lien', 'https://app.jolene.app/contrat/' || NEW.id::text
        )
      )
    );
  EXCEPTION WHEN OTHERS THEN NULL; END;

  -- Push étab (destinataire_id = etablissement_id qui est un user_id admin
  --   étab dans la convention Jolene)
  BEGIN
    PERFORM net.http_post(
      url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
      ),
      body := jsonb_build_object(
        'destinataire_id', NEW.etablissement_id,
        'type_evenement', 'CONTRAT_SIGNE',
        'titre', 'Contrat signé ✅',
        'corps', 'Mission confirmée : contrat ' || COALESCE(NEW.numero_contrat, '') || '.',
        'data', jsonb_build_object(
          'contrat_id', NEW.id,
          'lien', 'https://app.jolene.app/contrat/' || NEW.id::text
        )
      )
    );
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_dec_push_contrat_signe_complet ON public.contrats_mission;
CREATE TRIGGER trg_dec_push_contrat_signe_complet
  AFTER UPDATE OF statut ON public.contrats_mission
  FOR EACH ROW EXECUTE FUNCTION public.dec_push_contrat_signe_complet();

-- 5. Audit
INSERT INTO public.journaux_audit (
  acteur_id, type_acteur, action, type_ressource, id_ressource, details
) VALUES (
  '00000000-0000-0000-0000-000000000000', 'SYSTEME',
  'SYSTEM', 'fonction', NULL,
  jsonb_build_object(
    'evenement', 'SPRINT3_PR4_NOTIFICATIONS_HARDENED',
    'pr', 'PR 4 Sprint 3',
    'modifications', ARRAY[
      'fn_supprimer_mes_tokens_push : cleanup au logout',
      'pg_cron daily fn_nettoyer_tokens_push (tokens > 90j)',
      'trg_dec_push_contrat_a_signer : push auto sur INSERT contrat',
      'trg_dec_push_contrat_signe_complet : push auto sur SIGNE_COMPLET'
    ]
  )
);
