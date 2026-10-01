-- Régression SQL ciblée du trigger : vraie fonction, vrai choix des destinataires,
-- vraie table notifications et sa garde TEST. Les événements financiers sont
-- isolés dans une table temporaire : ce banc ne crée aucune facture réelle et
-- ne prouve ni paiement, ni remboursement, ni livraison de notification native.
-- Exécution staging CI exclusivement, transaction toujours annulée.
BEGIN;
SET LOCAL lock_timeout='3s';
SET LOCAL statement_timeout='45s';
SELECT set_config('request.jwt.claim.sub','',true);
SELECT set_config('request.jwt.claim.role','service_role',true);
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);

CREATE FUNCTION pg_temp.notif_avoir_id(n integer) RETURNS uuid LANGUAGE sql IMMUTABLE AS $f$
  SELECT ('f191a001-1000-4000-8000-'||lpad(n::text,12,'0'))::uuid;
$f$;

DO $preflight$
BEGIN
 IF session_user NOT IN ('postgres','supabase_admin') OR auth.uid() IS NOT NULL
   OR public.est_admin() OR EXISTS(SELECT 1 FROM cron.job WHERE active)
 THEN RAISE EXCEPTION 'NOTIF_AVOIR_CONTEXTE_ISOLE_REQUIS'; END IF;
 IF EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='auth.users'::regclass
   AND NOT tgisinternal AND (tgtype::integer & 4)<>0 AND tgenabled<>'D')
 THEN RAISE EXCEPTION 'NOTIF_AVOIR_AUTH_INSERT_TRIGGER_INATTENDU'; END IF;
 IF EXISTS(SELECT 1 FROM auth.users WHERE id::text LIKE 'f191a001-%')
   OR EXISTS(SELECT 1 FROM public.soignants WHERE id::text LIKE 'f191a001-%')
   OR EXISTS(SELECT 1 FROM public.equipe_admin WHERE user_id::text LIKE 'f191a001-%')
   OR EXISTS(SELECT 1 FROM public.notifications WHERE id_ressource::text LIKE 'f191a001-%')
   OR EXISTS(SELECT 1 FROM public.externalisation_actions WHERE source_id::text LIKE 'f191a001-%')
 THEN RAISE EXCEPTION 'NOTIF_AVOIR_COLLISION_FIXTURE'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.factures_honoraires'::regclass
   AND tgname='trg_notif_admin_remboursement_manuel' AND tgenabled='O'
   AND tgfoid='public.fn_trg_notif_admin_remboursement_manuel()'::regprocedure)
   OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.notifications'::regclass
     AND tgname='trg_bloquer_notification_admin_compte_test' AND tgenabled='O'
     AND tgfoid='private.dec_bloquer_notification_admin_compte_test()'::regprocedure)
   OR EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.notifications'::regclass
     AND NOT tgisinternal AND (tgtype::integer & 4)<>0
     AND tgname<>'trg_bloquer_notification_admin_compte_test' AND tgenabled<>'D')
 THEN RAISE EXCEPTION 'NOTIF_AVOIR_TRIGGER_OU_TRANSPORT_INATTENDU'; END IF;
 IF has_function_privilege('anon','public.fn_trg_notif_admin_remboursement_manuel()','EXECUTE')
   OR has_function_privilege('authenticated','public.fn_trg_notif_admin_remboursement_manuel()','EXECUTE')
   OR NOT has_function_privilege('service_role','public.fn_trg_notif_admin_remboursement_manuel()','EXECUTE')
 THEN RAISE EXCEPTION 'NOTIF_AVOIR_PRIVILEGES_MODIFIES'; END IF;
END;
$preflight$;

CREATE TEMP TABLE notif_avoir_anciennes AS SELECT id,to_jsonb(n) AS contenu
FROM public.notifications n WHERE type='REMBOURSEMENT_MANUEL_A_FAIRE';
CREATE TEMP TABLE notif_avoir_actions_anciennes AS SELECT id,to_jsonb(a) AS contenu
FROM public.externalisation_actions a WHERE type_action='REMBOURSEMENT_AVOIR_SWAN';

-- Auth SQL sans session ni transport ; tous les profils restent TEST.
INSERT INTO auth.users(id,instance_id,email,role,aud,raw_app_meta_data,email_confirmed_at,banned_until,deleted_at)
SELECT pg_temp.notif_avoir_id(n),'00000000-0000-0000-0000-000000000000',
 'notif-avoir-'||n||'@example.invalid','authenticated','authenticated',
 jsonb_build_object('role',CASE WHEN n IN(1,2) THEN 'SOIGNANT' WHEN n=16 THEN 'ADMIN' ELSE 'ADMIN_PLATEFORME' END,
   'est_compte_test',true,'is_test_playwright',true),
 CASE WHEN n<>15 THEN now() END,CASE WHEN n=14 THEN now()+interval '1 day' END,
 CASE WHEN n=17 THEN now() END
