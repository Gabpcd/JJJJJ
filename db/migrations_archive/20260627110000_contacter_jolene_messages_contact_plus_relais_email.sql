-- "Contacter Jolene" : un utilisateur (soignant/étab) envoie un message qui
-- atterrit dans l'espace admin (table messages_contact) + notif in-app admin +
-- relais email vers support@jolene.app (edge function notify-support).
-- Bonus : à l'ouverture d'un litige, email à support@jolene.app aussi.

CREATE TABLE IF NOT EXISTS public.messages_contact (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  expediteur_id uuid,
  expediteur_role text,
  expediteur_nom text,
  expediteur_email text,
  sujet text NOT NULL,
  corps text NOT NULL,
  source text NOT NULL DEFAULT 'aide',
  statut text NOT NULL DEFAULT 'NOUVEAU' CHECK (statut IN ('NOUVEAU','EN_COURS','TRAITE')),
  cree_le timestamptz NOT NULL DEFAULT now(),
  traite_le timestamptz,
  traite_par uuid
);

ALTER TABLE public.messages_contact ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS messages_contact_admin_all ON public.messages_contact;
CREATE POLICY messages_contact_admin_all ON public.messages_contact
  FOR ALL TO authenticated
  USING (est_admin()) WITH CHECK (est_admin());

DROP POLICY IF EXISTS messages_contact_insert_self ON public.messages_contact;
CREATE POLICY messages_contact_insert_self ON public.messages_contact
  FOR INSERT TO authenticated
  WITH CHECK (expediteur_id = auth.uid());

DROP POLICY IF EXISTS messages_contact_select_self ON public.messages_contact;
CREATE POLICY messages_contact_select_self ON public.messages_contact
  FOR SELECT TO authenticated
  USING (expediteur_id = auth.uid());

GRANT SELECT, INSERT ON public.messages_contact TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_envoyer_message_contact(p_sujet text, p_corps text, p_source text DEFAULT 'aide')
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_role text; v_nom text; v_email text;
  v_msg_id uuid;
  v_url text := 'https://flripxtsyegjshnhzjkz.supabase.co';
  v_token text;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('error', 'Non authentifié'); END IF;
  IF p_sujet IS NULL OR length(trim(p_sujet)) = 0 OR p_corps IS NULL OR length(trim(p_corps)) = 0 THEN
    RETURN jsonb_build_object('error', 'Sujet et message obligatoires');
  END IF;

  SELECT prenom || ' ' || nom, email INTO v_nom, v_email FROM soignants WHERE id = v_uid;
  IF v_nom IS NOT NULL THEN
    v_role := 'SOIGNANT';
  ELSE
    SELECT nom, email_contact INTO v_nom, v_email FROM etablissements WHERE id = v_uid;
    IF v_nom IS NOT NULL THEN v_role := 'ETABLISSEMENT'; END IF;
  END IF;

  INSERT INTO messages_contact (expediteur_id, expediteur_role, expediteur_nom, expediteur_email, sujet, corps, source)
  VALUES (v_uid, COALESCE(v_role, 'INCONNU'), v_nom, v_email,
          fn_html_escape(trim(p_sujet)), fn_html_escape(trim(p_corps)), COALESCE(p_source, 'aide'))
  RETURNING id INTO v_msg_id;

  INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien, type_ressource, id_ressource)
  SELECT a.id, 'ADMIN', 'MESSAGE_ADMIN',
    '✉️ Nouveau message — ' || COALESCE(v_nom, 'utilisateur'),
    left(trim(p_corps), 140),
    '/admin/messages-contact', 'message_contact', v_msg_id
  FROM soignants a WHERE a.role = 'ADMIN_PLATEFORME' AND a.supprime_le IS NULL LIMIT 5;

  BEGIN
    v_token := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1);
    IF v_token IS NOT NULL THEN
      PERFORM net.http_post(
        url := v_url || '/functions/v1/notify-support',
        headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_token),
        body := jsonb_build_object(
          'sujet', trim(p_sujet), 'corps', trim(p_corps),
          'expediteur_nom', v_nom, 'expediteur_email', v_email,
          'source', 'Contact ' || COALESCE(v_role, ''), 'lien', '/admin/messages-contact'
        )
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN jsonb_build_object('success', true, 'message_id', v_msg_id);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_envoyer_message_contact(text, text, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_trg_litige_notify_support()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_url text := 'https://flripxtsyegjshnhzjkz.supabase.co';
  v_token text;
BEGIN
  BEGIN
    v_token := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1);
    IF v_token IS NOT NULL THEN
      PERFORM net.http_post(
        url := v_url || '/functions/v1/notify-support',
        headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_token),
        body := jsonb_build_object(
          'sujet', 'Nouveau litige ouvert (' || COALESCE(NEW.type_litige::text, '') || ')',
          'corps', COALESCE(NEW.motif, '(sans motif)'),
          'source', 'Litige',
          'lien', '/admin/litiges'
        )
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN NULL; END;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_litige_notify_support ON public.litiges;
CREATE TRIGGER trg_litige_notify_support
  AFTER INSERT ON public.litiges
  FOR EACH ROW EXECUTE FUNCTION public.fn_trg_litige_notify_support();
