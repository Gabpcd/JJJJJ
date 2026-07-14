-- Les comptes de démonstration conservent contrats et notifications pour les
-- captures Store, sans jamais déclencher d'email, de push ni d'audit de
-- signature réel. Le rattachement est vérifié depuis les trois identifiants
-- persistés sur le contrat, et toute provenance incomplète est fail-closed.

CREATE OR REPLACE FUNCTION private.fn_contrat_lie_compte_test(
  p_mission_id uuid,
  p_soignant_id uuid,
  p_etablissement_id uuid
) RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT COALESCE((
    SELECT
      m.etablissement_id IS DISTINCT FROM p_etablissement_id
      OR m.soignant_assigne_id IS DISTINCT FROM p_soignant_id
      OR e_contrat.est_compte_test IS TRUE
      OR s_contrat.est_compte_test IS TRUE
      OR e_mission.est_compte_test IS TRUE
      OR s_mission.est_compte_test IS TRUE
    FROM public.missions m
    JOIN public.etablissements e_mission
      ON e_mission.id = m.etablissement_id
    JOIN public.soignants s_mission
      ON s_mission.id = m.soignant_assigne_id
    JOIN public.etablissements e_contrat
      ON e_contrat.id = p_etablissement_id
    JOIN public.soignants s_contrat
      ON s_contrat.id = p_soignant_id
    WHERE m.id = p_mission_id
  ), true);
$function$;

COMMENT ON FUNCTION private.fn_contrat_lie_compte_test(uuid, uuid, uuid) IS
  'Interne serveur : bloque les effets externes si le contrat ou sa mission touche un compte test, ou si leur provenance est incomplète/incohérente.';