FROM unnest(ARRAY[1,2,11,12,13,14,15,16,17]) n;
INSERT INTO public.soignants(id,prenom,nom,email,profession,type_exercice,date_naissance,est_compte_test,
 source_acquisition,code_parrainage,sms_actif,sms_alertes_actives,defacto_opt_in,iban_virement)
SELECT pg_temp.notif_avoir_id(n),'Fixture','Notification','notif-avoir-'||n||'@example.invalid',
 'IDE','SALARIE','1990-01-01',true,'RECETTE_SQL_ANNULEE','NOTIFAVOIR'||n,false,false,false,
 CASE WHEN n=1 THEN 'FR7612345987650123456789014' END FROM unnest(ARRAY[1,2]) n;
UPDATE public.preferences_notifications SET canal_email=false,canal_sms=false,canal_push=false,canal_in_app=false
WHERE utilisateur_id IN(pg_temp.notif_avoir_id(1),pg_temp.notif_avoir_id(2));
INSERT INTO public.equipe_admin(user_id,nom,prenom,email,poste,actif,acces_groupes)
SELECT pg_temp.notif_avoir_id(n),'SYNTHETIQUE','Notification','notif-avoir-'||n||'@example.invalid',
 'RECETTE SQL ANNULEE',n<>13,CASE WHEN n=12 THEN ARRAY['Dashboard'] ELSE
 ARRAY['Dashboard','Utilisateurs','Missions','Litiges & contrats','Finances','Messagerie','Conformité & Technique','Fondateur'] END
FROM generate_series(11,17) n;
CREATE TEMP TABLE notif_avoir_destinataires AS SELECT public.fn_list_admin_user_ids() AS id;
DO $fixtures$
BEGIN
 IF (SELECT count(*) FROM public.soignants WHERE id IN(pg_temp.notif_avoir_id(1),pg_temp.notif_avoir_id(2))
   AND est_compte_test IS TRUE)<>2
   OR NOT EXISTS(SELECT 1 FROM public.soignants WHERE id=pg_temp.notif_avoir_id(1) AND iban_virement IS NOT NULL)
   OR NOT EXISTS(SELECT 1 FROM public.soignants WHERE id=pg_temp.notif_avoir_id(2) AND iban_virement IS NULL)
 THEN RAISE EXCEPTION 'NOTIF_AVOIR_PROFILS_TEST_MODIFIES'; END IF;
 IF NOT EXISTS(SELECT 1 FROM notif_avoir_destinataires WHERE id=pg_temp.notif_avoir_id(11))
   OR EXISTS(SELECT 1 FROM notif_avoir_destinataires WHERE id IN
     (SELECT pg_temp.notif_avoir_id(n) FROM generate_series(12,17) n))
 THEN RAISE EXCEPTION 'NOTIF_AVOIR_DESTINATAIRES_INATTENDUS'; END IF;
END;
$fixtures$;

-- Événements de trigger synthétiques, sans désactivation des protections des
-- factures réelles. Le trigger canonique de production demeure inchangé.
CREATE TEMP TABLE notif_avoir_evenements (
 id uuid PRIMARY KEY,soignant_id uuid,type_document public.type_document_facture,
 mode_remboursement public.mode_remboursement_avoir,date_remboursement timestamptz,
 numero_facture text,montant_ht numeric,montant_ttc numeric
);
CREATE TRIGGER recette_notification_avoir
AFTER INSERT OR UPDATE OF mode_remboursement,type_document ON notif_avoir_evenements
FOR EACH ROW EXECUTE FUNCTION public.fn_trg_notif_admin_remboursement_manuel();

INSERT INTO notif_avoir_evenements(id,soignant_id,type_document,mode_remboursement,numero_facture,montant_ht,montant_ttc)
SELECT pg_temp.notif_avoir_id(100+n),pg_temp.notif_avoir_id(n),'AVOIR','VIREMENT_MANUEL','AV-RECETTE-'||n,60,72
FROM unnest(ARRAY[1,2]) n;
-- Rejeu de la même transition : aucune seconde notification.
UPDATE notif_avoir_evenements SET mode_remboursement='VIREMENT_MANUEL',type_document='AVOIR';

DO $contenu$
DECLARE n integer;
BEGIN
 FOR n IN 1..2 LOOP
   IF (SELECT count(*) FROM public.notifications WHERE id_ressource=pg_temp.notif_avoir_id(100+n)
     AND type='REMBOURSEMENT_MANUEL_A_FAIRE')<>(SELECT count(*) FROM notif_avoir_destinataires)
     OR EXISTS(SELECT 1 FROM public.notifications WHERE id_ressource=pg_temp.notif_avoir_id(100+n)
       AND (destinataire_id NOT IN(SELECT id FROM notif_avoir_destinataires) OR type_destinataire<>'ADMIN'
         OR type<>'REMBOURSEMENT_MANUEL_A_FAIRE' OR titre<>'💸 Remboursement manuel à traiter'
         OR corps<>('Avoir AV-RECETTE-'||n||' — 72,00 €. Remboursement manuel à traiter et à confirmer après vérification de la preuve bancaire.')
         OR lien<>'/admin/moderation?onglet=avoirs' OR type_ressource<>'facture_honoraire'))
   THEN RAISE EXCEPTION 'NOTIF_AVOIR_MESSAGE_OU_REJEU_INCORRECT_%',n; END IF;
 END LOOP;
