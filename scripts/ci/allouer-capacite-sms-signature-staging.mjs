// STAGING seulement (projet mejpriaetwgtcstbgfid, tout autre ref est refusé avant le
// réseau). Lot 2 S1 : alloue UNE capacité de signature OTP par SMS pour un contrat
// TEST (private.signature_sms_test_capacities, supplément sms-signature-staging.sql),
// écrit le secret Edge SIGNATURE_SMS_STAGING_TEST_RUN, active la capacité, attend la
// signature puis révoque capacité et secret. Aucune autre écriture : ni profil, ni
// préférence, ni contrat, ni signature, ni appel fournisseur. Téléphones et
// identifiants Twilio viennent de secrets d'environnement et ne sont jamais
// journalisés ni recopiés dans un reçu.
import {createHash,randomUUID} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {readFileSync,writeFileSync,renameSync,mkdirSync,lstatSync,openSync,fsyncSync,closeSync,existsSync} from 'node:fs';
import {resolve,isAbsolute} from 'node:path';
import {fileURLToPath} from 'node:url';
import {checkContract,sourceClosure,checkBody,readResponse,canonical} from './install-sms-staging-closed.mjs';
import {functionsMetadata} from './refresh-generate-invoice-staging.mjs';

export const PROJET='mejpriaetwgtcstbgfid';
export const DEPOT='Gabpcd/JJJJJ';
export const WORKFLOW='.github/workflows/sms-signature-capacite-staging.yml';
export const CONTRAT_INSTALLATION='scripts/ci/install-sms-staging-closed.contract.json';
export const SECRET_EDGE='SIGNATURE_SMS_STAGING_TEST_RUN';
export const FONCTION='send-sms';
export const VERROU='pg_advisory_xact_lock(184731,1018)';
export const FINS=Object.freeze(['signature_soignant','signature_complete']);
export const DUREE_MIN=10,DUREE_MAX=60;
const API=`https://api.supabase.com/v1/projects/${PROJET}`;
const GH=`https://api.github.com/repos/${DEPOT}`;
const URL_STAGING=`https://${PROJET}.supabase.co`;
const TABLE='private.signature_sms_test_capacities';
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const E164=/^\+[1-9][0-9]{7,14}$/;
const SID=/^AC[0-9a-fA-F]{32}$/;
const SHA40=/^[a-f0-9]{40}$/,SHA64=/^[a-f0-9]{64}$/;
const RUN=/^sms-signature-[a-z0-9-]{8,64}$/;
const STATUTS_SIGNATURE=['en_attente','otp_envoye','signe','refuse','expire'];
// Codes SQL publiables : constantes RAISE de ce script et du supplément relu.
export const CODES_SQL=Object.freeze(['SMS_CAPACITE_CONTEXTE_LECTURE','SMS_CAPACITE_CONTEXTE_ECRITURE','SMS_CAPACITE_INSERTION_REFUSEE',
 'SMS_CAPACITE_ACTIVATION_REFUSEE','SMS_CAPACITE_REVOCATION_REFUSEE','SIGNATURE_SMS_TEST_SCOPE_REFUSED','SIGNATURE_SMS_TEST_IMMUTABLE']);
const PRECONDITIONS_REQUISES=Object.freeze(['contrat','missionCoherente','statutSignable','documentRendu','empreinteCoherente',
 'soignantNonSigne','comptesTest','authTest','telephoneSoignant','telephoneEtablissement','canalSmsSoignant',
 'aucuneCapaciteContrat','aucuneCapaciteActive']);
// L'établissement peut signer autrement : sa préférence SMS est seulement relevée.
const PRECONDITIONS_INFORMATIVES=Object.freeze(['canalSmsEtablissement']);
const CLES_CAPACITE=['id','contratId','missionId','soignantId','etablissementId','documentSha256','runId','sourceSha','manifestSha256',
 'enabled','revoquee','dureeMinutes','expiresAt','tentativesSoignant','tentativesEtablissement','maxTentatives'];

export const sha256=v=>createHash('sha256').update(v).digest('hex');
export class Refus extends Error{constructor(code,sqlCode=null){super(code);this.code=code;this.sqlCode=sqlCode;}}
const refuser=(code,sqlCode=null)=>{throw new Refus(code,sqlCode);};
const objet=v=>v!==null&&typeof v==='object'&&!Array.isArray(v);
const cles=(v,k)=>objet(v)&&Object.keys(v).sort().join(',')===[...k].sort().join(',');
const memes=(a,b)=>JSON.stringify(canonical(a))===JSON.stringify(canonical(b));
const jeton=v=>typeof v==='string'&&v.length>=20&&!/\s/.test(v);
const entier=v=>Number.isSafeInteger(v)&&v>=0;
const pause=ms=>new Promise(r=>setTimeout(r,ms));

export function verifierProjet(ref){if(ref!==PROJET)refuser('PROJET_REFUSE');return PROJET;}

export function verifierContexte(env,local){
 verifierProjet(env?.SUPABASE_PROJECT_REF);
 if(env.GITHUB_ACTIONS!=='true'||env.GITHUB_EVENT_NAME!=='workflow_dispatch'||env.GITHUB_REPOSITORY!==DEPOT
   ||env.GITHUB_REF!=='refs/heads/main'||!SHA40.test(env.GITHUB_SHA??'')||env.EXPECTED_SHA!==env.GITHUB_SHA
   ||env.GITHUB_WORKFLOW_REF!==`${DEPOT}/${WORKFLOW}@refs/heads/main`
   ||!/^[1-9][0-9]{0,19}$/.test(env.GITHUB_RUN_ID??'')||env.GITHUB_RUN_ATTEMPT!=='1'
   ||local?.sha!==env.GITHUB_SHA||local.clean!==true)refuser('MAIN_EXACT_REQUIS');
}

export function lireEntrees(env){
 const contratId=env.CONTRAT_ID;
 if(typeof contratId!=='string'||!UUID.test(contratId))refuser('CONTRAT_ID_REFUSE');
 const duree=env.DUREE_MINUTES;
 if(typeof duree!=='string'||!/^[1-9][0-9]?$/.test(duree)||Number(duree)<DUREE_MIN||Number(duree)>DUREE_MAX)refuser('DUREE_REFUSEE');
 if(!FINS.includes(env.FIN_APRES))refuser('FIN_REFUSEE');
 const telephoneSoignant=env.SMS_RECETTE_TELEPHONE_SOIGNANT,telephoneEtablissement=env.SMS_RECETTE_TELEPHONE_ETABLISSEMENT;
 if(![telephoneSoignant,telephoneEtablissement].every(t=>typeof t==='string'&&E164.test(t))||telephoneSoignant===telephoneEtablissement)
  refuser('TELEPHONES_REFUSES');
 const twilioAccountSid=env.SMS_RECETTE_TWILIO_ACCOUNT_SID,expediteur=env.SMS_RECETTE_TWILIO_EXPEDITEUR;
 if(typeof twilioAccountSid!=='string'||!SID.test(twilioAccountSid)||typeof expediteur!=='string'||!E164.test(expediteur)
   ||[telephoneSoignant,telephoneEtablissement].includes(expediteur))refuser('TWILIO_REFUSE');
 return {contratId,dureeMinutes:Number(duree),finApres:env.FIN_APRES,telephoneSoignant,telephoneEtablissement,twilioAccountSid,expediteur};
}

