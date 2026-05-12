-- PR 7 Sprint 1 — Workflow post-signature
--
-- Intègre les PR 1-6 : triggers qui orchestrent les emails et notifications
-- aux moments clés du cycle de signature contrat.
--
-- Triggers ajoutés :
-- 1. dec_email_contrat_a_signer : AFTER INSERT contrats_mission → envoi
--    email CONTRAT_A_SIGNER au soignant (et à l'étab) avec lien direct
--    vers la page de signature.
-- 2. dec_email_contrat_signe_complet : AFTER UPDATE contrats_mission
--    quand statut passe à SIGNE_COMPLET → emails confirmation aux 2
--    parties + log post-signature (DPAE rappel pour CDD via
--    BandeauRappelDPAE côté UI, pas trigger backend ici car v1
--    Option A nécessite action manuelle étab).

-- 1. Trigger AFTER INSERT contrats_mission → CONTRAT_A_SIGNER soignant
CREATE OR REPLACE FUNCTION public.dec_email_contrat_a_signer()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_lien text;
BEGIN
  -- Ne tirer l'email que pour les contrats en attente de signature
  IF NEW.statut NOT IN ('EN_ATTENTE_SIGNATURES', 'EN_ATTENTE_SIGNATURE') THEN
    RETURN NEW;
  END IF;

  v_lien := 'https://app.jolene.app/contrat/' || NEW.id::text;

  -- Email soignant (best-effort, via net.http_post)
  BEGIN
    PERFORM net.http_post(
      url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/send-email',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
      ),
      body := jsonb_build_object(
        'type', 'CONTRAT_A_SIGNER',
        'destinataire_id', NEW.soignant_id,
        'data', jsonb_build_object(
          'numero_contrat', NEW.numero_contrat,
          'type_contrat', NEW.type_contrat,
          'lien', v_lien
        )
      )
    );
  EXCEPTION WHEN OTHERS THEN
    NULL; -- net pas dispo ou erreur réseau : silencieux
  END;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_dec_email_contrat_a_signer ON public.contrats_mission;
CREATE TRIGGER trg_dec_email_contrat_a_signer
  AFTER INSERT ON public.contrats_mission
  FOR EACH ROW EXECUTE FUNCTION public.dec_email_contrat_a_signer();

-- 2. Trigger AFTER UPDATE contrats_mission → CONTRAT_SIGNE quand 2 parties
CREATE OR REPLACE FUNCTION public.dec_email_contrat_signe_complet()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_lien text;
BEGIN
  -- Ne tirer que sur transition vers SIGNE_COMPLET
  IF OLD.statut = 'SIGNE_COMPLET' OR NEW.statut != 'SIGNE_COMPLET' THEN
    RETURN NEW;
  END IF;

  v_lien := 'https://app.jolene.app/contrat/' || NEW.id::text;

  -- Email soignant
  BEGIN
    PERFORM net.http_post(
      url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/send-email',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
      ),
      body := jsonb_build_object(
        'type', 'CONTRAT_SIGNE',
        'destinataire_id', NEW.soignant_id,
        'data', jsonb_build_object(
          'numero_contrat', NEW.numero_contrat,
          'lien', v_lien
        )
      )
    );
  EXCEPTION WHEN OTHERS THEN NULL; END;

  -- Email étab
  BEGIN
    PERFORM net.http_post(
      url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/send-email',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
      ),
      body := jsonb_build_object(
        'type', 'CONTRAT_SIGNE',
        'destinataire_id', NEW.etablissement_id,
        'data', jsonb_build_object(
          'numero_contrat', NEW.numero_contrat,
          'lien', v_lien
        )
      )
    );
  EXCEPTION WHEN OTHERS THEN NULL; END;

  -- Audit
  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    '00000000-0000-0000-0000-000000000000', 'SYSTEME',
    'CONTRAT_SIGNE', 'contrat_mission', NEW.id,
    jsonb_build_object(
      'evenement', 'CONTRAT_SIGNE_COMPLET_AUTO',
      'numero_contrat', NEW.numero_contrat,
      'type_contrat', NEW.type_contrat,
      'mode_signature', NEW.mode_signature,
      'dpae_requise', (NEW.type_contrat IN ('CDD', 'CDDU'))
    )
  );

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_dec_email_contrat_signe_complet ON public.contrats_mission;
CREATE TRIGGER trg_dec_email_contrat_signe_complet
  AFTER UPDATE OF statut ON public.contrats_mission
  FOR EACH ROW EXECUTE FUNCTION public.dec_email_contrat_signe_complet();

-- 3. Audit installation
INSERT INTO public.journaux_audit (
  acteur_id, type_acteur, action, type_ressource, id_ressource, details
) VALUES (
  '00000000-0000-0000-0000-000000000000', 'SYSTEME',
  'SYSTEM', 'fonction', NULL,
  jsonb_build_object(
    'evenement', 'WORKFLOW_POST_SIGNATURE_INSTALLED',
    'pr', 'PR 7 Sprint 1 (FINALE)',
    'triggers_crees', ARRAY[
      'trg_dec_email_contrat_a_signer',
      'trg_dec_email_contrat_signe_complet'
    ],
    'note', 'DPAE auto Option A : génération PDF reste manuelle (étab clique). Cron/automatique = Sprint 2.'
  )
);
