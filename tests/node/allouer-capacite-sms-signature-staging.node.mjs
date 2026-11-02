// Allocateur de capacité SMS de signature STAGING (lot 2 S1) : transports simulés,
// aucun réseau, aucun secret. Le vrai assistant Edge relit le secret écrit.
import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {signatureSmsStagingConfig} from '../../supabase/functions/_shared/signature-sms-staging-test.ts';
import {sourceClosure,canonical} from '../../scripts/ci/install-sms-staging-closed.mjs';
import {PROJET,DEPOT,WORKFLOW,CONTRAT_INSTALLATION,SECRET_EDGE,FONCTION,VERROU,Refus,verifierProjet,lireEntrees,
 configurationEdge,litteral,sqlInstallation,sqlPreconditions,sqlAllocation,sqlActivation,sqlEtat,sqlRevocation,
 IDENTITE_ROUTINE,METADONNEES_ROUTINE,allouerCapacite,revoquerDepuisRecu,resumeRecu} from '../../scripts/ci/allouer-capacite-sms-signature-staging.mjs';

const lire=chemin=>readFileSync(new URL('../../'+chemin,import.meta.url),'utf8');
const sha=v=>createHash('sha256').update(v).digest('hex');
const API=`https://api.supabase.com/v1/projects/${PROJET}`;
const GH=`https://api.github.com/repos/${DEPOT}`;
const PRODUCTION='flripxtsyegjshnhzjkz';
const SCRIPT='scripts/ci/allouer-capacite-sms-signature-staging.mjs';
const CANARI='canari-jamais-dans-un-recu-5521';
const SHA='5'.repeat(40);
const id=n=>`f2070000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const CONTRAT=id(1),MISSION=id(2),SOIGNANT=id(3),ETAB=id(4),CAPACITE=id(9);
const DOC=sha('<p>Contrat synthétique</p>');
// Valeurs synthétiques construites, jamais un vrai numéro ni un vrai identifiant.
const TEL_S='+3360000'+'0101',TEL_E='+3360000'+'0102',EXPEDITEUR='+3310000'+'0103',SID='AC'+'e'.repeat(32);
const ENV=Object.freeze({GITHUB_ACTIONS:'true',GITHUB_EVENT_NAME:'workflow_dispatch',GITHUB_REPOSITORY:DEPOT,GITHUB_REF:'refs/heads/main',
 GITHUB_SHA:SHA,EXPECTED_SHA:SHA,GITHUB_RUN_ID:'4242424242',GITHUB_RUN_ATTEMPT:'1',GITHUB_WORKFLOW_REF:`${DEPOT}/${WORKFLOW}@refs/heads/main`,
 SUPABASE_PROJECT_REF:PROJET,CONTRAT_ID:CONTRAT,DUREE_MINUTES:'45',FIN_APRES:'signature_soignant',
 SMS_RECETTE_TELEPHONE_SOIGNANT:TEL_S,SMS_RECETTE_TELEPHONE_ETABLISSEMENT:TEL_E,
 SMS_RECETTE_TWILIO_ACCOUNT_SID:SID,SMS_RECETTE_TWILIO_EXPEDITEUR:EXPEDITEUR,
 STAGING_SUPABASE_ACCESS_TOKEN:'gestion-'+CANARI,GITHUB_TOKEN:'github-'+CANARI});
const LOCAL=Object.freeze({sha:SHA,clean:true,lireFichier:lire});
const INSTALLATION=JSON.parse(lire(CONTRAT_INSTALLATION));
const INTERDITS=[TEL_S,TEL_E,EXPEDITEUR,SID,CANARI];
const ECRITURES=['insertion','activation','revocation'];
const INSERTION=/SELECT '([0-9a-f-]{36})'::uuid,'mejpriaetwgtcstbgfid','([^']+)','([0-9a-f]{40})','([0-9a-f]{64})',false,t\.maintenant,t\.maintenant\+make_interval\(mins=>([0-9]+)\),cm\.mission_id,cm\.id,cm\.hash_document,cm\.soignant_id,cm\.etablissement_id,'([^']+)','([^']+)','([^']+)','([^']+)',2\n/;
const PRECONDITIONS_OK=Object.freeze({contrat:true,missionCoherente:true,statutSignable:true,documentRendu:true,empreinteCoherente:true,
 soignantNonSigne:true,comptesTest:true,authTest:true,telephoneSoignant:true,telephoneEtablissement:true,canalSmsSoignant:true,
 canalSmsEtablissement:true,aucuneCapaciteContrat:true,aucuneCapaciteActive:true});

const json=(v,status=200)=>new Response(JSON.stringify(v),{status,headers:{'content-type':'application/json'}});
const erreurSql=texte=>json({message:`Failed to run sql query: ERROR:  ${texte} ${CANARI}`},400);
const routinesInstallees=()=>INSTALLATION.afterRoutines.map(r=>({...structuredClone(r),
 definition_md5:r.definition_md5??createHash('md5').update('definition:'+r.signature).digest('hex')}));
const sansLitteraux=q=>q.replace(/'(?:[^']|'')*'/g,"''");

function harnais(o={}){
 const s={appels:[],journal:[],etapes:[],sql:[],compte:{},capacite:null,lectures:0,attentes:[],secretsEcrits:[],suppressions:0,
  horloge:Date.parse('2026-11-02T21:00:00Z'),
  secrets:new Map(Object.entries(o.secrets??{TWILIO_ACCOUNT_SID:SID,TWILIO_AUTH_TOKEN:'jeton-'+CANARI,
   TWILIO_FROM_NUMBER:EXPEDITEUR,SUPABASE_URL:`https://${PROJET}.supabase.co`}))};
 const fichiers=[...sourceClosure(lire)].map(([chemin,contenu])=>({name:`source/${chemin}`,content:o.edge?.(chemin,contenu)??contenu}));
 const lireInsertion=q=>{
  const m=INSERTION.exec(q);assert.ok(m,'insertion au format attendu');
  return {id:m[1],runId:m[2],sourceSha:m[3],manifestSha256:m[4],duree:Number(m[5]),telephones:[m[6],m[7]],sid:m[8],expediteur:m[9],
   expire:s.horloge+Number(m[5])*60_000,enabled:false,revoquee:false};
 };
 const projection=()=>({id:s.capacite.id,contratId:CONTRAT,missionId:MISSION,soignantId:SOIGNANT,etablissementId:ETAB,documentSha256:DOC,
  runId:s.capacite.runId,sourceSha:s.capacite.sourceSha,manifestSha256:s.capacite.manifestSha256,enabled:s.capacite.enabled,
  revoquee:s.capacite.revoquee,dureeMinutes:s.capacite.duree,expiresAt:new Date(s.capacite.expire).toISOString(),
  tentativesSoignant:s.lectures>=1?1:0,tentativesEtablissement:0,maxTentatives:2});
 const actives=()=>s.capacite?.enabled&&!s.capacite.revoquee?1:0;
 const signatures=o.signatures??(n=>[{role:'soignant',statut:n>=2?'signe':n>=1?'otp_envoye':'en_attente',smsEnvoyes:n>=1?1:0,
  empreinteSignee:n>=2,signee:n>=2}]);
 const statut=o.statutContrat??(n=>n>=2?'SIGNE_SOIGNANT':'EN_ATTENTE_SIGNATURES');
 const sql={
  installation:()=>({installation:o.installation?.()??{pg17:true,vaultStaging:true,table:true,tableFermee:true,routines:routinesInstallees()}}),
  preconditions:()=>({preconditions:{identifiants:{missionId:MISSION,soignantId:SOIGNANT,etablissementId:ETAB,documentSha256:DOC},
   ...PRECONDITIONS_OK,...o.preconditions}}),
  apercu:q=>{const avant=s.capacite;s.capacite={...lireInsertion(q),enabled:true};
   const r={preuve:{capacite:projection(),scopeSoignant:true,capacitesActives:actives()}};s.capacite=avant;return r;},
  insertion:q=>{s.capacite=lireInsertion(q);return {preuve:{capacite:projection(),scopeSoignant:null,capacitesActives:0}};},
  activation:q=>{assert.ok(q.includes(`'${s.capacite.id}'::uuid`));s.capacite.enabled=true;
   return {preuve:{capacite:projection(),scopeSoignant:true,capacitesActives:actives()}};},
  etat:()=>{const n=++s.lectures;const sig=signatures(n);
   return {preuve:{maintenant:new Date(s.horloge).toISOString(),capacite:s.capacite?projection():null,
    contrat:{statut:statut(n),signatureSoignant:sig.some(x=>x.role==='soignant'&&x.signee),
     signatureEtablissement:sig.some(x=>x.role==='etablissement'&&x.signee),empreinteInchangee:o.empreinte?.(n)??true},signatures:sig}};},
  revocation:q=>{if(s.capacite&&(q.includes(`'${s.capacite.id}'::uuid`)||q.includes('WHERE enabled AND revoked_at IS NULL'))){
    s.capacite.enabled=false;s.capacite.revoquee=true;}
   return {preuve:{presente:!!s.capacite,enabled:s.capacite?s.capacite.enabled:null,revoquee:s.capacite?s.capacite.revoquee:null,
    capacitesActives:actives()}};},
 };
 const fetchImpl=async(url,req)=>{
  s.appels.push({url,methode:req.method});
  assert.equal(req.redirect,'error');assert.ok(req.signal instanceof AbortSignal);
  assert.ok(url===API||url.startsWith(API+'/')||url.startsWith(GH+'/'),'seulement GitHub et la Management API STAGING');
  assert.equal(req.headers.Authorization,`Bearer ${url.startsWith(API)?ENV.STAGING_SUPABASE_ACCESS_TOKEN:ENV.GITHUB_TOKEN}`);
  const chemin=url.startsWith(API)?url.slice(API.length)||'/':url.slice(GH.length);
  if(url===`${API}/database/query`){
   const {query,read_only}=JSON.parse(req.body);assert.equal(read_only,false);
   const etape=/^-- sms-capacite:([a-z]+)\n/.exec(query)?.[1];assert.ok(etape in sql,'étape SQL connue');
   s.compte[etape]=(s.compte[etape]??0)+1;s.etapes.push(etape);s.sql.push(query);s.journal.push(`sql:${etape}`);
   const injecte=o.erreurSql?.[etape]?.(s.compte[etape],s);
   if(injecte==='transport')throw Error(CANARI);
   if(injecte)return injecte;
   const reponse=json([sql[etape](query)]);
   if(o.perdre?.[etape]?.(s.compte[etape]))throw Error(CANARI);
   return reponse;
  }
  s.journal.push(`${req.method} ${chemin}`);
  const injecte=o.reponse?.(url,req,s);
  if(injecte==='transport')throw Error(CANARI);
  if(injecte)return injecte;
  if(url===`${GH}/git/ref/heads/main`)return json({ref:'refs/heads/main',object:{type:'commit',sha:o.main?.(s)??SHA}});
  if(url===API)return json(o.projet??{id:PROJET,status:'ACTIVE_HEALTHY',region:'eu-west-1',
   database:{host:`db.${PROJET}.supabase.co`,postgres_engine:'17'}});
  if(url===`${API}/functions`)return json(o.fonctions??[
   {id:'5e2f040c-7ad2-4d68-8b78-725a5880343d',slug:FONCTION,version:24,status:'ACTIVE',verify_jwt:false,import_map:false,
    import_map_path:null,ezbr_sha256:'b'.repeat(64)},
   {id:id(77),slug:'generate-invoice',version:22,status:'ACTIVE',verify_jwt:false,ezbr_sha256:'c'.repeat(64)}]);
  if(url===`${API}/functions/${FONCTION}/body`){assert.equal(req.headers.Accept,'multipart/form-data');return json({files:fichiers});}
  if(url===`${API}/secrets`){
   if(req.method==='GET')return json([...s.secrets].map(([name,v])=>({name,value:sha(v)})));
   if(req.method==='POST'){for(const x of JSON.parse(req.body)){s.secrets.set(x.name,x.value);s.secretsEcrits.push(x);}
    return new Response(null,{status:201});}
   if(req.method==='DELETE'){for(const n of JSON.parse(req.body))s.secrets.delete(n);s.suppressions++;return json({});}
  }
  assert.fail(`appel inattendu ${req.method} ${chemin}`);
 };
 const attendre=async ms=>{s.attentes.push(ms);s.horloge+=ms;};
 return {s,fetchImpl,attendre};
}
async function lancer(o={},env=ENV,local=LOCAL){
 const h=harnais(o),recus=[];
 const recu=await allouerCapacite({env,local,contratInstallation:INSTALLATION,fetchImpl:h.fetchImpl,attendre:h.attendre,
  checkpoint:v=>{recus.push(v);h.s.journal.push(`recu:${v.phase}:${v.insertionTentee}:${v.secretEcritureTentee}:${v.activationTentee}`);},
  nouvelId:()=>CAPACITE,intervalleMs:20_000,delaiRevocationMs:5_000});
 return {...h,recu,recus};
}
const ecritures=s=>[...s.etapes.filter(e=>ECRITURES.includes(e)),...s.appels.filter(a=>a.url===`${API}/secrets`&&a.methode!=='GET').map(a=>a.methode)];
const sansSecret=valeur=>{const texte=JSON.stringify(valeur);for(const x of INTERDITS)assert.equal(texte.includes(x),false,'aucun téléphone, identifiant Twilio ni jeton');};