const identifiantRun=env=>`sms-signature-gh-${env.GITHUB_RUN_ID}-${env.GITHUB_RUN_ATTEMPT}`;

// Manifeste publiable : aucun téléphone, identifiant Twilio ni dérivé de ceux-ci.
export function construireManifeste(p){
 const manifeste={schemaVersion:1,projectRef:PROJET,runId:p.runId,sourceSha:p.sourceSha,workflow:WORKFLOW,workflowRunId:p.workflowRunId,
  contratId:p.contratId,missionId:p.missionId,soignantId:p.soignantId,etablissementId:p.etablissementId,documentSha256:p.documentSha256,
  dureeMinutes:p.dureeMinutes,finApres:p.finApres,maxTentativesParActeur:2,installationManifestSha256:p.installationManifestSha256};
 return {manifeste,manifestSha256:sha256(JSON.stringify(canonical(manifeste)))};
}

// Format exact lu par signatureSmsStagingConfig (supabase/functions/_shared/signature-sms-staging-test.ts).
export function configurationEdge({runId,sourceSha,manifestSha256,twilioAccountSid,expediteur}){
 if(!RUN.test(runId??'')||!SHA40.test(sourceSha??'')||!SHA64.test(manifestSha256??'')||!SID.test(twilioAccountSid??'')||!E164.test(expediteur??''))
  refuser('CONFIGURATION_EDGE_REFUSEE');
 return JSON.stringify(canonical({accountSid:twilioAccountSid,manifestSha256,runId,senderPhone:expediteur,sourceSha}));
}

export const litteral=v=>"'"+String(v).replaceAll("'","''")+"'";
const uuid=v=>`${litteral(v)}::uuid`;
function verifierParametres(p){
 if(!objet(p)||![p.capaciteId,p.contratId,p.missionId,p.soignantId,p.etablissementId].every(v=>typeof v==='string'&&UUID.test(v))
   ||p.soignantId===p.etablissementId||!RUN.test(p.runId??'')||!SHA40.test(p.sourceSha??'')||!SHA64.test(p.manifestSha256??'')
   ||!SHA64.test(p.documentSha256??'')||!Number.isSafeInteger(p.dureeMinutes)||p.dureeMinutes<DUREE_MIN||p.dureeMinutes>DUREE_MAX
   ||![p.telephoneSoignant,p.telephoneEtablissement,p.expediteur].every(v=>typeof v==='string'&&E164.test(v))
   ||typeof p.twilioAccountSid!=='string'||!SID.test(p.twilioAccountSid))refuser('PARAMETRES_REFUSES');
 return p;
}

// Expression identique à scripts/ci/install-sms-staging-closed-sql.mjs (garde de test).
export const IDENTITE_ROUTINE="n.nspname||'.'||p.proname||'('||replace(oidvectortypes(p.proargtypes),', ',',')||')'";
export const METADONNEES_ROUTINE=`jsonb_build_object('signature',${IDENTITE_ROUTINE},'body_md5',md5(p.prosrc),
 'definition_md5',md5(pg_get_functiondef(p.oid)),'owner',pg_get_userbyid(p.proowner),
 'security_definer',p.prosecdef,'config',p.proconfig,
 'acl',(SELECT jsonb_agg(x::text ORDER BY x::text) FROM unnest(p.proacl) x),
 'language',l.lanname,'volatility',p.provolatile,'returns_set',p.proretset,'strict',p.proisstrict)`;

const prelude=`SET LOCAL search_path=pg_catalog; SET LOCAL row_security=off; SET LOCAL TIME ZONE 'UTC'; SET LOCAL standard_conforming_strings=on;`;
const lecture=etape=>`-- sms-capacite:${etape}
BEGIN READ ONLY; ${prelude}
SET LOCAL statement_timeout='30s'; SET LOCAL lock_timeout='3s';
DO $sms_capacite_lecture$ BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
   OR current_setting('transaction_read_only')<>'on' OR current_setting('row_security')<>'off'
 THEN RAISE EXCEPTION 'SMS_CAPACITE_CONTEXTE_LECTURE'; END IF;
END; $sms_capacite_lecture$;`;
// Chaque écriture reprouve la base STAGING (Vault) et suit l'ordre des verrous du
// supplément : contrat, puis capacité, puis signature.
const ecriture=(etape,contratId)=>`-- sms-capacite:${etape}
BEGIN; ${prelude}
SET LOCAL statement_timeout='30s'; SET LOCAL lock_timeout='5s';
DO $sms_capacite_ecriture$ BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
   OR current_setting('transaction_read_only')<>'off' OR current_setting('row_security')<>'off'
   OR current_setting('server_version_num')::integer/10000<>17
   OR (SELECT count(*) FROM vault.decrypted_secrets WHERE name='supabase_url')<>1
   OR (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name='supabase_url') IS DISTINCT FROM ${litteral(URL_STAGING)}
 THEN RAISE EXCEPTION 'SMS_CAPACITE_CONTEXTE_ECRITURE'; END IF;
 PERFORM ${VERROU};${contratId===null?'':`
 PERFORM 1 FROM public.contrats_mission WHERE id=${uuid(contratId)} FOR UPDATE;`}
END; $sms_capacite_ecriture$;`;
const projectionCapacite=capaciteId=>`(SELECT jsonb_build_object('id',k.id,'contratId',k.contrat_id,'missionId',k.mission_id,
  'soignantId',k.soignant_id,'etablissementId',k.etablissement_id,'documentSha256',k.document_sha256,'runId',k.run_id,
  'sourceSha',k.source_sha,'manifestSha256',k.manifest_sha256,'enabled',k.enabled,'revoquee',k.revoked_at IS NOT NULL,
  'dureeMinutes',round(extract(epoch FROM k.expires_at-k.installed_at)/60)::integer,'expiresAt',k.expires_at,
  'tentativesSoignant',k.soignant_attempts,'tentativesEtablissement',k.etablissement_attempts,'maxTentatives',k.max_attempts_per_actor)
 FROM ${TABLE} k WHERE k.id=${uuid(capaciteId)})`;
