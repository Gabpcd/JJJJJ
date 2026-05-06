-- J2.3.A — Préférences notifications granulaires

DO $$ BEGIN
  CREATE TYPE public.type_evenement_notification AS ENUM (
    'NOUVELLE_MISSION_MATCHANT_FILTRE','CANDIDATURE_RECUE','CANDIDATURE_ACCEPTEE',
    'MISSION_ASSIGNEE','RAPPEL_J1_MISSION','POINTAGE_MANQUANT','FACTURE_EMISE',
    'PAIEMENT_RECU','CONTRAT_TRAVAIL_DEPOSE','LITIGE_OUVERT','LITIGE_RESOLU',
    'DOCUMENT_EXPIRANT','MANDAT_RE_SIGNATURE','SERIE_ONBOARDING','URGENCE'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.canal_notification AS ENUM ('EMAIL','SMS','PUSH','IN_APP');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS public.preferences_notifications (
  utilisateur_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  canal_email boolean NOT NULL DEFAULT true,
  canal_sms boolean NOT NULL DEFAULT false,
  canal_push boolean NOT NULL DEFAULT true,
  canal_in_app boolean NOT NULL DEFAULT true,
  cree_le timestamptz NOT NULL DEFAULT now(),
  mis_a_jour_le timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.preferences_notifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY pn_select_own ON public.preferences_notifications FOR SELECT TO authenticated USING (utilisateur_id = auth.uid() OR est_admin());
CREATE POLICY pn_insert_own ON public.preferences_notifications FOR INSERT TO authenticated WITH CHECK (utilisateur_id = auth.uid());
CREATE POLICY pn_update_own ON public.preferences_notifications FOR UPDATE TO authenticated USING (utilisateur_id = auth.uid()) WITH CHECK (utilisateur_id = auth.uid());
GRANT SELECT, INSERT, UPDATE ON public.preferences_notifications TO authenticated;

CREATE TABLE IF NOT EXISTS public.preferences_notifications_par_evenement (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  utilisateur_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  type_evenement public.type_evenement_notification NOT NULL,
  canal public.canal_notification NOT NULL,
  actif boolean NOT NULL DEFAULT true,
  cree_le timestamptz NOT NULL DEFAULT now(),
  mis_a_jour_le timestamptz NOT NULL DEFAULT now(),
  UNIQUE (utilisateur_id, type_evenement, canal)
);
CREATE INDEX IF NOT EXISTS idx_pn_pe_user_event_canal ON public.preferences_notifications_par_evenement (utilisateur_id, type_evenement, canal);

ALTER TABLE public.preferences_notifications_par_evenement ENABLE ROW LEVEL SECURITY;
CREATE POLICY pnpe_select_own ON public.preferences_notifications_par_evenement FOR SELECT TO authenticated USING (utilisateur_id = auth.uid() OR est_admin());
CREATE POLICY pnpe_insert_own ON public.preferences_notifications_par_evenement FOR INSERT TO authenticated WITH CHECK (utilisateur_id = auth.uid());
CREATE POLICY pnpe_update_own ON public.preferences_notifications_par_evenement FOR UPDATE TO authenticated USING (utilisateur_id = auth.uid()) WITH CHECK (utilisateur_id = auth.uid());
CREATE POLICY pnpe_delete_own ON public.preferences_notifications_par_evenement FOR DELETE TO authenticated USING (utilisateur_id = auth.uid());
GRANT SELECT, INSERT, UPDATE, DELETE ON public.preferences_notifications_par_evenement TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_trg_pn_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.mis_a_jour_le := now(); RETURN NEW; END $$;
DROP TRIGGER IF EXISTS trg_pn_updated_at ON public.preferences_notifications;
CREATE TRIGGER trg_pn_updated_at BEFORE UPDATE ON public.preferences_notifications FOR EACH ROW EXECUTE FUNCTION public.fn_trg_pn_updated_at();
DROP TRIGGER IF EXISTS trg_pnpe_updated_at ON public.preferences_notifications_par_evenement;
CREATE TRIGGER trg_pnpe_updated_at BEFORE UPDATE ON public.preferences_notifications_par_evenement FOR EACH ROW EXECUTE FUNCTION public.fn_trg_pn_updated_at();

-- Étendre journaux_audit.action_check
ALTER TABLE public.journaux_audit DROP CONSTRAINT IF EXISTS journaux_audit_action_check;
ALTER TABLE public.journaux_audit ADD CONSTRAINT journaux_audit_action_check CHECK (action IN (
  'INSCRIPTION','CONNEXION','DECONNEXION','MODIFICATION_PROFIL','SUPPRESSION_COMPTE',
  'UPLOAD_DOCUMENT','TELECHARGEMENT_DOCUMENT','VERIFICATION_DOCUMENT','VERIFICATION_RPPS',
  'CREATION_MISSION','MODIFICATION_MISSION','ANNULATION_MISSION','CANDIDATURE','ASSIGNATION',
  'POINTAGE','SIGNATURE_CONTRAT','EVALUATION','PAIEMENT','FACTURATION',
  'DONNEES_PERSO_CONSULTATION','DONNEES_PERSO_EXPORT','DONNEES_PERSO_SUPPRESSION',
  'ADMIN_ACTION','SYSTEM','RIB_CONSULTE','RIB_PARTAGE','CONTRAT_SIGNE',
  'DOCUMENT_CONSULTATION','DOCUMENT_TELEVERSEMENT','DONNEES_PERSO_MODIFICATION',
  'EXPORT_RH_PAIE','FINANCE_FACTURE_PAYEE','MISSION_ASSIGNATION','MISSION_CREATION',
  'RGPD_EXPORT_DONNEES','RGPD_SUPPRESSION_COMPTE','RGPD_SUPPRESSION_COMPTE_ETABLISSEMENT',
  'DEGEL_APPLIED','OVERRIDE_CHAMP_POST_GEL','GEL_APPLIED','OVERRIDE_ANTI_SEED',
  'CONNECT_METADATA_MANQUANTE','DOCUMENT_VERIFICATION_AUTO',
  'FACTURE_COMMISSION_PAYEE_SKIP_ANOMALIE','FACTURE_HONORAIRES_PAYEE_SKIP_ANOMALIE',
  'FINANCE_CHARGE_EXPIRED','FINANCE_CHARGE_FAILED','FINANCE_CHARGE_PENDING',
  'FINANCE_CHARGE_REFUNDED','FINANCE_DISPUTE_CLOSE','FINANCE_DISPUTE_OUVERTE',
  'FINANCE_PAYOUT_CANCELED','FINANCE_PAYOUT_CREATED','FINANCE_PAYOUT_FAILED',
  'FINANCE_PAYOUT_PAID','FINANCE_SEPA_CAPTURE','FINANCE_TRANSFER_CONNECT',
  'FINANCE_TRANSFER_CREATED','FINANCE_TRANSFER_FAILED','FINANCE_TRANSFER_REVERSED',
  'FINANCE_TRANSFER_UPDATED','STRIPE_CHECKOUT_ORPHANED_RECOVERED',
  'STRIPE_CONNECT_ACCOUNT_DELETED','ATTESTATION_SANTE_SIGNEE',
  'EXCLUSION_CREEE','EXCLUSION_SUPPRIMEE','FACTURE_GENEREE',
  'MISSION_ANNULATION_SERIE','MISSION_MODIFICATION','PAIEMENT_SOIGNANT_DECLARE_ETAB',
  'RECLAMATION_CREEE','ADMIN_CONSULTATION_ETABLISSEMENT','ADMIN_CONSULTATION_SOIGNANT',
  'DOCUMENT_SUPPRESSION','HEURES_EXTERNES_DECLAREES','MISSION_ANNULATION',
  'NOTE_HONORAIRES_GENEREE','PRESENCE_CONTESTATION','PRESENCE_POINTAGE_ARRIVEE',
  'PRESENCE_VALIDATION','PRESENCE_VALIDATION_LOT','RGPD_CONSENTEMENT_DONNE',
  'PAIEMENT_MONTANT_ECART','FACTURE_COMMISSION_CREATED_VIA_STRIPE',
  'TAUX_COMMISSION_MODIFIE','LITIGE_GEL_SCOPE_MODIFIE',
  'PREFERENCE_NOTIFICATION_MODIFIEE','NOTIFICATION_SKIPPED'
));

-- RPC fn_doit_notifier (utilisée par send-email/sms/push avant envoi)
CREATE OR REPLACE FUNCTION public.fn_doit_notifier(
  p_utilisateur_id uuid,
  p_type_evenement public.type_evenement_notification,
  p_canal public.canal_notification
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions STABLE AS $$
DECLARE v_canal_global boolean; v_pref_event boolean;
BEGIN
  IF p_type_evenement = 'URGENCE' THEN RETURN true; END IF;
  SELECT CASE p_canal
    WHEN 'EMAIL' THEN canal_email
    WHEN 'SMS' THEN canal_sms
    WHEN 'PUSH' THEN canal_push
    WHEN 'IN_APP' THEN canal_in_app
  END INTO v_canal_global FROM preferences_notifications WHERE utilisateur_id = p_utilisateur_id;
  IF v_canal_global IS NULL THEN
    v_canal_global := CASE p_canal WHEN 'SMS' THEN false ELSE true END;
  END IF;
  IF NOT v_canal_global THEN RETURN false; END IF;
  SELECT actif INTO v_pref_event FROM preferences_notifications_par_evenement
  WHERE utilisateur_id = p_utilisateur_id AND type_evenement = p_type_evenement AND canal = p_canal;
  RETURN COALESCE(v_pref_event, true);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_doit_notifier(uuid, public.type_evenement_notification, public.canal_notification) TO authenticated, service_role;

-- RPC fn_modifier_preferences_notifications
CREATE OR REPLACE FUNCTION public.fn_modifier_preferences_notifications(
  p_canal_email boolean DEFAULT NULL, p_canal_sms boolean DEFAULT NULL,
  p_canal_push boolean DEFAULT NULL, p_canal_in_app boolean DEFAULT NULL,
  p_par_evenement jsonb DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v_uid uuid := auth.uid(); v_item jsonb;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('error','Non authentifié'); END IF;
  INSERT INTO preferences_notifications (utilisateur_id, canal_email, canal_sms, canal_push, canal_in_app)
  VALUES (v_uid, COALESCE(p_canal_email,true), COALESCE(p_canal_sms,false), COALESCE(p_canal_push,true), COALESCE(p_canal_in_app,true))
  ON CONFLICT (utilisateur_id) DO UPDATE
    SET canal_email = COALESCE(p_canal_email, preferences_notifications.canal_email),
        canal_sms = COALESCE(p_canal_sms, preferences_notifications.canal_sms),
        canal_push = COALESCE(p_canal_push, preferences_notifications.canal_push),
        canal_in_app = COALESCE(p_canal_in_app, preferences_notifications.canal_in_app);
  IF p_par_evenement IS NOT NULL THEN
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_par_evenement) LOOP
      INSERT INTO preferences_notifications_par_evenement (utilisateur_id, type_evenement, canal, actif)
      VALUES (v_uid, (v_item->>'type_evenement')::public.type_evenement_notification,
              (v_item->>'canal')::public.canal_notification, (v_item->>'actif')::boolean)
      ON CONFLICT (utilisateur_id, type_evenement, canal) DO UPDATE SET actif = EXCLUDED.actif;
    END LOOP;
  END IF;
  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid, p_type_acteur := 'SOIGNANT',
    p_action := 'PREFERENCE_NOTIFICATION_MODIFIEE',
    p_type_ressource := 'preferences', p_id_ressource := v_uid,
    p_details := jsonb_build_object('canaux', jsonb_build_object('email',p_canal_email,'sms',p_canal_sms,'push',p_canal_push,'in_app',p_canal_in_app),
                                    'par_evenement', p_par_evenement)
  );
  RETURN jsonb_build_object('success', true);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_modifier_preferences_notifications(boolean, boolean, boolean, boolean, jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_obtenir_mes_preferences_notifications()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v_uid uuid := auth.uid(); v_global jsonb; v_par_evenement jsonb;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('error','Non authentifié'); END IF;
  SELECT to_jsonb(p) - 'utilisateur_id' INTO v_global FROM preferences_notifications p WHERE utilisateur_id = v_uid;
  IF v_global IS NULL THEN
    INSERT INTO preferences_notifications (utilisateur_id) VALUES (v_uid) ON CONFLICT DO NOTHING;
    SELECT to_jsonb(p) - 'utilisateur_id' INTO v_global FROM preferences_notifications p WHERE utilisateur_id = v_uid;
  END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('type_evenement', type_evenement, 'canal', canal, 'actif', actif)), '[]'::jsonb)
  INTO v_par_evenement FROM preferences_notifications_par_evenement WHERE utilisateur_id = v_uid;
  RETURN jsonb_build_object('global', v_global, 'par_evenement', v_par_evenement);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_obtenir_mes_preferences_notifications() TO authenticated;

-- Backfill : créer une row default pour tous les users existants
INSERT INTO public.preferences_notifications (utilisateur_id)
SELECT u.id FROM auth.users u
WHERE NOT EXISTS (SELECT 1 FROM preferences_notifications p WHERE p.utilisateur_id = u.id)
ON CONFLICT (utilisateur_id) DO NOTHING;

NOTIFY pgrst, 'reload schema';