test('seul le projet STAGING mejpriaetwgtcstbgfid est accepté',()=>{
 assert.equal(verifierProjet(PROJET),PROJET);
 for(const ref of [PRODUCTION,'',undefined,null,PROJET.toUpperCase(),` ${PROJET}`,`${PROJET}x`,'abcdefghijklmnopqrst'])
  assert.throws(()=>verifierProjet(ref),e=>e instanceof Refus&&e.code==='PROJET_REFUSE');
});

test('un autre projet (dont la production) est refusé avant tout appel réseau, en allocation comme en révocation',async()=>{
 for(const ref of [PRODUCTION,'abcdefghijklmnopqrst',undefined]){
  const {s,recu}=await lancer({},{...ENV,SUPABASE_PROJECT_REF:ref});
  assert.equal(recu.code,'PROJET_REFUSE');assert.equal(recu.status,'echec');assert.equal(s.appels.length,0);
  const h=harnais();
  const r=await revoquerDepuisRecu({env:{...ENV,SUPABASE_PROJECT_REF:ref},local:LOCAL,recu:null,fetchImpl:h.fetchImpl,attendre:h.attendre});
  assert.equal(r.code,'PROJET_REFUSE');assert.equal(h.s.appels.length,0);
 }
});

test('tout contexte autre que main exact, dispatch manuel et premier essai est refusé avant le réseau',async()=>{
 for(const [nom,env,local] of [
  ['push',{GITHUB_EVENT_NAME:'push'}],['pull_request',{GITHUB_EVENT_NAME:'pull_request'}],['branche',{GITHUB_REF:'refs/heads/feat/x'}],
  ['dépôt',{GITHUB_REPOSITORY:'autre/JJJJJ'}],['SHA attendu',{EXPECTED_SHA:'6'.repeat(40)}],['deuxième essai',{GITHUB_RUN_ATTEMPT:'2'}],
  ['autre workflow',{GITHUB_WORKFLOW_REF:`${DEPOT}/.github/workflows/autre.yml@refs/heads/main`}],['hors Actions',{GITHUB_ACTIONS:undefined}],
  ['checkout sale',{},{clean:false}],['checkout autre SHA',{},{sha:'7'.repeat(40)}],
 ]){
  const {s,recu}=await lancer({},{...ENV,...env},{...LOCAL,...local});
  assert.equal(recu.code,'MAIN_EXACT_REQUIS',nom);assert.equal(s.appels.length,0,nom);
 }
});