const actives=`(SELECT count(*) FROM ${TABLE} WHERE enabled AND revoked_at IS NULL)`;
const preuveCapacite=(p,scope)=>`SELECT jsonb_build_object('capacite',${projectionCapacite(p.capaciteId)},
 'scopeSoignant',${scope?'true':'null'},'capacitesActives',${actives}) AS preuve`;
const corpsActivation=p=>`UPDATE ${TABLE} SET enabled=true
 WHERE id=${uuid(p.capaciteId)} AND contrat_id=${uuid(p.contratId)} AND NOT enabled AND revoked_at IS NULL
   AND soignant_attempts=0 AND etablissement_attempts=0 AND expires_at>clock_timestamp()+interval '5 minutes';
DO $sms_capacite_activation$ BEGIN
 IF (SELECT count(*) FROM ${TABLE} WHERE id=${uuid(p.capaciteId)} AND enabled AND revoked_at IS NULL)<>1 OR ${actives}<>1
 THEN RAISE EXCEPTION 'SMS_CAPACITE_ACTIVATION_REFUSEE'; END IF;
 -- Le périmètre du supplément fait foi ; il lève SIGNATURE_SMS_TEST_SCOPE_REFUSED.
 PERFORM private.fn_signature_sms_test_scope(${uuid(p.contratId)},${uuid(p.soignantId)});
END; $sms_capacite_activation$;`;

export function sqlInstallation(signatures){
 if(!Array.isArray(signatures)||signatures.length!==8
   ||signatures.some(s=>typeof s!=='string'||!/^(?:public|private)\.fn_[a-z0-9_]+\([a-z,]*\)$/.test(s)))refuser('PARAMETRES_REFUSES');
 return `${lecture('installation')}
SELECT jsonb_build_object(
 'pg17',current_setting('server_version_num')::integer/10000=17,
 'vaultStaging',(SELECT count(*) FROM vault.decrypted_secrets WHERE name='supabase_url')=1
   AND (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name='supabase_url') IS NOT DISTINCT FROM ${litteral(URL_STAGING)},
 'table',to_regclass('${TABLE}') IS NOT NULL,
 'tableFermee',COALESCE((SELECT c.relowner='postgres'::regrole AND c.relrowsecurity AND NOT c.relforcerowsecurity
   AND NOT EXISTS(SELECT 1 FROM pg_policy WHERE polrelid=c.oid)
   AND NOT EXISTS(SELECT 1 FROM (VALUES ('anon'),('authenticated'),('service_role')) r(nom)
     WHERE has_table_privilege(r.nom,c.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN'))
   AND EXISTS(SELECT 1 FROM pg_trigger t WHERE t.tgrelid=c.oid AND NOT t.tgisinternal
     AND t.tgname='signature_sms_test_immutable' AND t.tgenabled='O')
   AND EXISTS(SELECT 1 FROM pg_index x JOIN pg_class i ON i.oid=x.indexrelid
     WHERE x.indrelid=c.oid AND i.relname='signature_sms_test_one_active_run' AND x.indisvalid AND x.indisunique)
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='private' AND c.relname='signature_sms_test_capacities' AND c.relkind='r'),false),
 'routines',(SELECT COALESCE(jsonb_agg(${METADONNEES_ROUTINE} ORDER BY ${IDENTITE_ROUTINE}),'[]'::jsonb)
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace JOIN pg_language l ON l.oid=p.prolang
  WHERE p.prokind IN ('f','p') AND ${IDENTITE_ROUTINE}=ANY(ARRAY[${signatures.map(litteral).join(',')}]::text[]))) AS installation;
ROLLBACK;`;
}

const GABARIT=String.raw`'\{\{[[:space:]]*[^}]+[[:space:]]*\}\}'`;
// Diagnostic lisible du périmètre de private.fn_signature_sms_test_scope, sans donnée
// personnelle en sortie ; le périmètre lui-même reste l'arbitre à l'activation.
export function sqlPreconditions({contratId,telephoneSoignant,telephoneEtablissement}){
 if(typeof contratId!=='string'||!UUID.test(contratId)
   ||![telephoneSoignant,telephoneEtablissement].every(t=>typeof t==='string'&&E164.test(t)))refuser('PARAMETRES_REFUSES');
 const parActeur=(table,colonne,acteur,valeur)=>`EXISTS(SELECT 1 FROM cm JOIN public.${table} x ON x.id=cm.${acteur}
   WHERE private.fn_signature_sms_test_telephone(x.${colonne})=${litteral(valeur)})`;
 const canal=acteur=>`EXISTS(SELECT 1 FROM cm JOIN public.preferences_notifications p ON p.utilisateur_id=cm.${acteur} WHERE p.canal_sms IS TRUE)`;
 return `${lecture('preconditions')}
WITH cm AS (SELECT * FROM public.contrats_mission WHERE id=${uuid(contratId)})
SELECT jsonb_build_object(
 'identifiants',(SELECT jsonb_build_object('missionId',mission_id,'soignantId',soignant_id,'etablissementId',etablissement_id,
   'documentSha256',hash_document) FROM cm),
 'contrat',(SELECT count(*)=1 FROM cm),
 'missionCoherente',EXISTS(SELECT 1 FROM cm JOIN public.missions m ON m.id=cm.mission_id
   WHERE m.soignant_assigne_id=cm.soignant_id AND m.etablissement_id=cm.etablissement_id AND cm.soignant_id<>cm.etablissement_id),
 'statutSignable',EXISTS(SELECT 1 FROM cm WHERE cm.statut NOT IN ('ANNULE','EXPIRE','REFUSE','SIGNE_COMPLET')),
 'documentRendu',EXISTS(SELECT 1 FROM cm WHERE NULLIF(btrim(cm.storage_path),'') IS NOT NULL AND cm.contenu_html_rendu_le IS NOT NULL
   AND NULLIF(btrim(cm.contenu_html),'') IS NOT NULL AND cm.contenu_html !~ ${GABARIT}),
 'empreinteCoherente',EXISTS(SELECT 1 FROM cm WHERE cm.hash_document ~ '^[a-f0-9]{64}$'
   AND encode(extensions.digest(convert_to(cm.contenu_html,'UTF8'),'sha256'),'hex')=cm.hash_document),
 'soignantNonSigne',EXISTS(SELECT 1 FROM cm WHERE cm.signature_soignant IS NOT TRUE),
 'comptesTest',EXISTS(SELECT 1 FROM cm JOIN public.soignants s ON s.id=cm.soignant_id JOIN public.etablissements e ON e.id=cm.etablissement_id
   WHERE s.est_compte_test IS TRUE AND e.est_compte_test IS TRUE AND s.supprime_le IS NULL AND e.supprime_le IS NULL
     AND s.statut_compte::text='ACTIF'),
 'authTest',(SELECT count(*)=2 FROM auth.users u JOIN cm ON u.id IN (cm.soignant_id,cm.etablissement_id)
   WHERE u.deleted_at IS NULL AND u.email_confirmed_at IS NOT NULL AND (u.banned_until IS NULL OR u.banned_until<=clock_timestamp())
     AND u.raw_app_meta_data->'est_compte_test'='true'::jsonb),
 'telephoneSoignant',${parActeur('soignants','telephone','soignant_id',telephoneSoignant)},
 'telephoneEtablissement',${parActeur('etablissements','telephone_contact','etablissement_id',telephoneEtablissement)},
 'canalSmsSoignant',${canal('soignant_id')},
 'canalSmsEtablissement',${canal('etablissement_id')},
 'aucuneCapaciteContrat',NOT EXISTS(SELECT 1 FROM ${TABLE} k JOIN cm ON k.contrat_id=cm.id OR k.mission_id=cm.mission_id),
 'aucuneCapaciteActive',NOT EXISTS(SELECT 1 FROM ${TABLE} WHERE enabled AND revoked_at IS NULL)) AS preconditions;
ROLLBACK;`;
}

