// Allocateur de capacité SMS de signature STAGING (lot 2 S1) : transports simulés,
// aucun réseau, aucun secret. Le vrai assistant Edge relit le secret écrit.
import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync,mkdtempSync,mkdirSync,writeFileSync,symlinkSync,rmSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {signatureSmsStagingConfig} from '../../supabase/functions/_shared/signature-sms-staging-test.ts';
import {sourceClosure,canonical} from '../../scripts/ci/install-sms-staging-closed.mjs';
import {PROJET,DEPOT,WORKFLOW,WORKFLOW_LOT2,WORKFLOWS_APPELANTS,CONTRAT_INSTALLATION,SECRET_EDGE,AUTRES_CAMPAGNES,FONCTION,VERROU,
 DELAI_PROPAGATION_MS,Refus,verifierProjet,verifierContexte,lireEntrees,configurationEdge,litteral,sqlInstallation,sqlPreconditions,
 sqlAllocation,sqlActivation,sqlEtat,sqlRevocation,IDENTITE_ROUTINE,METADONNEES_ROUTINE,allouerCapacite,attendreSignature,
 revoquerDepuisRecu,resumeRecu,codeSortie,preuveSignature,corpsRevocation,lireLocal} from '../../scripts/ci/allouer-capacite-sms-signature-staging.mjs';

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
const RUN='sms-signature-gh-4242424242-1';
// Valeurs synthétiques construites, jamais un vrai numéro ni un vrai identifiant.
const TEL_S='+3360000'+'0101',TEL_E='+3360000'+'0102',EXPEDITEUR='+3310000'+'0103',SID='AC'+'e'.repeat(32);
const ENV=Object.freeze({GITHUB_ACTIONS:'true',GITHUB_EVENT_NAME:'workflow_dispatch',GITHUB_REPOSITORY:DEPOT,GITHUB_REF:'refs/heads/main',
 GITHUB_SHA:SHA,EXPECTED_SHA:SHA,GITHUB_RUN_ID:'4242424242',GITHUB_RUN_ATTEMPT:'1',GITHUB_WORKFLOW_REF:`${DEPOT}/${WORKFLOW}@refs/heads/main`,
 SUPABASE_PROJECT_REF:PROJET,CONTRAT_ID:CONTRAT,DUREE_MINUTES:'45',FIN_APRES:'signature_soignant',
 SMS_RECETTE_TELEPHONE_SOIGNANT:TEL_S,SMS_RECETTE_TELEPHONE_ETABLISSEMENT:TEL_E,
 SMS_RECETTE_TWILIO_ACCOUNT_SID:SID,SMS_RECETTE_TWILIO_EXPEDITEUR:EXPEDITEUR,
 STAGING_SUPABASE_ACCESS_TOKEN:'gestion-'+CANARI,GITHUB_TOKEN:'github-'+CANARI});
// Les étapes d'attente et de révocation ne reçoivent que le jeton de gestion.
const ENV_LECTURE=Object.freeze(Object.fromEntries(Object.entries(ENV).filter(([k])=>!k.startsWith('SMS_RECETTE_')
 &&!['CONTRAT_ID','DUREE_MINUTES','FIN_APRES','GITHUB_TOKEN'].includes(k))));
const ENV_LOT2=Object.freeze({...ENV,GITHUB_WORKFLOW_REF:`${DEPOT}/${WORKFLOW_LOT2}@refs/heads/main`});
const LOCAL=Object.freeze({sha:SHA,clean:true,lireFichier:lire});
const INSTALLATION=JSON.parse(lire(CONTRAT_INSTALLATION));
const INTERDITS=[TEL_S,TEL_E,EXPEDITEUR,SID,CANARI];
const ECRITURES=['insertion','activation','revocation'];
const INSERTION=/SELECT '([0-9a-f-]{36})'::uuid,'mejpriaetwgtcstbgfid','([^']+)','([0-9a-f]{40})','([0-9a-f]{64})',false,t\.maintenant,t\.maintenant\+make_interval\(mins=>([0-9]+)\),cm\.mission_id,cm\.id,cm\.hash_document,cm\.soignant_id,cm\.etablissement_id,'([^']+)','([^']+)','([^']+)','([^']+)',2\n/;
const REVOCATION=/\nUPDATE private\.signature_sms_test_capacities SET enabled=false,revoked_at=clock_timestamp\(\) WHERE run_id='([^']+)' AND revoked_at IS NULL;\n/;
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
 // Corps Edge et supplément relus à chaque appel : un redéploiement ou un db push
 // pendant la séance se simule en changeant l'état `s`.
 const fichiers=()=>[...sourceClosure(lire)].map(([chemin,contenu])=>({name:`source/${chemin}`,content:o.edge?.(chemin,contenu,s)??contenu}));
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
  installation:()=>({installation:o.installation?.(s)??{pg17:true,vaultStaging:true,table:true,tableFermee:true,routines:routinesInstallees()}}),
  preconditions:()=>({preconditions:{identifiants:{missionId:MISSION,soignantId:SOIGNANT,etablissementId:ETAB,documentSha256:DOC},
   ...PRECONDITIONS_OK,...o.preconditions}}),
  apercu:q=>{
   const avant=s.capacite;s.capacite={...lireInsertion(q),enabled:true};
   assert.ok(q.includes('PERFORM private.fn_signature_sms_test_scope('),'portée exercée dans l’aperçu');
   // Même révocation que le mode revoquer, exercée avant l'annulation.
   assert.equal(REVOCATION.exec(q)?.[1],s.capacite.runId,'aperçu : révocation de la ligne de ce run');
   if(!o.apercuSansRevocation){s.capacite.enabled=false;s.capacite.revoquee=true;}
   const r={preuve:{capacite:projection(),scopeSoignant:true,capacitesActives:actives()}};s.capacite=avant;return r;},
  insertion:q=>{s.capacite=lireInsertion(q);return {preuve:{capacite:projection(),scopeSoignant:null,capacitesActives:0}};},
  activation:q=>{assert.ok(q.includes(`'${s.capacite.id}'::uuid`));s.capacite.enabled=true;
   return {preuve:{capacite:projection(),scopeSoignant:true,capacitesActives:actives()}};},
  etat:()=>{const n=++s.lectures;const sig=signatures(n);
   return {preuve:{maintenant:new Date(s.horloge).toISOString(),capacite:s.capacite?projection():null,
    contrat:{statut:statut(n),signatureSoignant:sig.some(x=>x.role==='soignant'&&x.signee),
     signatureEtablissement:sig.some(x=>x.role==='etablissement'&&x.signee),empreinteInchangee:o.empreinte?.(n)??true},signatures:sig}};},
  revocation:q=>{
   const run=REVOCATION.exec(q)?.[1];assert.ok(run,'révocation ciblée par run_id');
   const notre=!!s.capacite&&s.capacite.runId===run;
   if(notre){s.capacite.enabled=false;s.capacite.revoquee=true;}
   return {preuve:{presente:notre,capacite:notre?{id:s.capacite.id,contratId:CONTRAT,documentSha256:DOC,enabled:false,revoquee:true}:null,
    capacitesActives:actives()+(o.autresActives??0)}};},
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
  // Réponse perdue : la requête est appliquée, puis la réponse se perd.
  const reponse=repondre(url,req,chemin);
  if(o.perdreHttp?.(url,req,s))throw Error(CANARI);
  return reponse;
 };
 function repondre(url,req,chemin){
  if(url===`${GH}/git/ref/heads/main`)return json({ref:'refs/heads/main',object:{type:'commit',sha:o.main?.(s)??SHA}});
  if(url===API)return json(o.projet??{id:PROJET,status:'ACTIVE_HEALTHY',region:'eu-west-1',
   database:{host:`db.${PROJET}.supabase.co`,postgres_engine:'17'}});
  if(url===`${API}/functions`)return json(o.fonctions??[
   {id:'5e2f040c-7ad2-4d68-8b78-725a5880343d',slug:FONCTION,version:24,status:'ACTIVE',verify_jwt:false,import_map:false,
    import_map_path:null,ezbr_sha256:'b'.repeat(64)},
   {id:id(77),slug:'generate-invoice',version:22,status:'ACTIVE',verify_jwt:false,ezbr_sha256:'c'.repeat(64)}]);
  if(url===`${API}/functions/${FONCTION}/body`){assert.equal(req.headers.Accept,'multipart/form-data');return json({files:fichiers()});}
  if(url===`${API}/secrets`){
   if(req.method==='GET')return json([...s.secrets].map(([name,v])=>({name,value:sha(v)})));
   if(req.method==='POST'){for(const x of JSON.parse(req.body)){s.secrets.set(x.name,x.value);s.secretsEcrits.push(x);}
    return new Response(null,{status:201});}
   if(req.method==='DELETE'){for(const n of JSON.parse(req.body))s.secrets.delete(n);s.suppressions++;return json({});}
  }
  assert.fail(`appel inattendu ${req.method} ${chemin}`);
 }
 const attendre=async ms=>{s.attentes.push(ms);s.journal.push(`pause:${ms}`);s.horloge+=ms;o.pendantPause?.(ms,s);};
 return {s,fetchImpl,attendre};
}
async function lancer(o={},env=ENV,local=LOCAL,h=harnais(o)){
 const recus=[];
 const recu=await allouerCapacite({env,local,contratInstallation:INSTALLATION,fetchImpl:h.fetchImpl,attendre:h.attendre,
  checkpoint:v=>{recus.push(v);h.s.journal.push(`recu:${v.phase}:${v.insertionTentee}:${v.secretEcritureTentee}:${v.activationTentee}`);},
  nouvelId:()=>CAPACITE,delaiRevocationMs:5_000});
 return {...h,recu,recus};
}
async function attendreAvec(h,recu,env=ENV_LECTURE,local=LOCAL){
 const etapes=[];
 const r=await attendreSignature({env,local,recu,fetchImpl:h.fetchImpl,attendre:h.attendre,intervalleMs:20_000,checkpoint:v=>etapes.push(v)});
 return {r,etapes};
}
const revoquerAvec=(h,recu,o={},env=ENV_LECTURE,local=LOCAL)=>revoquerDepuisRecu({env,local,recu,recuIllisible:o.illisible??false,
 contratInstallation:Object.hasOwn(o,'contrat')?o.contrat:INSTALLATION,fetchImpl:h.fetchImpl,attendre:h.attendre,delaiMs:1});
