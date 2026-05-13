-- ============================================================================
-- Sprint 6 PR 1 — Wire email INVITATION_EQUIPE_ETAB sur INSERT invitations_etablissement
-- ============================================================================
-- Suite Sprint 5.7 PR 4 follow-up : envoi automatique email à l'invité
-- via net.http_post vers l'edge function send-email avec destinataire_email
-- (flow externe, l'invité peut ne pas avoir de compte auth.users).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.dec_email_invitation_equipe_etab()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $body$
DECLARE
  v_etab_nom text;
  v_invite_par_email text;
  v_invite_par_nom text;
BEGIN
  -- Ne tirer l'email que pour les invitations EN_ATTENTE fraîches
  IF NEW.statut != 'EN_ATTENTE' THEN
    RETURN NEW;
  END IF;

  -- Récupérer nom étab
  SELECT nom INTO v_etab_nom FROM public.etablissements WHERE id = NEW.etablissement_id;
  IF v_etab_nom IS NULL THEN
    RETURN NEW;
  END IF;

  -- Récupérer nom de l'invitant (PROPRIETAIRE qui crée l'invitation)
  SELECT u.email INTO v_invite_par_email FROM auth.users u WHERE u.id = NEW.invite_par;
  v_invite_par_nom := COALESCE(v_invite_par_email, 'Un administrateur');

  -- Envoi best-effort via net.http_post → send-email edge function
  -- Flow externe : destinataire_email (l'invité peut ne pas avoir de compte)
  BEGIN
    PERFORM net.http_post(
      url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/send-email',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
      ),
      body := jsonb_build_object(
        'type', 'INVITATION_EQUIPE_ETAB',
        'destinataire_email', NEW.email_invite,
        'data', jsonb_build_object(
          'token', NEW.token,
          'nom_etablissement', v_etab_nom,
          'role', NEW.role_propose,
          'invite_par_nom', v_invite_par_nom,
          'expire_le', to_char(NEW.expire_le AT TIME ZONE 'Europe/Paris', 'DD/MM/YYYY à HH24:MI')
        )
      )
    );
  EXCEPTION WHEN OTHERS THEN
    -- net.http_post indisponible ou erreur réseau : silencieux
    -- L'UI affiche déjà le lien d'invitation pour copier/coller manuel
    NULL;
  END;

  -- Audit (action générique SYSTEM, contexte dans details)
  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    NEW.invite_par, 'SYSTEME', 'SYSTEM', 'invitation_etab', NEW.id,
    jsonb_build_object(
      'evenement', 'EMAIL_INVITATION_EQUIPE_ENVOYE',
      'destinataire_email', NEW.email_invite,
      'etablissement_id', NEW.etablissement_id,
      'role_propose', NEW.role_propose
    )
  );

  RETURN NEW;
END;
$body$;

DROP TRIGGER IF EXISTS trg_email_invitation_equipe_etab ON public.invitations_etablissement;

CREATE TRIGGER trg_email_invitation_equipe_etab
AFTER INSERT ON public.invitations_etablissement
FOR EACH ROW
EXECUTE FUNCTION public.dec_email_invitation_equipe_etab();

-- Audit installation
INSERT INTO public.journaux_audit (
  acteur_id, type_acteur, action, type_ressource, id_ressource, details
) VALUES (
  '00000000-0000-0000-0000-000000000000', 'SYSTEME',
  'SYSTEM', 'fonction', NULL,
  jsonb_build_object(
    'evenement', 'SPRINT6_PR1_TRIGGER_EMAIL_INVITATION_INSTALLED',
    'pr', 'PR 1 Sprint 6',
    'trigger', 'trg_email_invitation_equipe_etab',
    'fonction', 'dec_email_invitation_equipe_etab'
  )
);