// L'aperçu insère, active et passe le périmètre puis annule ; l'insertion réelle
// reste fermée (enabled=false) jusqu'à la confirmation du secret Edge.
export function sqlAllocation(p,{apercu}={}){
 verifierParametres(p);if(typeof apercu!=='boolean')refuser('PARAMETRES_REFUSES');
 return `${ecriture(apercu?'apercu':'insertion',p.contratId)}
WITH t AS (SELECT clock_timestamp() AS maintenant)
INSERT INTO ${TABLE}(id,project_ref,run_id,source_sha,manifest_sha256,enabled,installed_at,expires_at,
 mission_id,contrat_id,document_sha256,soignant_id,etablissement_id,soignant_phone,etablissement_phone,twilio_account_sid,sender_phone,
 max_attempts_per_actor)
SELECT ${uuid(p.capaciteId)},${litteral(PROJET)},${litteral(p.runId)},${litteral(p.sourceSha)},${litteral(p.manifestSha256)},false,t.maintenant,t.maintenant+make_interval(mins=>${p.dureeMinutes}),cm.mission_id,cm.id,cm.hash_document,cm.soignant_id,cm.etablissement_id,${litteral(p.telephoneSoignant)},${litteral(p.telephoneEtablissement)},${litteral(p.twilioAccountSid)},${litteral(p.expediteur)},2
FROM public.contrats_mission cm CROSS JOIN t
WHERE cm.id=${uuid(p.contratId)} AND cm.mission_id=${uuid(p.missionId)} AND cm.soignant_id=${uuid(p.soignantId)}
  AND cm.etablissement_id=${uuid(p.etablissementId)} AND cm.hash_document=${litteral(p.documentSha256)};
DO $sms_capacite_insertion$ BEGIN
 IF (SELECT count(*) FROM ${TABLE} WHERE id=${uuid(p.capaciteId)} AND contrat_id=${uuid(p.contratId)} AND NOT enabled
     AND revoked_at IS NULL AND soignant_attempts=0 AND etablissement_attempts=0)<>1
 THEN RAISE EXCEPTION 'SMS_CAPACITE_INSERTION_REFUSEE'; END IF;
END; $sms_capacite_insertion$;
${apercu?corpsActivation(p)+'\n':''}${preuveCapacite(p,apercu)};
${apercu?'ROLLBACK':'COMMIT'};`;
}

export function sqlActivation(p){
 verifierParametres(p);
 return `${ecriture('activation',p.contratId)}
${corpsActivation(p)}
${preuveCapacite(p,true)};
COMMIT;`;
}

export function sqlEtat(p){
 verifierParametres(p);
 return `${lecture('etat')}
SELECT jsonb_build_object('maintenant',clock_timestamp(),'capacite',${projectionCapacite(p.capaciteId)},
 'contrat',(SELECT jsonb_build_object('statut',statut,'signatureSoignant',signature_soignant IS TRUE,
   'signatureEtablissement',signature_etablissement IS TRUE,'empreinteInchangee',hash_document IS NOT DISTINCT FROM ${litteral(p.documentSha256)})
  FROM public.contrats_mission WHERE id=${uuid(p.contratId)}),
 'signatures',(SELECT COALESCE(jsonb_agg(jsonb_build_object('role',signataire_role,'statut',statut_signature,
   'smsEnvoyes',COALESCE(sms_envoyes_count,0),'empreinteSignee',hash_document IS NOT DISTINCT FROM ${litteral(p.documentSha256)},
   'signee',signe_a IS NOT NULL) ORDER BY signataire_role,cree_le),'[]'::jsonb)
  FROM public.signatures_contrats WHERE contrat_id=${uuid(p.contratId)})) AS preuve;
ROLLBACK;`;
}

// Idempotente : une capacité absente (insertion jamais arrivée) est un état fermé.
// Une autre capacité active éventuelle est seulement comptée : elle n'annule jamais
// la révocation de celle-ci (au plus une active par projet, index unique).
export function sqlRevocation({capaciteId,contratId}){
 if(![capaciteId,contratId].every(v=>typeof v==='string'&&UUID.test(v)))refuser('PARAMETRES_REFUSES');
 const ligne=`FROM ${TABLE} WHERE id=${uuid(capaciteId)}`;
 return `${ecriture('revocation',contratId)}
UPDATE ${TABLE} SET enabled=false,revoked_at=clock_timestamp() WHERE id=${uuid(capaciteId)} AND revoked_at IS NULL;
DO $sms_capacite_revocation$ BEGIN
 IF EXISTS(SELECT 1 ${ligne} AND (enabled OR revoked_at IS NULL))
 THEN RAISE EXCEPTION 'SMS_CAPACITE_REVOCATION_REFUSEE'; END IF;
END; $sms_capacite_revocation$;
SELECT jsonb_build_object('presente',EXISTS(SELECT 1 ${ligne}),'enabled',(SELECT enabled ${ligne}),
 'revoquee',(SELECT revoked_at IS NOT NULL ${ligne}),'capacitesActives',${actives}) AS preuve;
COMMIT;`;
}