test('les entrées invalides sont refusées avant le réseau',async()=>{
 for(const [code,env] of [
  ['CONTRAT_ID_REFUSE',{CONTRAT_ID:'pas-un-uuid'}],['CONTRAT_ID_REFUSE',{CONTRAT_ID:CONTRAT.toUpperCase()}],['CONTRAT_ID_REFUSE',{CONTRAT_ID:`${CONTRAT}'--`}],
  ['DUREE_REFUSEE',{DUREE_MINUTES:'61'}],['DUREE_REFUSEE',{DUREE_MINUTES:'9'}],['DUREE_REFUSEE',{DUREE_MINUTES:'45.5'}],['DUREE_REFUSEE',{DUREE_MINUTES:undefined}],
  ['FIN_REFUSEE',{FIN_APRES:'jamais'}],
  ['TELEPHONES_REFUSES',{SMS_RECETTE_TELEPHONE_SOIGNANT:'0600000101'}],['TELEPHONES_REFUSES',{SMS_RECETTE_TELEPHONE_ETABLISSEMENT:undefined}],
  ['TELEPHONES_REFUSES',{SMS_RECETTE_TELEPHONE_ETABLISSEMENT:TEL_S}],
  ['TWILIO_REFUSE',{SMS_RECETTE_TWILIO_ACCOUNT_SID:'AC123'}],['TWILIO_REFUSE',{SMS_RECETTE_TWILIO_EXPEDITEUR:TEL_S}],
  ['TWILIO_REFUSE',{SMS_RECETTE_TWILIO_EXPEDITEUR:undefined}],
  ['JETONS_REQUIS',{STAGING_SUPABASE_ACCESS_TOKEN:''}],['JETONS_REQUIS',{GITHUB_TOKEN:undefined}],
 ]){
  const {s,recu}=await lancer({},{...ENV,...env});
  assert.equal(recu.code,code,JSON.stringify(env));assert.equal(s.appels.length,0);sansSecret(recu);
 }
 assert.deepEqual(lireEntrees(ENV),{contratId:CONTRAT,dureeMinutes:45,finApres:'signature_soignant',telephoneSoignant:TEL_S,
  telephoneEtablissement:TEL_E,twilioAccountSid:SID,expediteur:EXPEDITEUR});
});