// Séquence du workflow S1 : allouer (verrou), attendre (hors verrou), révoquer (verrou).
async function seance(o={},env=ENV){
 const a=await lancer(o,env);
 const attente=a.recu.status==='active'?await attendreAvec(a,a.recu):null;
 const revocation=await revoquerAvec(a,a.recu);
 return {...a,attente:attente?.r??null,revocation};
}
const ecritures=s=>[...s.etapes.filter(e=>ECRITURES.includes(e)),...s.appels.filter(a=>a.url===`${API}/secrets`&&a.methode!=='GET').map(a=>a.methode)];
const sansSecret=valeur=>{const texte=JSON.stringify(valeur);for(const x of INTERDITS)assert.equal(texte.includes(x),false,'aucun téléphone, identifiant Twilio ni jeton');};

test('seul le projet STAGING mejpriaetwgtcstbgfid est accepté',()=>{
 assert.equal(verifierProjet(PROJET),PROJET);
 for(const ref of [PRODUCTION,'',undefined,null,PROJET.toUpperCase(),` ${PROJET}`,`${PROJET}x`,'abcdefghijklmnopqrst'])
  assert.throws(()=>verifierProjet(ref),e=>e instanceof Refus&&e.code==='PROJET_REFUSE');
});

test('un autre projet (dont la production) est refusé avant tout appel réseau, dans les trois modes',async()=>{
 for(const ref of [PRODUCTION,'abcdefghijklmnopqrst',undefined]){
  const {s,recu}=await lancer({},{...ENV,SUPABASE_PROJECT_REF:ref});
  assert.equal(recu.code,'PROJET_REFUSE');assert.equal(recu.status,'echec');assert.equal(s.appels.length,0);
  const base=await lancer();
  const h=harnais();
  const {r:attente}=await attendreAvec(h,base.recu,{...ENV_LECTURE,SUPABASE_PROJECT_REF:ref});
  assert.equal(attente.code,'PROJET_REFUSE');assert.equal(h.s.appels.length,0);
  const r=await revoquerAvec(h,null,{},{...ENV_LECTURE,SUPABASE_PROJECT_REF:ref});
  assert.equal(r.code,'PROJET_REFUSE');assert.equal(h.s.appels.length,0);
 }
});

