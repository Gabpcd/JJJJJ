-- Nouvelle candidature uniquement ; aucun backfill, HTTP ou modification de stock.
-- Corps/ACL/catalogue observés en production le 01/10/2026. Déploiement refusé
-- en cas de dérive. La file existante n'est consommée qu'après COMMIT.
DO $preflight$
DECLARE r record; p record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
('private.fn_externalisation_est_reelle(externalisation_actions)','19210f99b41e9820080825fd5d66b570'),
('public.fn_doit_notifier(uuid,type_evenement_notification,canal_notification)','67328d3d53cb0df47ce67a7f3018cb41'),
('public.fn_enregistrer_swipe(uuid,text,text)','626ab227717d28ef2973857fdd4d937b'),
('public.fn_externalisations_a_traiter(integer,text)','3717e517ee36b1165faf7cbf5e132121'),
('public.fn_postuler_mission(uuid,text,text)','ef020a1cc109c8e0a7c12c9a71e2aafc'),
('private.fn_json_uuid(text)','ae1887c242c9bdacfadf386078543cfe'),
('public.fn_a_permission_etablissement(text,uuid)','324d479198251e9c91524f28496780ba'),
('public.mon_etablissement_id()','c460c68169ff164cb109501d6dde885d'),
('public.fn_role_etablissement_courant(uuid)','c263e1db47a25c67de3a2308dc8aa81c'),
('public.fn_externalisation_echec(uuid,text,text)','e9f4dfc258514e4b450e2f2aedb356c9')
  ) attendu(signature, empreinte) LOOP
    IF to_regprocedure(r.signature) IS NULL OR md5(pg_get_functiondef(to_regprocedure(r.signature))) IS DISTINCT FROM r.empreinte
    THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_PREREQUIS_DEFINITION (%)',r.signature; END IF;
  END LOOP;
  FOR r IN SELECT * FROM (VALUES
    ('fn_postuler_mission(uuid,text,text)','5c9f5056d51cc3ffc9b463f74423286f','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
    ('fn_enregistrer_swipe(uuid,text,text)','9ceb2fe85ed287a7c94d915c12a780c0','{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}')
  ) attendu(signature,corps,acl) LOOP
    SELECT * INTO p FROM pg_proc WHERE oid=('public.'||r.signature)::regprocedure;
    IF NOT p.prosecdef OR pg_get_userbyid(p.proowner)<>'postgres'
      OR p.proconfig IS DISTINCT FROM ARRAY['search_path=public']::text[] OR p.proacl IS DISTINCT FROM r.acl::aclitem[]
      OR (SELECT count(*) FROM private.security_definer_inventory WHERE signature=r.signature
        AND categorie='RPC_UTILISATEUR_AUTH_INTERNE' AND definition_md5=r.corps)<>1
    THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_PREREQUIS_DROITS_INVENTAIRE'; END IF;
  END LOOP;
  SELECT * INTO p FROM pg_proc WHERE oid='public.fn_externalisations_a_traiter(integer,text)'::regprocedure;
  IF p.prosecdef OR p.proacl IS DISTINCT FROM '{postgres=X/postgres,service_role=X/postgres}'::aclitem[]
    OR p.proconfig IS DISTINCT FROM ARRAY['search_path=""']::text[]
  THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_CLAIM_DROITS_DERIVES'; END IF;
  IF EXISTS(SELECT 1 FROM private.security_definer_inventory WHERE signature='fn_externalisations_a_traiter(integer,text,boolean)')
  THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_CLAIM_INVENTAIRE_INATTENDU'; END IF;
  IF to_regprocedure('private.fn_payload_push_candidature_recue(uuid,uuid,uuid)') IS NOT NULL
    OR to_regprocedure('private.fn_enfiler_push_candidature_recue(uuid,uuid)') IS NOT NULL
    OR to_regprocedure('public.fn_preparer_push_candidature_recue(uuid)') IS NOT NULL
    OR to_regprocedure('public.fn_externalisations_a_traiter(integer,text,boolean)') IS NOT NULL
    OR to_regclass('public.uniq_push_candidature_destinataire') IS NOT NULL
    OR EXISTS(SELECT 1 FROM private.security_definer_inventory WHERE signature='fn_preparer_push_candidature_recue(uuid)')
    OR EXISTS(SELECT 1 FROM public.externalisation_actions WHERE type_action='PUSH_NOTIF'
      AND source='AUTRE' AND payload->>'type_evenement'='CANDIDATURE_RECUE')
  THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_INSTALLATION_OU_STOCK_INATTENDU'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.notifications'::regclass AND attname='id' AND NOT attisdropped AND format_type(atttypid,atttypmod)='uuid' AND attnotnull IS true) THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_COLONNE_INATTENDUE'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.notifications'::regclass AND attname='destinataire_id' AND NOT attisdropped AND format_type(atttypid,atttypmod)='uuid' AND attnotnull IS true) THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_COLONNE_INATTENDUE'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.notifications'::regclass AND attname='type_destinataire' AND NOT attisdropped AND format_type(atttypid,atttypmod)='text' AND attnotnull IS true) THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_COLONNE_INATTENDUE'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.notifications'::regclass AND attname='type' AND NOT attisdropped AND format_type(atttypid,atttypmod)='text' AND attnotnull IS true) THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_COLONNE_INATTENDUE'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.notifications'::regclass AND attname='titre' AND NOT attisdropped AND format_type(atttypid,atttypmod)='text' AND attnotnull IS true) THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_COLONNE_INATTENDUE'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.notifications'::regclass AND attname='corps' AND NOT attisdropped AND format_type(atttypid,atttypmod)='text' AND attnotnull IS true) THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_COLONNE_INATTENDUE'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.notifications'::regclass AND attname='lien' AND NOT attisdropped AND format_type(atttypid,atttypmod)='text' AND attnotnull IS false) THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_COLONNE_INATTENDUE'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.notifications'::regclass AND attname='type_ressource' AND NOT attisdropped AND format_type(atttypid,atttypmod)='text' AND attnotnull IS false) THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_COLONNE_INATTENDUE'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.notifications'::regclass AND attname='id_ressource' AND NOT attisdropped AND format_type(atttypid,atttypmod)='uuid' AND attnotnull IS false) THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_COLONNE_INATTENDUE'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.notifications'::regclass AND attname='lue' AND NOT attisdropped AND format_type(atttypid,atttypmod)='boolean' AND attnotnull IS false) THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_COLONNE_INATTENDUE'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.notifications'::regclass AND attname='lue_le' AND NOT attisdropped AND format_type(atttypid,atttypmod)='timestamp with time zone' AND attnotnull IS false) THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_COLONNE_INATTENDUE'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.notifications'::regclass AND attname='push_envoyee' AND NOT attisdropped AND format_type(atttypid,atttypmod)='boolean' AND attnotnull IS false) THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_COLONNE_INATTENDUE'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.notifications'::regclass AND attname='push_envoyee_le' AND NOT attisdropped AND format_type(atttypid,atttypmod)='timestamp with time zone' AND attnotnull IS false) THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_COLONNE_INATTENDUE'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.notifications'::regclass AND attname='email_envoye' AND NOT attisdropped AND format_type(atttypid,atttypmod)='boolean' AND attnotnull IS false) THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_COLONNE_INATTENDUE'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.notifications'::regclass AND attname='email_envoye_le' AND NOT attisdropped AND format_type(atttypid,atttypmod)='timestamp with time zone' AND attnotnull IS false) THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_COLONNE_INATTENDUE'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.notifications'::regclass AND attname='cree_le' AND NOT attisdropped AND format_type(atttypid,atttypmod)='timestamp with time zone' AND attnotnull IS false) THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_COLONNE_INATTENDUE'; END IF;
  IF (SELECT count(*) FROM pg_trigger WHERE tgrelid='public.notifications'::regclass AND NOT tgisinternal)<>3 THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_TRIGGER_INATTENDU'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.notifications'::regclass AND tgname='dec_proteger_notif' AND tgenabled='O' AND pg_get_triggerdef(oid)='CREATE TRIGGER dec_proteger_notif BEFORE UPDATE ON public.notifications FOR EACH ROW EXECUTE FUNCTION dec_proteger_contenu_notification()' AND md5(pg_get_functiondef(tgfoid))='a7a58adc195c76b8da4d60054047a555') THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_TRIGGER_DERIVE'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.notifications'::regclass AND tgname='trg_bloquer_notification_admin_compte_test' AND tgenabled='O' AND pg_get_triggerdef(oid)='CREATE TRIGGER trg_bloquer_notification_admin_compte_test BEFORE INSERT ON public.notifications FOR EACH ROW EXECUTE FUNCTION private.dec_bloquer_notification_admin_compte_test()' AND md5(pg_get_functiondef(tgfoid))='24e922102229e1d108aea5fbe7d20455') THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_TRIGGER_DERIVE'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.notifications'::regclass AND tgname='trg_protect_notification_update' AND tgenabled='O' AND pg_get_triggerdef(oid)='CREATE TRIGGER trg_protect_notification_update BEFORE UPDATE ON public.notifications FOR EACH ROW WHEN ((NOT est_admin())) EXECUTE FUNCTION fn_protect_notification_update()' AND md5(pg_get_functiondef(tgfoid))='8bde065cc49fcc5efafa98f984c272b9') THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_TRIGGER_DERIVE'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.candidatures'::regclass AND attname='id' AND NOT attisdropped AND format_type(atttypid,atttypmod)='uuid' AND attnotnull IS true) THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_COLONNE_INATTENDUE'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.candidatures'::regclass AND attname='mission_id' AND NOT attisdropped AND format_type(atttypid,atttypmod)='uuid' AND attnotnull IS true) THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_COLONNE_INATTENDUE'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.candidatures'::regclass AND attname='soignant_id' AND NOT attisdropped AND format_type(atttypid,atttypmod)='uuid' AND attnotnull IS true) THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_COLONNE_INATTENDUE'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.candidatures'::regclass AND attname='message' AND NOT attisdropped AND format_type(atttypid,atttypmod)='text' AND attnotnull IS false) THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_COLONNE_INATTENDUE'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.candidatures'::regclass AND attname='statut' AND NOT attisdropped AND format_type(atttypid,atttypmod)='text' AND attnotnull IS false) THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_COLONNE_INATTENDUE'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.candidatures'::regclass AND attname='motif_refus' AND NOT attisdropped AND format_type(atttypid,atttypmod)='text' AND attnotnull IS false) THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_COLONNE_INATTENDUE'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.candidatures'::regclass AND attname='cree_le' AND NOT attisdropped AND format_type(atttypid,atttypmod)='timestamp with time zone' AND attnotnull IS false) THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_COLONNE_INATTENDUE'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.candidatures'::regclass AND attname='traite_le' AND NOT attisdropped AND format_type(atttypid,atttypmod)='timestamp with time zone' AND attnotnull IS false) THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_COLONNE_INATTENDUE'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.candidatures'::regclass AND attname='type_contrat_choisi' AND NOT attisdropped AND format_type(atttypid,atttypmod)='text' AND attnotnull IS false) THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_COLONNE_INATTENDUE'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.candidatures'::regclass AND attname='acceptee_a' AND NOT attisdropped AND format_type(atttypid,atttypmod)='timestamp with time zone' AND attnotnull IS false) THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_COLONNE_INATTENDUE'; END IF;
  IF (SELECT count(*) FROM pg_trigger WHERE tgrelid='public.candidatures'::regclass AND NOT tgisinternal)<>9 THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_TRIGGER_INATTENDU'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.candidatures'::regclass AND tgname='trg_award_badges_match' AND tgenabled='O' AND pg_get_triggerdef(oid)='CREATE TRIGGER trg_award_badges_match AFTER UPDATE ON public.candidatures FOR EACH ROW EXECUTE FUNCTION fn_award_badges_match()' AND md5(pg_get_functiondef(tgfoid))='24e7bea5d992dd7495655ed250e8223b') THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_TRIGGER_DERIVE'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.candidatures'::regclass AND tgname='trg_candidature_acceptee_chat' AND tgenabled='O' AND pg_get_triggerdef(oid)='CREATE TRIGGER trg_candidature_acceptee_chat AFTER UPDATE OF statut ON public.candidatures FOR EACH ROW WHEN (((new.statut = ''ACCEPTEE''::text) AND ((old.statut IS NULL) OR (old.statut <> ''ACCEPTEE''::text)))) EXECUTE FUNCTION tg_candidature_acceptee_creer_conversation()' AND md5(pg_get_functiondef(tgfoid))='81b99e2defe947daeac3fee9435326b0') THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_TRIGGER_DERIVE'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.candidatures'::regclass AND tgname='trg_candidature_conflit_planning' AND tgenabled='O' AND pg_get_triggerdef(oid)='CREATE TRIGGER trg_candidature_conflit_planning BEFORE INSERT ON public.candidatures FOR EACH ROW EXECUTE FUNCTION fn_trg_candidature_conflit_planning()' AND md5(pg_get_functiondef(tgfoid))='488ebb2df2803561fc373188dd31e1fb') THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_TRIGGER_DERIVE'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.candidatures'::regclass AND tgname='trg_dec_exiger_planning_confirme_candidature' AND tgenabled='O' AND pg_get_triggerdef(oid)='CREATE TRIGGER trg_dec_exiger_planning_confirme_candidature BEFORE INSERT ON public.candidatures FOR EACH ROW EXECUTE FUNCTION dec_exiger_planning_confirme_candidature()' AND md5(pg_get_functiondef(tgfoid))='6988ad4179e36aa00608a2765ed4944e') THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_TRIGGER_DERIVE'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.candidatures'::regclass AND tgname='trg_p0_rbac_candidatures' AND tgenabled='O' AND pg_get_triggerdef(oid)='CREATE TRIGGER trg_p0_rbac_candidatures BEFORE INSERT OR DELETE OR UPDATE ON public.candidatures FOR EACH ROW EXECUTE FUNCTION fn_enforce_etablissement_rbac_trigger(''candidatures'')' AND md5(pg_get_functiondef(tgfoid))='694bd8f7e2fedbb48b66f3499fc39feb') THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_TRIGGER_DERIVE'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.candidatures'::regclass AND tgname='trg_protect_candidature_statut' AND tgenabled='O' AND pg_get_triggerdef(oid)='CREATE TRIGGER trg_protect_candidature_statut BEFORE UPDATE ON public.candidatures FOR EACH ROW EXECUTE FUNCTION fn_protect_candidature_statut()' AND md5(pg_get_functiondef(tgfoid))='41bbf1a424f50ac25d7eef1c3d572582') THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_TRIGGER_DERIVE'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.candidatures'::regclass AND tgname='trg_recompute_score_urgence' AND tgenabled='O' AND pg_get_triggerdef(oid)='CREATE TRIGGER trg_recompute_score_urgence AFTER INSERT OR UPDATE ON public.candidatures FOR EACH ROW EXECUTE FUNCTION fn_trg_recompute_score_urgence()' AND md5(pg_get_functiondef(tgfoid))='dce6f18db5a2f48e9c2388a4f3f48a40') THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_TRIGGER_DERIVE'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.candidatures'::regclass AND tgname='trg_set_candidature_acceptee_a' AND tgenabled='O' AND pg_get_triggerdef(oid)='CREATE TRIGGER trg_set_candidature_acceptee_a BEFORE UPDATE OF statut ON public.candidatures FOR EACH ROW EXECUTE FUNCTION dec_set_candidature_acceptee_a()' AND md5(pg_get_functiondef(tgfoid))='eca2685aa6d1917017e02d88fd87d186') THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_TRIGGER_DERIVE'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.candidatures'::regclass AND tgname='trg_verifier_profession_etudiant' AND tgenabled='O' AND pg_get_triggerdef(oid)='CREATE TRIGGER trg_verifier_profession_etudiant BEFORE INSERT ON public.candidatures FOR EACH ROW EXECUTE FUNCTION dec_verifier_profession_etudiant()' AND md5(pg_get_functiondef(tgfoid))='602c15976e2a0c563839ed99acee15b5') THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_TRIGGER_DERIVE'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.externalisation_actions'::regclass AND attname='id' AND NOT attisdropped AND format_type(atttypid,atttypmod)='uuid' AND attnotnull IS true) THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_COLONNE_INATTENDUE'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.externalisation_actions'::regclass AND attname='type_action' AND NOT attisdropped AND format_type(atttypid,atttypmod)='text' AND attnotnull IS true) THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_COLONNE_INATTENDUE'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.externalisation_actions'::regclass AND attname='payload' AND NOT attisdropped AND format_type(atttypid,atttypmod)='jsonb' AND attnotnull IS true) THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_COLONNE_INATTENDUE'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.externalisation_actions'::regclass AND attname='source' AND NOT attisdropped AND format_type(atttypid,atttypmod)='text' AND attnotnull IS true) THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_COLONNE_INATTENDUE'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.externalisation_actions'::regclass AND attname='source_id' AND NOT attisdropped AND format_type(atttypid,atttypmod)='uuid' AND attnotnull IS false) THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_COLONNE_INATTENDUE'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.externalisation_actions'::regclass AND attname='statut' AND NOT attisdropped AND format_type(atttypid,atttypmod)='text' AND attnotnull IS true) THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_COLONNE_INATTENDUE'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.externalisation_actions'::regclass AND attname='tentatives' AND NOT attisdropped AND format_type(atttypid,atttypmod)='integer' AND attnotnull IS true) THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_COLONNE_INATTENDUE'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.externalisation_actions'::regclass AND attname='derniere_tentative_le' AND NOT attisdropped AND format_type(atttypid,atttypmod)='timestamp with time zone' AND attnotnull IS false) THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_COLONNE_INATTENDUE'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.externalisation_actions'::regclass AND attname='derniere_erreur' AND NOT attisdropped AND format_type(atttypid,atttypmod)='text' AND attnotnull IS false) THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_COLONNE_INATTENDUE'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.externalisation_actions'::regclass AND attname='resultat' AND NOT attisdropped AND format_type(atttypid,atttypmod)='jsonb' AND attnotnull IS false) THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_COLONNE_INATTENDUE'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.externalisation_actions'::regclass AND attname='cree_le' AND NOT attisdropped AND format_type(atttypid,atttypmod)='timestamp with time zone' AND attnotnull IS true) THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_COLONNE_INATTENDUE'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.externalisation_actions'::regclass AND attname='traite_le' AND NOT attisdropped AND format_type(atttypid,atttypmod)='timestamp with time zone' AND attnotnull IS false) THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_COLONNE_INATTENDUE'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.externalisation_actions'::regclass AND attname='next_retry_at' AND NOT attisdropped AND format_type(atttypid,atttypmod)='timestamp with time zone' AND attnotnull IS false) THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_COLONNE_INATTENDUE'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.externalisation_actions'::regclass AND attname='cron_lock_at' AND NOT attisdropped AND format_type(atttypid,atttypmod)='timestamp with time zone' AND attnotnull IS false) THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_COLONNE_INATTENDUE'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.externalisation_actions'::regclass AND attname='cron_lock_par' AND NOT attisdropped AND format_type(atttypid,atttypmod)='text' AND attnotnull IS false) THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_COLONNE_INATTENDUE'; END IF;
  IF (SELECT count(*) FROM pg_trigger WHERE tgrelid='public.externalisation_actions'::regclass AND NOT tgisinternal)<>0 THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_TRIGGER_INATTENDU'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='public.externalisation_actions'::regclass AND conname='externalisation_actions_type_action_check' AND pg_get_constraintdef(oid)='CHECK ((type_action = ANY (ARRAY[''STRIPE_REFUND_PARTIEL''::text, ''STRIPE_REFUND_TOTAL''::text, ''STRIPE_PAYMENT''::text, ''STRIPE_PAYOUT''::text, ''CHORUS_RECYCLER_FACTURE''::text, ''CHORUS_RECYCLE_FACTURE''::text, ''DPAE_ANNULATION''::text, ''DPAE_ANNULATION_NOTIF''::text, ''EMAIL_NOTIF''::text, ''SMS_NOTIF''::text, ''PUSH_NOTIF''::text, ''AVOIR_PDF_GENERATION''::text, ''RECOMPENSE_PARRAINAGE_SOIGNANT''::text, ''REMBOURSEMENT_AVOIR_SWAN''::text])))') THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_CHECK_TYPE_DERIVE'; END IF;