test('identité du projet, Edge send-sms, secrets Edge, supplément et préconditions : tout écart arrête avant la moindre écriture',async()=>{
 const cas=[
  ['PROJET_IDENTITE_REFUSEE',{projet:{id:PRODUCTION,status:'ACTIVE_HEALTHY',region:'eu-west-1',database:{host:`db.${PRODUCTION}.supabase.co`,postgres_engine:'17'}}}],
  ['PROJET_IDENTITE_REFUSEE',{projet:{id:PROJET,status:'PAUSED',region:'eu-west-1',database:{host:`db.${PROJET}.supabase.co`,postgres_engine:'17'}}}],
  ['MAIN_DEPLACE',{main:()=>'6'.repeat(40)}],
  ['EDGE_SEND_SMS_REFUSEE',{fonctions:[{id:id(70),slug:FONCTION,version:24,status:'ACTIVE',verify_jwt:true,ezbr_sha256:'b'.repeat(64)}]}],
  ['EDGE_SEND_SMS_REFUSEE',{fonctions:[{id:id(70),slug:'generate-invoice',version:24,status:'ACTIVE',verify_jwt:false,ezbr_sha256:'b'.repeat(64)}]}],
  ['EDGE_SOURCE_DIFFERENTE',{edge:(chemin,contenu)=>chemin.endsWith('signature-sms-staging-test.ts')?contenu+'\n// dérive':undefined}],
  ['CAPACITE_EDGE_DEJA_OUVERTE',{secrets:{[SECRET_EDGE]:'{}',TWILIO_ACCOUNT_SID:SID,TWILIO_AUTH_TOKEN:'x',TWILIO_FROM_NUMBER:EXPEDITEUR}}],
  ['TWILIO_EDGE_NON_CONFORME',{secrets:{TWILIO_ACCOUNT_SID:'AC'+'d'.repeat(32),TWILIO_AUTH_TOKEN:'x',TWILIO_FROM_NUMBER:EXPEDITEUR}}],
  ['TWILIO_EDGE_NON_CONFORME',{secrets:{TWILIO_ACCOUNT_SID:SID,TWILIO_FROM_NUMBER:EXPEDITEUR}}],
  ['TWILIO_EDGE_NON_CONFORME',{secrets:{TWILIO_ACCOUNT_SID:SID,TWILIO_AUTH_TOKEN:'x',TWILIO_FROM_NUMBER:'+3310000'+'0999'}}],
  ['ENV_EDGE_NON_CONFORME',{secrets:{TWILIO_ACCOUNT_SID:SID,TWILIO_AUTH_TOKEN:'x',TWILIO_FROM_NUMBER:EXPEDITEUR,SUPABASE_ENV:'production'}}],
  ['ENV_EDGE_NON_CONFORME',{secrets:{TWILIO_ACCOUNT_SID:SID,TWILIO_AUTH_TOKEN:'x',TWILIO_FROM_NUMBER:EXPEDITEUR,SUPABASE_URL:`https://${PRODUCTION}.supabase.co`}}],
  ['BASE_NON_STAGING',{installation:()=>({pg17:true,vaultStaging:false,table:true,tableFermee:true,routines:routinesInstallees()})}],
  ['SUPPLEMENT_ABSENT',{installation:()=>({pg17:true,vaultStaging:true,table:false,tableFermee:false,routines:[]})}],
  ['SUPPLEMENT_DIFFERENT',{installation:()=>({pg17:true,vaultStaging:true,table:true,tableFermee:false,routines:routinesInstallees()})}],
  ['SUPPLEMENT_DIFFERENT',{installation:()=>({pg17:true,vaultStaging:true,table:true,tableFermee:true,
   routines:routinesInstallees().map(r=>r.signature.startsWith('private.fn_signature_sms_test_scope')?{...r,body_md5:'0'.repeat(31)+'1'}:r)})}],
  ['SUPPLEMENT_DIFFERENT',{installation:()=>({pg17:true,vaultStaging:true,table:true,tableFermee:true,routines:routinesInstallees().slice(1)})}],
  ['PRECONDITIONS_NON_REMPLIES',{preconditions:{canalSmsSoignant:false}}],
  ['PRECONDITIONS_NON_REMPLIES',{preconditions:{telephoneEtablissement:false,aucuneCapaciteContrat:false}}],
  ['SQL_REFUSE',{erreurSql:{apercu:()=>erreurSql('P0001: SIGNATURE_SMS_TEST_SCOPE_REFUSED')}}],
 ];
 for(const [code,o] of cas){
  const {s,recu}=await lancer(o);
  assert.equal(recu.code,code,JSON.stringify(o).slice(0,160));
  assert.equal(recu.status,'echec');assert.deepEqual(ecritures(s),[]);assert.equal(recu.insertionTentee,false);
  assert.equal(recu.revocation,null);sansSecret(recu);
 }
 const {recu}=await lancer({preconditions:{telephoneEtablissement:false,aucuneCapaciteContrat:false}});
 assert.deepEqual(recu.preconditionsManquantes,['telephoneEtablissement','aucuneCapaciteContrat']);
 const scope=await lancer({erreurSql:{apercu:()=>erreurSql('P0001: SIGNATURE_SMS_TEST_SCOPE_REFUSED')}});
 assert.equal(scope.recu.sqlCode,'SIGNATURE_SMS_TEST_SCOPE_REFUSED');
 const informatif=await lancer({preconditions:{canalSmsEtablissement:false}});
 assert.equal(informatif.recu.status,'succes');assert.equal(informatif.recu.preconditions.canalSmsEtablissement,false);
});