// Reçu illisible : on ferme toute capacité encore active (une seule possible par
// projet, index signature_sms_test_one_active_run), direction toujours sûre.
export function sqlRevocationActives(){
 return `${ecriture('revocation',null)}
UPDATE ${TABLE} SET enabled=false,revoked_at=clock_timestamp() WHERE enabled AND revoked_at IS NULL;
SELECT jsonb_build_object('presente',false,'enabled',null,'revoquee',null,'capacitesActives',${actives}) AS preuve;
COMMIT;`;
}

async function codeSql(reponse){
 let texte='';
 try{
  const lecteur=reponse.body?.getReader();if(!lecteur)return null;
  const morceaux=[];let taille=0;
  while(true){const {value,done}=await lecteur.read();if(done)break;taille+=value.byteLength;
   if(taille>65536){await lecteur.cancel();break;}morceaux.push(Buffer.from(value));}
  texte=Buffer.concat(morceaux).toString('utf8');
 }catch{return null;}
 // Seules des constantes relues sortent ; le corps brut n'est jamais conservé.
 const code=/\b(SMS_CAPACITE_[A-Z_]+|SIGNATURE_SMS_TEST_[A-Z_]+)\b/.exec(texte)?.[1];
 if(code&&CODES_SQL.includes(code))return code;
 const etat=/ERROR:\s+([0-9A-Z]{5}):/.exec(texte)?.[1];
 return etat?`SQLSTATE_${etat}`:null;
}

function creerClient({env,fetchImpl}){
 async function requete(url,{methode='GET',corps,fichiers=false,idDeploiement,sansReponse=false}={}){
  const gestion=url===API||url.startsWith(API+'/');
  if(!gestion&&!url.startsWith(GH+'/'))refuser('DESTINATION_REFUSEE');
  if(!gestion&&!jeton(env.GITHUB_TOKEN))refuser('JETONS_REQUIS');
  let reponse;
  try{
   reponse=await fetchImpl(url,{method:methode,redirect:'error',signal:AbortSignal.timeout(60_000),
    headers:gestion?{Authorization:`Bearer ${env.STAGING_SUPABASE_ACCESS_TOKEN}`,'Content-Type':'application/json',...(fichiers?{Accept:'multipart/form-data'}:{})}
     :{Authorization:`Bearer ${env.GITHUB_TOKEN}`,Accept:'application/vnd.github+json','User-Agent':'Jolene-capacite-sms-staging'},
    ...(corps===undefined?{}:{body:JSON.stringify(corps)})});
  }catch{refuser('TRANSPORT_INCERTAIN');}
  if(!reponse.ok){const sqlCode=await codeSql(reponse);refuser(sqlCode?'SQL_REFUSE':'HTTP_REFUSE',sqlCode);}
  if(sansReponse){try{await reponse.body?.cancel();}catch{/* corps ignoré */}return null;}
  try{return await readResponse(reponse,fichiers,idDeploiement);}catch{refuser('REPONSE_ILLISIBLE');}
 }
 async function sql(texte,cle){
  const lignes=await requete(`${API}/database/query`,{methode:'POST',corps:{query:texte,read_only:false}});
  if(!Array.isArray(lignes)||lignes.length!==1||!cles(lignes[0],[cle]))refuser('REPONSE_SQL_REFUSEE');
  return lignes[0][cle];
 }
 return {requete,sql};
}

async function verifierMain(requete,env){
 const x=await requete(`${GH}/git/ref/heads/main`);
 if(x?.ref!=='refs/heads/main'||x.object?.type!=='commit'||x.object.sha!==env.GITHUB_SHA)refuser('MAIN_DEPLACE');
}
export function verifierIdentite(x){
 if(x?.id!==PROJET||x.status!=='ACTIVE_HEALTHY'||x.region!=='eu-west-1'||x.database?.host!==`db.${PROJET}.supabase.co`
   ||String(x.database?.postgres_engine)!=='17')refuser('PROJET_IDENTITE_REFUSEE');
}
// send-sms déployée = sources send-sms de ce commit (fermeture d'import comprise).
async function verifierEdge(requete,local){
 const brut=await requete(`${API}/functions`);
 try{functionsMetadata(brut);}catch{refuser('EDGE_METADONNEES_REFUSEES');}
 const cibles=brut.filter(x=>x.slug===FONCTION),f=cibles[0];
 if(cibles.length!==1||f.status!=='ACTIVE'||f.verify_jwt!==false||f.import_map===true||(f.import_map_path??null)!==null
   ||!Number.isSafeInteger(f.version)||f.version<1)refuser('EDGE_SEND_SMS_REFUSEE');
 let attendu;
 try{attendu=new Map([...sourceClosure(chemin=>local.lireFichier(chemin))].map(([chemin,contenu])=>[chemin,sha256(contenu)]));}
 catch{refuser('SOURCES_LOCALES_REFUSEES');}
 const corps=await requete(`${API}/functions/${FONCTION}/body`,{fichiers:true,idDeploiement:`${PROJET}_${f.id}_${f.version}`});
 try{checkBody(corps,attendu);}catch{refuser('EDGE_SOURCE_DIFFERENTE');}
}

function empreintes(lignes){
 if(!Array.isArray(lignes)||lignes.length>1000||lignes.some(l=>!objet(l)||typeof l.name!=='string'))refuser('SECRETS_EDGE_ILLISIBLES');
 return nom=>{
  const t=lignes.filter(l=>l.name===nom);if(!t.length)return null;
  const d=t[0].digest??t[0].value;
  if(t.length>1||typeof d!=='string'||!SHA64.test(d))refuser('SECRETS_EDGE_ILLISIBLES');
  return d;
 };
}
// Reproduit les conditions de signatureSmsStagingConfig sur les seules empreintes.
export function verifierSecretsEdge(lignes,e){
 const empreinte=empreintes(lignes),vide=sha256('');
 if(empreinte(SECRET_EDGE)!==null)refuser('CAPACITE_EDGE_DEJA_OUVERTE');
 const url=empreinte('SUPABASE_URL'),envEdge=empreinte('SUPABASE_ENV');
 if((url!==null&&url!==sha256(URL_STAGING))||(envEdge!==null&&![sha256('staging'),sha256('test')].includes(envEdge)))refuser('ENV_EDGE_NON_CONFORME');
 const de=empreinte('TWILIO_FROM_NUMBER'),jetonTwilio=empreinte('TWILIO_AUTH_TOKEN');
 const expediteur=de!==null&&de!==vide?de:empreinte('TWILIO_PHONE_NUMBER');
 if(empreinte('TWILIO_ACCOUNT_SID')!==sha256(e.twilioAccountSid)||jetonTwilio===null||jetonTwilio===vide||expediteur!==sha256(e.expediteur))
  refuser('TWILIO_EDGE_NON_CONFORME');
}
const secretPresent=lignes=>empreintes(lignes)(SECRET_EDGE)!==null;