REVOKE ALL ON FUNCTION private.fn_contrat_lie_compte_test(uuid, uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.fn_contrat_lie_compte_test(uuid, uuid, uuid)
  TO service_role;

CREATE OR REPLACE FUNCTION public.dec_email_contrat_a_signer()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_lien text;
BEGIN
  IF private.fn_contrat_lie_compte_test(
       NEW.mission_id, NEW.soignant_id, NEW.etablissement_id
     ) IS NOT FALSE THEN
    RETURN NEW;
  END IF;

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
        'Authorization', 'Bearer ' || (
          SELECT decrypted_secret
          FROM vault.decrypted_secrets
          WHERE name = 'service_role_key'
          LIMIT 1
        )
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

CREATE OR REPLACE FUNCTION public.dec_email_contrat_signe_complet()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_lien text;
BEGIN
  IF private.fn_contrat_lie_compte_test(
       NEW.mission_id, NEW.soignant_id, NEW.etablissement_id
     ) IS NOT FALSE THEN
    RETURN NEW;
  END IF;

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
        'Authorization', 'Bearer ' || (
          SELECT decrypted_secret
          FROM vault.decrypted_secrets
          WHERE name = 'service_role_key'
          LIMIT 1
        )
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
        'Authorization', 'Bearer ' || (
          SELECT decrypted_secret
          FROM vault.decrypted_secrets
          WHERE name = 'service_role_key'
          LIMIT 1
        )
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
      'dpae_requise', (NEW.type_contrat IN ('CDD', 'CDD'))
    )
  );

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.dec_notif_signature_soignant_recue()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_lien text;
BEGIN
  IF private.fn_contrat_lie_compte_test(
       NEW.mission_id, NEW.soignant_id, NEW.etablissement_id
     ) IS NOT FALSE THEN
    RETURN NEW;
  END IF;

  IF NEW.signature_soignant IS NOT TRUE THEN RETURN NEW; END IF;
  IF OLD.signature_soignant = TRUE THEN RETURN NEW; END IF;
  IF NEW.signature_etablissement IS TRUE THEN RETURN NEW; END IF;
  IF NEW.statut IN ('SIGNE_COMPLET','ANNULE','EXPIRE','REFUSE') THEN RETURN NEW; END IF;
  v_lien := 'https://app.jolene.app/contrat/' || NEW.id::text;
  BEGIN
    PERFORM net.http_post(
      url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/send-email',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (
          SELECT decrypted_secret
          FROM vault.decrypted_secrets
          WHERE name = 'service_role_key'
          LIMIT 1
        )
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
  BEGIN
    PERFORM net.http_post(
      url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (
          SELECT decrypted_secret
          FROM vault.decrypted_secrets
          WHERE name = 'service_role_key'
          LIMIT 1
        )
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

CREATE OR REPLACE FUNCTION public.dec_push_contrat_a_signer()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  IF private.fn_contrat_lie_compte_test(
       NEW.mission_id, NEW.soignant_id, NEW.etablissement_id
     ) IS NOT FALSE THEN
    RETURN NEW;
  END IF;

  IF NEW.statut NOT IN ('EN_ATTENTE_SIGNATURES', 'EN_ATTENTE_SIGNATURE') THEN
    RETURN NEW;
  END IF;
  BEGIN
    PERFORM net.http_post(
      url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (
          SELECT decrypted_secret
          FROM vault.decrypted_secrets
          WHERE name = 'service_role_key'
          LIMIT 1
        )
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

CREATE OR REPLACE FUNCTION public.dec_push_contrat_signe_complet()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  IF private.fn_contrat_lie_compte_test(
       NEW.mission_id, NEW.soignant_id, NEW.etablissement_id
     ) IS NOT FALSE THEN
    RETURN NEW;
  END IF;

  IF OLD.statut = 'SIGNE_COMPLET' OR NEW.statut != 'SIGNE_COMPLET' THEN
    RETURN NEW;
  END IF;
  BEGIN
    PERFORM net.http_post(
      url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (
          SELECT decrypted_secret
          FROM vault.decrypted_secrets
          WHERE name = 'service_role_key'
          LIMIT 1
        )
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
  BEGIN
    PERFORM net.http_post(
      url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (
          SELECT decrypted_secret
          FROM vault.decrypted_secrets
          WHERE name = 'service_role_key'
          LIMIT 1
        )
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

REVOKE ALL ON FUNCTION public.dec_email_contrat_a_signer()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.dec_email_contrat_signe_complet()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.dec_notif_signature_soignant_recue()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.dec_push_contrat_a_signer()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.dec_push_contrat_signe_complet()
  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.dec_email_contrat_a_signer() TO service_role;
GRANT EXECUTE ON FUNCTION public.dec_email_contrat_signe_complet() TO service_role;
GRANT EXECUTE ON FUNCTION public.dec_notif_signature_soignant_recue() TO service_role;
GRANT EXECUTE ON FUNCTION public.dec_push_contrat_a_signer() TO service_role;
GRANT EXECUTE ON FUNCTION public.dec_push_contrat_signe_complet() TO service_role;

-- Un compte soignant de démonstration peut continuer à recevoir ses propres
-- notifications. Seules ses tentatives d'alerte vers la file ADMIN sont
-- neutralisées avant persistance, quel que soit le chemin RPC appelant.
CREATE OR REPLACE FUNCTION private.dec_bloquer_notification_admin_compte_test()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  IF NEW.type_destinataire = 'ADMIN'
     AND EXISTS (
       SELECT 1
       FROM public.soignants s
       WHERE s.id = auth.uid()
         AND s.est_compte_test IS TRUE
     ) THEN
    RETURN NULL;
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION private.dec_bloquer_notification_admin_compte_test()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.dec_bloquer_notification_admin_compte_test()
  TO service_role;

DROP TRIGGER IF EXISTS trg_bloquer_notification_admin_compte_test
  ON public.notifications;
CREATE TRIGGER trg_bloquer_notification_admin_compte_test
BEFORE INSERT ON public.notifications
FOR EACH ROW
EXECUTE FUNCTION private.dec_bloquer_notification_admin_compte_test();