test('parcours nominal : aperçu annulé, insertion fermée, secret Edge, activation, attente, révocation et retrait du secret',async()=>{
 const {s,recu,recus}=await lancer();
 assert.equal(recu.status,'succes');assert.equal(recu.code,null);assert.equal(recu.attente.raison,'SIGNATURE_SOIGNANT');
 assert.deepEqual(s.etapes,['installation','preconditions','apercu','insertion','activation','etat','etat','revocation','etat']);
 assert.equal(s.compte.insertion,1);assert.equal(s.compte.activation,1);
 assert.deepEqual(s.appels.filter(a=>a.url===`${API}/secrets`).map(a=>a.methode),['GET','POST','GET','GET','DELETE','GET']);
 assert.equal(s.appels.filter(a=>a.url===`${GH}/git/ref/heads/main`).length,2);
 // Le reçu est écrit avant chaque mutation.
 const avant=(marque,etape)=>assert.ok(s.journal.findIndex(x=>x.startsWith(marque))<s.journal.indexOf(etape),`${marque} avant ${etape}`);
 avant('recu:insertion:true','sql:insertion');avant('recu:secret_edge:true:true','POST /secrets');avant('recu:activation:true:true:true','sql:activation');
 // État final : capacité révoquée, secret retiré, preuve P5 relue.
 assert.equal(s.capacite.enabled,false);assert.equal(s.capacite.revoquee,true);assert.equal(s.secrets.has(SECRET_EDGE),false);
 assert.deepEqual(recu.revocation,{capacite:'revoquee',secret:'absent',confirmee:true,essaisSql:1,essaisSecret:1});
 assert.equal(recu.preuveP5,true);assert.equal(recu.final.signatureSoignant.statut,'signe');
 // Le secret Edge est exactement celui qu'accepte le vrai assistant send-sms, et il égale la ligne insérée.
 assert.equal(s.secretsEcrits.length,1);const [ecrit]=s.secretsEcrits;assert.equal(ecrit.name,SECRET_EDGE);
 const config=signatureSmsStagingConfig(k=>({SUPABASE_URL:`https://${PROJET}.supabase.co`,TWILIO_ACCOUNT_SID:SID,
  TWILIO_FROM_NUMBER:EXPEDITEUR,TWILIO_AUTH_TOKEN:'x',[SECRET_EDGE]:ecrit.value})[k]);
 const ligne=INSERTION.exec(s.sql[s.etapes.indexOf('insertion')]);
 assert.deepEqual([config.runId,config.sourceSha,config.manifestSha256,config.accountSid,config.senderPhone],[ligne[2],ligne[3],ligne[4],ligne[8],ligne[9]]);
 assert.deepEqual([ligne[1],ligne[5],ligne[6],ligne[7]],[CAPACITE,'45',TEL_S,TEL_E]);
 assert.equal(config.runId,'sms-signature-gh-4242424242-1');assert.equal(config.sourceSha,SHA);
 assert.equal(sha(JSON.stringify(canonical(recu.manifeste))),recu.manifestSha256);assert.equal(config.manifestSha256,recu.manifestSha256);
 assert.equal(recu.manifeste.projectRef,PROJET);assert.equal(recu.manifeste.installationManifestSha256,INSTALLATION.manifestSha256);
 // Aucun téléphone, identifiant Twilio, jeton ni corps brut dans les reçus.
 for(const r of [recu,...recus,resumeRecu(recu)])sansSecret(r);
 assert.equal(recu.appelFournisseur,false);
});

