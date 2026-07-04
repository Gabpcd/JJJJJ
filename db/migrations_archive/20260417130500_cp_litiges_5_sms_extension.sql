-- ============================================================
-- CP-LITIGES-5 — Extension fn_litige_push_notification pour SMS
-- ============================================================
-- Étend la function helper créée en CP4 pour :
--   1. Insérer aussi un row SMS_ dans email_queue pour les types
--      éligibles (LITIGE_OUVERTURE, REMBOURSEMENT_CONFIRME,
--      LITIGE_RAPPEL_J1/J3/J5).
--   2. Lookup automatique du téléphone du destinataire via
--      soignants.telephone ou etablissements.telephone_contact (pattern JWT).
--
-- email-cron route les types SMS_* vers send-sms (passthrough contenu).
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_litige_push_notification(
  p_destinataire_id UUID,
  p_type_destinataire TEXT,
  p_type_notif TEXT,
  p_titre TEXT,
  p_corps TEXT,
  p_litige_id UUID,
  p_email_data JSONB DEFAULT '{}'::jsonb
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_telephone TEXT;
  v_sms_eligible BOOLEAN;
  v_sms_contenu TEXT;
  v_lien TEXT;
BEGIN
  -- Lien contextuel
  v_lien := CASE p_type_destinataire
    WHEN 'SOIGNANT'       THEN '/soignant/litiges'
    WHEN 'ETABLISSEMENT'  THEN '/etablissement/litiges'
    WHEN 'ADMIN'          THEN '/admin/moderation'
    ELSE NULL
  END;

  -- 1. Notification in-app
  INSERT INTO public.notifications (
    destinataire_id, type_destinataire, type, titre, corps,
    id_ressource, type_ressource, lien
  ) VALUES (
    p_destinataire_id, p_type_destinataire, p_type_notif, p_titre, p_corps,
    p_litige_id, 'litige', v_lien
  );

  -- 2. Email via email_queue
  INSERT INTO public.email_queue (type, destinataire_id, data)
  VALUES (
    p_type_notif,
    p_destinataire_id,
    p_email_data || jsonb_build_object('litige_id', p_litige_id, 'url_litige', v_lien)
  );

  -- 3. SMS pour types éligibles (email-cron route SMS_* vers send-sms)
  v_sms_eligible := p_type_notif IN (
    'LITIGE_OUVERTURE',
    'REMBOURSEMENT_CONFIRME',
    'LITIGE_RAPPEL_J1',
    'LITIGE_RAPPEL_J3',
    'LITIGE_RAPPEL_J5'
  );

  IF NOT v_sms_eligible THEN
    RETURN;
  END IF;

  -- Lookup téléphone
  IF p_type_destinataire = 'SOIGNANT' THEN
    SELECT s.telephone INTO v_telephone
      FROM public.soignants s WHERE s.id = p_destinataire_id;
  ELSIF p_type_destinataire = 'ETABLISSEMENT' THEN
    SELECT e.telephone_contact INTO v_telephone
      FROM public.etablissements e
     WHERE e.id = p_destinataire_id;
  END IF;

  IF v_telephone IS NULL OR length(trim(v_telephone)) < 10 THEN
    RETURN;
  END IF;

  -- Générer le body SMS (max ~140 car Jolene: préfixe ajouté par send-sms)
  v_sms_contenu := CASE p_type_notif
    WHEN 'LITIGE_OUVERTURE'       THEN 'un litige ' || COALESCE(p_email_data->>'type_litige', '') || ' a été ouvert sur votre mission. Répondez sous 72h.'
    WHEN 'REMBOURSEMENT_CONFIRME' THEN 'remboursement de ' || COALESCE(p_email_data->>'montant', '?') || '€ effectué (avoir ' || COALESCE(p_email_data->>'numero_avoir', '') || '). Délai bancaire 2-5j.'
    WHEN 'LITIGE_RAPPEL_J1'       THEN 'litige en attente depuis 1j. Répondez sous 24h pour éviter l''escalade.'
    WHEN 'LITIGE_RAPPEL_J3'       THEN 'litige en attente depuis 3j. Réponse urgente requise.'
    WHEN 'LITIGE_RAPPEL_J5'       THEN 'litige en attente depuis 5j ouvrés. Escalade imminente.'
    ELSE p_corps
  END;

  INSERT INTO public.email_queue (type, destinataire_id, data)
  VALUES (
    'SMS_' || p_type_notif,
    p_destinataire_id,
    jsonb_build_object(
      'telephone', v_telephone,
      'contenu', v_sms_contenu,
      'litige_id', p_litige_id
    )
  );
END;
$$;

COMMIT;