test('tout contexte autre que main exact, dispatch manuel, premier essai et workflow appelant listé est refusé avant le réseau',async()=>{
 for(const [nom,env,local] of [
  ['push',{GITHUB_EVENT_NAME:'push'}],['pull_request',{GITHUB_EVENT_NAME:'pull_request'}],['branche',{GITHUB_REF:'refs/heads/feat/x'}],
  ['dépôt',{GITHUB_REPOSITORY:'autre/JJJJJ'}],['SHA attendu',{EXPECTED_SHA:'6'.repeat(40)}],['deuxième essai',{GITHUB_RUN_ATTEMPT:'2'}],
  ['autre workflow',{GITHUB_WORKFLOW_REF:`${DEPOT}/.github/workflows/autre.yml@refs/heads/main`}],
  ['workflow lot 2 depuis une branche',{GITHUB_WORKFLOW_REF:`${DEPOT}/${WORKFLOW_LOT2}@refs/heads/feat/x`}],
  ['workflow S1 depuis une étiquette',{GITHUB_WORKFLOW_REF:`${DEPOT}/${WORKFLOW}@refs/tags/v1`}],
  ['workflow d’un autre dépôt',{GITHUB_WORKFLOW_REF:`autre/JJJJJ/${WORKFLOW}@refs/heads/main`}],
  ['hors Actions',{GITHUB_ACTIONS:undefined}],['checkout autre SHA',{},{sha:'7'.repeat(40)}],
 ]){
  const {s,recu}=await lancer({},{...ENV,...env},{...LOCAL,...local});
  assert.equal(recu.code,'MAIN_EXACT_REQUIS',nom);assert.equal(s.appels.length,0,nom);
 }
 assert.deepEqual(WORKFLOWS_APPELANTS,[WORKFLOW,WORKFLOW_LOT2]);
 assert.equal(WORKFLOW_LOT2,'.github/workflows/ios-swift-lot2-staging.yml');
 for(const w of WORKFLOWS_APPELANTS)
  assert.equal(verifierContexte({...ENV,GITHUB_WORKFLOW_REF:`${DEPOT}/${w}@refs/heads/main`},LOCAL),w);
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
 const twilio={TWILIO_ACCOUNT_SID:SID,TWILIO_AUTH_TOKEN:'x',TWILIO_FROM_NUMBER:EXPEDITEUR};
 const cas=[
  ['PROJET_IDENTITE_REFUSEE',{projet:{id:PRODUCTION,status:'ACTIVE_HEALTHY',region:'eu-west-1',database:{host:`db.${PRODUCTION}.supabase.co`,postgres_engine:'17'}}}],
  ['PROJET_IDENTITE_REFUSEE',{projet:{id:PROJET,status:'PAUSED',region:'eu-west-1',database:{host:`db.${PROJET}.supabase.co`,postgres_engine:'17'}}}],
  ['MAIN_DEPLACE',{main:()=>'6'.repeat(40)}],
  ['EDGE_SEND_SMS_REFUSEE',{fonctions:[{id:id(70),slug:FONCTION,version:24,status:'ACTIVE',verify_jwt:true,ezbr_sha256:'b'.repeat(64)}]}],
  ['EDGE_SEND_SMS_REFUSEE',{fonctions:[{id:id(70),slug:'generate-invoice',version:24,status:'ACTIVE',verify_jwt:false,ezbr_sha256:'b'.repeat(64)}]}],
  ['EDGE_SOURCE_DIFFERENTE',{edge:(chemin,contenu)=>chemin.endsWith('signature-sms-staging-test.ts')?contenu+'\n// dérive':undefined}],
  ['CAPACITE_EDGE_DEJA_OUVERTE',{secrets:{[SECRET_EDGE]:'{}',...twilio}}],
  // Exclusivité : aucune autre campagne STAGING ouverte (mêmes noms que les assistants voisins).
  ...AUTRES_CAMPAGNES.map(nom=>['AUTRE_CAPACITE_OUVERTE',{secrets:{[nom]:'{}',...twilio}}]),
  ['TWILIO_EDGE_NON_CONFORME',{secrets:{...twilio,TWILIO_ACCOUNT_SID:'AC'+'d'.repeat(32)}}],
  ['TWILIO_EDGE_NON_CONFORME',{secrets:{TWILIO_ACCOUNT_SID:SID,TWILIO_FROM_NUMBER:EXPEDITEUR}}],
  ['TWILIO_EDGE_NON_CONFORME',{secrets:{...twilio,TWILIO_FROM_NUMBER:'+3310000'+'0999'}}],
  ['ENV_EDGE_NON_CONFORME',{secrets:{...twilio,SUPABASE_ENV:'production'}}],
  ['ENV_EDGE_NON_CONFORME',{secrets:{...twilio,SUPABASE_URL:`https://${PRODUCTION}.supabase.co`}}],
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
 assert.deepEqual(AUTRES_CAMPAGNES,['CONNECT_STAGING_TEST_RUN','INVOICE_STAGING_TEST_RUN','HONORAIRES_STAGING_TEST_RUN','INVOICE_EMAIL_STAGING_TEST_RUN']);
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
});

test('canal_sms de l’établissement : relevé pour la signature du soignant, exigé pour la signature complète',async()=>{
 const soignant=await lancer({preconditions:{canalSmsEtablissement:false}});
 assert.equal(soignant.recu.status,'active');assert.equal(soignant.recu.preconditions.canalSmsEtablissement,false);
 assert.deepEqual(soignant.recu.preconditionsManquantes,[]);
 const complete=await lancer({preconditions:{canalSmsEtablissement:false}},{...ENV,FIN_APRES:'signature_complete'});
 assert.equal(complete.recu.code,'PRECONDITIONS_NON_REMPLIES');assert.deepEqual(complete.recu.preconditionsManquantes,['canalSmsEtablissement']);
 assert.deepEqual(ecritures(complete.s),[]);
 const ok=await lancer({},{...ENV,FIN_APRES:'signature_complete'});
 assert.equal(ok.recu.status,'active');assert.equal(ok.recu.manifeste.finApres,'signature_complete');
});

test('allouer rend la main une fois la capacité active : aperçu annulé, insertion fermée, secret, délai de propagation, activation',async()=>{
 const {s,recu,recus}=await lancer();
 assert.equal(recu.mode,'allouer');assert.equal(recu.status,'active');assert.equal(recu.code,null);assert.equal(codeSortie(recu),0);
 assert.deepEqual(s.etapes,['installation','preconditions','apercu','insertion','activation'],'aucune attente ni révocation dans allouer');
 assert.equal(s.compte.insertion,1);assert.equal(s.compte.activation,1);assert.equal(s.lectures,0);
 assert.deepEqual(s.appels.filter(a=>a.url===`${API}/secrets`).map(a=>a.methode),['GET','POST','GET','GET']);
 assert.equal(s.appels.filter(a=>a.url===`${GH}/git/ref/heads/main`).length,2);
 // Le reçu est écrit avant chaque mutation, puis une dernière fois capacité active.
 const indice=marque=>s.journal.findIndex(x=>x.startsWith(marque));
 const avant=(a,b)=>assert.ok(indice(a)>=0&&indice(a)<indice(b),`${a} avant ${b}`);
 avant('recu:insertion:true','sql:insertion');avant('recu:secret_edge:true:true','POST /secrets');avant('recu:activation:true:true:true','sql:activation');
 // Délai borné entre la confirmation du secret et l'activation, puis relecture des secrets.
 assert.equal(DELAI_PROPAGATION_MS,60_000);assert.deepEqual(s.attentes,[DELAI_PROPAGATION_MS]);
 avant('POST /secrets','recu:propagation');avant('recu:propagation',`pause:${DELAI_PROPAGATION_MS}`);
 const relecture=s.journal.indexOf('GET /secrets',s.journal.indexOf(`pause:${DELAI_PROPAGATION_MS}`));
 assert.ok(relecture>0&&relecture<s.journal.indexOf('sql:activation'),'secrets relus après le délai, avant l’activation');
 assert.equal(recus.at(-1).phase,'active');assert.equal(recus.at(-1).status,'active');
 // Capacité ouverte, secret présent : la révocation reste due par le mode revoquer.
 assert.equal(s.capacite.enabled,true);assert.equal(s.capacite.revoquee,false);assert.equal(s.secrets.has(SECRET_EDGE),true);
 assert.equal(recu.revocation,null);
 // Le secret Edge est exactement celui qu'accepte le vrai assistant send-sms, et il égale la ligne insérée.
 assert.equal(s.secretsEcrits.length,1);const [ecrit]=s.secretsEcrits;assert.equal(ecrit.name,SECRET_EDGE);
 const config=signatureSmsStagingConfig(k=>({SUPABASE_URL:`https://${PROJET}.supabase.co`,TWILIO_ACCOUNT_SID:SID,
  TWILIO_FROM_NUMBER:EXPEDITEUR,TWILIO_AUTH_TOKEN:'x',[SECRET_EDGE]:ecrit.value})[k]);
 const ligne=INSERTION.exec(s.sql[s.etapes.indexOf('insertion')]);
 assert.deepEqual([config.runId,config.sourceSha,config.manifestSha256,config.accountSid,config.senderPhone],[ligne[2],ligne[3],ligne[4],ligne[8],ligne[9]]);
 assert.deepEqual([ligne[1],ligne[5],ligne[6],ligne[7]],[CAPACITE,'45',TEL_S,TEL_E]);
 assert.equal(config.runId,RUN);assert.equal(config.sourceSha,SHA);
 assert.equal(sha(JSON.stringify(canonical(recu.manifeste))),recu.manifestSha256);assert.equal(config.manifestSha256,recu.manifestSha256);
 assert.equal(recu.manifeste.projectRef,PROJET);assert.equal(recu.manifeste.installationManifestSha256,INSTALLATION.manifestSha256);
 assert.equal(recu.manifeste.workflow,WORKFLOW);assert.equal(recu.workflow,WORKFLOW);
 // Aucun téléphone, identifiant Twilio, jeton ni corps brut dans les reçus.
 for(const r of [recu,...recus,resumeRecu(recu)])sansSecret(r);
 assert.equal(recu.appelFournisseur,false);
});

test('une autre campagne ouverte pendant le délai de propagation : aucune activation, capacité et secret refermés',async()=>{
 for(const nom of AUTRES_CAMPAGNES){
  const {s,recu}=await lancer({pendantPause:(ms,x)=>{if(ms===DELAI_PROPAGATION_MS)x.secrets.set(nom,'{}');}});
  assert.equal(recu.code,'AUTRE_CAPACITE_OUVERTE',nom);assert.equal(s.compte.activation,undefined);
  assert.equal(s.capacite.revoquee,true);assert.equal(s.secrets.has(SECRET_EDGE),false);assert.equal(s.secrets.has(nom),true,'jamais le secret d’autrui');
  assert.equal(recu.status,'echec');assert.equal(codeSortie(recu),1);
 }
 const remplace=await lancer({pendantPause:(ms,x)=>{if(ms===DELAI_PROPAGATION_MS)x.secrets.set(SECRET_EDGE,'{"autre":1}');}});
 assert.equal(remplace.recu.code,'SECRET_EDGE_NON_CONFIRME');assert.equal(remplace.s.compte.activation,undefined);
 assert.equal(remplace.s.capacite.revoquee,true);
});

test('le workflow iOS du lot 2 alloue dans son job, garde la main pour l’envoi, puis révoque à part (T11)',async()=>{
 const h=harnais();
 const a=await lancer({},ENV_LOT2,LOCAL,h);
 assert.equal(a.recu.status,'active');assert.equal(a.recu.manifeste.workflow,WORKFLOW_LOT2);
 assert.equal(h.s.capacite.enabled,true);assert.equal(h.s.secrets.has(SECRET_EDGE),true);
 // … XCUITest « temps 3 » : l'envoi a lieu pendant que la capacité est ouverte …
 const r=await revoquerAvec(h,a.recu,{},{...ENV_LECTURE,GITHUB_WORKFLOW_REF:ENV_LOT2.GITHUB_WORKFLOW_REF},{...LOCAL,clean:false});
 assert.equal(r.status,'succes');assert.equal(codeSortie(r),0);assert.equal(r.revocation.capacite,'revoquee');assert.equal(r.revocation.secret,'absent');
 assert.equal(h.s.capacite.revoquee,true);assert.equal(h.s.secrets.has(SECRET_EDGE),false);
 assert.equal(r.final.signatureSoignant.statut,'otp_envoye');assert.equal(r.preuveP5,false);sansSecret(r);
});

test('chaque requête SQL est bornée : lecture seule vérifiée, écritures limitées à la table de capacités, verrous et garde STAGING',()=>{
 const p={capaciteId:CAPACITE,runId:'sms-signature-gh-12345-1',sourceSha:SHA,manifestSha256:'a'.repeat(64),dureeMinutes:45,contratId:CONTRAT,
  missionId:MISSION,soignantId:SOIGNANT,etablissementId:ETAB,documentSha256:DOC,telephoneSoignant:TEL_S,telephoneEtablissement:TEL_E,
  twilioAccountSid:SID,expediteur:EXPEDITEUR};
 const cible={capaciteId:CAPACITE,contratId:CONTRAT,documentSha256:DOC};
 const lectures=[sqlInstallation(INSTALLATION.afterRoutines.map(r=>r.signature)),sqlPreconditions({contratId:CONTRAT,telephoneSoignant:TEL_S,telephoneEtablissement:TEL_E}),sqlEtat(cible)];
 for(const q of lectures){
  assert.match(q,/^-- sms-capacite:[a-z]+\nBEGIN READ ONLY;/);assert.match(q,/ROLLBACK;$/);assert.match(q,/SMS_CAPACITE_CONTEXTE_LECTURE/);
  assert.doesNotMatch(sansLitteraux(q),/\b(INSERT|UPDATE|DELETE|TRUNCATE|DROP|ALTER|CREATE|GRANT|REVOKE|COMMIT)\b/);
 }
 const ecrituresSql=[[sqlAllocation(p,{apercu:true}),'ROLLBACK'],[sqlAllocation(p,{apercu:false}),'COMMIT'],[sqlActivation(p),'COMMIT'],
  [sqlRevocation({runId:p.runId}),'COMMIT']];
 for(const [q,fin] of ecrituresSql){
  assert.match(q,/^-- sms-capacite:[a-z]+\nBEGIN;/);assert.ok(q.endsWith(`${fin};`));
  assert.ok(q.includes('SMS_CAPACITE_CONTEXTE_ECRITURE')&&q.includes("'https://mejpriaetwgtcstbgfid.supabase.co'")&&q.includes(VERROU));
  const cibles=[...sansLitteraux(q).matchAll(/\b(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM)\s+([a-z_.]+)/g)].map(m=>m[1]);
  assert.ok(cibles.length>0&&cibles.every(c=>c==='private.signature_sms_test_capacities'),cibles.join(','));
  assert.doesNotMatch(sansLitteraux(q),/\b(DELETE|TRUNCATE|DROP|ALTER|CREATE|GRANT|REVOKE)\b/);
 }
 for(const [q] of ecrituresSql.slice(0,3))
  assert.ok(q.includes(`PERFORM 1 FROM public.contrats_mission WHERE id='${CONTRAT}'::uuid FOR UPDATE;`),'verrou contrat avant capacité');
 // La révocation vise la seule ligne de CE run (run_id UNIQUE), jamais « toute capacité active ».
 const revocation=sqlRevocation({runId:p.runId});
 assert.ok(revocation.includes(`PERFORM 1 FROM public.contrats_mission WHERE id=(SELECT contrat_id FROM private.signature_sms_test_capacities WHERE run_id='${p.runId}') FOR UPDATE;`));
 assert.equal(REVOCATION.exec(revocation)?.[1],p.runId);
 assert.doesNotMatch(revocation,/WHERE enabled AND revoked_at IS NULL;/);
 assert.ok(sqlActivation(p).includes(`PERFORM private.fn_signature_sms_test_scope('${CONTRAT}'::uuid,'${SOIGNANT}'::uuid);`));
 assert.ok(sqlAllocation(p,{apercu:true}).includes('PERFORM private.fn_signature_sms_test_scope'));
 assert.equal(sqlAllocation(p,{apercu:false}).includes('SET enabled=true'),false,'insertion fermée sans activation');
 assert.equal(litteral("a'b"),"'a''b'");
 for(const mauvais of [{capaciteId:'x'},{telephoneSoignant:"+33'"},{dureeMinutes:61},{runId:'autre'},{documentSha256:'z'}])
  assert.throws(()=>sqlAllocation({...p,...mauvais},{apercu:false}),e=>e instanceof Refus&&e.code==='PARAMETRES_REFUSES');
 for(const mauvais of [{runId:"sms-signature-gh-1'--"},{runId:'autre'},{}])
  assert.throws(()=>sqlRevocation(mauvais),e=>e instanceof Refus&&e.code==='PARAMETRES_REFUSES');
 for(const mauvais of [{capaciteId:'x'},{contratId:"x'"},{documentSha256:'z'}])
  assert.throws(()=>sqlEtat({...cible,...mauvais}),e=>e instanceof Refus&&e.code==='PARAMETRES_REFUSES');
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
 assert.equal(perdue.recu.revocation.secret,'non_touche','secret jamais écrit par ce run : jamais retiré');
 assert.equal(perdue.recu.status,'echec');assert.equal(perdue.s.compte.activation,undefined);
 const jamais=await lancer({erreurSql:{insertion:()=>'transport'}});
 assert.equal(jamais.recu.revocation.capacite,'absente');assert.equal(jamais.recu.status,'echec');
 assert.equal(jamais.s.secretsEcrits.length,0);sansSecret(jamais.recu);
});

test('secret Edge non confirmé ou activation refusée : la capacité et le secret sont refermés',async()=>{
 const secret=await lancer({reponse:(url,req,s)=>url===`${API}/secrets`&&req.method==='GET'&&s.secretsEcrits.length&&s.secrets.has(SECRET_EDGE)
  &&!s.relu?(s.relu=true,json([{name:SECRET_EDGE,value:sha('autre')}])):undefined});
 assert.equal(secret.recu.code,'SECRET_EDGE_NON_CONFIRME');assert.equal(secret.s.compte.activation,undefined);
 assert.equal(secret.s.capacite.revoquee,true);assert.ok(secret.s.suppressions>=1);assert.equal(secret.s.secrets.has(SECRET_EDGE),false);
 const activation=await lancer({erreurSql:{activation:()=>erreurSql('P0001: SMS_CAPACITE_ACTIVATION_REFUSEE')}});
 assert.equal(activation.recu.sqlCode,'SMS_CAPACITE_ACTIVATION_REFUSEE');assert.equal(activation.s.capacite.revoquee,true);
 assert.equal(activation.s.secrets.has(SECRET_EDGE),false);assert.equal(activation.recu.status,'echec');sansSecret(activation.recu);
});

test('un reçu « active » qui ne s’écrit pas referme aussitôt la capacité et le secret',async()=>{
 const h=harnais();
 const recu=await allouerCapacite({env:ENV,local:LOCAL,contratInstallation:INSTALLATION,fetchImpl:h.fetchImpl,attendre:h.attendre,
  checkpoint:v=>{if(v.phase==='active')throw Error('disque plein');},nouvelId:()=>CAPACITE,delaiRevocationMs:1});
 assert.equal(recu.code,'RECU_NON_ECRIT');assert.equal(recu.status,'echec');assert.equal(codeSortie(recu),1);
 assert.equal(h.s.capacite.revoquee,true);assert.equal(h.s.secrets.has(SECRET_EDGE),false);
});

test('séance S1 nominale : allouer, attendre la signature du soignant hors verrou, puis révoquer',async()=>{
 const {s,recu,attente,revocation}=await seance();
 assert.equal(recu.status,'active');
 assert.equal(attente.mode,'attendre');assert.equal(attente.status,'succes');assert.equal(codeSortie(attente),0);
 assert.equal(attente.attente.raison,'SIGNATURE_SOIGNANT');assert.equal(attente.preuveFin,true);assert.equal(attente.preuveP5,true);
 assert.equal(attente.finApres,'signature_soignant','fin dérivée du manifeste du reçu, jamais ressaisie');
 // La révocation relit ensuite, en lecture seule, l'état prouvé à l'allocation (supplément et send-sms).
 assert.deepEqual(s.etapes,['installation','preconditions','apercu','insertion','activation','etat','etat','revocation','etat','installation']);
 assert.equal(revocation.status,'succes');
 assert.deepEqual(revocation.revocation,{capacite:'revoquee',secret:'absent',confirmee:true,essaisSql:1,essaisSecret:1,autresCapacitesActives:0,
  identite:'confirmee'});
 assert.deepEqual(revocation.reattestation,{edge:'conforme',supplement:'conforme'});
 assert.equal(revocation.preuveP5,true);assert.equal(revocation.final.signatureSoignant.statut,'signe');
 assert.equal(s.capacite.revoquee,true);assert.equal(s.secrets.has(SECRET_EDGE),false);
 for(const r of [attente,revocation,resumeRecu(attente),resumeRecu(revocation)])sansSecret(r);
});

test('attendre lit seulement : aucune écriture SQL ni secret, et refuse tout reçu autre que celui de ce run, actif',async()=>{
 const base=await lancer();
 const {s}=base;const ecrituresAvant=ecritures(s).length;
 const {r}=await attendreAvec(base,base.recu);
 assert.equal(r.status,'succes');assert.equal(ecritures(s).length,ecrituresAvant);
 assert.equal(s.capacite.enabled,true,'attendre ne révoque jamais');
 const {manifeste}=base.recu;
 for(const [nom,recu] of [
  ['absent',null],['autre run',{...base.recu,runId:'sms-signature-gh-1-1'}],['autre mode',{...base.recu,mode:'revoquer'}],
  ['non active',{...base.recu,status:'echec'}],['autre projet',{...base.recu,projectRef:PRODUCTION}],
  ['manifeste altéré',{...base.recu,manifeste:{...manifeste,finApres:'signature_complete'}}],
  ['manifeste d’un autre contrat',{...base.recu,contratId:id(5)}],['autre SHA',{...base.recu,sourceSha:'6'.repeat(40)}],
  ['activation non confirmée',{...base.recu,activationConfirmee:false}],
 ]){
  const h=harnais();const {r:refus}=await attendreAvec(h,recu);
  assert.equal(refus.code,'RECU_REFUSE',nom);assert.equal(refus.status,'echec',nom);assert.equal(h.s.appels.length,0,nom);
  assert.equal(codeSortie(refus),1);
 }
 // Sources lues dans le commit HEAD : un arbre de travail modifié n'empêche pas d'attendre.
 const sale=await lancer();const {r:attenteSale}=await attendreAvec(sale,sale.recu,ENV_LECTURE,{...LOCAL,clean:false});
 assert.equal(attenteSale.status,'succes');
});

test('« succes » est réservé à la fin attendue prouvée ; toute autre fin sort en code non nul',async()=>{
 const sansSignature={signatures:()=>[{role:'soignant',statut:'otp_envoye',smsEnvoyes:1,empreinteSignee:false,signee:false}],statutContrat:()=>'EN_ATTENTE_SIGNATURES'};
 const echeance=await seance(sansSignature);
 assert.equal(echeance.attente.attente.raison,'ECHEANCE');assert.equal(echeance.attente.status,'termine_sans_preuve');
 assert.equal(codeSortie(echeance.attente),1);assert.equal(echeance.attente.preuveFin,false);
 // Échéance serveur : installed_at + 45 min, l'attente commence après le délai de propagation.
 assert.equal(echeance.s.attentes.filter(ms=>ms===20_000).length,(45*60_000-DELAI_PROPAGATION_MS)/20_000);
 assert.equal(echeance.revocation.status,'succes');assert.equal(echeance.s.capacite.revoquee,true);
 const complete=await seance({signatures:n=>[{role:'soignant',statut:n>=2?'signe':'otp_envoye',smsEnvoyes:1,empreinteSignee:n>=2,signee:n>=2},
  {role:'etablissement',statut:n>=4?'signe':'en_attente',smsEnvoyes:n>=3?1:0,empreinteSignee:n>=4,signee:n>=4}],
  statutContrat:n=>n>=4?'SIGNE_COMPLET':n>=2?'SIGNE_SOIGNANT':'EN_ATTENTE_SIGNATURES'},{...ENV,FIN_APRES:'signature_complete'});
 assert.equal(complete.attente.attente.raison,'SIGNATURE_COMPLETE');assert.equal(complete.attente.status,'succes');
 assert.equal(complete.attente.finApres,'signature_complete');
 for(const [nom,o,raison] of [
  ['document modifié',{empreinte:n=>n<2},'DOCUMENT_MODIFIE'],
  ['contrat annulé',{statutContrat:()=>'ANNULE'},'CONTRAT_NON_SIGNABLE'],
  ['lectures en échec',{erreurSql:{etat:n=>n<=6?json({message:'indisponible'},503):undefined}},'LECTURES_EN_ECHEC'],
  ['signature sur une autre empreinte',{signatures:n=>[{role:'soignant',statut:n>=2?'signe':'otp_envoye',smsEnvoyes:1,empreinteSignee:false,signee:n>=2}]},'SIGNATURE_SOIGNANT'],
 ]){
  const x=await seance(o);
  assert.equal(x.attente.attente.raison,raison,nom);assert.equal(x.attente.status,'termine_sans_preuve',nom);
  assert.equal(codeSortie(x.attente),1,nom);assert.equal(x.attente.preuveFin,false,nom);
  assert.equal(x.s.capacite.revoquee,true,nom);assert.equal(x.s.secrets.has(SECRET_EDGE),false,nom);
 }
 // Hors verrou, quelques lectures refusées (verrou d'une migration concurrente) ne closent pas la séance.
 const passager=await seance({erreurSql:{etat:n=>n<=5?json({message:'indisponible'},503):undefined}});
 assert.equal(passager.attente.status,'succes');assert.equal(passager.attente.attente.echecsLecture,5);
 assert.equal(preuveSignature(null,'signature_soignant'),false);
});

test('la révocation est réessayée puis confirmée, ou déclarée incertaine sans jamais être annoncée',async()=>{
 const reessai=await seance({erreurSql:{revocation:n=>n<=2?erreurSql('55P03: canceling statement due to lock timeout'):undefined},
  reponse:(url,req,s)=>url===`${API}/secrets`&&req.method==='DELETE'&&s.suppressions===0&&!s.dejaRefuse?(s.dejaRefuse=true,'transport'):undefined});
 assert.equal(reessai.revocation.status,'succes');assert.equal(reessai.revocation.revocation.essaisSql,3);assert.equal(reessai.revocation.revocation.essaisSecret,2);
 assert.equal(reessai.s.capacite.revoquee,true);assert.equal(reessai.s.secrets.has(SECRET_EDGE),false);
 const jamais=await seance({erreurSql:{revocation:()=>'transport'}});
 assert.equal(jamais.revocation.status,'incertain');assert.equal(jamais.revocation.revocation.confirmee,false);assert.equal(codeSortie(jamais.revocation),1);
 assert.equal(jamais.revocation.revocation.capacite,'non_confirmee');assert.equal(jamais.s.compte.revocation,5);
 assert.equal(jamais.revocation.revocation.secret,'absent','le secret écrit par ce run est retiré même si le SQL échoue');
 assert.ok(Date.parse(jamais.recu.expiresAt)>0,'l’échéance serveur reste la borne écrite dans le reçu');
});

const PANNE_SONDE=(url,req,s)=>url===API&&s.sondeEnPanne?(typeof s.sondeEnPanne==='number'&&s.sondeEnPanne--,s.panne?.()??json({message:'indisponible'},503)):undefined;
test('révoquer : la sonde d’identité ne conditionne jamais la fermeture ; ratée une fois, elle est réessayée dans la boucle du SQL',async()=>{
 const statutTransitoire={id:PROJET,status:'COMING_UP',region:'eu-west-1',database:{host:`db.${PROJET}.supabase.co`,postgres_engine:'17'}};
 for(const [nom,panne] of [['429',()=>json({message:'trop de requêtes'},429)],['503',()=>json({message:'indisponible'},503)],
  ['délai ou transport',()=>'transport'],['statut transitoire',()=>json(statutTransitoire)]]){
  const a=await lancer({reponse:PANNE_SONDE});
  assert.equal(a.recu.status,'active',nom);a.s.sondeEnPanne=1;a.s.panne=panne;
  const r=await revoquerAvec(a,a.recu);
  assert.equal(r.status,'succes',nom);assert.equal(r.code,null,nom);assert.equal(r.revocation.identite,'confirmee',nom);
  assert.equal(r.revocation.capacite,'revoquee',nom);assert.equal(r.revocation.essaisSql,1,nom);assert.equal(a.s.compte.revocation,1,nom);
  assert.equal(a.s.capacite.revoquee,true,nom);assert.equal(a.s.secrets.has(SECRET_EDGE),false,nom);
  // La première écriture de révocation part sans attendre la sonde.
  assert.ok(a.s.journal.indexOf('sql:revocation')<a.s.journal.lastIndexOf('GET /'),nom);
 }
});

test('révoquer : sonde d’identité toujours en échec, ligne et secret refermés quand même, statut « incertain », jamais « echec »',async()=>{
 const a=await lancer({reponse:PANNE_SONDE});a.s.sondeEnPanne=true;
 const r=await revoquerAvec(a,a.recu);
 assert.equal(r.status,'incertain');assert.equal(r.code,'PROJET_IDENTITE_NON_CONFIRMEE');assert.equal(codeSortie(r),1);
 assert.equal(r.revocation.identite,'non_confirmee');assert.equal(r.revocation.confirmee,true,'fermeture confirmée : aucun nettoyage manuel');
 assert.equal(r.revocation.capacite,'revoquee');assert.equal(r.revocation.secret,'absent');
 assert.equal(a.s.compte.revocation,1,'SQL de révocation jamais rejoué une fois confirmé');
 assert.equal(a.s.capacite.revoquee,true);assert.equal(a.s.secrets.has(SECRET_EDGE),false);
 assert.equal(a.s.appels.filter(x=>x.url===API).length,1+5,'une sonde à l’allocation, cinq essais à la révocation');
 // Même fonction pour l'étape de repli du job allouer et pour le revoquer always() de T11 (arbre de travail modifié).
 const t11=await lancer({reponse:PANNE_SONDE},ENV_LOT2);t11.s.sondeEnPanne=true;t11.s.panne=()=>'transport';
 const r11=await revoquerAvec(t11,t11.recu,{},{...ENV_LECTURE,GITHUB_WORKFLOW_REF:ENV_LOT2.GITHUB_WORKFLOW_REF},{...LOCAL,clean:false});
 assert.equal(r11.status,'incertain');assert.equal(r11.revocation.confirmee,true);
 assert.equal(t11.s.capacite.revoquee,true);assert.equal(t11.s.secrets.has(SECRET_EDGE),false);
 // API de gestion entièrement indisponible : essais faits, statut « incertain ».
 const panne=await lancer({reponse:(url,req,s)=>s.panneTotale&&url.startsWith(API)?'transport':undefined,
  erreurSql:{revocation:(n,s)=>s.panneTotale?'transport':undefined}});
 panne.s.panneTotale=true;
 const rp=await revoquerAvec(panne,panne.recu);
 assert.equal(rp.status,'incertain');assert.equal(rp.revocation.confirmee,false);assert.equal(panne.s.compte.revocation,5);
 for(const x of [r,r11,rp])sansSecret(x);
});

test('attendre : une sonde d’identité ratée ne clôt pas la séance ; persistante, l’attente échoue sans aucune lecture',async()=>{
 const a=await lancer({reponse:PANNE_SONDE});a.s.sondeEnPanne=2;
 const {r}=await attendreAvec(a,a.recu);
 assert.equal(r.status,'succes');assert.equal(r.attente.raison,'SIGNATURE_SOIGNANT');
 const b=await lancer({reponse:PANNE_SONDE});b.s.sondeEnPanne=true;b.s.panne=()=>'transport';
 const {r:refus}=await attendreAvec(b,b.recu);
 assert.equal(refus.status,'echec');assert.equal(refus.code,'TRANSPORT_INCERTAIN');assert.equal(codeSortie(refus),1);
 assert.equal(b.s.lectures,0,'aucune lecture sans identité attestée');
 assert.equal(b.s.appels.filter(x=>x.url===API).length,1+6,'six essais, comme les lectures');
});

test('révoquer relit l’état prouvé à l’allocation : un redéploiement de send-sms ou un db push pendant la séance n’est jamais « succes »',async()=>{
 const routineModifiee=s=>s.derive?{pg17:true,vaultStaging:true,table:true,tableFermee:true,
  routines:routinesInstallees().map(r=>r.signature.startsWith('private.fn_signature_sms_test_scope')?{...r,body_md5:'0'.repeat(31)+'2'}:r)}:undefined;
 const derive=(ms,s)=>{if(ms===20_000)s.derive=true;};
 for(const [nom,o,reattestation,code] of [
  ['send-sms redéployé',{edge:(chemin,contenu,s)=>s.derive&&chemin==='supabase/functions/send-sms/index.ts'?contenu+'\n// redéployé':undefined},
   {edge:'differente',supplement:'conforme'},'REATTESTATION_DIFFERENTE'],
  ['supplément réécrit',{installation:routineModifiee},{edge:'conforme',supplement:'different'},'REATTESTATION_DIFFERENTE'],
  ['send-sms illisible',{reponse:(url,req,s)=>s.derive&&url===`${API}/functions`?json({message:'indisponible'},503):undefined},
   {edge:'non_relue',supplement:'conforme'},'REATTESTATION_NON_RELUE'],
 ]){
  const x=await seance({...o,pendantPause:derive});
  assert.equal(x.attente.status,'succes',nom);
  assert.equal(x.revocation.status,'incertain',nom);assert.equal(x.revocation.code,code,nom);assert.equal(codeSortie(x.revocation),1,nom);
  assert.deepEqual(x.revocation.reattestation,reattestation,nom);
  assert.equal(x.revocation.revocation.confirmee,true,`${nom} : fermeture confirmée`);assert.equal(x.s.capacite.revoquee,true,nom);
  assert.equal(x.s.secrets.has(SECRET_EDGE),false,nom);
  assert.equal(x.revocation.final.signatureSoignant.statut,'signe',nom);assert.equal(x.revocation.preuveP5,false,`${nom} : preuve P5 invalidée`);
  assert.deepEqual(resumeRecu(x.revocation).reattestation,reattestation,nom);
 }
 // Lecture refusée une fois : réessayée, puis conforme.
 const passager=await seance({reponse:(url,req,s)=>s.derive&&url===`${API}/functions`&&!s.dejaRefuse?(s.dejaRefuse=true,json({},503)):undefined,
  pendantPause:derive});
 assert.equal(passager.revocation.status,'succes');assert.deepEqual(passager.revocation.reattestation,{edge:'conforme',supplement:'conforme'});
 assert.equal(passager.revocation.preuveP5,true);
 // Contrat d'installation illisible : la fermeture a lieu, la relecture est déclarée non faite.
 const a=await lancer();const r=await revoquerAvec(a,a.recu,{contrat:null});
 assert.equal(r.status,'incertain');assert.equal(r.code,'REATTESTATION_NON_RELUE');assert.equal(a.s.capacite.revoquee,true);
 // Aucune ligne de ce run : rien à relire.
 const vide=harnais();const rv=await revoquerAvec(vide,null);
 assert.equal(rv.status,'succes');assert.equal(rv.reattestation,null);
 assert.equal(vide.s.appels.some(x=>x.url.startsWith(`${API}/functions`)),false);
});

test('réponse perdue sur l’écriture du secret ou sur l’activation : jamais rejouée, toujours refermée',async()=>{
 // POST /secrets appliqué, réponse perdue : secret présent, retiré, jamais réécrit.
 const secret=await lancer({perdreHttp:(url,req)=>url===`${API}/secrets`&&req.method==='POST'});
 assert.equal(secret.recu.code,'TRANSPORT_INCERTAIN');assert.equal(secret.recu.secretEcritureTentee,true);assert.equal(secret.recu.secretConfirme,false);
 assert.equal(secret.s.appels.filter(a=>a.url===`${API}/secrets`&&a.methode==='POST').length,1,'aucune seconde écriture');
 assert.equal(secret.s.secretsEcrits.length,1);assert.equal(secret.s.suppressions,1,'secret présent : retiré');
 assert.equal(secret.s.secrets.has(SECRET_EDGE),false);assert.equal(secret.s.capacite.revoquee,true);assert.equal(secret.s.compte.activation,undefined);
 assert.equal(secret.recu.revocation.secret,'absent');assert.equal(secret.recu.status,'echec');assert.equal(codeSortie(secret.recu),1);
 // POST /secrets jamais arrivé : rien à retirer, jamais réécrit.
 const jamais=await lancer({reponse:(url,req)=>url===`${API}/secrets`&&req.method==='POST'?'transport':undefined});
 assert.equal(jamais.recu.secretEcritureTentee,true);assert.equal(jamais.s.secretsEcrits.length,0);
 assert.equal(jamais.s.appels.filter(a=>a.url===`${API}/secrets`&&a.methode==='POST').length,1);assert.equal(jamais.s.suppressions,0);
 assert.equal(jamais.recu.revocation.secret,'absent');assert.equal(jamais.s.capacite.revoquee,true);assert.equal(jamais.recu.status,'echec');
 // Activation appliquée, réponse perdue : aucune seconde activation, ligne révoquée, secret retiré.
 const activation=await lancer({perdre:{activation:()=>true}});
 assert.equal(activation.recu.code,'TRANSPORT_INCERTAIN');assert.equal(activation.recu.activationTentee,true);
 assert.equal(activation.recu.activationConfirmee,false);assert.equal(activation.s.compte.activation,1,'aucune seconde activation');
 assert.equal(activation.s.capacite.revoquee,true);assert.equal(activation.s.secrets.has(SECRET_EDGE),false);
 assert.equal(activation.recu.revocation.confirmee,true);assert.equal(activation.recu.status,'echec');
 for(const x of [secret,jamais,activation])sansSecret(x.recu);
});

test('l’aperçu annulé exerce aussi la révocation sous le trigger du supplément, avant toute écriture réelle',async()=>{
 const p={capaciteId:CAPACITE,runId:RUN,sourceSha:SHA,manifestSha256:'a'.repeat(64),dureeMinutes:45,contratId:CONTRAT,
  missionId:MISSION,soignantId:SOIGNANT,etablissementId:ETAB,documentSha256:DOC,telephoneSoignant:TEL_S,telephoneEtablissement:TEL_E,
  twilioAccountSid:SID,expediteur:EXPEDITEUR};
 const apercu=sqlAllocation(p,{apercu:true}),corps=corpsRevocation(RUN);
 assert.ok(sqlRevocation({runId:RUN}).includes(corps),'même texte que le mode revoquer');
 const i=apercu.indexOf(corps);
 assert.ok(i>apercu.indexOf('PERFORM private.fn_signature_sms_test_scope'),'après l’activation et la portée');
 assert.ok(i<apercu.lastIndexOf("SELECT jsonb_build_object('capacite'"),'avant la preuve');assert.ok(apercu.endsWith('ROLLBACK;'));
 assert.equal(sqlAllocation(p,{apercu:false}).includes(corps),false);assert.equal(sqlActivation(p).includes(corps),false);
 // Preuve attendue : ligne fermée et révoquée, aucune capacité active ; sinon arrêt avant l'insertion réelle.
 const ok=await lancer();assert.equal(ok.recu.status,'active');assert.equal(ok.s.compte.apercu,1);
 const sans=await lancer({apercuSansRevocation:true});
 assert.equal(sans.recu.code,'CAPACITE_NON_CONFIRMEE');assert.deepEqual(ecritures(sans.s),[]);assert.equal(sans.recu.insertionTentee,false);
 for(const code of ['SIGNATURE_SMS_TEST_IMMUTABLE','SMS_CAPACITE_REVOCATION_REFUSEE']){
  const refus=await lancer({erreurSql:{apercu:()=>erreurSql(`P0001: ${code}`)}});
  assert.equal(refus.recu.sqlCode,code);assert.deepEqual(ecritures(refus.s),[]);assert.equal(refus.recu.revocation,null);
 }
});

test('les sources send-sms et le contrat d’installation sont lus dans le commit HEAD : un arbre de travail modifié n’empêche rien',async()=>{
 const racine=mkdtempSync(join(tmpdir(),'sms-capacite-'));
 const g=(...args)=>execFileSync('git',['-C',racine,'-c','user.name=Recette','-c','user.email=recette@exemple.invalid','-c','commit.gpgsign=false',...args],
  {encoding:'utf8',env:{PATH:process.env.PATH,GIT_CONFIG_GLOBAL:'/dev/null',GIT_CONFIG_NOSYSTEM:'1',LC_ALL:'C'}});
 const source='supabase/functions/send-sms/index.ts';
 try{
  g('init','-q');
  mkdirSync(join(racine,'supabase/functions/send-sms'),{recursive:true});mkdirSync(join(racine,'scripts/ci'),{recursive:true});
  writeFileSync(join(racine,source),'// commité\n');writeFileSync(join(racine,CONTRAT_INSTALLATION),'{"commite":true}\n');
  symlinkSync('index.ts',join(racine,'supabase/functions/send-sms/lien.ts'));
  g('add','-A');g('commit','-q','-m','init');
  writeFileSync(join(racine,source),'// modifié dans l’arbre de travail\n');
  writeFileSync(join(racine,'supabase/functions/send-sms/nouveau.ts'),'// non suivi\n');
  writeFileSync(join(racine,CONTRAT_INSTALLATION),'{"modifie":true}\n');
  const local=lireLocal(racine);
  assert.equal(local.sha,g('rev-parse','HEAD').trim());assert.equal(Object.hasOwn(local,'clean'),false,'aucune exigence de propreté');
  assert.equal(local.lireFichier(source),'// commité\n');assert.equal(local.lireBlob(CONTRAT_INSTALLATION),'{"commite":true}\n');
  for(const [lecteur,chemin] of [['lireFichier','supabase/functions/send-sms/nouveau.ts'],['lireFichier','supabase/functions/send-sms/lien.ts'],
   ['lireFichier','supabase/functions/send-sms/../send-sms/index.ts'],['lireFichier',`./${source}`],['lireFichier','supabase/functions/send-sms/index.js'],
   ['lireFichier',CONTRAT_INSTALLATION],['lireBlob','scripts/ci/autre.json'],['lireBlob','supabase/functions//send-sms/index.ts']])
   assert.throws(()=>local[lecteur](chemin),e=>e instanceof Refus&&e.code==='SOURCES_LOCALES_REFUSEES',`${lecteur} ${chemin}`);
 }finally{rmSync(racine,{recursive:true,force:true});}
 // Allouer et attendre acceptent un arbre de travail modifié (HEAD égal à GITHUB_SHA reste exigé).
 const sale=await lancer({},ENV,{...LOCAL,clean:false});assert.equal(sale.recu.status,'active');
 const {r}=await attendreAvec(sale,sale.recu,ENV_LECTURE,{...LOCAL,clean:false});assert.equal(r.status,'succes');
 // main qui avance entre la provenance et l'insertion : refus avant toute écriture.
 const deplace=await lancer({main:s=>s.appels.filter(a=>a.url===`${GH}/git/ref/heads/main`).length>1?'6'.repeat(40):SHA});
 assert.equal(deplace.recu.code,'MAIN_DEPLACE');assert.deepEqual(ecritures(deplace.s),[]);assert.equal(deplace.recu.insertionTentee,false);
});

test('mode opératoire : exclusivité réelle des campagnes, approbation immédiate, gel des merges, écarts au blueprint',()=>{
 const doc=lire('docs/recettes/2026-11-02-capacite-sms-signature-staging.md'),wf=lire(WORKFLOW);
 assert.doesNotMatch(doc,/les autres campagnes STAGING refusent de\s+s'ouvrir/);
 // Seuls ces lecteurs refusent pendant une séance ; Connect et Invoice ignorent le secret (exclusivité tenue par l'opératrice).
 for(const f of ['supabase/functions/_shared/honoraires-staging-test.ts','supabase/functions/_shared/invoice-email-staging-test.ts',
  'scripts/ci/invoice-emails-staging-test.mjs']){assert.ok(lire(f).includes(SECRET_EDGE),f);assert.ok(doc.includes(f.split('/').at(-1)),f);}
 for(const f of ['supabase/functions/_shared/stripe-connect-staging-test.ts','supabase/functions/_shared/stripe-invoice-staging-test.ts']){
  assert.equal(lire(f).includes(SECRET_EDGE),false,`${f} : mettre à jour le mode opératoire si la garde est ajoutée`);
  assert.ok(doc.includes(f.split('/').at(-1)),f);
 }
 assert.match(doc,/approuver ou rejeter immédiatement/);assert.match(wf,/approuver ou rejeter immédiatement/);
 assert.match(doc,/gel des merges/);
 for(const ecart of ['S1-E1','S1-E2'])assert.ok(doc.includes(ecart),ecart);
 assert.ok(doc.includes('docs/mobile-swift/DECISIONS_LOT2.md'));
});

test('une autre capacité active est comptée sans être touchée',async()=>{
 const autre=await seance({autresActives:1});
 assert.equal(autre.revocation.status,'succes');assert.equal(autre.revocation.revocation.autresCapacitesActives,1);
 assert.equal(autre.s.compte.revocation,1);
});

test('révoquer : capacité de CE run retrouvée par run_id, secret retiré seulement s’il vient de ce run',async()=>{
 // Reçu perdu (artefact absent) après une allocation réussie : la ligne du run est retrouvée, le secret est le sien.
 const sansRecu=await lancer();
 const r1=await revoquerAvec(sansRecu,null);
 assert.equal(r1.status,'succes');assert.equal(r1.recuUtilise,false);assert.equal(r1.revocation.capacite,'revoquee');
 assert.equal(r1.revocation.secret,'absent');assert.equal(sansRecu.s.capacite.revoquee,true);assert.equal(sansRecu.s.secrets.has(SECRET_EDGE),false);
 assert.equal(r1.capaciteId,CAPACITE);assert.equal(r1.contratId,CONTRAT);
 // Allocation refusée car une autre séance (hors verrou) détient le secret : il n'est jamais retiré.
 const occupe=await lancer({secrets:{[SECRET_EDGE]:'{"autre":1}',TWILIO_ACCOUNT_SID:SID,TWILIO_AUTH_TOKEN:'x',TWILIO_FROM_NUMBER:EXPEDITEUR}});
 assert.equal(occupe.recu.code,'CAPACITE_EDGE_DEJA_OUVERTE');
 const r2=await revoquerAvec(occupe,occupe.recu);
 assert.equal(r2.status,'succes');assert.equal(r2.revocation.capacite,'absente');assert.equal(r2.revocation.secret,'non_touche');
 assert.equal(occupe.s.secrets.get(SECRET_EDGE),'{"autre":1}');assert.equal(occupe.s.suppressions,0);
 // Sans reçu ni ligne de ce run : rien n'est touché.
 const vide=harnais();vide.s.secrets.set(SECRET_EDGE,'{"autre":1}');
 const r3=await revoquerAvec(vide,null);
 assert.equal(r3.status,'succes');assert.deepEqual(vide.s.etapes,['revocation']);assert.equal(vide.s.secrets.has(SECRET_EDGE),true);
 assert.equal(r3.revocation.secret,'non_touche');
 // Reçu illisible : même ciblage par run_id, statut incertain pour relecture humaine.
 const illisible=await lancer();
 const r4=await revoquerAvec(illisible,null,{illisible:true});
 assert.equal(r4.status,'incertain');assert.equal(r4.code,'RECU_ILLISIBLE');assert.equal(illisible.s.capacite.revoquee,true);
 assert.equal(illisible.s.secrets.has(SECRET_EDGE),false);
 // Reçu d'un autre run ou d'un autre projet : refus avant le réseau.
 const base=await lancer();
 for(const recu of [{...base.recu,projectRef:PRODUCTION},{...base.recu,capaciteId:"x'"},{...base.recu,mode:'revoquer'},{...base.recu,runId:'sms-signature-gh-1-1'}]){
  const x=harnais();const refus=await revoquerAvec(x,recu);
  assert.equal(refus.code,'RECU_REFUSE');assert.equal(x.s.appels.length,0);
 }
 // Un arbre de travail modifié n'empêche jamais de refermer (sources lues dans HEAD).
 const sale=await revoquerAvec(base,base.recu,{},ENV_LECTURE,{...LOCAL,clean:false});
 assert.equal(sale.status,'succes');assert.equal(base.s.capacite.revoquee,true);
 for(const r of [r1,r2,r3,r4,sale])sansSecret(r);
});

test('codes de sortie : seuls « active » (allouer) et « succes » (attendre, revoquer) sortent en 0',()=>{
 assert.equal(codeSortie({mode:'allouer',status:'active'}),0);
 assert.equal(codeSortie({mode:'attendre',status:'succes'}),0);assert.equal(codeSortie({mode:'revoquer',status:'succes'}),0);
 for(const r of [{mode:'allouer',status:'succes'},{mode:'allouer',status:'echec'},{mode:'allouer',status:'incertain'},
  {mode:'attendre',status:'termine_sans_preuve'},{mode:'attendre',status:'active'},{mode:'revoquer',status:'incertain'},{mode:null,status:'succes'},null])
  assert.equal(codeSortie(r),1,JSON.stringify(r));
});

test('le workflow S1 : allocation et révocation sous le verrou STAGING, attente hors verrou, révocation sans approbation',()=>{
 const wf=lire(WORKFLOW);
 assert.match(wf,/^on:\n  workflow_dispatch:\n/m);
 assert.doesNotMatch(wf,/^\s*(pull_request|pull_request_target|push|schedule|workflow_run|workflow_call|repository_dispatch):/m);
 assert.match(wf,/^permissions:\n  contents: read\n\n/m);
 assert.doesNotMatch(wf,/^concurrency:/m,'aucun verrou au niveau du workflow');
 assert.match(wf,/^  SUPABASE_PROJECT_REF: mejpriaetwgtcstbgfid$/m);
 const debut=n=>wf.indexOf(`\n  ${n}:\n`);
 const [ja,jt,jr]=['allouer','attendre','revoquer'].map(debut);
 assert.ok(ja>0&&ja<jt&&jt<jr,'trois jobs dans l’ordre');
 const allouer=wf.slice(ja,jt),attendre=wf.slice(jt,jr),revoquer=wf.slice(jr);
 const verrou=/\n    concurrency:\n      group: jolene-supabase-staging-writes\n      queue: max\n      cancel-in-progress: false\n/;
 assert.match(allouer,verrou);assert.match(revoquer,verrou);assert.doesNotMatch(attendre,/concurrency:/);
 assert.match(allouer,/\n    if: github\.ref == 'refs\/heads\/main'\n/);
 assert.match(allouer,/\n    environment: staging-sms-signature\n/);
 assert.doesNotMatch(attendre+revoquer,/environment:/,'attente et révocation sans approbation supplémentaire');
 assert.match(attendre,/\n    needs: allouer\n    if: needs\.allouer\.result == 'success'\n/);
 assert.match(revoquer,/\n    needs: \[allouer, attendre\]\n    if: always\(\) && needs\.allouer\.result == 'success'\n/);
 // Chaque job refuse un contexte autre que main exact avant le checkout.
 for(const job of [allouer,attendre,revoquer]){
  const contexte=job.indexOf('EXACT_TRUSTED_MAIN_REQUIRED'),checkout=job.indexOf('uses: actions/checkout@');
  assert.ok(contexte>0&&contexte<checkout);
 }
 // Allocation : tests avant credentials, révocation immédiate si l'allocation échoue ou est annulée.
 const testsA=allouer.indexOf('run: node --test tests/node/allouer-capacite-sms-signature-staging.node.mjs');
 const runA=allouer.indexOf(`run: node ${SCRIPT} allouer`),revA=allouer.indexOf(`run: node ${SCRIPT} revoquer`);
 assert.ok(testsA>0&&testsA<runA&&runA<revA);
 assert.equal(allouer.slice(0,testsA).includes('secrets.'),false,'aucun secret avant les tests');
 assert.match(allouer.slice(allouer.lastIndexOf('- name:',revA),revA),/if: \(failure\(\) \|\| cancelled\(\)\) && steps\.contexte\.outcome == 'success'/);
 assert.ok(attendre.includes(`run: node ${SCRIPT} attendre`)&&revoquer.includes(`run: node ${SCRIPT} revoquer`));
 // Téléphones et Twilio : dans le seul job d'allocation (environnement protégé).
 const secrets=t=>[...t.matchAll(/\$\{\{ secrets\.([A-Z_]+) \}\}/g)].map(m=>m[1]);
 assert.deepEqual(secrets(allouer).sort(),['SMS_RECETTE_TELEPHONE_ETABLISSEMENT','SMS_RECETTE_TELEPHONE_SOIGNANT','SMS_RECETTE_TWILIO_ACCOUNT_SID',
  'SMS_RECETTE_TWILIO_EXPEDITEUR','STAGING_SUPABASE_ACCESS_TOKEN','STAGING_SUPABASE_ACCESS_TOKEN'].sort());
 assert.deepEqual(secrets(attendre),['STAGING_SUPABASE_ACCESS_TOKEN']);assert.deepEqual(secrets(revoquer),['STAGING_SUPABASE_ACCESS_TOKEN']);
 assert.doesNotMatch(wf,/run:[^\n]*secrets\./);
 // Le reçu d'allocation passe d'un job à l'autre par artefact ; sans lui, la révocation retrouve la ligne par run_id.
 assert.match(allouer,/uses: actions\/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02/);
 for(const job of [attendre,revoquer])assert.match(job,/uses: actions\/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093/);
 assert.match(revoquer.slice(revoquer.indexOf('download-artifact')-200,revoquer.indexOf('download-artifact')),/continue-on-error: true/);
 // Bornes : allocation courte, attente au-delà de 60 min, révocation brève.
 const minutes=t=>[...t.matchAll(/timeout-minutes: ([0-9]+)/g)].map(m=>Number(m[1]));
 assert.ok(minutes(allouer)[0]<=20&&minutes(attendre)[0]>=65&&minutes(revoquer)[0]<=15,JSON.stringify([minutes(allouer),minutes(attendre),minutes(revoquer)]));
 // La révocation (fermeture, sonde, relecture finale) dispose d'au moins 12 min, le repli de l'allocation d'au moins 8.
 assert.ok(minutes(revoquer)[1]>=12&&minutes(revoquer)[1]<minutes(revoquer)[0],JSON.stringify(minutes(revoquer)));
 assert.ok(minutes(allouer).at(-1)>=8,JSON.stringify(minutes(allouer)));
 assert.match(wf,/if-no-files-found: ignore/);
});

test('aucun littéral de secret, de téléphone ou de projet de production dans l’allocateur, son workflow et son mode opératoire',()=>{
 for(const chemin of [SCRIPT,WORKFLOW,'docs/recettes/2026-11-02-capacite-sms-signature-staging.md']){
  const texte=lire(chemin);
  assert.equal(texte.includes(PRODUCTION),false,chemin);
  for(const motif of [/AC[0-9a-fA-F]{32}/,/\+[1-9][0-9]{7,}/,/eyJ[A-Za-z0-9_-]{10,}/,/sb_(?:secret|publishable)_[A-Za-z0-9]/,/sk_(?:live|test)_/])
   assert.doesNotMatch(texte,motif,`${chemin} ${motif}`);
 }
});
