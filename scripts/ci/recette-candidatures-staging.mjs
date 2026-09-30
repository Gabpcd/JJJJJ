import { mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { demarrerPreview } from './dashboard-ui-preview.mjs';
import { preparerHtmlPreview } from './recette-dashboard-staging.mjs';
import { executerD } from './prepare-candidatures-fixture.mjs';
import { utilisateurDValide, validerEtatD } from './candidatures-fixture-contract.mjs';
import { sqlCompterD } from './candidatures-fixture-sql.mjs';
import { ORIGINE_UI, STAGING_REF, STAGING_URL, configurationFrontendD, identitesFrontendD, requeteFrontendD, budgetEcrituresD,
  sqlAuditsFrontendD, projectionAuditsD, verifierAuditsD, rpcEcritureD, rpcLectureD, rpcParametresD, tablesLectureD } from './candidatures-ui-contract.mjs';

const dossier = resolve('tests/load/results/d2-frontend');
const sauver = (nom, value) => { mkdirSync(dossier,{recursive:true}); writeFileSync(`${dossier}/${nom}.json`, JSON.stringify(value,null,2)+'\n',{mode:0o600}); };
export function projeterErreurNavigateurD({source,texte,classe,location,stack,contexteFerme=false},assetsConnus=new Set()) {
  const message=typeof texte==='string'?texte:'';
  // WebKit/Playwright place parfois tout le préfixe précédant le premier
  // deux-points (y compris le début d'une URL) dans name. Ne jamais l'exporter.
  const nom=typeof classe==='string'?classe:'',cause=nom?`${nom}: ${message}`:message;
  const classes=new Set(['Error','TypeError','ReferenceError','SyntaxError','RangeError','URIError','EvalError','AbortError','NetworkError','TimeoutError','AssertionError']);
  const typeNom=classes.has(nom)?'classe_connue':!nom?'absent':/^(?:Fetch API cannot load|XMLHttpRequest cannot load|WebSocket connection to|Failed to load resource|Unhandled Promise Rejection|Origin\s)/i.test(nom)?'prefixe_webkit':'autre';
  const react=cause.match(/Minified React error #(\d{1,4})\b/);
  const categorie=contexteFerme||/Target (?:page, context or browser|closed)|context (?:has been )?closed/i.test(cause)?'contexte_ferme'
    :/WebSocket/i.test(cause)?'websocket'
    :/\babort(?:ed|error)?\b|cancelled|canceled/i.test(cause)?'requete_abandonnee'
    :/navigation[\s\S]*interrupted[\s\S]*navigation/i.test(cause)?'navigation_interrompue'
    :/access control|Access-Control-Allow-Origin|cross-origin|\bCORS\b/i.test(cause)?'controle_origine'
    :/Load failed|Failed to fetch|Failed to load resource|NetworkError|Network request failed|Fetch API cannot load|XMLHttpRequest cannot load/i.test(cause)?'chargement_reseau'
    :react?'react_minifie':/strict mode violation/i.test(cause)?'strict_mode':/\btimeout\b|timed out/i.test(cause)?'delai_attente':/^expect\(/.test(message)?'assertion':'autre';
  const candidates=location?[location]:[];
  if(typeof stack==='string')for(const url of stack.match(/https?:\/\/[^\s)]+/g)||[]){
    const match=url.match(/^(.*):(\d+):(\d+)$/);if(match)candidates.push({url:match[1],lineNumber:Number(match[2]),columnNumber:Number(match[3])});
  }
  let emplacement=null;
  for(const l of candidates){
    try{const u=new URL(l.url);if(u.origin!==ORIGINE_UI||u.username||u.password||!assetsConnus.has(u.pathname))continue;
      const entier=v=>Number.isSafeInteger(v)&&v>=0&&v<=10_000_000?v:null;
      emplacement={asset:u.pathname,ligne:entier(l.lineNumber),colonne:entier(l.columnNumber)};break;
    }catch{/* Aucun chemin ou texte libre n'est conservé. */}
  }
  return {source:['pageerror','exception_finale'].includes(source)?source:'console_error',classe:classes.has(nom)?nom:'autre',typeNom,
    categorie,code:react?Number(react[1]):null,emplacement,empreinte:createHash('sha256').update(message).digest('hex'),empreinteNom:createHash('sha256').update(nom).digest('hex')};
}
export function observerErreursNavigateurD(context,slot,diagnostic,assetsConnus=new Set()) {
  context.on('page',page=>{
    page.on('pageerror',error=>diagnostic.erreurNavigateur(slot,projeterErreurNavigateurD({source:'pageerror',texte:error.message,classe:error.name,stack:error.stack,contexteFerme:page.isClosed()},assetsConnus)));
    page.on('console',message=>{if(message.type()==='error')diagnostic.erreurNavigateur(slot,projeterErreurNavigateurD({source:'console_error',texte:message.text(),location:message.location(),contexteFerme:page.isClosed()},assetsConnus));});
  });
}
export function diagnosticD({temps=()=>performance.now()}={}) {
  const origine=temps();let dernierTemps=0;
  const relatif=()=>{const valeur=temps()-origine;if(Number.isFinite(valeur))dernierTemps=Math.max(dernierTemps,Math.min(1_800_000,Math.max(0,Math.floor(valeur))));return dernierTemps;};
  const principal={phase:'preflight',slot:null,action:null,actionDepuisMs:0},contextes=new Map();let erreurFinale=null,erreurs=0,erreursNavigateurTronquees=0; const reseau=new Map(),erreursNavigateur=new Map();
  const noms=new Set([...rpcEcritureD,...rpcLectureD,...rpcParametresD,...tablesLectureD]);
  const actions=new Set(['preview_html','preview_assets','preview_demarrer','navigateur_lancer','contexte_creer','reseau_installer','page_creer',
    'connexion_navigation','connexion_email','connexion_motdepasse','connexion_envoyer','connexion_url','connexion_audit','connexion_reseau','connexion_drain',
    'mission_navigation','mission_titre','candidature_message','candidature_bouton_actif','candidature_ouvrir_dialogue','candidature_dialogue_visible','candidature_debut','candidature_fin',
    'candidature_envoyer','candidature_dialogue_ferme','candidature_attente','candidature_rappel','candidature_documents','candidature_reseau','candidature_capture',
    'recharge_navigation','recharge_attente','recharge_bouton_absent','recharge_reseau','recharge_capture',
    'etablissement_navigation','etablissement_compteur','etablissement_attente','etablissement_nom_visible','etablissement_nom_exact','etablissement_documents','etablissement_boutons','etablissement_reseau','etablissement_capture',
    'contexte_drain','contexte_budget','contexte_fermer','identites','catalogue','audits_avant','backend_verifier','backend_correlation','audits_apres']);
  const facade=etat=>({ phase(p,s=etat===principal?null:etat.slot) { if(!['preflight','preview','browser','login','mission','postuler','reload','etablissement','backend','cleanup'].includes(p)||![null,0,1,2].includes(s)||(etat!==principal&&s!==etat.slot))throw Error('Phase D2 invalide.');etat.phase=p;etat.slot=s;etat.action=null;etat.actionDepuisMs=relatif(); },
    action(n) { if(!actions.has(n))throw Error('Action D2 inconnue.');etat.action=n;etat.actionDepuisMs=relatif(); },
    exceptionFinale(error) { erreurFinale??={...etat,tempsMs:relatif(),...projeterErreurNavigateurD({source:'exception_finale',texte:error?.message,classe:error?.name})}; },
    erreur() { erreurs++; }, erreurNavigateur(slotEmetteur,projection) {
      erreurs++;const r={phase:etat.phase,action:etat.action,slotPhase:etat.slot,slotEmetteur,...projection},k=JSON.stringify(r);
      const precedent=erreursNavigateur.get(k),ms=relatif();
      if(erreursNavigateur.size<32||precedent)erreursNavigateur.set(k,{...r,nombre:(precedent?.nombre||0)+1,actionDepuisMs:etat.actionDepuisMs,premierMs:precedent?.premierMs??ms,dernierMs:ms});else erreursNavigateurTronquees++;
    }, reseau(url,method,status,missionId) {
      let origine='invalide',chemin='autre',requeteMission;
      try { const u=new URL(url);origine=u.origin===ORIGINE_UI?'preview':u.origin===STAGING_URL?'staging':'externe';
        const nom=u.pathname.split('/').pop();chemin=origine==='preview'?'local':origine!=='staging'?'externe':noms.has(nom)?nom:['/auth/v1/token','/auth/v1/user'].includes(u.pathname)?`auth-${nom}`:'autre';
        if(origine==='staging'&&u.pathname==='/rest/v1/missions'&&status==='refus') {
          const cles=[...u.searchParams.keys()],connues=new Set(['select','id','etablissement_id','soignant_assigne_id','or','and','order','limit','offset']);
          const id=u.searchParams.getAll('id'),select=u.searchParams.getAll('select');
          requeteMission={projection:select.length===1&&select[0]==='id,nb_creneaux'?'id_nb_creneaux':'autre',
            selecteur:typeof missionId==='string'&&id.length===1?(id[0]===`eq.${missionId}`?'eq_manifeste':id[0]===`in.(${missionId})`?'in_manifeste':'autre'):'autre',
            parametresUniques:new Set(cles).size===cles.length,cles:[...new Set(cles.map(c=>connues.has(c)?c:'autre'))].sort()};
        }
      }catch{/* Projection fermée. */}
      const r={phase:etat.phase,slot:etat.slot,origine,chemin,methode:['GET','HEAD','POST','OPTIONS','PATCH','PUT','DELETE'].includes(method)?method:'autre',statut:Number.isInteger(status)&&status>=100&&status<=599?status:['refus','transport','ferme'].includes(status)?status:'autre',...(requeteMission?{requeteMission}:{})};
      const k=JSON.stringify(r),precedent=reseau.get(k),ms=relatif(); if(reseau.size<128||precedent)reseau.set(k,{...r,nombre:(precedent?.nombre||0)+1,premierMs:precedent?.premierMs??ms,dernierMs:ms});else erreurs++;
    }, resultat() { return {...principal,contextes:[...contextes.values()].map(e=>({...e})),tempsMs:relatif(),erreurFinale,erreurs,erreursNavigateur:[...erreursNavigateur.values()].map(r=>({...r})),erreursNavigateurTronquees,reseau:[...reseau.values()].map(r=>({...r}))}; }, pourSlot(slot) { if(![0,1,2].includes(slot))throw Error('Slot D2 invalide.');if(!contextes.has(slot))contextes.set(slot,{phase:'browser',slot,action:null,actionDepuisMs:relatif()});return facade(contextes.get(slot)); } });
  return facade(principal);
}
export async function lireBackendD(query, env, fetchImpl=fetch) {
  if(env.STAGING_SUPABASE_PROJECT_REF!==STAGING_REF||env.STAGING_SUPABASE_URL!==STAGING_URL||!env.STAGING_SUPABASE_ACCESS_TOKEN)throw Error('Lecture D2 staging refusée.');
  let response;try {response=await fetchImpl(`https://api.supabase.com/v1/projects/${STAGING_REF}/database/query`,{
    method:'POST',redirect:'error',signal:AbortSignal.timeout(35000),headers:{Authorization:`Bearer ${env.STAGING_SUPABASE_ACCESS_TOKEN}`,'Content-Type':'application/json'},body:JSON.stringify({query})});}catch{throw Error('Lecture D2 ambiguë sans réessai.');}
  if(!response.ok)throw Error('Lecture D2 refusée.');
  try{return await response.json();}catch{throw Error('Lecture D2 JSON invalide.');}
}
const heureParis = value => new Intl.DateTimeFormat('fr-FR',{timeZone:'Europe/Paris',hour:'2-digit',minute:'2-digit',hour12:false}).format(new Date(value)).replace(':','h');
export async function preparerCandidatureD(page,m,{expect,phase=etape=>{void etape;},action=etape=>{void etape;}}) {
  // Le lien n'existe qu'après le chargement complet du planning dashboard.
  // La navigation React préserve les lectures en cours du document connecté.
  phase('mission');action('mission_navigation');await page.getByRole('link',{name:`Voir la mission ${m.marker}`,exact:true}).click();
  action('mission_titre');await expect(page.getByRole('heading',{level:1,name:m.marker,exact:true})).toBeVisible();
  action('candidature_message');await page.getByPlaceholder('Présente-toi brièvement…').fill(m.marker);
  action('candidature_bouton_actif');await expect(page.getByRole('button',{name:/Vérifier et postuler/})).toBeEnabled();
  action('candidature_ouvrir_dialogue');await page.getByRole('button',{name:/Vérifier et postuler/}).click();
  const dialogue=page.getByRole('dialog',{name:'Vérifie ton engagement'});
  action('candidature_dialogue_visible');await expect(dialogue).toBeVisible();
  action('candidature_debut');await expect(dialogue).toContainText(heureParis(m.debut));
  action('candidature_fin');await expect(dialogue).toContainText(heureParis(m.fin));
}
export async function envoyerCandidatureD(page,{expect,phase=etape=>{void etape;},action=etape=>{void etape;}}) {
  const dialogue=page.getByRole('dialog',{name:'Vérifie ton engagement'});
  phase('postuler');action('candidature_envoyer');await dialogue.getByRole('button',{name:'Envoyer ma candidature',exact:true}).click();
  action('candidature_dialogue_ferme');await expect(dialogue).toBeHidden();
  action('candidature_attente');await expect(page.getByText('✅ Candidature envoyée — En attente de réponse',{exact:true})).toBeVisible();
  action('candidature_rappel');await expect(page.getByText('Candidature envoyée ! Valide tes documents pour pouvoir être accepté.',{exact:true})).toBeVisible();
  action('candidature_documents');await expect(page.getByRole('button',{name:'Mes documents',exact:true})).toBeVisible();
}
export async function rechargerCandidatureD(page,{expect,capturer=async etape=>{void etape;},phase=etape=>{void etape;},action=etape=>{void etape;}}) {
  action('candidature_reseau');await page.waitForLoadState('networkidle');action('candidature_capture');await capturer('candidature');
  phase('reload');action('recharge_navigation');await page.reload();
  action('recharge_attente');await expect(page.getByText('✅ Candidature envoyée — En attente de réponse',{exact:true})).toBeVisible();
  action('recharge_bouton_absent');await expect(page.getByRole('button',{name:/Vérifier et postuler/})).toBeHidden();
  action('recharge_reseau');await page.waitForLoadState('networkidle');action('recharge_capture');await capturer('recharge');
}
/** Une barrière AVANT transport ; aucune réponse n'est retardée pour fabriquer un chevauchement. */
export function concurrenceCandidaturesD({temps=()=>performance.now(),delaiMs=20000}={}) {
  if(!Number.isFinite(delaiMs)||delaiMs<=0||delaiMs>20000)throw Error('Délai D2 invalide.');
  const origine=temps(),attentes=new Map(),mesures=new Map();let minuterie,annule=false;
  const relatif=()=>{const n=Math.floor(temps()-origine);if(!Number.isSafeInteger(n)||n<0||n>1_800_000)throw Error('Horloge D2 invalide.');return n;};
  const annuler=()=>{annule=true;clearTimeout(minuterie);for(const a of attentes.values())a.reject(Error('Barrière D2 interrompue.'));};
  return {annuler,async transporter(slot,transport) {
    if(annule||![0,1].includes(slot)||attentes.has(slot))throw Error('Participation D2 refusée.');
    await new Promise((resolve,reject)=>{
      attentes.set(slot,{resolve,reject});
      if(attentes.size===2){clearTimeout(minuterie);for(const a of attentes.values())a.resolve();}
      else minuterie=setTimeout(annuler,delaiMs);
    });
    if(annule)throw Error('Barrière D2 interrompue.');
    const mesure={slot,debutMs:relatif(),receptionMs:null};mesures.set(slot,mesure);
    try{const response=await transport();mesure.receptionMs=relatif();return response;}
    catch(error){annuler();throw error;}
  },verifier() {
    if(annule)throw Error('Chevauchement HTTP D2 non confirmé.');
    return verifierConcurrenceD([...mesures.values()].sort((a,b)=>a.slot-b.slot));
  }};
}
export function verifierConcurrenceD(slots) {
  if(!Array.isArray(slots)||slots.length!==2||slots.some((r,i)=>r?.slot!==i||
    Object.keys(r).sort().join(',')!=='debutMs,receptionMs,slot'||
    ![r.debutMs,r.receptionMs].every(n=>Number.isSafeInteger(n)&&n>=0&&n<=1_800_000)||r.receptionMs<=r.debutMs))throw Error('Mesures HTTP D2 incomplètes.');
  const chevauchementMs=Math.min(...slots.map(r=>r.receptionMs))-Math.max(...slots.map(r=>r.debutMs));
  if(chevauchementMs<=0)throw Error('Chevauchement HTTP D2 non confirmé.');
  return {slots:slots.map(r=>({...r})),chevauchementMs};
}
export async function envoyerCandidaturesConcurrentesD(participants,concurrence) {
  if(participants.length!==2||participants.some((p,i)=>p.slot!==i))throw Error('Deux interfaces D2 distinctes requises.');
  // Une erreur ne rend jamais la main pendant que l'autre interface travaille.
  const issues=await Promise.allSettled(participants.map(async p=>{
    try{await envoyerCandidatureD(p.page,p.options);}
    catch(error){p.options.echec?.(error);concurrence.annuler();throw error;}
  }));
  const echec=issues.find(r=>r.status==='rejected');if(echec)throw echec.reason;
  return concurrence.verifier();
}
export async function deposerCandidatureD(page,m,options) {
  await preparerCandidatureD(page,m,options);await envoyerCandidatureD(page,options);await rechargerCandidatureD(page,options);
}
export async function relireCandidaturesD(page,m,{expect,capturer=async etape=>{void etape;},phase=etape=>{void etape;},action=etape=>{void etape;}}) {
  // Le dashboard déclenche encore ses cartes après l'audit : suivre son bouton
  // React conserve leurs lectures, sans interrompre le document connecté.
  phase('etablissement');action('etablissement_navigation');
  const carte=page.locator('.card-base').filter({has:page.getByRole('heading',{level:3,name:m.marker,exact:true})});
  await expect(carte).toHaveCount(1);await carte.getByRole('button',{name:'Voir détail',exact:true}).click();
  for(const recharge of [false,true]) {
    if(recharge){phase('reload');action('recharge_navigation');await page.reload();}
    action('etablissement_compteur');await expect(page.getByRole('heading',{name:'Candidatures (2)',exact:true})).toBeVisible();
    action('etablissement_attente');await expect(page.getByText('En attente (2)',{exact:true})).toBeVisible();
    for(const a of m.membres.slice(0,2)) {
      // Candidature seule, sans affectation : le RPC masque le nom de famille.
      const nomAffiche=`${a.prenom} ${Array.from(a.nom)[0]||''}.`;
      const nom=page.locator('p').filter({hasText:new RegExp(`👤\\s+${RegExp.escape(nomAffiche)}`)});
      action('etablissement_nom_visible');await expect(nom).toBeVisible();
      // Les badges sont des enfants du même paragraphe : comparer exactement
      // ses nœuds texte propres, sans inclure profession/statut documentaire.
      action('etablissement_nom_exact');const texte=await nom.evaluate(element=>Array.from(element.childNodes).filter(n=>n.nodeType===Node.TEXT_NODE).map(n=>n.textContent).join('').replace(/\s+/g,' ').trim());
      expect(texte).toBe(`👤 ${nomAffiche}`);
    }
    action('etablissement_documents');await expect(page.getByText('📄 Documents en vérification',{exact:true})).toHaveCount(2);
    action('etablissement_boutons');await expect(page.getByRole('button',{name:'Accepter cette candidature',exact:true})).toHaveCount(2);
    action('etablissement_reseau');await page.waitForLoadState('networkidle');action('etablissement_capture');await capturer(recharge?'recharge':'candidatures');
  }
}
export function verifierReponseFrontendD({path,data},a,m) {
  if(path==='/auth/v1/token' && (typeof data?.access_token!=='string'||!data.access_token||!utilisateurDValide(data.user,m,a.slot)))throw Error('Session UI D2 étrangère.');
  if(path==='/auth/v1/user'&&!utilisateurDValide(data,m,a.slot))throw Error('Utilisateur UI D2 étranger.');
  const rpc=path.split('/').pop();
  if(rpcEcritureD.has(rpc)&&data?.success!==true)throw Error('Écriture UI D2 non confirmée.');
  if(rpc==='fn_confirmer_action_planning_v1'&&(data.error||data.choix_contrat!=='SALARIE'||data.profession_requise!=='AS'||data.docs_a_completer!==true||!/^[a-f0-9-]{36}$/.test(data.candidature_id||'')))throw Error('Réponse candidature D2 incomplète.');
  if(rpc==='fn_mon_profil_soignant_complet'&&data?.id!==a.userId)throw Error('Profil UI D2 étranger.');
  if(rpc==='fn_mon_etablissement_complet'&&data?.id!==m.membres[2].userId)throw Error('Établissement UI D2 étranger.');
}
export async function installerReseauD(context,a,m,diagnostic,{budget=budgetEcrituresD(a),assetsConnus=new Set(),concurrence}={}) {
  const enCours=new Set();const candidatures=[];let ferme=false;
  await context.addInitScript(()=>{
    localStorage.setItem('cookie-consent','refused');
    // Le détail établissement importe stripe-js. Ce banc ne charge pas son SDK
    // externe et toute tentative de paiement provoque une erreur navigateur.
    Object.defineProperty(window,'Stripe',{value:()=>{throw Error('Paiement interdit dans la recette D2.');}});
  });
  await context.routeWebSocket('**/*',socket=>socket.close());
  observerErreursNavigateurD(context,a.slot,diagnostic,assetsConnus);
  await context.route('**/*',async route=>{
    const execution=(async()=>{
      const request=route.request();let body;
      if(ferme){diagnostic.erreur();diagnostic.reseau(request.url(),request.method(),'ferme');await route.abort();return;}
      try{body=request.postData()?request.postDataJSON():undefined;}catch{diagnostic.erreur();diagnostic.reseau(request.url(),request.method(),'refus',m.missionId);await route.abort();return;}
      if(!requeteFrontendD({url:request.url(),method:request.method(),body},a,m)){diagnostic.erreur();diagnostic.reseau(request.url(),request.method(),'refus',m.missionId);await route.abort();return;}
      const u=new URL(request.url());if(u.origin===ORIGINE_UI){await route.continue();return;}
      const rpc=u.pathname.split('/').pop();
      try {
        if(request.method()==='POST'&&(rpcEcritureD.has(rpc)||u.pathname==='/auth/v1/token'))budget.consommer(u.pathname==='/auth/v1/token'?'auth-token':rpc);
        const transporter=()=>route.fetch({maxRedirects:0,maxRetries:0,timeout:25000});
        const response=request.method()==='POST'&&rpc==='fn_confirmer_action_planning_v1'&&concurrence
          ?await concurrence.transporter(a.slot,transporter):await transporter();
        diagnostic.reseau(request.url(),request.method(),response.status());
        if(!response.ok())throw Error('HTTP D2 non confirmé.');
        if(request.method()!=='HEAD'&&request.method()!=='OPTIONS'&&response.status()!==204){
          const data=await response.json();verifierReponseFrontendD({path:u.pathname,data},a,m);
          if(rpc==='fn_confirmer_action_planning_v1')candidatures.push({slot:a.slot,id:data.candidature_id});
        }
        await route.fulfill({response});
      }catch{diagnostic.erreur();diagnostic.reseau(request.url(),request.method(),'transport');await route.abort().catch(()=>{});}
    })();
    enCours.add(execution);try{await execution;}finally{enCours.delete(execution);}
  });
  return {budget,candidatures,fermer(){ferme=true;},async drainer(){while(enCours.size)await Promise.allSettled([...enCours]);},enCours:()=>enCours.size};
}
export async function parcourirFrontendD({m,identites,env,diagnostic,chargerPlaywright=()=>import('@playwright/test'),previewFn=demarrerPreview,lireAssets=()=>new Set(readdirSync(resolve('dist/assets'),{withFileTypes:true}).filter(f=>f.isFile()&&/^[A-Za-z0-9_-]+\.js$/.test(f.name)).map(f=>`/assets/${f.name}`)),preparerBuild=()=>{const index=resolve('dist/index.html');writeFileSync(index,preparerHtmlPreview(readFileSync(index,'utf8')));}}={}) {
  let browser,preview;const contextes=new Set(),reseaux=new Set(),preuves=[],candidatures=[],concurrence=concurrenceCandidaturesD();
  try {
    diagnostic.phase('preview');diagnostic.action('preview_html');preparerBuild();diagnostic.action('preview_assets');const assetsConnus=lireAssets();
    diagnostic.action('preview_demarrer');preview=await previewFn({env,observer:etat=>sauver('preview',etat)});
    const {webkit,devices,expect}=await chargerPlaywright();diagnostic.phase('browser');
    const envNavigateur=Object.fromEntries(['PATH','HOME','TMPDIR','XDG_RUNTIME_DIR','DISPLAY','WAYLAND_DISPLAY'].filter(k=>typeof env[k]==='string').map(k=>[k,env[k]]));
    diagnostic.action('navigateur_lancer');browser=await webkit.launch({env:envNavigateur});
    const ouvrir=async(slot,appareil)=>{
      const a=identites[slot],d=diagnostic.pourSlot(slot);let context;
      try {
        d.action('contexte_creer');context=await browser.newContext({...devices[appareil],baseURL:ORIGINE_UI,locale:'fr-FR',timezoneId:'Europe/Paris',serviceWorkers:'block'});contextes.add(context);
        d.action('reseau_installer');const reseau=await installerReseauD(context,a,m,d,{assetsConnus,concurrence});reseaux.add(reseau);
        d.action('page_creer');const page=await context.newPage();page.setDefaultTimeout(20000);page.setDefaultNavigationTimeout(25000);
        d.phase('login');d.action('connexion_navigation');await page.goto('/connexion');
        d.action('connexion_email');await page.getByLabel('Email',{exact:true}).fill(a.email);d.action('connexion_motdepasse');await page.getByLabel('Mot de passe',{exact:true}).fill(a.password);
        d.action('connexion_envoyer');await page.getByRole('button',{name:'Se connecter',exact:true}).click();
        d.action('connexion_url');await expect(page).toHaveURL(slot<2?/\/soignant\/tableau-de-bord$/:/\/etablissement\/tableau-de-bord$/);
        d.action('connexion_audit');await expect.poll(()=>reseau.budget.projection()[slot<2?'fn_maj_activite_soignant':'fn_ecrire_audit_safe']).toBe(1);
        d.action('connexion_reseau');await page.waitForLoadState('networkidle');d.action('connexion_drain');await reseau.drainer();
        const options={expect,phase:p=>d.phase(p),action:n=>d.action(n),echec:error=>d.exceptionFinale(error),capturer:async etape=>{
          await reseau.drainer();if(diagnostic.resultat().erreurs)throw Error('Anomalie UI D2.');
          await page.locator('main').screenshot({path:`${dossier}/slot-${slot}-${etape}.png`,animations:'disabled'});
        }};
        return {slot,appareil,context,page,reseau,options,d};
      }catch(error){d.exceptionFinale(error);throw error;}
    };
    const terminer=async p=>{
      const {d,reseau,context}=p;
      d.action('contexte_drain');reseau.fermer();await reseau.drainer();d.action('contexte_budget');
      if(!reseau.budget.complet()||diagnostic.resultat().erreurs)throw Error('Budget ou navigateur D2 incomplet.');
      candidatures.push(...reseau.candidatures);preuves.push({slot:p.slot,appareil:p.appareil,connexion_formulaire:true,recharge:true,ecritures:reseau.budget.projection()});
      d.action('contexte_fermer');await context.close();contextes.delete(context);reseaux.delete(reseau);
    };
    const participants=[];
    for(const [slot,appareil]of ['iPhone 13','iPad Pro 11'].entries()) {
      const p=await ouvrir(slot,appareil);participants.push(p);
      try{await preparerCandidatureD(p.page,m,p.options);}catch(error){p.d.exceptionFinale(error);throw error;}
    }
    const concurrenceHTTP=await envoyerCandidaturesConcurrentesD(participants,concurrence);
    for(const p of participants){try{await rechargerCandidatureD(p.page,p.options);await terminer(p);}catch(error){p.d.exceptionFinale(error);throw error;}}
    const etab=await ouvrir(2,'iPad Pro 11');
    try{await relireCandidaturesD(etab.page,m,etab.options);await terminer(etab);}catch(error){etab.d.exceptionFinale(error);throw error;}
    return {preuves,candidatures,concurrenceHTTP};
  }finally{
    // Fermer le transport AVANT drainage : aucune nouvelle écriture ne peut
    // partir pendant qu'une requête déjà envoyée finit (sans retry).
    concurrence.annuler();for(const r of reseaux)r.fermer();
    await Promise.allSettled([...reseaux].map(r=>r.drainer()));
    try{await Promise.allSettled([...contextes].map(c=>c.close()));await browser?.close();}finally{preview?.kill('SIGTERM');}
  }
}

export async function executerFrontendD({action,env=process.env,now=Date.now(),fixture=executerD,sql=lireBackendD,naviguer=parcourirFrontendD,save=sauver,read=nom=>JSON.parse(readFileSync(`${dossier}/${nom}.json`,'utf8'))}={}) {
  const config=configurationFrontendD(env,now,action),m=config.m;const sauver=save;
  env=config.env;
  if(action==='check')return {parametres:true};
  if(action==='catalogue')return fixture({action:'catalogue',env});
  if(action==='verify-preview'){let preview;try{preview=await demarrerPreview({env,observer:r=>sauver('preview',r)});}finally{preview?.kill('SIGTERM');}return {preview:true};}
  if(action==='prepare')return fixture({action:'prepare',env});
  if(action==='cleanup'){const resultat=await fixture({action:'cleanup',env});sauver('cleanup-fixture',{skipped:resultat.skipped===true,nettoye:resultat.skipped!==true});return {nettoye:resultat.skipped!==true};}
  if(action==='snapshot'){const rows=projectionAuditsD(await sql(sqlAuditsFrontendD(m),env));sauver('avant-cleanup',rows);return {snapshot:true};}
  if(action==='verify-cleanup') {
    const rows=projectionAuditsD(await sql(sqlAuditsFrontendD(m),env));sauver('apres-cleanup',rows);
    const before=read('avant-cleanup');verifierAuditsD(rows,'cleanup',before);
    const counts=await sql(sqlCompterD(m),env);if(!Array.isArray(counts)||counts.length!==1)throw Error('Compteurs nettoyage D2 incomplets.');
    validerEtatD(counts[0],'cleaned',m);sauver('cleanup-verifie',{zeros:true,audits_conserves:true});return {zeros:true,audits_conserves:true};
  }
  if(action!=='run')throw Error('Action UI D2 inconnue.');
  const diagnostic=diagnosticD();let resultat;
  try{
    diagnostic.action('identites');const identites=identitesFrontendD(env,m);
    diagnostic.action('catalogue');await fixture({action:'catalogue',env});
    diagnostic.action('audits_avant');const before=verifierAuditsD(await sql(sqlAuditsFrontendD(m),env),'avant');sauver('avant',before);
    const {preuves,candidatures,concurrenceHTTP}=await naviguer({m,identites,env,diagnostic});diagnostic.phase('backend');
    diagnostic.action('backend_verifier');const etat=await fixture({action:'verify',env});
    diagnostic.action('backend_correlation');const chevauchement=verifierConcurrenceD(concurrenceHTTP?.slots);if(candidatures.length!==2||new Set(candidatures.map(c=>c.id)).size!==2||new Set(candidatures.map(c=>c.slot)).size!==2||candidatures.some(c=>![0,1].includes(c.slot))||candidatures.some(c=>!etat.candidatures.some(e=>e.id===c.id&&e.soignant_id===m.membres[c.slot]?.userId)))throw Error('Candidatures UI/backend non corrélées.');
    diagnostic.action('audits_apres');sauver('apres',verifierAuditsD(await sql(sqlAuditsFrontendD(m),env),'apres',before));
    // naviguer ne rend la main qu'après fermeture des contextes et du browser.
    // Une erreur reçue pendant ces fermetures reste bloquante pour le verdict.
    if(diagnostic.resultat().erreurs)throw Error('Anomalie UI D2.');
    resultat={version:1,mode:'D2_FRONTEND_STAGING',succes:true,sha:env.GITHUB_SHA,runId:m.runId,jour:m.jour,preuves,candidatures:2,notifications:etat.notifications,k6:false,concurrenceHTTP:chevauchement,concurrenceDB:false,diagnostic:diagnostic.resultat()};
  }catch(error){
    diagnostic.exceptionFinale(error);throw error;
  }finally{
    sauver('resultat',resultat||{version:1,mode:'D2_FRONTEND_STAGING',succes:false,sha:env.GITHUB_SHA,diagnostic:diagnostic.resultat()});
  }
  return {succes:true,candidatures:2};
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href){
  try{const result=await executerFrontendD({action:process.argv[2]});console.log(JSON.stringify(result));}
  catch{console.error('D2 frontend non confirmé ; consulter les preuves filtrées et le nettoyage.');process.exitCode=1;}
}