END;
$preflight$;

ALTER TABLE public.externalisation_actions DROP CONSTRAINT externalisation_actions_type_action_check;
ALTER TABLE public.externalisation_actions ADD CONSTRAINT externalisation_actions_type_action_check CHECK ((type_action = ANY (ARRAY['STRIPE_REFUND_PARTIEL'::text, 'STRIPE_REFUND_TOTAL'::text, 'STRIPE_PAYMENT'::text, 'STRIPE_PAYOUT'::text, 'CHORUS_RECYCLER_FACTURE'::text, 'CHORUS_RECYCLE_FACTURE'::text, 'DPAE_ANNULATION'::text, 'DPAE_ANNULATION_NOTIF'::text, 'EMAIL_NOTIF'::text, 'SMS_NOTIF'::text, 'PUSH_NOTIF'::text, 'PUSH_CANDIDATURE_RECUE'::text, 'AVOIR_PDF_GENERATION'::text, 'RECOMPENSE_PARRAINAGE_SOIGNANT'::text, 'REMBOURSEMENT_AVOIR_SWAN'::text])));
-- Versionnement de capacité sans état d'activation mutable. L'ancien worker
-- ne prend jamais le nouveau type, même si son déploiement échoue durablement.
CREATE OR REPLACE FUNCTION public.fn_externalisations_a_traiter(p_limit integer DEFAULT 50, p_worker_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE
  v_actions jsonb;
  v_count integer;
  v_exclues_non_reelles integer;
  v_worker text := COALESCE(
    p_worker_id,
    'worker_' || substring(md5(random()::text), 1, 8)
  );
BEGIN
  SELECT count(*) INTO v_exclues_non_reelles
    FROM public.externalisation_actions a
   WHERE (
       (a.statut = 'PENDING'
         AND (a.next_retry_at IS NULL OR a.next_retry_at < now()))
       OR (a.statut = 'PENDING_AIFE'
         AND a.next_retry_at IS NOT NULL AND a.next_retry_at < now())
       OR (a.statut = 'PROCESSING'
         AND a.cron_lock_at < now() - interval '10 minutes')
     )
     AND a.type_action <> 'PUSH_CANDIDATURE_RECUE'
     AND private.fn_externalisation_est_reelle(a) IS FALSE;

  WITH selectionnees AS (
    SELECT a.id
      FROM public.externalisation_actions a
     WHERE (
         (a.statut = 'PENDING'
           AND (a.next_retry_at IS NULL OR a.next_retry_at < now()))
         OR (a.statut = 'PENDING_AIFE'
           AND a.next_retry_at IS NOT NULL AND a.next_retry_at < now())
         OR (a.statut = 'PROCESSING'
           AND a.cron_lock_at < now() - interval '10 minutes')
       )
       AND a.type_action <> 'PUSH_CANDIDATURE_RECUE'
     AND private.fn_externalisation_est_reelle(a) IS TRUE
     ORDER BY a.cree_le ASC
     LIMIT p_limit
     FOR UPDATE SKIP LOCKED
  )
  UPDATE public.externalisation_actions a
     SET statut = 'PROCESSING',
         cron_lock_at = now(),
         cron_lock_par = v_worker
    FROM selectionnees s
   WHERE a.id = s.id;

  SELECT jsonb_agg(jsonb_build_object(
           'id', a.id,
           'type_action', a.type_action,
           'payload', a.payload,
           'source', a.source,
           'source_id', a.source_id,
           'tentatives', a.tentatives
         )),
         count(*)
    INTO v_actions, v_count
    FROM public.externalisation_actions a
   WHERE a.type_action <> 'PUSH_CANDIDATURE_RECUE'
     AND a.cron_lock_par = v_worker
     AND a.statut = 'PROCESSING'
     AND a.cron_lock_at > now() - interval '5 seconds';

  RETURN jsonb_build_object(
    'success', true,
    'worker_id', v_worker,
    'count', COALESCE(v_count, 0),
    'excluded_non_real', COALESCE(v_exclues_non_reelles, 0),
    'actions', COALESCE(v_actions, '[]'::jsonb)
  );
END;
$function$
;
CREATE OR REPLACE FUNCTION public.fn_externalisations_a_traiter(p_limit integer, p_worker_id text, p_push_candidature_v1 boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE
  v_actions jsonb;
  v_count integer;
  v_exclues_non_reelles integer;
  v_worker text := COALESCE(
    p_worker_id,
    'worker_' || substring(md5(random()::text), 1, 8)
  );
BEGIN
  IF COALESCE(auth.jwt()->>'role',current_setting('request.jwt.claim.role',true),'')<>'service_role'
  THEN RAISE EXCEPTION 'Accès refusé' USING ERRCODE='42501'; END IF;
  SELECT count(*) INTO v_exclues_non_reelles
    FROM public.externalisation_actions a
   WHERE (
       (a.statut = 'PENDING'
         AND (a.next_retry_at IS NULL OR a.next_retry_at < now()))
       OR (a.statut = 'PENDING_AIFE'
         AND a.next_retry_at IS NOT NULL AND a.next_retry_at < now())
       OR (a.statut = 'PROCESSING'
         AND a.cron_lock_at < now() - interval '10 minutes')
     )
     AND (p_push_candidature_v1 IS TRUE OR a.type_action <> 'PUSH_CANDIDATURE_RECUE')
     AND private.fn_externalisation_est_reelle(a) IS FALSE;

  WITH selectionnees AS (
    SELECT a.id
      FROM public.externalisation_actions a
     WHERE (
         (a.statut = 'PENDING'
           AND (a.next_retry_at IS NULL OR a.next_retry_at < now()))
         OR (a.statut = 'PENDING_AIFE'
           AND a.next_retry_at IS NOT NULL AND a.next_retry_at < now())
         OR (a.statut = 'PROCESSING'
           AND a.cron_lock_at < now() - interval '10 minutes')
       )
       AND (p_push_candidature_v1 IS TRUE OR a.type_action <> 'PUSH_CANDIDATURE_RECUE')
     AND private.fn_externalisation_est_reelle(a) IS TRUE
     ORDER BY a.cree_le ASC
     LIMIT p_limit
     FOR UPDATE SKIP LOCKED
  )
  UPDATE public.externalisation_actions a
     SET statut = 'PROCESSING',
         cron_lock_at = now(),
         cron_lock_par = v_worker
    FROM selectionnees s
   WHERE a.id = s.id;

  SELECT jsonb_agg(jsonb_build_object(
           'id', a.id,
           'type_action', a.type_action,
           'payload', a.payload,
           'source', a.source,
           'source_id', a.source_id,
           'tentatives', a.tentatives
         )),
         count(*)
    INTO v_actions, v_count
    FROM public.externalisation_actions a
   WHERE (p_push_candidature_v1 IS TRUE OR a.type_action <> 'PUSH_CANDIDATURE_RECUE')
     AND a.cron_lock_par = v_worker
     AND a.statut = 'PROCESSING'
     AND a.cron_lock_at > now() - interval '5 seconds';

  RETURN jsonb_build_object(
    'success', true,
    'worker_id', v_worker,
    'count', COALESCE(v_count, 0),
    'excluded_non_real', COALESCE(v_exclues_non_reelles, 0),
    'actions', COALESCE(v_actions, '[]'::jsonb)
  );
END;
$function$
;
REVOKE ALL ON FUNCTION public.fn_externalisations_a_traiter(integer,text,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.fn_externalisations_a_traiter(integer,text,boolean) TO service_role;

-- Lecture canonique commune à l'enfilage et au dispatch différé. Aucun effet.
CREATE FUNCTION private.fn_payload_push_candidature_recue(p_candidature_id uuid, p_notification_id uuid, p_destinataire_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v record;
BEGIN
  SELECT c.id AS candidature_id,c.soignant_id,c.mission_id,m.etablissement_id,n.titre,n.corps,n.lien
  INTO v
  FROM public.candidatures c
  JOIN public.missions m ON m.id=c.mission_id
  JOIN public.soignants s ON s.id=c.soignant_id
  JOIN public.etablissements e ON e.id=m.etablissement_id
  JOIN public.notifications n ON n.id=p_notification_id
    AND n.destinataire_id=e.id AND n.type_destinataire='ETABLISSEMENT'
    AND n.type='CANDIDATURE_RECUE' AND n.type_ressource='candidature' AND n.id_ressource=c.id
    AND n.lien='/etablissement/missions/'||m.id::text
  WHERE c.id=p_candidature_id AND c.statut='EN_ATTENTE'
    AND m.statut='OUVERTE' AND m.mode_attribution='CANDIDATURE'
    AND s.est_compte_test IS FALSE AND e.est_compte_test IS FALSE
    AND s.supprime_le IS NULL AND e.supprime_le IS NULL;
  IF NOT FOUND THEN RETURN jsonb_build_object('eligible',false,'raison','source_inactive'); END IF;

  -- Même droit de traitement que fn_a_permission_etablissement('candidatures').
  -- Pas de fallback app_metadata.etablissement_id : mon_etablissement_id et
  -- fn_role_etablissement_courant ne lui attribuent aucun droit sur la fiche.
  IF NOT EXISTS (
    SELECT 1 FROM auth.users u WHERE u.id=p_destinataire_id
      AND u.deleted_at IS NULL AND u.email_confirmed_at IS NOT NULL
      AND (u.banned_until IS NULL OR u.banned_until<=now())
      AND COALESCE(u.raw_app_meta_data->'est_compte_test','false'::jsonb)='false'::jsonb
      AND COALESCE(u.raw_app_meta_data->'is_test_playwright','false'::jsonb)='false'::jsonb
      AND (
        EXISTS(SELECT 1 FROM public.membres_etablissement me WHERE me.user_id=u.id
          AND me.etablissement_id=v.etablissement_id AND me.actif IS TRUE
          AND me.role IN ('PROPRIETAIRE','ADMIN_GROUPE','RH'))
        OR (u.id=v.etablissement_id AND u.raw_app_meta_data->>'role' IN ('ADMIN_ETABLISSEMENT','ETABLISSEMENT')
          AND NOT EXISTS(SELECT 1 FROM public.membres_etablissement me
            WHERE me.user_id=u.id AND me.etablissement_id=v.etablissement_id))
      )
      AND NOT EXISTS(SELECT 1 FROM public.soignants s WHERE s.id=u.id
        AND (s.est_compte_test IS DISTINCT FROM false OR s.supprime_le IS NOT NULL))
      AND NOT EXISTS(SELECT 1 FROM public.etablissements e WHERE e.id=u.id
        AND (e.est_compte_test IS DISTINCT FROM false OR e.supprime_le IS NOT NULL))
      AND NOT EXISTS(SELECT 1 FROM public.membres_etablissement me
        LEFT JOIN public.etablissements e ON e.id=me.etablissement_id
        WHERE me.user_id=u.id AND me.actif IS TRUE
          AND (e.est_compte_test IS DISTINCT FROM false OR e.supprime_le IS NOT NULL))
  ) THEN RETURN jsonb_build_object('eligible',false,'raison','destinataire_inactif'); END IF;
  IF public.fn_doit_notifier(p_destinataire_id,'CANDIDATURE_RECUE','PUSH') IS DISTINCT FROM true
  THEN RETURN jsonb_build_object('eligible',false,'raison','preference_desactivee'); END IF;
  RETURN jsonb_build_object('eligible',true,'payload',jsonb_build_object(
    'destinataire_id',p_destinataire_id,'type_evenement','CANDIDATURE_RECUE',
    'mission_id',v.mission_id,'titre',left(v.titre,120),'corps',left(v.corps,500),'lien',v.lien,
    'data',jsonb_build_object('candidature_id',v.candidature_id,'mission_id',v.mission_id,
      'soignant_id',v.soignant_id,'etablissement_id',v.etablissement_id,'notification_id',p_notification_id)));
END;
$function$;
REVOKE ALL ON FUNCTION private.fn_payload_push_candidature_recue(uuid,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE UNIQUE INDEX uniq_push_candidature_destinataire
ON public.externalisation_actions(source_id,(payload->>'destinataire_id'))
WHERE type_action='PUSH_CANDIDATURE_RECUE' AND source='AUTRE' AND payload->>'type_evenement'='CANDIDATURE_RECUE';

CREATE FUNCTION private.fn_enfiler_push_candidature_recue(p_candidature_id uuid,p_notification_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_etab uuid; v_dest uuid; v_resultat jsonb;
BEGIN
  -- Seuls les deux producteurs peuvent appeler ce helper privé. L'événement
  -- et la notification doivent venir de cette transaction, jamais du stock.
  SELECT m.etablissement_id INTO v_etab FROM public.candidatures c
  JOIN public.missions m ON m.id=c.mission_id
  JOIN public.notifications n ON n.id=p_notification_id
    AND n.id_ressource=c.id AND n.type_ressource='candidature'
  WHERE c.id=p_candidature_id AND c.soignant_id=auth.uid()
    AND c.cree_le>=transaction_timestamp() AND n.cree_le>=transaction_timestamp();
  IF NOT FOUND THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_EVENEMENT_INVALIDE' USING ERRCODE='23514'; END IF;
  FOR v_dest IN
    SELECT v_etab UNION SELECT me.user_id FROM public.membres_etablissement me
      WHERE me.etablissement_id=v_etab AND me.actif IS TRUE
  LOOP
    v_resultat:=private.fn_payload_push_candidature_recue(p_candidature_id,p_notification_id,v_dest);
    IF v_resultat->'eligible'='true'::jsonb THEN
      INSERT INTO public.externalisation_actions(type_action,source,source_id,payload)
      VALUES('PUSH_CANDIDATURE_RECUE','AUTRE',p_candidature_id,v_resultat->'payload')
      ON CONFLICT (source_id,(payload->>'destinataire_id'))
      WHERE type_action='PUSH_CANDIDATURE_RECUE' AND source='AUTRE' AND payload->>'type_evenement'='CANDIDATURE_RECUE'
      DO NOTHING;
    END IF;
  END LOOP;
END;
$function$;
REVOKE ALL ON FUNCTION private.fn_enfiler_push_candidature_recue(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;

-- Appel du worker uniquement ; aucune projection libre du payload reçu.
CREATE FUNCTION public.fn_preparer_push_candidature_recue(p_action_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_action public.externalisation_actions%ROWTYPE; v_resultat jsonb;
BEGIN
  IF COALESCE(auth.jwt()->>'role',current_setting('request.jwt.claim.role',true),'')<>'service_role'
  THEN RAISE EXCEPTION 'Accès refusé' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_action FROM public.externalisation_actions WHERE id=p_action_id;
  IF NOT FOUND OR v_action.type_action<>'PUSH_CANDIDATURE_RECUE' OR v_action.source<>'AUTRE'
    OR v_action.statut<>'PROCESSING' OR v_action.payload->>'type_evenement' IS DISTINCT FROM 'CANDIDATURE_RECUE'
    OR v_action.source_id IS NULL
  THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_ACTION_INVALIDE' USING ERRCODE='23514'; END IF;
  v_resultat:=private.fn_payload_push_candidature_recue(v_action.source_id,
    private.fn_json_uuid(v_action.payload#>>'{data,notification_id}'),
    private.fn_json_uuid(v_action.payload->>'destinataire_id'));
  IF v_resultat->'eligible'='true'::jsonb
    AND v_action.payload IS DISTINCT FROM v_resultat->'payload'
  THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_PROVENANCE_INVALIDE' USING ERRCODE='23514'; END IF;
  RETURN v_resultat;
END;
$function$;
REVOKE ALL ON FUNCTION public.fn_preparer_push_candidature_recue(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.fn_preparer_push_candidature_recue(uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.fn_postuler_mission(p_mission_id uuid, p_message text DEFAULT NULL::text, p_choix_contrat text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_mission record;
  v_soignant record;
  v_resolution jsonb;
  v_choix text;
  v_candidature_id uuid;
  v_notification_id uuid;
  v_docs_ok boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('error', 'Non authentifié');
  END IF;

  SELECT * INTO v_mission
  FROM public.missions
  WHERE id = p_mission_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Mission introuvable');
  END IF;
  IF v_mission.statut <> 'OUVERTE' THEN
    RETURN jsonb_build_object(
      'error',
      'Cette mission n''est plus disponible'
    );
  END IF;
  IF v_mission.mode_attribution <> 'CANDIDATURE' THEN
    RETURN jsonb_build_object(
      'error',
      'Cette mission n''accepte pas les candidatures'
    );
  END IF;

  SELECT * INTO v_soignant
  FROM public.soignants
  WHERE id = auth.uid()
    AND supprime_le IS NULL;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Profil soignant introuvable');
  END IF;
  IF COALESCE(v_soignant.statut_compte::text, 'ACTIF') <> 'ACTIF' THEN
    RETURN jsonb_build_object(
      'error',
      'Votre compte ne permet pas de candidater. Contactez bonjour@jolene.app.'
    );
  END IF;

  IF NOT private.fn_comptes_meme_cohorte_test(
    auth.uid(),
    v_mission.etablissement_id
  ) THEN
    RETURN jsonb_build_object(
      'error',
      'Mission indisponible pour ce compte'
    );
  END IF;

  IF NOT public.fn_soignant_compatible_mission(
    v_soignant.profession,
    v_soignant.specialite_medicale,
    v_mission.profession_requise,
    v_mission.specialite_medicale_requise,
    COALESCE(v_mission.accepte_non_specialises, true)
  ) THEN
    RETURN jsonb_build_object(
      'error',
      'Votre profession ne correspond pas à la mission requise ('
        || v_mission.profession_requise::text
        || ').'
    );
  END IF;
  IF public.fn_est_exclu(auth.uid(), v_mission.etablissement_id) THEN
    RETURN jsonb_build_object('error', 'Accès refusé.');
  END IF;

  v_resolution := public.fn_resoudre_contrat_mission(
    p_mission_id,
    auth.uid(),
    p_choix_contrat
  );
  IF COALESCE((v_resolution->>'ok')::boolean, false) IS NOT TRUE THEN
    RETURN v_resolution - 'ok';
  END IF;
  v_choix := v_resolution->>'contrat';

  IF EXISTS (
    SELECT 1
    FROM public.candidatures
    WHERE mission_id = p_mission_id
      AND soignant_id = auth.uid()
  ) THEN
    RETURN jsonb_build_object(
      'error',
      'Vous avez déjà postulé à cette mission'
    );
  END IF;

  v_docs_ok := public.fn_documents_ok_pour_mission(
    auth.uid(),
    v_choix
  );
  IF v_choix = 'LIBERAL' AND NOT v_docs_ok THEN
    RETURN jsonb_build_object(
      'error',
        'Les documents requis pour candidater en libéral sont manquants ou expirés.',
      'documents_requis_pour', 'LIBERAL',
      'lien_documents', '/soignant/mes-documents'
    );
  END IF;

  INSERT INTO public.candidatures (
    mission_id,
    soignant_id,
    message,
    statut,
    type_contrat_choisi
  ) VALUES (
    p_mission_id,
    auth.uid(),
    public.fn_html_escape(p_message),
    'EN_ATTENTE',
    v_choix
  )
  RETURNING id INTO v_candidature_id;

  INSERT INTO public.notifications (
    destinataire_id,
    type_destinataire,
    type,
    titre,
    corps,
    lien,
    type_ressource,
    id_ressource
  ) VALUES (
    v_mission.etablissement_id,
    'ETABLISSEMENT',
    'CANDIDATURE_RECUE',
    '📋 Nouvelle candidature reçue',
    COALESCE(v_soignant.prenom, 'Un soignant')
      || ' a postulé à votre mission « '
      || public.fn_html_escape(v_mission.intitule)
      || ' ».',
    '/etablissement/missions/' || p_mission_id, 'candidature', v_candidature_id
  ) RETURNING id INTO v_notification_id;
  PERFORM private.fn_enfiler_push_candidature_recue(v_candidature_id, v_notification_id);

  IF NOT v_docs_ok THEN
    INSERT INTO public.notifications (
      destinataire_id,
      type,
      titre,
      corps,
      lien,
      type_destinataire
    )
    SELECT
      auth.uid(),
      'RAPPEL_DOCUMENTS',
      'Complétez vos documents salariés',
      'Votre candidature est envoyée. Les documents requis pour le CDD doivent être validés avant que l''établissement puisse vous accepter.',
      '/soignant/mes-documents',
      'SOIGNANT'
    WHERE NOT EXISTS (
      SELECT 1
      FROM public.notifications
      WHERE destinataire_id = auth.uid()
        AND type = 'RAPPEL_DOCUMENTS'
        AND cree_le > now() - interval '24 hours'
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'candidature_id', v_candidature_id,
    'choix_contrat', v_choix,
    'profession_requise', v_mission.profession_requise::text,
    'docs_a_completer', NOT v_docs_ok,
    'documents_requis_pour', v_choix
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.fn_enregistrer_swipe(p_mission_id uuid, p_direction text, p_choix_contrat text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_direction public.swipe_direction;
  v_mission record;
  v_soignant record;
  v_resolution jsonb;
  v_choix text;
  v_swipe_id uuid;
  v_candidature_id uuid;
  v_notification_id uuid;
  v_planning jsonb;
  v_warning text;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'auth_required'); END IF;
  IF p_direction = 'SUPER_LIKE' THEN p_direction := 'FAVORI'; END IF;
  IF p_direction NOT IN ('LIKE', 'DISLIKE', 'FAVORI') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'direction_invalide');
  END IF;
  v_direction := p_direction::public.swipe_direction;

  SELECT * INTO v_mission FROM public.missions WHERE id = p_mission_id;
  IF NOT FOUND OR v_mission.statut <> 'OUVERTE' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'mission_indisponible');
  END IF;
  SELECT * INTO v_soignant FROM public.soignants WHERE id = v_uid AND supprime_le IS NULL;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'profil_introuvable'); END IF;
  IF NOT public.fn_soignant_compatible_mission(
    v_soignant.profession, v_soignant.specialite_medicale,
    v_mission.profession_requise, v_mission.specialite_medicale_requise,
    COALESCE(v_mission.accepte_non_specialises, true)
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'profession_incompatible');
  END IF;
  IF public.fn_est_exclu(v_uid, v_mission.etablissement_id) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'acces_refuse');
  END IF;

  IF v_direction = 'LIKE' THEN
    IF EXISTS (SELECT 1 FROM public.candidatures WHERE mission_id = p_mission_id AND soignant_id = v_uid) THEN
      RETURN jsonb_build_object('ok', false, 'error', 'Vous avez déjà candidaté à cette mission');
    END IF;
    v_planning := public.fn_conflit_planning_soignant(v_uid, p_mission_id);
    IF COALESCE((v_planning->>'conflit')::boolean, false) THEN
      RETURN jsonb_build_object('ok', false, 'error', v_planning->>'message', 'conflit_planning', true);
    END IF;
    v_warning := v_planning->>'warning';

    v_resolution := public.fn_resoudre_contrat_mission(p_mission_id, v_uid, p_choix_contrat);
    IF COALESCE((v_resolution->>'ok')::boolean, false) IS NOT TRUE THEN
      RETURN jsonb_build_object('ok', false) || (v_resolution - 'ok');
    END IF;
    v_choix := v_resolution->>'contrat';
    IF v_choix = 'LIBERAL' AND NOT public.fn_documents_ok_pour_mission(v_uid, 'LIBERAL') THEN
      RETURN jsonb_build_object(
        'ok', false,
        'error', 'Les documents requis pour candidater en libéral sont manquants ou expirés.',
        'documents_requis_pour', 'LIBERAL'
      );
    END IF;
  END IF;

  INSERT INTO public.swipes(soignant_id, mission_id, direction)
  VALUES (v_uid, p_mission_id, v_direction)
  ON CONFLICT (soignant_id, mission_id) DO NOTHING
  RETURNING id INTO v_swipe_id;
  IF v_swipe_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'mission_deja_swipee');
  END IF;

  IF v_direction = 'FAVORI' THEN
    INSERT INTO public.missions_sauvegardees(soignant_id, mission_id)
    VALUES (v_uid, p_mission_id)
    ON CONFLICT (soignant_id, mission_id) DO NOTHING;
    RETURN jsonb_build_object('ok', true, 'swipe_id', v_swipe_id, 'direction', 'FAVORI', 'sauvegardee', true);
  ELSIF v_direction = 'LIKE' THEN
    INSERT INTO public.candidatures(mission_id, soignant_id, message, statut, type_contrat_choisi)
    VALUES (p_mission_id, v_uid, NULL, 'EN_ATTENTE', v_choix)
    RETURNING id INTO v_candidature_id;
    INSERT INTO public.notifications(destinataire_id, type_destinataire, type, titre, corps, lien, type_ressource, id_ressource)
    VALUES (
      v_mission.etablissement_id, 'ETABLISSEMENT', 'CANDIDATURE_RECUE',
      '📋 Nouvelle candidature reçue',
      COALESCE(v_soignant.prenom, 'Un soignant') || ' a postulé à votre mission « ' ||
        public.fn_html_escape(v_mission.intitule) || ' ».',
      '/etablissement/missions/' || p_mission_id, 'candidature', v_candidature_id
  ) RETURNING id INTO v_notification_id;
  PERFORM private.fn_enfiler_push_candidature_recue(v_candidature_id, v_notification_id);
  END IF;

  RETURN jsonb_build_object(
    'ok', true, 'swipe_id', v_swipe_id, 'direction', p_direction,
    'candidature_id', v_candidature_id, 'choix_contrat', v_choix,
    'profession_requise', v_mission.profession_requise::text,
    'docs_a_completer', v_direction = 'LIKE' AND NOT public.fn_documents_ok_pour_mission(v_uid, v_choix),
    'warning', v_warning
  );
END;
$function$
;

DO $inventory$
DECLARE r record;
BEGIN
  FOR r IN SELECT p.* FROM pg_proc p WHERE p.oid IN ('public.fn_postuler_mission(uuid,text,text)'::regprocedure,'public.fn_enregistrer_swipe(uuid,text,text)'::regprocedure) LOOP
    UPDATE private.security_definer_inventory SET definition_md5=md5(r.prosrc),recense_le=now()
      WHERE signature=r.oid::regprocedure::text AND categorie='RPC_UTILISATEUR_AUTH_INTERNE';
    IF NOT FOUND THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_INVENTAIRE_ABSENT'; END IF;
  END LOOP;
  INSERT INTO private.security_definer_inventory(signature,categorie,definition_md5,justification,recense_le)
  SELECT 'fn_preparer_push_candidature_recue(uuid)','SERVICE_ONLY_REVOQUE',md5(prosrc),
    'Lecture service liée à une action en traitement ; provenance candidature/notification et membre habilité actifs, cohorte réelle et préférence PUSH revalidées.',now()
  FROM pg_proc WHERE oid='public.fn_preparer_push_candidature_recue(uuid)'::regprocedure;
  INSERT INTO private.security_definer_inventory(signature,categorie,definition_md5,justification,recense_le)
  SELECT 'fn_externalisations_a_traiter(integer,text,boolean)','SERVICE_ONLY_REVOQUE',md5(prosrc),
    'Capacité de claim push candidatures explicite : SECURITY INVOKER, ACL service_role seules, même verrou et budget que le claim historique.',now()
  FROM pg_proc WHERE oid='public.fn_externalisations_a_traiter(integer,text,boolean)'::regprocedure;
END;
$inventory$;
DO $postflight$
DECLARE r record; p record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    ('private.fn_payload_push_candidature_recue(uuid,uuid,uuid)',true,false),
    ('private.fn_enfiler_push_candidature_recue(uuid,uuid)',true,false),
    ('public.fn_preparer_push_candidature_recue(uuid)',true,true),
    ('public.fn_externalisations_a_traiter(integer,text,boolean)',false,true)
  ) attendu(signature,definer,service_access) LOOP
    SELECT * INTO STRICT p FROM pg_proc WHERE oid=r.signature::regprocedure;
    IF p.prosecdef IS DISTINCT FROM r.definer OR p.provolatile<>'v'
      OR p.proconfig IS DISTINCT FROM ARRAY['search_path=""']::text[]
      OR pg_get_userbyid(p.proowner)<>'postgres'
      OR has_function_privilege('anon',p.oid,'execute')
      OR has_function_privilege('authenticated',p.oid,'execute')
      OR has_function_privilege('service_role',p.oid,'execute') IS DISTINCT FROM r.service_access
      OR EXISTS(SELECT 1 FROM aclexplode(COALESCE(p.proacl,acldefault('f',p.proowner))) a
        WHERE a.grantee=0 AND a.privilege_type='EXECUTE')
    THEN RAISE EXCEPTION 'PUSH_CANDIDATURE_DROITS_FINAUX_INCOHERENTS'; END IF;
  END LOOP;
END;
$postflight$;
