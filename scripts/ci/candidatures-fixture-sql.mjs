import { createHash } from 'node:crypto';
import { literal as q, catalogueD, sqlCatalogueD } from './candidatures-fixture-contract.mjs';
const ids=m=>`ARRAY[${m.membres.map(a=>`${q(a.userId)}::uuid`).join(',')}]::uuid[]`;
const soignants=m=>`ARRAY[${m.membres.slice(0,2).map(a=>`${q(a.userId)}::uuid`).join(',')}]::uuid[]`;
const belongs=(m,a)=>`u.id=${q(a.userId)}::uuid AND u.email=${q(a.email)} AND u.email_confirmed_at IS NOT NULL${a.role==='ADMIN_ETABLISSEMENT'?` AND u.raw_app_meta_data->>'etablissement_id'=${q(a.userId)}`:''} AND u.raw_app_meta_data->>'role'=${q(a.role)} AND u.raw_app_meta_data->'est_compte_test'='true'::jsonb AND u.raw_app_meta_data->'is_test_playwright'='true'::jsonb AND u.raw_app_meta_data->>'load_fixture_kind'='CANDIDATURES_D2' AND u.raw_app_meta_data->>'load_fixture_run'=${q(m.runId)}`;
const header=m=>`BEGIN; SET LOCAL statement_timeout='25s'; SET LOCAL lock_timeout='5s';
SET LOCAL request.jwt.claims='{"role":"service_role"}'; SET LOCAL request.jwt.claim.sub=''; SET LOCAL request.jwt.claim.role='service_role';
SET LOCAL app.test_mode='true';
DO $d_lock$ BEGIN PERFORM pg_advisory_xact_lock(${BigInt('0x'+createHash('sha256').update('D2:'+m.runId).digest('hex').slice(0,15))}::bigint); END $d_lock$;
LOCK TABLE auth.users, public.soignants, public.etablissements, public.missions, public.mission_creneaux, public.candidatures, public.notifications, public.preferences_notifications, public.rate_limits IN SHARE ROW EXCLUSIVE MODE;
`;
const guard=`SELECT * INTO c FROM (${sqlCatalogueD}) c0;
IF c.fonctions<>${q(catalogueD.fonctions)} OR c.triggers<>${q(catalogueD.triggers)} OR c.schema IS DISTINCT FROM ${q(catalogueD.schema)} OR c.crons_actifs<>0 OR c.audit_fk<>0 OR c.fonctions IS NULL OR c.triggers IS NULL THEN RAISE EXCEPTION 'Catalogue D non conforme'; END IF;
IF auth.uid() IS NOT NULL OR NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname=current_user AND (rolsuper OR rolbypassrls)) THEN RAISE EXCEPTION 'Management sans identité requis'; END IF;`;
export function sqlAvantD(m) {return `${header(m)}DO $d_guard$ DECLARE c record; BEGIN ${guard}
IF ${q(m.debut)}::timestamptz <= now()+interval '1 day' OR ${q(m.debut)}::timestamptz > now()+interval '31 days' THEN RAISE EXCEPTION 'Mission D future bornée requise'; END IF;
IF EXISTS(SELECT 1 FROM auth.users WHERE id=ANY(${ids(m)}) OR email=ANY(ARRAY[${m.membres.map(a=>q(a.email)).join(',')}]))
 OR EXISTS(SELECT 1 FROM public.soignants WHERE id=ANY(${ids(m)})) OR EXISTS(SELECT 1 FROM public.etablissements WHERE id=ANY(${ids(m)}))
 OR EXISTS(SELECT 1 FROM public.missions WHERE id=${q(m.missionId)}::uuid)
 OR EXISTS(SELECT 1 FROM public.journaux_audit WHERE id IN (${q(m.preuveId)}::uuid,${q(m.nettoyageId)}::uuid)) THEN RAISE EXCEPTION 'Run D déjà utilisé'; END IF;
END $d_guard$; ROLLBACK; SELECT true AS pret;`;}
const fingerprint=(table,where,ignore="'derniere_activite_le'")=>`(SELECT coalesce(jsonb_object_agg(x.id::text,md5((to_jsonb(x)-${ignore})::text)),'{}'::jsonb) FROM ${table} x WHERE ${where})`;
const snapshot=m=>`jsonb_build_object('soignants',${fingerprint('public.soignants',`id=ANY(${soignants(m)})`)},'etablissement',${fingerprint('public.etablissements',`id=${q(m.membres[2].userId)}::uuid`)},'mission',${fingerprint('public.missions',`id=${q(m.missionId)}::uuid`)},'creneau',${fingerprint('public.mission_creneaux',`id=${q(m.creneauId)}::uuid`)})`;
export function sqlSeedD(m) {const e=m.membres[2];return `${header(m)}DO $d_seed$ DECLARE c record; BEGIN ${guard}
IF EXISTS(SELECT 1 FROM public.journaux_audit WHERE id IN (${q(m.preuveId)}::uuid,${q(m.nettoyageId)}::uuid)) THEN RAISE EXCEPTION 'Run D déjà préparé/nettoyé : seed tardif refusé'; END IF;
${m.membres.map(a=>`IF NOT EXISTS(SELECT 1 FROM auth.users u WHERE ${belongs(m,a)} AND coalesce(u.raw_app_meta_data->'load_cleanup_pending','false'::jsonb)<>'true'::jsonb) THEN RAISE EXCEPTION 'Auth D non confirmé'; END IF;`).join('\n')}
INSERT INTO public.soignants(id,prenom,nom,email,profession,type_exercice,date_naissance,telephone,est_compte_test,source_acquisition,sms_actif,sms_alertes_actives,identite_verifiee,diplome_verifie,rpps_verifie,tous_documents_valides)
VALUES ${m.membres.slice(0,2).map(a=>`(${q(a.userId)}::uuid,${q(a.prenom)},${q(a.nom)},${q(a.email)},'AS','SALARIE','1990-01-01','+33000000000',true,${q(m.marker)},false,false,false,false,false,false)`).join(',')};
INSERT INTO public.etablissements(id,nom,siret,type,adresse_rue,adresse_ville,adresse_code_postal,email_contact,est_compte_test,source_acquisition,sms_actif,chorus_pro_actif,statut_verification,peut_publier_missions)
VALUES(${q(e.userId)}::uuid,${q(m.marker)},${q(m.siret)},'CLINIQUE_PRIVEE','Adresse fictive','Paris','75001',${q(e.email)},true,${q(m.marker)},false,false,'EN_ATTENTE',false);
UPDATE public.preferences_notifications SET canal_email=false,canal_sms=false,canal_push=false,canal_in_app=false WHERE utilisateur_id=ANY(${ids(m)});
IF (SELECT count(*) FROM public.preferences_notifications WHERE utilisateur_id=ANY(${ids(m)}) AND NOT canal_email AND NOT canal_sms AND NOT canal_push AND NOT canal_in_app)<>3 THEN RAISE EXCEPTION 'Transports D non fermés'; END IF;
IF EXISTS(SELECT 1 FROM public.favoris_soignant_etab WHERE etablissement_id=${q(e.userId)}::uuid) THEN RAISE EXCEPTION 'Favori externe imprévu'; END IF;
PERFORM set_config('jolene.planning_exact_managed','true',true);
INSERT INTO public.missions(id,etablissement_id,intitule,description,profession_requise,service,debut_le,fin_le,duree_heures,taux_horaire_base,statut,mode_attribution,type_contrat_recherche,est_urgente)
VALUES(${q(m.missionId)}::uuid,${q(e.userId)}::uuid,${q(m.marker)},'Mission fictive de recette D, aucune activité réelle.','AS','Recette D',${q(m.debut)}::timestamptz,${q(m.fin)}::timestamptz,4,20,'OUVERTE','CANDIDATURE','SALARIE',false);
INSERT INTO public.mission_creneaux(id,mission_id,debut,fin,est_pause,ordre,type_creneau) VALUES(${q(m.creneauId)}::uuid,${q(m.missionId)}::uuid,${q(m.debut)}::timestamptz,${q(m.fin)}::timestamptz,false,1,'PREVISIONNEL');
INSERT INTO public.journaux_audit(id,acteur_id,type_acteur,action,type_ressource,details) VALUES(${q(m.preuveId)}::uuid,NULL,'SYSTEME','SYSTEM','RECETTE_D2',jsonb_build_object('run_id',${q(m.runId)},'evenement','PREPARE','snapshot',${snapshot(m)}));
END $d_seed$; COMMIT; SELECT true AS prepare;`;}
// Vérification avant suppression : lignes exactes, empreintes du seed et toutes
// les dépendances FK (CASCADE inclus), y compris enfants des candidatures.
function controle(m) { const e=m.membres[2];return `
${m.membres.map(a=>`IF EXISTS(SELECT 1 FROM auth.users u WHERE u.id=${q(a.userId)}::uuid AND (${belongs(m,a)}) IS NOT TRUE) THEN RAISE EXCEPTION 'Auth hors lot D'; END IF;`).join('\n')}
SELECT details->'snapshot' INTO preuve FROM public.journaux_audit WHERE id=${q(m.preuveId)}::uuid AND type_ressource='RECETTE_D2' AND action='SYSTEM' AND details->>'run_id'=${q(m.runId)} AND details->>'evenement'='PREPARE';
IF EXISTS(SELECT 1 FROM public.soignants WHERE id=ANY(${ids(m)})) OR EXISTS(SELECT 1 FROM public.etablissements WHERE id=${q(e.userId)}::uuid) OR EXISTS(SELECT 1 FROM public.missions WHERE id=${q(m.missionId)}::uuid) THEN
 IF preuve IS NULL OR preuve IS DISTINCT FROM ${snapshot(m)} THEN RAISE EXCEPTION 'Ligne D modifiée ou preuve absente'; END IF;
END IF;
IF EXISTS(SELECT 1 FROM public.missions WHERE etablissement_id=${q(e.userId)}::uuid AND id<>${q(m.missionId)}::uuid)
 OR EXISTS(SELECT 1 FROM public.mission_creneaux WHERE mission_id=${q(m.missionId)}::uuid AND id<>${q(m.creneauId)}::uuid)
 OR EXISTS(SELECT 1 FROM public.soignants WHERE id=${q(e.userId)}::uuid)
 OR EXISTS(SELECT 1 FROM public.etablissements WHERE id=ANY(${soignants(m)})) THEN RAISE EXCEPTION 'Enfant D non prévu'; END IF;
IF EXISTS(SELECT 1 FROM public.preferences_notifications WHERE utilisateur_id=ANY(${ids(m)}) AND (canal_email IS DISTINCT FROM false OR canal_sms IS DISTINCT FROM false OR canal_push IS DISTINCT FROM false OR canal_in_app IS DISTINCT FROM false)) THEN RAISE EXCEPTION 'Transport D réactivé'; END IF;
IF EXISTS(SELECT 1 FROM public.candidatures WHERE (mission_id=${q(m.missionId)}::uuid OR soignant_id=ANY(${soignants(m)})) AND (mission_id IS DISTINCT FROM ${q(m.missionId)}::uuid OR NOT(soignant_id=ANY(${soignants(m)})) OR statut IS DISTINCT FROM 'EN_ATTENTE' OR type_contrat_choisi IS DISTINCT FROM 'SALARIE' OR message IS DISTINCT FROM ${q(m.marker)})) THEN RAISE EXCEPTION 'Candidature D étrangère/altérée'; END IF;
IF (SELECT count(*) FROM public.candidatures WHERE mission_id=${q(m.missionId)}::uuid)>2 THEN RAISE EXCEPTION 'Trop de candidatures D'; END IF;
IF EXISTS(SELECT 1 FROM public.notifications WHERE destinataire_id=ANY(${ids(m)}) AND (
(destinataire_id=${q(e.userId)}::uuid AND type_destinataire='ETABLISSEMENT' AND type='CANDIDATURE_RECUE' AND lien=${q('/etablissement/missions/'+m.missionId)} AND titre='📋 Nouvelle candidature reçue' AND corps IN (${m.membres.slice(0,2).map(a=>q(a.prenom+' a postulé à votre mission « '+m.marker+' ».')).join(',')}))
OR (destinataire_id=ANY(${soignants(m)}) AND type_destinataire='SOIGNANT' AND type='RAPPEL_DOCUMENTS' AND lien='/soignant/mes-documents' AND titre='Complétez vos documents salariés' AND corps='Votre candidature est envoyée. Les documents requis pour le CDD doivent être validés avant que l''établissement puisse vous accepter.')) IS NOT TRUE)
 OR EXISTS(SELECT 1 FROM public.notifications WHERE destinataire_id=ANY(${ids(m)}) AND (coalesce(email_envoye,false) OR coalesce(push_envoyee,false))) THEN RAISE EXCEPTION 'Notification D imprévue ou expédiée'; END IF;
IF (SELECT count(*) FROM public.notifications WHERE destinataire_id=ANY(${ids(m)}))<>2*(SELECT count(*) FROM public.candidatures WHERE mission_id=${q(m.missionId)}::uuid) THEN RAISE EXCEPTION 'Notifications D non corrélées'; END IF;
IF EXISTS(SELECT 1 FROM public.rate_limits WHERE cle=ANY(${ids(m)}::text[]) AND (action<>'candidature' OR tentatives<1 OR tentatives>2)) THEN RAISE EXCEPTION 'Compteur D imprévu'; END IF;
FOR fk IN SELECT c.conrelid::regclass AS enfant,c.confrelid::regclass AS parent,c.conkey,c.confkey,a.attname AS col,r.attname AS ref FROM pg_constraint c JOIN pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=c.conkey[1] JOIN pg_attribute r ON r.attrelid=c.confrelid AND r.attnum=c.confkey[1] WHERE c.contype='f' AND c.confrelid IN ('auth.users'::regclass,'public.soignants'::regclass,'public.etablissements'::regclass,'public.missions'::regclass,'public.mission_creneaux'::regclass,'public.candidatures'::regclass,'public.notifications'::regclass,'public.preferences_notifications'::regclass,'public.rate_limits'::regclass) LOOP
 IF cardinality(fk.conkey)<>1 OR cardinality(fk.confkey)<>1 OR fk.ref<>'id' THEN RAISE EXCEPTION 'FK D composite/inconnue'; END IF;
 lot:=CASE WHEN fk.parent='public.missions'::regclass THEN ARRAY[${q(m.missionId)}::uuid] WHEN fk.parent='public.mission_creneaux'::regclass THEN ARRAY[${q(m.creneauId)}::uuid]
 WHEN fk.parent='public.candidatures'::regclass THEN ARRAY(SELECT id FROM public.candidatures WHERE mission_id=${q(m.missionId)}::uuid)
 WHEN fk.parent='public.notifications'::regclass THEN ARRAY(SELECT id FROM public.notifications WHERE destinataire_id=ANY(${ids(m)}))
 WHEN fk.parent='public.preferences_notifications'::regclass THEN ARRAY(SELECT utilisateur_id FROM public.preferences_notifications WHERE utilisateur_id=ANY(${ids(m)}))
 WHEN fk.parent='public.rate_limits'::regclass THEN ARRAY(SELECT id FROM public.rate_limits WHERE cle=ANY(${ids(m)}::text[])) ELSE ${ids(m)} END;
 -- Chaque exception correspond à une relation déjà vérifiée ci-dessus.
 IF (fk.parent='auth.users'::regclass AND fk.enfant IN ('auth.sessions'::regclass,'auth.identities'::regclass,'public.preferences_notifications'::regclass,'public.soignants'::regclass,'public.etablissements'::regclass))
 OR (fk.parent='public.etablissements'::regclass AND fk.enfant='public.missions'::regclass AND fk.col='etablissement_id')
 OR (fk.parent='public.missions'::regclass AND fk.enfant IN ('public.candidatures'::regclass,'public.mission_creneaux'::regclass) AND fk.col='mission_id')
 OR (fk.parent='public.soignants'::regclass AND fk.enfant='public.candidatures'::regclass AND fk.col='soignant_id') THEN CONTINUE; END IF;
 EXECUTE format('SELECT count(*) FROM %s WHERE %I=ANY($1)',fk.enfant,fk.col) INTO n USING lot;
 IF n>0 THEN RAISE EXCEPTION 'Dépendance hors lot D : %',fk.enfant; END IF;
END LOOP;
IF EXISTS(SELECT 1 FROM public.email_queue WHERE destinataire_id=ANY(${ids(m)}) OR data->>'mission_id'=${q(m.missionId)}) OR EXISTS(SELECT 1 FROM public.tokens_push WHERE utilisateur_id=ANY(${ids(m)})) OR EXISTS(SELECT 1 FROM public.presence_status WHERE user_id=ANY(${ids(m)})) OR EXISTS(SELECT 1 FROM public.notifications WHERE id_ressource=${q(m.missionId)}::uuid AND NOT(destinataire_id=ANY(${ids(m)}))) THEN RAISE EXCEPTION 'Effet D hors lot'; END IF;`;}
export function sqlEtatD(m,nettoyer=false) { const e=m.membres[2];return `${header(m)}DO $d_check$ DECLARE c record;preuve jsonb;fk record;lot uuid[];n bigint; BEGIN ${guard}
${controle(m)}
${nettoyer?`UPDATE auth.users SET raw_app_meta_data=raw_app_meta_data||'{"load_cleanup_pending":true}'::jsonb WHERE id=ANY(${ids(m)});
DELETE FROM public.notifications WHERE destinataire_id=ANY(${ids(m)});
DELETE FROM public.rate_limits WHERE cle=ANY(${ids(m)}::text[]);
DELETE FROM public.candidatures WHERE mission_id=${q(m.missionId)}::uuid;
PERFORM set_config('jolene.sync_in_progress','true',true);
DELETE FROM public.mission_creneaux WHERE id=${q(m.creneauId)}::uuid;
DELETE FROM public.missions WHERE id=${q(m.missionId)}::uuid;
DELETE FROM public.preferences_notifications WHERE utilisateur_id=ANY(${ids(m)});
DELETE FROM public.soignants WHERE id=ANY(${soignants(m)});
DELETE FROM public.etablissements WHERE id=${q(e.userId)}::uuid;
INSERT INTO public.journaux_audit(id,acteur_id,type_acteur,action,type_ressource,details) VALUES(${q(m.nettoyageId)}::uuid,NULL,'SYSTEME','SYSTEM','RECETTE_D2',jsonb_build_object('run_id',${q(m.runId)},'evenement','CLEANUP')) ON CONFLICT(id) DO NOTHING;
IF NOT EXISTS(SELECT 1 FROM public.journaux_audit WHERE id=${q(m.nettoyageId)}::uuid AND action='SYSTEM' AND type_ressource='RECETTE_D2' AND details=jsonb_build_object('run_id',${q(m.runId)},'evenement','CLEANUP')) THEN RAISE EXCEPTION 'Reçu D altéré'; END IF;`:''}
END $d_check$; ${nettoyer?'COMMIT':'ROLLBACK'};
${sqlCompterD(m)}`;}
export function sqlCompterD(m) {return `SELECT
(SELECT count(*)::integer FROM auth.users WHERE id=ANY(${ids(m)})) AS auth,
(SELECT count(*)::integer FROM public.soignants WHERE id=ANY(${ids(m)})) AS profils,
(SELECT count(*)::integer FROM public.etablissements WHERE id=ANY(${ids(m)})) AS etablissements,
(SELECT count(*)::integer FROM public.missions WHERE id=${q(m.missionId)}::uuid) AS missions,
(SELECT count(*)::integer FROM public.mission_creneaux WHERE mission_id=${q(m.missionId)}::uuid) AS creneaux,
(SELECT count(*)::integer FROM public.preferences_notifications WHERE utilisateur_id=ANY(${ids(m)})) AS preferences,
(SELECT count(*)::integer FROM public.notifications WHERE destinataire_id=ANY(${ids(m)})) AS notifications,
(SELECT count(*)::integer FROM public.rate_limits WHERE cle=ANY(${ids(m)}::text[])) AS limites,
(SELECT count(*)::integer FROM auth.sessions WHERE user_id=ANY(${ids(m)})) AS sessions,
(SELECT count(*)::integer FROM auth.identities WHERE user_id=ANY(${ids(m)})) AS identites,
(SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'soignant_id',soignant_id) ORDER BY soignant_id),'[]'::jsonb) FROM public.candidatures WHERE mission_id=${q(m.missionId)}::uuid) AS candidatures,
(SELECT count(*)::integer FROM public.journaux_audit WHERE acteur_id=ANY(${ids(m)}) OR id IN (${q(m.preuveId)}::uuid,${q(m.nettoyageId)}::uuid)) AS audits_conserves,
(SELECT count(*)::integer FROM public.journaux_audit WHERE id=${q(m.nettoyageId)}::uuid AND type_ressource='RECETTE_D2' AND details->>'evenement'='CLEANUP' AND details->>'run_id'=${q(m.runId)}) AS recu_cleanup, 0::integer AS inattendus;`;}