test('chaque requête SQL est bornée : lecture seule vérifiée, écritures limitées à la table de capacités, verrous et garde STAGING',()=>{
 const p={capaciteId:CAPACITE,runId:'sms-signature-gh-1-1',sourceSha:SHA,manifestSha256:'a'.repeat(64),dureeMinutes:45,contratId:CONTRAT,
  missionId:MISSION,soignantId:SOIGNANT,etablissementId:ETAB,documentSha256:DOC,telephoneSoignant:TEL_S,telephoneEtablissement:TEL_E,
  twilioAccountSid:SID,expediteur:EXPEDITEUR};
 const lectures=[sqlInstallation(INSTALLATION.afterRoutines.map(r=>r.signature)),sqlPreconditions({contratId:CONTRAT,telephoneSoignant:TEL_S,telephoneEtablissement:TEL_E}),sqlEtat(p)];
 for(const q of lectures){
  assert.match(q,/^-- sms-capacite:[a-z]+\nBEGIN READ ONLY;/);assert.match(q,/ROLLBACK;$/);assert.match(q,/SMS_CAPACITE_CONTEXTE_LECTURE/);
  assert.doesNotMatch(sansLitteraux(q),/\b(INSERT|UPDATE|DELETE|TRUNCATE|DROP|ALTER|CREATE|GRANT|REVOKE|COMMIT)\b/);
 }
 const ecrituresSql=[[sqlAllocation(p,{apercu:true}),'ROLLBACK'],[sqlAllocation(p,{apercu:false}),'COMMIT'],[sqlActivation(p),'COMMIT'],
  [sqlRevocation({capaciteId:CAPACITE,contratId:CONTRAT}),'COMMIT']];
 for(const [q,fin] of ecrituresSql){
  assert.match(q,/^-- sms-capacite:[a-z]+\nBEGIN;/);assert.ok(q.endsWith(`${fin};`));
  assert.ok(q.includes('SMS_CAPACITE_CONTEXTE_ECRITURE')&&q.includes("'https://mejpriaetwgtcstbgfid.supabase.co'")&&q.includes(VERROU));
  assert.ok(q.includes(`PERFORM 1 FROM public.contrats_mission WHERE id='${CONTRAT}'::uuid FOR UPDATE;`),'verrou contrat avant capacité');
  const cibles=[...sansLitteraux(q).matchAll(/\b(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM)\s+([a-z_.]+)/g)].map(m=>m[1]);
  assert.ok(cibles.length>0&&cibles.every(c=>c==='private.signature_sms_test_capacities'),cibles.join(','));
  assert.doesNotMatch(sansLitteraux(q),/\b(DELETE|TRUNCATE|DROP|ALTER|CREATE|GRANT|REVOKE)\b/);
 }
 assert.ok(sqlActivation(p).includes(`PERFORM private.fn_signature_sms_test_scope('${CONTRAT}'::uuid,'${SOIGNANT}'::uuid);`));
 assert.ok(sqlAllocation(p,{apercu:true}).includes('PERFORM private.fn_signature_sms_test_scope'));
 assert.equal(sqlAllocation(p,{apercu:false}).includes('SET enabled=true'),false,'insertion fermée sans activation');
 assert.equal(litteral("a'b"),"'a''b'");
 for(const mauvais of [{capaciteId:'x'},{telephoneSoignant:"+33'"},{dureeMinutes:61},{runId:'autre'},{documentSha256:'z'}])
  assert.throws(()=>sqlAllocation({...p,...mauvais},{apercu:false}),e=>e instanceof Refus&&e.code==='PARAMETRES_REFUSES');
 assert.throws(()=>sqlPreconditions({contratId:CONTRAT,telephoneSoignant:"x'",telephoneEtablissement:TEL_E}),e=>e.code==='PARAMETRES_REFUSES');
 assert.throws(()=>configurationEdge({...p,twilioAccountSid:'AC1'}),e=>e.code==='CONFIGURATION_EDGE_REFUSEE');
});

test('les métadonnées de routines sont lues exactement comme l’installateur relu',()=>{
 const installateur=lire('scripts/ci/install-sms-staging-closed-sql.mjs');
 const identite=/const identity="([^"]+)";/.exec(installateur)[1];
 const metadonnees=/const metadata=`([\s\S]*?)`;/.exec(installateur)[1].replaceAll('${identity}',identite);
 assert.equal(IDENTITE_ROUTINE,identite);assert.equal(METADONNEES_ROUTINE,metadonnees);
});