export function verifierInstallation(i,contrat){
 if(!cles(i,['pg17','vaultStaging','table','tableFermee','routines']))refuser('REPONSE_SQL_REFUSEE');
 if(i.pg17!==true||i.vaultStaging!==true)refuser('BASE_NON_STAGING');
 if(i.table!==true)refuser('SUPPLEMENT_ABSENT');
 const attendues=contrat.afterRoutines;
 if(i.tableFermee!==true||!Array.isArray(i.routines)||i.routines.length!==attendues.length)refuser('SUPPLEMENT_DIFFERENT');
 for(const e of attendues){
  const a=i.routines.filter(x=>x?.signature===e.signature);
  if(a.length!==1||!objet(a[0])
    ||!memes(Object.fromEntries(Object.entries(a[0]).filter(([k])=>k!=='definition_md5'||Object.hasOwn(e,k))),e))refuser('SUPPLEMENT_DIFFERENT');
 }
}

export function verifierPreconditions(x){
 const toutes=[...PRECONDITIONS_REQUISES,...PRECONDITIONS_INFORMATIVES];
 if(!cles(x,['identifiants',...toutes])||toutes.some(k=>typeof x[k]!=='boolean'))refuser('REPONSE_SQL_REFUSEE');
 const manquantes=PRECONDITIONS_REQUISES.filter(k=>x[k]!==true),ids=x.identifiants;
 if(!manquantes.length&&(!cles(ids,['missionId','soignantId','etablissementId','documentSha256'])
   ||![ids.missionId,ids.soignantId,ids.etablissementId].every(v=>typeof v==='string'&&UUID.test(v))||!SHA64.test(ids.documentSha256??'')))
  refuser('REPONSE_SQL_REFUSEE');
 return {etat:Object.fromEntries(toutes.map(k=>[k,x[k]])),manquantes,identifiants:manquantes.length?null:{...ids}};
}

function capaciteValide(c){
 return cles(c,CLES_CAPACITE)&&typeof c.enabled==='boolean'&&typeof c.revoquee==='boolean'&&Number.isFinite(Date.parse(c.expiresAt))
  &&[c.tentativesSoignant,c.tentativesEtablissement,c.maxTentatives,c.dureeMinutes].every(entier);
}
export function verifierPreuveCapacite(x,p,{enabled,scope}){
 if(!cles(x,['capacite','scopeSoignant','capacitesActives']))refuser('REPONSE_SQL_REFUSEE');
 const c=x.capacite;
 if(!capaciteValide(c)||c.id!==p.capaciteId||c.contratId!==p.contratId||c.missionId!==p.missionId||c.soignantId!==p.soignantId
   ||c.etablissementId!==p.etablissementId||c.documentSha256!==p.documentSha256||c.runId!==p.runId||c.sourceSha!==p.sourceSha
   ||c.manifestSha256!==p.manifestSha256||c.enabled!==enabled||c.revoquee!==false||c.dureeMinutes!==p.dureeMinutes
   ||c.tentativesSoignant!==0||c.tentativesEtablissement!==0||c.maxTentatives!==2
   ||x.scopeSoignant!==(scope?true:null)||x.capacitesActives!==(enabled?1:0))refuser('CAPACITE_NON_CONFIRMEE');
 return c;
}

export function verifierEtat(x){
 const contrat=x?.contrat,signatures=x?.signatures;
 if(!cles(x,['maintenant','capacite','contrat','signatures'])||!Number.isFinite(Date.parse(x.maintenant))
   ||(x.capacite!==null&&!capaciteValide(x.capacite))
   ||(contrat!==null&&(!cles(contrat,['statut','signatureSoignant','signatureEtablissement','empreinteInchangee'])
     ||typeof contrat.statut!=='string'||!['signatureSoignant','signatureEtablissement','empreinteInchangee'].every(k=>typeof contrat[k]==='boolean')))
   ||!Array.isArray(signatures)||signatures.length>4||signatures.some(s=>!cles(s,['role','statut','smsEnvoyes','empreinteSignee','signee'])
     ||!['soignant','etablissement'].includes(s.role)||!STATUTS_SIGNATURE.includes(s.statut)||!entier(s.smsEnvoyes)
     ||typeof s.empreinteSignee!=='boolean'||typeof s.signee!=='boolean'))refuser('REPONSE_SQL_REFUSEE');
 return x;
}
const signatureDe=(e,role)=>{const s=e.signatures.filter(x=>x.role===role).at(-1);
 return s?{statut:s.statut,empreinteSignee:s.empreinteSignee,signee:s.signee,smsEnvoyes:s.smsEnvoyes}:null;};
const projectionEtat=e=>({lueLe:e.maintenant,contratStatut:e.contrat?.statut??null,empreinteInchangee:e.contrat?.empreinteInchangee??null,
 signatureSoignant:signatureDe(e,'soignant'),signatureEtablissement:signatureDe(e,'etablissement'),
 capaciteActive:!!e.capacite&&e.capacite.enabled&&!e.capacite.revoquee,capaciteRevoquee:e.capacite?.revoquee??null,
 tentativesSoignant:e.capacite?.tentativesSoignant??null,tentativesEtablissement:e.capacite?.tentativesEtablissement??null});

// Fin d'attente, horloge du serveur (jamais celle du runner) pour l'échéance.
export function raisonFin(e,finApres){
 const c=e.capacite;
 if(!c||c.enabled!==true||c.revoquee!==false)return 'CAPACITE_FERMEE';
 if(!e.contrat||e.contrat.empreinteInchangee!==true)return 'DOCUMENT_MODIFIE';
 if(e.contrat.statut==='SIGNE_COMPLET')return 'SIGNATURE_COMPLETE';
 if(['ANNULE','EXPIRE','REFUSE'].includes(e.contrat.statut))return 'CONTRAT_NON_SIGNABLE';
 if(finApres==='signature_soignant'&&signatureDe(e,'soignant')?.statut==='signe')return 'SIGNATURE_SOIGNANT';
 if(Date.parse(e.maintenant)>=Date.parse(c.expiresAt))return 'ECHEANCE';
 return null;
}
async function attendreFin({sql,p,finApres,attendre,intervalleMs}){
 const a={raison:null,lectures:0,echecsLecture:0,derniere:null};
 const maximum=Math.ceil((p.dureeMinutes+2)*60_000/intervalleMs)+3;
 let echecs=0;
 for(let i=0;i<maximum;i++){
  let etat=null;
  try{etat=verifierEtat(await sql(sqlEtat(p),'preuve'));a.lectures++;echecs=0;}
  catch{a.echecsLecture++;if(++echecs>=3){a.raison='LECTURES_EN_ECHEC';return a;}}
  if(etat){a.derniere=projectionEtat(etat);const raison=raisonFin(etat,finApres);if(raison){a.raison=raison;return a;}}
  await attendre(intervalleMs);
 }
 a.raison='LECTURES_EPUISEES';return a;
}

