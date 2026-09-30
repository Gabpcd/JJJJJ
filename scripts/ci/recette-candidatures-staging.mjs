import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
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
export function diagnosticD() {
  let phase='preflight',slot=null,erreurs=0; const reseau=new Map();
  const noms=new Set([...rpcEcritureD,...rpcLectureD,...rpcParametresD,...tablesLectureD]);
  return { phase(p,s=null) { if(!['preflight','preview','browser','login','mission','postuler','reload','etablissement','backend','cleanup'].includes(p)||![null,0,1,2].includes(s))throw Error('Phase D2 invalide.');phase=p;slot=s; },
    erreur() { erreurs++; }, reseau(url,method,status) {
      let origine='invalide',chemin='autre';
      try { const u=new URL(url);origine=u.origin===ORIGINE_UI?'preview':u.origin===STAGING_URL?'staging':'externe';
        const nom=u.pathname.split('/').pop();chemin=origine==='preview'?'local':origine!=='staging'?'externe':noms.has(nom)?nom:['/auth/v1/token','/auth/v1/user'].includes(u.pathname)?`auth-${nom}`:'autre'; }catch{/* Projection fermée. */}
      const r={phase,slot,origine,chemin,methode:['GET','HEAD','POST','OPTIONS','PATCH','PUT','DELETE'].includes(method)?method:'autre',statut:Number.isInteger(status)&&status>=100&&status<=599?status:['refus','transport','ferme'].includes(status)?status:'autre'};
      const k=JSON.stringify(r); if(reseau.size<128||reseau.has(k))reseau.set(k,{...r,nombre:(reseau.get(k)?.nombre||0)+1});else erreurs++;
    }, resultat() { return {phase,slot,erreurs,reseau:[...reseau.values()].map(r=>({...r}))}; } };
}
export async function lireBackendD(query, env, fetchImpl=fetch) {
  if(env.STAGING_SUPABASE_PROJECT_REF!==STAGING_REF||env.STAGING_SUPABASE_URL!==STAGING_URL||!env.STAGING_SUPABASE_ACCESS_TOKEN)throw Error('Lecture D2 staging refusée.');
  let response;try {response=await fetchImpl(`https://api.supabase.com/v1/projects/${STAGING_REF}/database/query`,{
    method:'POST',redirect:'error',signal:AbortSignal.timeout(35000),headers:{Authorization:`Bearer ${env.STAGING_SUPABASE_ACCESS_TOKEN}`,'Content-Type':'application/json'},body:JSON.stringify({query})});}catch{throw Error('Lecture D2 ambiguë sans réessai.');}
  if(!response.ok)throw Error('Lecture D2 refusée.');
  try{return await response.json();}catch{throw Error('Lecture D2 JSON invalide.');}
}
const heureParis = value => new Intl.DateTimeFormat('fr-FR',{timeZone:'Europe/Paris',hour:'2-digit',minute:'2-digit',hour12:false}).format(new Date(value)).replace(':','h');
export async function deposerCandidatureD(page,m,{expect,capturer=async etape=>{void etape;},phase=etape=>{void etape;}}) {
  phase('mission'); await page.goto(`/soignant/missions/${m.missionId}`);
  await expect(page.getByRole('heading',{name:m.marker,exact:true})).toBeVisible();
  await page.getByPlaceholder('Présente-toi brièvement…').fill(m.marker);
  await expect(page.getByRole('button',{name:/Vérifier et postuler/})).toBeEnabled();
  await page.getByRole('button',{name:/Vérifier et postuler/}).click();
  const dialogue=page.getByRole('dialog',{name:'Vérifie ton engagement'});
  await expect(dialogue).toBeVisible();await expect(dialogue).toContainText(heureParis(m.debut));await expect(dialogue).toContainText(heureParis(m.fin));
  phase('postuler');await dialogue.getByRole('button',{name:'Envoyer ma candidature',exact:true}).click();
  await expect(dialogue).toBeHidden();
  await expect(page.getByText('✅ Candidature envoyée — En attente de réponse',{exact:true})).toBeVisible();
  await expect(page.getByText('Candidature envoyée ! Valide tes documents pour pouvoir être accepté.',{exact:true})).toBeVisible();
  await expect(page.getByRole('button',{name:'Mes documents',exact:true})).toBeVisible();
  await page.waitForLoadState('networkidle');await capturer('candidature');
  phase('reload');await page.reload();
  await expect(page.getByText('✅ Candidature envoyée — En attente de réponse',{exact:true})).toBeVisible();
  await expect(page.getByRole('button',{name:/Vérifier et postuler/})).toBeHidden();
  await page.waitForLoadState('networkidle');await capturer('recharge');
}
export async function relireCandidaturesD(page,m,{expect,capturer=async etape=>{void etape;},phase=etape=>{void etape;}}) {
  phase('etablissement');await page.goto(`/etablissement/missions/${m.missionId}`);
  for(const recharge of [false,true]) {
    if(recharge){phase('reload');await page.reload();}
    await expect(page.getByRole('heading',{name:'Candidatures (2)',exact:true})).toBeVisible();
    await expect(page.getByText('En attente (2)',{exact:true})).toBeVisible();
    for(const a of m.membres.slice(0,2)) {
      const nom=page.locator('p').filter({hasText:new RegExp(`👤\\s+${RegExp.escape(a.prenom)} ${RegExp.escape(a.nom)}`)});
      await expect(nom).toBeVisible();
      // Les badges sont des enfants du même paragraphe : comparer exactement
      // ses nœuds texte propres, sans inclure profession/statut documentaire.
      const texte=await nom.evaluate(element=>Array.from(element.childNodes).filter(n=>n.nodeType===Node.TEXT_NODE).map(n=>n.textContent).join('').replace(/\s+/g,' ').trim());
      expect(texte).toBe(`👤 ${a.prenom} ${a.nom}`);
    }
    await expect(page.getByText('📄 Documents en vérification',{exact:true})).toHaveCount(2);
    await expect(page.getByRole('button',{name:'Accepter cette candidature',exact:true})).toHaveCount(2);
    await page.waitForLoadState('networkidle');await capturer(recharge?'recharge':'candidatures');
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
export async function installerReseauD(context,a,m,diagnostic,{budget=budgetEcrituresD(a)}={}) {
  const enCours=new Set();const candidatures=[];
  await context.addInitScript(()=>{
    localStorage.setItem('cookie-consent','refused');
    // Le détail établissement importe stripe-js. Ce banc ne charge pas son SDK
    // externe et toute tentative de paiement provoque une erreur navigateur.
    Object.defineProperty(window,'Stripe',{value:()=>{throw Error('Paiement interdit dans la recette D2.');}});
  });
  await context.routeWebSocket('**/*',socket=>socket.close());
  context.on('page',page=>{page.on('pageerror',()=>diagnostic.erreur());page.on('console',message=>{if(message.type()==='error')diagnostic.erreur();});});
  await context.route('**/*',async route=>{
    const execution=(async()=>{
      const request=route.request();let body;
      try{body=request.postData()?request.postDataJSON():undefined;}catch{diagnostic.erreur();diagnostic.reseau(request.url(),request.method(),'refus');await route.abort();return;}
      if(!requeteFrontendD({url:request.url(),method:request.method(),body},a,m)){diagnostic.erreur();diagnostic.reseau(request.url(),request.method(),'refus');await route.abort();return;}
      const u=new URL(request.url());if(u.origin===ORIGINE_UI){await route.continue();return;}
      const rpc=u.pathname.split('/').pop();
      try {
        if(request.method()==='POST'&&(rpcEcritureD.has(rpc)||u.pathname==='/auth/v1/token'))budget.consommer(u.pathname==='/auth/v1/token'?'auth-token':rpc);
        const response=await route.fetch({maxRedirects:0,maxRetries:0,timeout:25000});
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
  return {budget,candidatures,async drainer(){await Promise.all([...enCours]);},enCours:()=>enCours.size};
}
export async function parcourirFrontendD({m,identites,env,diagnostic,chargerPlaywright=()=>import('@playwright/test'),previewFn=demarrerPreview,preparerBuild=()=>{const index=resolve('dist/index.html');writeFileSync(index,preparerHtmlPreview(readFileSync(index,'utf8')));}}={}) {
  let browser,preview;const contextes=[],preuves=[],candidatures=[];
  try {
    diagnostic.phase('preview');preparerBuild();
    preview=await previewFn({env,observer:etat=>sauver('preview',etat)});
    const {webkit,devices,expect}=await chargerPlaywright();diagnostic.phase('browser');
    // Les clés serveur et le JSON privé restent dans le runner Node ; le
    // processus navigateur ne reçoit que les variables système nécessaires.
    const envNavigateur=Object.fromEntries(['PATH','HOME','TMPDIR','XDG_RUNTIME_DIR','DISPLAY','WAYLAND_DISPLAY'].filter(k=>typeof env[k]==='string').map(k=>[k,env[k]]));
    browser=await webkit.launch({env:envNavigateur});
    for(const [slot,appareil]of ['iPhone 13','iPad Pro 11','iPad Pro 11'].entries()) {
      const a=identites[slot];diagnostic.phase('browser',slot);
      const context=await browser.newContext({...devices[appareil],baseURL:ORIGINE_UI,locale:'fr-FR',timezoneId:'Europe/Paris',serviceWorkers:'block'});contextes.push(context);
      const reseau=await installerReseauD(context,a,m,diagnostic);const page=await context.newPage();page.setDefaultTimeout(20000);page.setDefaultNavigationTimeout(25000);
      diagnostic.phase('login',slot);await page.goto('/connexion');
      await page.getByLabel('Email',{exact:true}).fill(a.email);await page.getByLabel('Mot de passe',{exact:true}).fill(a.password);
      await page.getByRole('button',{name:'Se connecter',exact:true}).click();
      await expect(page).toHaveURL(slot<2?/\/soignant\/tableau-de-bord$/:/\/etablissement\/tableau-de-bord$/);
      // Attendre aussi l'audit automatique du dashboard établissement avant de
      // quitter son écran : aucune navigation précipitée qui annule une écriture.
      await expect.poll(()=>reseau.budget.projection()[slot<2?'fn_maj_activite_soignant':'fn_ecrire_audit_safe']).toBe(1);
      await page.waitForLoadState('networkidle');await reseau.drainer();
      const options={expect,phase:p=>diagnostic.phase(p,slot),capturer:async etape=>{
        await reseau.drainer();if(diagnostic.resultat().erreurs)throw Error('Anomalie UI D2.');
        await page.locator('main').screenshot({path:`${dossier}/slot-${slot}-${etape}.png`,animations:'disabled'});
      }};
      if(slot<2)await deposerCandidatureD(page,m,options);else await relireCandidaturesD(page,m,options);
      await reseau.drainer();if(!reseau.budget.complet()||diagnostic.resultat().erreurs)throw Error('Budget ou navigateur D2 incomplet.');
      candidatures.push(...reseau.candidatures);preuves.push({slot,appareil,connexion_formulaire:true,recharge:true,ecritures:reseau.budget.projection()});
      await context.close();contextes.pop();
    }
    return {preuves,candidatures};
  }finally{
    // Tous les contextes sont fermés AVANT retour, y compris sur échec. Le job
    // de cleanup ne peut commencer tant que ce processus n'est pas terminé.
    try{await Promise.allSettled(contextes.map(c=>c.close()));await browser?.close();}finally{preview?.kill('SIGTERM');}
  }
}
export async function executerFrontendD({action,env=process.env,now=Date.now(),fixture=executerD,sql=lireBackendD,naviguer=parcourirFrontendD,save=sauver,read=nom=>JSON.parse(readFileSync(`${dossier}/${nom}.json`,'utf8'))}={}) {
  const config=configurationFrontendD(env,now),m=config.m;const sauver=save;
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
    const identites=identitesFrontendD(env,m);
    await fixture({action:'catalogue',env});
    const before=verifierAuditsD(await sql(sqlAuditsFrontendD(m),env),'avant');sauver('avant',before);
    const {preuves,candidatures}=await naviguer({m,identites,env,diagnostic});diagnostic.phase('backend');
    const etat=await fixture({action:'verify',env});
    if(candidatures.length!==2||candidatures.some(c=>!etat.candidatures.some(e=>e.id===c.id&&e.soignant_id===m.membres[c.slot]?.userId)))throw Error('Candidatures UI/backend non corrélées.');
    sauver('apres',verifierAuditsD(await sql(sqlAuditsFrontendD(m),env),'apres',before));
    resultat={version:1,mode:'D2_FRONTEND_STAGING',succes:true,sha:env.GITHUB_SHA,runId:m.runId,jour:m.jour,preuves,candidatures:2,notifications:etat.notifications,k6:false,concurrenceDB:false,diagnostic:diagnostic.resultat()};
  }finally{
    sauver('resultat',resultat||{version:1,mode:'D2_FRONTEND_STAGING',succes:false,sha:env.GITHUB_SHA,diagnostic:diagnostic.resultat()});
  }
  return {succes:true,candidatures:2};
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href){
  try{const result=await executerFrontendD({action:process.argv[2]});console.log(JSON.stringify(result));}
  catch{console.error('D2 frontend non confirmé ; consulter les preuves filtrées et le nettoyage.');process.exitCode=1;}
}