test('aucune nouvelle insertion après une réponse perdue : révocation idempotente, statut honnête',async()=>{
 const perdue=await lancer({perdre:{insertion:()=>true}});
 assert.equal(perdue.recu.code,'TRANSPORT_INCERTAIN');assert.equal(perdue.s.compte.insertion,1);
 assert.equal(perdue.s.capacite.revoquee,true);assert.equal(perdue.recu.revocation.confirmee,true);
 assert.equal(perdue.recu.status,'echec');assert.equal(perdue.s.compte.activation,undefined);
 const jamais=await lancer({erreurSql:{insertion:()=>'transport'}});
 assert.equal(jamais.recu.revocation.capacite,'absente');assert.equal(jamais.recu.status,'echec');
 assert.equal(jamais.s.secretsEcrits.length,0);sansSecret(jamais.recu);
});

test('secret Edge non confirmé, activation refusée ou lectures en échec : la capacité et le secret sont refermés',async()=>{
 const secret=await lancer({reponse:(url,req,s)=>url===`${API}/secrets`&&req.method==='GET'&&s.secretsEcrits.length&&s.secrets.has(SECRET_EDGE)
  &&!s.relu?(s.relu=true,json([{name:SECRET_EDGE,value:sha('autre')}])):undefined});
 assert.equal(secret.recu.code,'SECRET_EDGE_NON_CONFIRME');assert.equal(secret.s.compte.activation,undefined);
 assert.equal(secret.s.capacite.revoquee,true);assert.ok(secret.s.suppressions>=1);assert.equal(secret.s.secrets.has(SECRET_EDGE),false);
 const activation=await lancer({erreurSql:{activation:()=>erreurSql('P0001: SMS_CAPACITE_ACTIVATION_REFUSEE')}});
 assert.equal(activation.recu.sqlCode,'SMS_CAPACITE_ACTIVATION_REFUSEE');assert.equal(activation.s.capacite.revoquee,true);
 assert.equal(activation.s.secrets.has(SECRET_EDGE),false);assert.equal(activation.recu.status,'echec');sansSecret(activation.recu);
 const lectures=await lancer({erreurSql:{etat:n=>n<=3?json({message:'indisponible'},503):undefined}});
 assert.equal(lectures.recu.attente.raison,'LECTURES_EN_ECHEC');assert.equal(lectures.s.capacite.revoquee,true);
 assert.equal(lectures.s.secrets.has(SECRET_EDGE),false);
});

test('la fin d’attente suit la signature, le contrat, le document ou l’échéance serveur',async()=>{
 const echeance=await lancer({signatures:()=>[{role:'soignant',statut:'otp_envoye',smsEnvoyes:1,empreinteSignee:false,signee:false}],statutContrat:()=>'EN_ATTENTE_SIGNATURES'});
 assert.equal(echeance.recu.attente.raison,'ECHEANCE');assert.equal(echeance.recu.status,'succes');assert.equal(echeance.recu.preuveP5,false);
 assert.equal(echeance.s.attentes.filter(ms=>ms===20_000).length,45*3);assert.equal(echeance.s.capacite.revoquee,true);
 const complete=await lancer({signatures:n=>[{role:'soignant',statut:n>=2?'signe':'otp_envoye',smsEnvoyes:1,empreinteSignee:n>=2,signee:n>=2},
  {role:'etablissement',statut:n>=4?'signe':'en_attente',smsEnvoyes:n>=3?1:0,empreinteSignee:n>=4,signee:n>=4}],
  statutContrat:n=>n>=4?'SIGNE_COMPLET':n>=2?'SIGNE_SOIGNANT':'EN_ATTENTE_SIGNATURES'},{...ENV,FIN_APRES:'signature_complete'});
 assert.equal(complete.recu.attente.raison,'SIGNATURE_COMPLETE');assert.equal(complete.s.lectures,5);
 const document=await lancer({empreinte:n=>n<2});
 assert.equal(document.recu.attente.raison,'DOCUMENT_MODIFIE');assert.equal(document.recu.preuveP5,false);
 const annule=await lancer({statutContrat:()=>'ANNULE'});
 assert.equal(annule.recu.attente.raison,'CONTRAT_NON_SIGNABLE');
});

test('la révocation est réessayée puis confirmée, ou déclarée incertaine sans jamais être annoncée',async()=>{
 const reessai=await lancer({erreurSql:{revocation:n=>n<=2?erreurSql('55P03: canceling statement due to lock timeout'):undefined},
  reponse:(url,req,s)=>url===`${API}/secrets`&&req.method==='DELETE'&&s.suppressions===0&&!s.dejaRefuse?(s.dejaRefuse=true,'transport'):undefined});
 assert.equal(reessai.recu.status,'succes');assert.equal(reessai.recu.revocation.essaisSql,3);assert.equal(reessai.recu.revocation.essaisSecret,2);
 assert.equal(reessai.s.capacite.revoquee,true);assert.equal(reessai.s.secrets.has(SECRET_EDGE),false);
 const jamais=await lancer({erreurSql:{revocation:()=>'transport'}});
 assert.equal(jamais.recu.status,'incertain');assert.equal(jamais.recu.revocation.confirmee,false);
 assert.equal(jamais.recu.revocation.capacite,'non_confirmee');assert.equal(jamais.s.compte.revocation,5);
 assert.ok(Date.parse(jamais.recu.expiresAt)>0,'l’échéance serveur reste la borne écrite dans le reçu');
});