// Toujours sûre et rejouable : capacité révoquée (ou absente), puis secret Edge absent.
async function revoquer({requete,sql,capaciteId,contratId,toutes=false,attendre,essais=5,delaiMs=5_000}){
 const r={capacite:capaciteId||toutes?'non_confirmee':'sans_objet',secret:'non_confirme',confirmee:false,essaisSql:0,essaisSecret:0,
  autresCapacitesActives:null};
 for(let i=0;i<essais&&r.capacite==='non_confirmee';i++){
  r.essaisSql++;
  try{
   const x=await sql(capaciteId?sqlRevocation({capaciteId,contratId}):sqlRevocationActives(),'preuve');
   if(!cles(x,['presente','enabled','revoquee','capacitesActives'])||!entier(x.capacitesActives)||(toutes&&x.capacitesActives!==0)
     ||(x.presente!==false&&(x.presente!==true||x.enabled!==false||x.revoquee!==true)))refuser('REVOCATION_NON_CONFIRMEE');
   r.capacite=toutes?'actives_revoquees':x.presente?'revoquee':'absente';r.autresCapacitesActives=x.capacitesActives;
  }catch{if(i<essais-1)await attendre(delaiMs);}
 }
 for(let i=0;i<essais&&r.secret==='non_confirme';i++){
  r.essaisSecret++;
  try{
   if(secretPresent(await requete(`${API}/secrets`))){
    await requete(`${API}/secrets`,{methode:'DELETE',corps:[SECRET_EDGE],sansReponse:true});
    if(secretPresent(await requete(`${API}/secrets`)))refuser('SECRET_EDGE_TOUJOURS_PRESENT');
   }
   r.secret='absent';
  }catch{if(i<essais-1)await attendre(delaiMs);}
 }
 r.confirmee=r.capacite!=='non_confirmee'&&r.secret==='absent';
 return r;
}

function recuVierge(){
 return {schemaVersion:1,mode:'allouer',status:'echec',phase:'contexte',code:null,sqlCode:null,projectRef:PROJET,sourceSha:null,runId:null,
  capaciteId:null,contratId:null,missionId:null,manifestSha256:null,manifeste:null,preconditions:null,preconditionsManquantes:[],
  insertionTentee:false,insertionConfirmee:false,secretEcritureTentee:false,secretConfirme:false,activationTentee:false,
  activationConfirmee:false,expiresAt:null,attente:null,revocation:null,final:null,preuveP5:false,appelFournisseur:false};
}

export async function allouerCapacite({env,local,contratInstallation,fetchImpl=fetch,attendre=pause,checkpoint=()=>{},
 nouvelId=randomUUID,intervalleMs=20_000,delaiRevocationMs=5_000}){
 const r=recuVierge();
 const sauver=()=>{try{checkpoint(structuredClone(r));}catch{refuser('RECU_NON_ECRIT');}};
 let mutation=false,p=null,client=null;
 try{
  verifierContexte(env,local);
  const e=lireEntrees(env);
  if(!jeton(env.STAGING_SUPABASE_ACCESS_TOKEN)||!jeton(env.GITHUB_TOKEN))refuser('JETONS_REQUIS');
  try{checkContract(contratInstallation);}catch{refuser('CONTRAT_INSTALLATION_REFUSE');}
  r.sourceSha=env.GITHUB_SHA;r.runId=identifiantRun(env);r.contratId=e.contratId;sauver();
  client=creerClient({env,fetchImpl});const {requete,sql}=client;
  r.phase='provenance';await verifierMain(requete,env);
  r.phase='identite';verifierIdentite(await requete(API));
  r.phase='edge';await verifierEdge(requete,local);
  r.phase='secrets_edge';verifierSecretsEdge(await requete(`${API}/secrets`),e);
  r.phase='installation';
  verifierInstallation(await sql(sqlInstallation(contratInstallation.afterRoutines.map(x=>x.signature)),'installation'),contratInstallation);
  r.phase='preconditions';
  const pre=verifierPreconditions(await sql(sqlPreconditions(e),'preconditions'));
  r.preconditions=pre.etat;r.preconditionsManquantes=pre.manquantes;sauver();
  if(pre.manquantes.length)refuser('PRECONDITIONS_NON_REMPLIES');
  const {manifeste,manifestSha256}=construireManifeste({runId:r.runId,sourceSha:env.GITHUB_SHA,workflowRunId:env.GITHUB_RUN_ID,
   contratId:e.contratId,...pre.identifiants,dureeMinutes:e.dureeMinutes,finApres:e.finApres,
   installationManifestSha256:contratInstallation.manifestSha256});
  p=verifierParametres(Object.freeze({capaciteId:nouvelId(),runId:r.runId,sourceSha:env.GITHUB_SHA,manifestSha256,dureeMinutes:e.dureeMinutes,
   contratId:e.contratId,...pre.identifiants,telephoneSoignant:e.telephoneSoignant,telephoneEtablissement:e.telephoneEtablissement,
   twilioAccountSid:e.twilioAccountSid,expediteur:e.expediteur}));
  const config=configurationEdge(p);
  r.capaciteId=p.capaciteId;r.missionId=p.missionId;r.manifeste=manifeste;r.manifestSha256=manifestSha256;
  r.phase='apercu';verifierPreuveCapacite(await sql(sqlAllocation(p,{apercu:true}),'preuve'),p,{enabled:true,scope:true});
  r.phase='insertion';await verifierMain(requete,env);
  // Reçu écrit avant chaque mutation ; une réponse perdue n'est jamais rejouée.
  r.insertionTentee=true;sauver();mutation=true;
  verifierPreuveCapacite(await sql(sqlAllocation(p,{apercu:false}),'preuve'),p,{enabled:false,scope:false});
  r.insertionConfirmee=true;
  r.phase='secret_edge';r.secretEcritureTentee=true;sauver();
  await requete(`${API}/secrets`,{methode:'POST',corps:[{name:SECRET_EDGE,value:config}],sansReponse:true});
  const ecrit=empreintes(await requete(`${API}/secrets`))(SECRET_EDGE);
  if(ecrit!==sha256(config))refuser('SECRET_EDGE_NON_CONFIRME');
  r.secretConfirme=true;
  r.phase='activation';r.activationTentee=true;sauver();
  const active=verifierPreuveCapacite(await sql(sqlActivation(p),'preuve'),p,{enabled:true,scope:true});
  r.activationConfirmee=true;r.expiresAt=active.expiresAt;
  r.phase='attente';sauver();
  r.attente=await attendreFin({sql,p,finApres:e.finApres,attendre,intervalleMs});
 }catch(err){r.code=err instanceof Refus?err.code:'REFUS_LOCAL';r.sqlCode=err instanceof Refus?err.sqlCode:null;}
 if(mutation){
  r.phase='revocation';
  try{sauver();}catch{/* la révocation passe avant le reçu */}
  try{r.revocation=await revoquer({...client,capaciteId:p.capaciteId,contratId:p.contratId,attendre,delaiMs:delaiRevocationMs});}
  catch{r.revocation={capacite:'non_confirmee',secret:'non_confirme',confirmee:false,essaisSql:0,essaisSecret:0,autresCapacitesActives:null};}
  try{
   const fin=projectionEtat(verifierEtat(await client.sql(sqlEtat(p),'preuve')));r.final=fin;
   r.preuveP5=fin.signatureSoignant?.statut==='signe'&&fin.signatureSoignant.empreinteSignee===true&&fin.empreinteInchangee===true;
  }catch{r.final=null;}
 }
 r.status=!mutation?'echec':r.revocation?.confirmee!==true?'incertain':r.code?'echec':'succes';
 r.phase='termine';
 try{sauver();}catch{r.code=r.code??'RECU_NON_ECRIT';}
 return r;
}

