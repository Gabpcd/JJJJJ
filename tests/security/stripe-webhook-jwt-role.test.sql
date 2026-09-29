-- Aucun appel fournisseur. Événements fictifs isolés, transaction annulée.
BEGIN;
SELECT set_config('request.jwt.claim.sub','',true);
SELECT set_config('request.jwt.claim.role','',true);
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);
SET LOCAL ROLE service_role;
DO $service_json$
DECLARE v_event_id text:='evt_recette_jwt_'||gen_random_uuid(); legacy_id text:='evt_recette_jwt_legacy_'||gen_random_uuid(); r text;
BEGIN
  r:=public.fn_stripe_webhook_event_claim(v_event_id,'payment_intent.succeeded','{}','PLATFORM',false);
  IF r IS DISTINCT FROM 'CLAIMED' THEN RAISE EXCEPTION 'Service JSON refusé';END IF;
  r:=public.fn_stripe_webhook_event_claim(v_event_id,'payment_intent.succeeded','{}','PLATFORM',false);
  IF r IS DISTINCT FROM 'PROCESSING' THEN RAISE EXCEPTION 'Lease concurrent perdu';END IF;
  UPDATE public.stripe_webhook_events SET traitement_commence_le=now()-interval '6 minutes' WHERE stripe_webhook_events.event_id=v_event_id;
  r:=public.fn_stripe_webhook_event_claim(v_event_id,'payment_intent.succeeded','{}','PLATFORM',false);
  IF r IS DISTINCT FROM 'CLAIMED' THEN RAISE EXCEPTION 'Reprise de lease cassée';END IF;
  UPDATE public.stripe_webhook_events SET traite_le=now() WHERE stripe_webhook_events.event_id=v_event_id;
  r:=public.fn_stripe_webhook_event_claim(v_event_id,'payment_intent.succeeded','{}','PLATFORM',false);
  IF r IS DISTINCT FROM 'PROCESSED' THEN RAISE EXCEPTION 'Événement terminé retraité';END IF;
  IF public.fn_stripe_webhook_event_is_new(legacy_id,'payment_intent.succeeded','{}') IS DISTINCT FROM true THEN RAISE EXCEPTION 'Ancien helper JSON refusé';END IF;
  UPDATE public.stripe_webhook_events SET traite_le=now() WHERE stripe_webhook_events.event_id=legacy_id;
  IF public.fn_stripe_webhook_event_is_new(legacy_id,'payment_intent.succeeded','{}') IS DISTINCT FROM false THEN RAISE EXCEPTION 'Ancien helper idempotence cassée';END IF;
END $service_json$;
RESET ROLE;
-- Refus réel du rôle authenticated, y compris user_metadata usurpé et
-- ancienne variable service_role : le rôle signé JSON est prioritaire.
SELECT set_config('request.jwt.claim.role','service_role',true);
SELECT set_config('request.jwt.claims','{"role":"authenticated","user_metadata":{"role":"service_role"}}',true);
-- Le rôle SQL a EXECUTE ; le refus doit donc venir du contrôle interne,
-- pas seulement des ACL. Un ancien GUC service_role ne masque pas le JWT.
SET LOCAL ROLE service_role;
DO $priorite_json$
DECLARE blocked boolean:=false; v_event_id text:='evt_recette_priorite_'||gen_random_uuid();
BEGIN
  BEGIN PERFORM public.fn_stripe_webhook_event_claim(v_event_id,'payment_intent.succeeded','{}','PLATFORM',false);
  EXCEPTION WHEN insufficient_privilege THEN blocked:=true; END;
  IF NOT blocked THEN RAISE EXCEPTION 'Ancien rôle privilégié a masqué le JWT';END IF;
  blocked:=false;
  BEGIN PERFORM public.fn_stripe_webhook_event_is_new(v_event_id,'payment_intent.succeeded','{}');
  EXCEPTION WHEN insufficient_privilege THEN blocked:=true; END;
  IF NOT blocked THEN RAISE EXCEPTION 'Ancien helper ignore la priorité JWT';END IF;
END $priorite_json$;
RESET ROLE;
SET LOCAL ROLE authenticated;
DO $refus_auth$
DECLARE blocked boolean:=false; v_event_id text:='evt_recette_refused_'||gen_random_uuid();
BEGIN
  BEGIN PERFORM public.fn_stripe_webhook_event_claim(v_event_id,'payment_intent.succeeded','{}','PLATFORM',false);
  EXCEPTION WHEN insufficient_privilege THEN blocked:=true; END;
  IF NOT blocked THEN RAISE EXCEPTION 'Utilisateur autorisé à réclamer un webhook';END IF;
  blocked:=false;
  BEGIN PERFORM public.fn_stripe_webhook_event_is_new(v_event_id,'payment_intent.succeeded','{}');
  EXCEPTION WHEN insufficient_privilege THEN blocked:=true; END;
  IF NOT blocked THEN RAISE EXCEPTION 'Utilisateur autorisé dans ancien helper';END IF;
END $refus_auth$;
RESET ROLE;
SELECT set_config('request.jwt.claim.role','',true);
SELECT set_config('request.jwt.claims','{"role":"anon","user_metadata":{"role":"service_role"}}',true);
SET LOCAL ROLE anon;
DO $refus_anon$
DECLARE blocked boolean:=false;
BEGIN
  BEGIN PERFORM public.fn_stripe_webhook_event_claim('evt_recette_anon_'||gen_random_uuid(),'payment_intent.succeeded','{}','PLATFORM',false);
  EXCEPTION WHEN insufficient_privilege THEN blocked:=true; END;
  IF NOT blocked THEN RAISE EXCEPTION 'Webhook accessible anonymement';END IF;
END $refus_anon$;
RESET ROLE;
-- Compatibilité des anciens jobs qui ne disposent que de la variable dédiée.
SELECT set_config('request.jwt.claims','{}',true);
SELECT set_config('request.jwt.claim.role','service_role',true);
SET LOCAL ROLE service_role;
DO $legacy$
BEGIN
  IF public.fn_stripe_webhook_event_claim('evt_recette_legacy_'||gen_random_uuid(),'payment_intent.succeeded','{}','CONNECT',false) IS DISTINCT FROM 'CLAIMED' THEN RAISE EXCEPTION 'Legacy service refusé';END IF;
END $legacy$;
RESET ROLE;
ROLLBACK;