test('le mode révocation referme la capacité du reçu, retire le secret et refuse un reçu étranger',async()=>{
 const base=await lancer({erreurSql:{revocation:()=>'transport'}});
 assert.equal(base.recu.status,'incertain');
 const h=harnais();h.s.capacite={id:CAPACITE,enabled:true,revoquee:false,duree:45,expire:h.s.horloge+60_000,runId:'r',sourceSha:SHA,manifestSha256:'a'.repeat(64)};
 h.s.secrets.set(SECRET_EDGE,'{}');
 const r=await revoquerDepuisRecu({env:ENV,local:LOCAL,recu:base.recu,fetchImpl:h.fetchImpl,attendre:h.attendre,delaiMs:1});
 assert.equal(r.status,'succes');assert.equal(h.s.capacite.revoquee,true);assert.equal(h.s.secrets.has(SECRET_EDGE),false);
 assert.deepEqual(h.s.etapes,['revocation']);sansSecret(r);
 const vide=harnais();vide.s.secrets.set(SECRET_EDGE,'{}');
 const sansRecu=await revoquerDepuisRecu({env:ENV,local:LOCAL,recu:null,fetchImpl:vide.fetchImpl,attendre:vide.attendre,delaiMs:1});
 assert.equal(sansRecu.status,'succes');assert.deepEqual(vide.s.etapes,[]);assert.equal(vide.s.secrets.has(SECRET_EDGE),false);
 const illisible=harnais();
 const rIllisible=await revoquerDepuisRecu({env:ENV,local:LOCAL,recu:null,recuIllisible:true,fetchImpl:illisible.fetchImpl,attendre:illisible.attendre,delaiMs:1});
 assert.equal(rIllisible.status,'incertain');assert.deepEqual(illisible.s.etapes,['revocation']);
 assert.ok(illisible.s.sql[0].includes('WHERE enabled AND revoked_at IS NULL'));
 for(const recu of [{...base.recu,projectRef:PRODUCTION},{...base.recu,capaciteId:"x'"},{...base.recu,mode:'revoquer'}]){
  const x=harnais();const refus=await revoquerDepuisRecu({env:ENV,local:LOCAL,recu,fetchImpl:x.fetchImpl,attendre:x.attendre,delaiMs:1});
  assert.equal(refus.code,'RECU_REFUSE');assert.equal(x.s.appels.length,0);
 }
});

test('le workflow est manuel, sur main, en environnement protégé, testé avant credentials et révoque toujours',()=>{
 const wf=lire(WORKFLOW);
 assert.match(wf,/^on:\n  workflow_dispatch:\n/m);
 assert.doesNotMatch(wf,/^\s*(pull_request|pull_request_target|push|schedule|workflow_run|workflow_call|repository_dispatch):/m);
 assert.match(wf,/^    if: github\.ref == 'refs\/heads\/main'$/m);
 assert.match(wf,/^    environment: staging-sms-signature$/m);
 assert.match(wf,/^concurrency:\n  group: jolene-supabase-staging-writes\n/m);
 assert.match(wf,/^permissions:\n  contents: read\n\n/m);
 assert.match(wf,/^      SUPABASE_PROJECT_REF: mejpriaetwgtcstbgfid$/m);
 const test=wf.indexOf('run: node --test tests/node/allouer-capacite-sms-signature-staging.node.mjs');
 const allouer=wf.indexOf(`run: node ${SCRIPT} allouer`),revoquer=wf.indexOf(`run: node ${SCRIPT} revoquer`);
 assert.ok(test>0&&test<allouer&&allouer<revoquer);
 const etapeRevocation=wf.slice(wf.lastIndexOf('- name:',revoquer),revoquer);
 assert.match(etapeRevocation,/if: always\(\) && steps\.contexte\.outcome == 'success'/);
 assert.equal([...wf.matchAll(/\$\{\{ secrets\.([A-Z_]+) \}\}/g)].map(m=>m[1]).sort().join(','),
  ['SMS_RECETTE_TELEPHONE_ETABLISSEMENT','SMS_RECETTE_TELEPHONE_SOIGNANT','SMS_RECETTE_TWILIO_ACCOUNT_SID','SMS_RECETTE_TWILIO_EXPEDITEUR',
   'STAGING_SUPABASE_ACCESS_TOKEN','STAGING_SUPABASE_ACCESS_TOKEN'].sort().join(','));
 assert.equal(wf.slice(0,test).includes('secrets.'),false,'aucun secret avant les tests');
 assert.doesNotMatch(wf,/run:[^\n]*secrets\./);
 const minutes=[...wf.matchAll(/timeout-minutes: ([0-9]+)/g)].map(m=>Number(m[1]));
 assert.ok(minutes[0]>minutes.slice(1).reduce((a,b)=>a+b,0),'le job laisse le temps à la révocation');
 assert.match(wf,/if-no-files-found: ignore/);
});

test('aucun littéral de secret, de téléphone ou de projet de production dans l’allocateur et son workflow',()=>{
 for(const chemin of [SCRIPT,WORKFLOW]){
  const texte=lire(chemin);
  assert.equal(texte.includes(PRODUCTION),false,chemin);
  for(const motif of [/AC[0-9a-fA-F]{32}/,/\+[1-9][0-9]{7,}/,/eyJ[A-Za-z0-9_-]{10,}/,/sb_(?:secret|publishable)_[A-Za-z0-9]/,/sk_(?:live|test)_/])
   assert.doesNotMatch(texte,motif,`${chemin} ${motif}`);
 }
});