export async function revoquerDepuisRecu({env,local,recu,recuIllisible=false,fetchImpl=fetch,attendre=pause,delaiMs=5_000}){
 const r={schemaVersion:1,mode:'revoquer',status:'echec',code:null,projectRef:PROJET,capaciteId:null,contratId:null,revocation:null};
 try{
  verifierContexte(env,local);
  if(!jeton(env.STAGING_SUPABASE_ACCESS_TOKEN))refuser('JETONS_REQUIS');
  if(recu!==null){
   if(!objet(recu)||recu.schemaVersion!==1||recu.mode!=='allouer'||recu.projectRef!==PROJET
     ||(recu.capaciteId!==null&&(!UUID.test(String(recu.capaciteId))||!UUID.test(String(recu.contratId)))))refuser('RECU_REFUSE');
   r.capaciteId=recu.capaciteId;r.contratId=recu.capaciteId?recu.contratId:null;
  }
  const client=creerClient({env,fetchImpl});
  verifierIdentite(await client.requete(API));
  r.revocation=await revoquer({...client,capaciteId:r.capaciteId,contratId:r.contratId,toutes:recuIllisible,attendre,delaiMs});
  r.status=r.revocation.confirmee&&!recuIllisible?'succes':'incertain';
  if(recuIllisible)r.code='RECU_ILLISIBLE';
 }catch(err){r.code=err instanceof Refus?err.code:'REFUS_LOCAL';}
 return r;
}

export const resumeRecu=r=>({mode:r?.mode??null,status:r?.status??'echec',phase:r?.phase??null,code:r?.code??null,sqlCode:r?.sqlCode??null,
 raison:r?.attente?.raison??null,preuveP5:r?.preuveP5??false,preconditionsManquantes:r?.preconditionsManquantes??[],
 capacite:r?.revocation?.capacite??null,secret:r?.revocation?.secret??null});

const git=(racine,args)=>execFileSync('git',['-C',racine,...args],{encoding:'utf8',stdio:['ignore','pipe','pipe'],
 env:{PATH:process.env.PATH,LC_ALL:'C',GIT_CONFIG_NOSYSTEM:'1',GIT_CONFIG_GLOBAL:'/dev/null',GIT_TERMINAL_PROMPT:'0'}}).trim();
export function lireLocal(racine){
 return {sha:git(racine,['rev-parse','HEAD']),clean:git(racine,['status','--porcelain','--untracked-files=all'])==='',
  lireFichier:chemin=>{
   if(typeof chemin!=='string'||!/^supabase\/functions\/[a-zA-Z0-9_./-]+\.ts$/.test(chemin)||chemin.split('/').includes('..'))
    refuser('SOURCES_LOCALES_REFUSEES');
   const fichier=resolve(racine,chemin),etat=lstatSync(fichier);
   if(etat.isSymbolicLink()||!etat.isFile())refuser('SOURCES_LOCALES_REFUSEES');
   return readFileSync(fichier,'utf8');
  }};
}
function ecrireAtomique(dossier,nom,valeur){
 const temporaire=resolve(dossier,`${nom}.tmp`);
 writeFileSync(temporaire,JSON.stringify(valeur,null,2)+'\n',{mode:0o600});
 const fd=openSync(temporaire,'r');try{fsyncSync(fd);}finally{closeSync(fd);}
 renameSync(temporaire,resolve(dossier,nom));
}

if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 const mode=process.argv[2];let rapport;
 try{
  if(process.argv.length!==3||!['allouer','revoquer'].includes(mode))refuser('ARGUMENTS_REFUSES');
  if(!process.env.RUNNER_TEMP||!isAbsolute(process.env.RUNNER_TEMP))refuser('DOSSIER_RECU_REQUIS');
  const dossier=resolve(process.env.RUNNER_TEMP,'sms-signature-capacite');mkdirSync(dossier,{recursive:true,mode:0o700});
  const racine=process.cwd(),local=lireLocal(racine),chemin=resolve(dossier,'recu.json');
  if(mode==='allouer'){
   if(existsSync(chemin))refuser('RECU_DEJA_PRESENT');
   const contrat=JSON.parse(readFileSync(resolve(racine,CONTRAT_INSTALLATION),'utf8'));
   rapport=await allouerCapacite({env:process.env,local,contratInstallation:contrat,checkpoint:v=>ecrireAtomique(dossier,'recu.json',v)});
  }else{
   let recu=null,recuIllisible=false;
   if(existsSync(chemin)){try{recu=JSON.parse(readFileSync(chemin,'utf8'));}catch{recuIllisible=true;}}
   rapport=await revoquerDepuisRecu({env:process.env,local,recu,recuIllisible});
   ecrireAtomique(dossier,'revocation.json',rapport);
  }
 }catch(e){rapport={schemaVersion:1,mode:mode??null,status:'echec',code:e instanceof Refus?e.code:'REFUS_LOCAL'};}
 console.log(JSON.stringify(resumeRecu(rapport)));
 if(rapport.status!=='succes')process.exitCode=1;
}