END;
$contenu$;

-- Les trois exclusions historiques restent silencieuses.
INSERT INTO notif_avoir_evenements(id,soignant_id,type_document,mode_remboursement,date_remboursement,numero_facture,montant_ht,montant_ttc)
VALUES(pg_temp.notif_avoir_id(103),pg_temp.notif_avoir_id(1),'FACTURE','VIREMENT_MANUEL',NULL,'FACTURE',60,72),
 (pg_temp.notif_avoir_id(104),pg_temp.notif_avoir_id(1),'AVOIR','N_A',NULL,'AV-AUTRE',60,72),
 (pg_temp.notif_avoir_id(105),pg_temp.notif_avoir_id(1),'AVOIR','VIREMENT_MANUEL',now(),'AV-REMBOURSE',60,72);
DO $exclusions$
BEGIN
 IF EXISTS(SELECT 1 FROM public.notifications WHERE id_ressource IN
   (pg_temp.notif_avoir_id(103),pg_temp.notif_avoir_id(104),pg_temp.notif_avoir_id(105)))
 THEN RAISE EXCEPTION 'NOTIF_AVOIR_EXCLUSION_PERDUE'; END IF;
END;
$exclusions$;
-- Entrée dans le mode manuel via UPDATE : une notification, TTC nul => HT.
UPDATE notif_avoir_evenements SET montant_ttc=NULL WHERE id=pg_temp.notif_avoir_id(104);
UPDATE notif_avoir_evenements SET mode_remboursement='VIREMENT_MANUEL' WHERE id=pg_temp.notif_avoir_id(104);
UPDATE notif_avoir_evenements SET mode_remboursement='VIREMENT_MANUEL' WHERE id=pg_temp.notif_avoir_id(104);
DO $transition$
BEGIN
 IF (SELECT count(*) FROM public.notifications WHERE id_ressource=pg_temp.notif_avoir_id(104))
   <>(SELECT count(*) FROM notif_avoir_destinataires)
   OR EXISTS(SELECT 1 FROM public.notifications WHERE id_ressource=pg_temp.notif_avoir_id(104)
     AND corps<>'Avoir AV-AUTRE — 60,00 €. Remboursement manuel à traiter et à confirmer après vérification de la preuve bancaire.')
 THEN RAISE EXCEPTION 'NOTIF_AVOIR_TRANSITION_OU_HT_INCORRECT'; END IF;
END;
$transition$;

-- Un soignant TEST connecté ne doit toujours pas notifier les admins.
SELECT set_config('request.jwt.claim.sub',pg_temp.notif_avoir_id(1)::text,true);
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.notif_avoir_id(1),'role','authenticated')::text,true);
INSERT INTO notif_avoir_evenements(id,soignant_id,type_document,mode_remboursement,numero_facture,montant_ht,montant_ttc)
VALUES(pg_temp.notif_avoir_id(106),pg_temp.notif_avoir_id(1),'AVOIR','VIREMENT_MANUEL','AV-GARDE-TEST',60,72);
SELECT set_config('request.jwt.claim.sub','',true);
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);
DO $invariants$
BEGIN
 IF EXISTS(SELECT 1 FROM public.notifications WHERE id_ressource=pg_temp.notif_avoir_id(106))
 THEN RAISE EXCEPTION 'NOTIF_AVOIR_GARDE_TEST_CONTOURNEE'; END IF;
 IF EXISTS(SELECT 1 FROM public.externalisation_actions WHERE source_id::text LIKE 'f191a001-%')
 THEN RAISE EXCEPTION 'NOTIF_AVOIR_TACHE_EXTERNE_CREEE'; END IF;
 IF EXISTS(SELECT 1 FROM notif_avoir_anciennes a LEFT JOIN public.notifications n ON n.id=a.id
   WHERE to_jsonb(n) IS DISTINCT FROM a.contenu)
   OR EXISTS(SELECT 1 FROM notif_avoir_actions_anciennes a LEFT JOIN public.externalisation_actions e ON e.id=a.id
     WHERE to_jsonb(e) IS DISTINCT FROM a.contenu)
 THEN RAISE EXCEPTION 'NOTIF_AVOIR_HISTORIQUE_MODIFIE'; END IF;
 IF EXISTS(SELECT 1 FROM public.factures_honoraires WHERE id::text LIKE 'f191a001-%')
 THEN RAISE EXCEPTION 'NOTIF_AVOIR_FACTURE_PERSISTANTE_CREEE'; END IF;
END;
$invariants$;
ROLLBACK;
