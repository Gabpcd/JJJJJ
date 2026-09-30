import { randomBytes } from 'node:crypto';
import { appendFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { configurationD,validerManifesteD,utilisateurDValide,validerCatalogueD,validerEtatD,sqlCatalogueD,STAGING_REF,STAGING_URL } from './candidatures-fixture-contract.mjs';
import { sqlAvantD,sqlSeedD,sqlEtatD } from './candidatures-fixture-sql.mjs';
export async function executerD({action,env=process.env,fetchImpl=fetch,log=console.log,genererMotDePasse=()=>`Aa1!${randomBytes(36).toString('base64url')}`}={}) {
  if(!['catalogue','prepare','verify','cleanup'].includes(action)) throw new Error('Action D inconnue.');
  const c=configurationD(env),m=c.m;
  if(!env.STAGING_SUPABASE_ACCESS_TOKEN) throw new Error('Accès catalogue staging requis.');
  if(action!=='catalogue' && env.LOAD_D_EXECUTION_APPROUVEE!=='DEUX_PROFILS') throw new Error('Préflight D à revoir avant toute fixture distante ; activation explicite requise.');
  if(action!=='catalogue' && (!env.STAGING_SUPABASE_SERVICE_ROLE_KEY || !env.STAGING_SUPABASE_ANON_KEY)) throw new Error('Accès staging D incomplets.');
  const req=async(url,{method='GET',body,key=env.STAGING_SUPABASE_SERVICE_ROLE_KEY,absent=false}={})=>{
    let r;try {r=await fetchImpl(url,{method,redirect:'error',headers:{Authorization:`Bearer ${key}`,apikey:key,'Content-Type':'application/json'},...(body===undefined?{}:{body:JSON.stringify(body)}),signal:AbortSignal.timeout(35_000)});} catch {throw new Error('Réponse D ambiguë : manifeste conservé, aucun réessai de mutation.');}
    if(absent&&r.status===404)return null;
    if(!r.ok)throw new Error(`Requête D refusée (HTTP ${Number(r.status)||0}).`);
    try {return await r.json();} catch {throw new Error('Réponse D JSON invalide.');}
  };
  const sql=async query=>{const r=await req(`https://api.supabase.com/v1/projects/${STAGING_REF}/database/query`,{method:'POST',body:{query},key:env.STAGING_SUPABASE_ACCESS_TOKEN}); if(!Array.isArray(r)||r.length!==1)throw new Error('Réponse SQL D incomplète.');return r[0];};
  if(action==='catalogue'){const r=await sql(sqlCatalogueD);validerCatalogueD(r);return Object.fromEntries(['schema','fonctions','triggers','crons_actifs','audit_fk'].map(k=>[k,r[k]]));}
  let doc;
  const save=()=>writeFileSync(c.path,JSON.stringify(doc,null,2)+'\n',{mode:0o600});
  const url=a=>`${STAGING_URL}/auth/v1/admin/users/${a.userId}`;
  if(action==='prepare') {
    if(!env.GITHUB_ENV)throw new Error('Canal privé GITHUB_ENV requis.');
    if(existsSync(c.path))throw new Error('Manifeste D déjà présent : aucune recréation.');
    const passwords=m.membres.map(()=>genererMotDePasse());
    if(new Set(passwords).size!==3 || passwords.some(p=>typeof p!=='string'||p.length<32||/[\r\n]/.test(p)))throw new Error('Trois mots de passe aléatoires distincts requis.');
    // Tous les IDs sont durables AVANT le premier POST, même SQL.
    mkdirSync(dirname(c.path),{recursive:true});doc={...m,status:'planned',authStatus:['not-started','not-started','not-started']};
    writeFileSync(c.path,JSON.stringify(doc,null,2)+'\n',{flag:'wx',mode:0o600});
    if((await sql(sqlAvantD(m))).pret!==true)throw new Error('Préflight D non confirmé.');
    for(const [i,a] of m.membres.entries()) {
      doc.authStatus[i]='planned';save();log(`::add-mask::${passwords[i]}`);
      const u=await req(`${STAGING_URL}/auth/v1/admin/users`,{method:'POST',body:{id:a.userId,email:a.email,password:passwords[i],email_confirm:true,
        app_metadata:{role:a.role,est_compte_test:true,is_test_playwright:true,load_fixture_kind:'CANDIDATURES_D2',load_fixture_run:m.runId,...(i===2?{etablissement_id:a.userId}:{})}}});
      if(!utilisateurDValide(u,m,i))throw new Error('Auth D créée non confirmée.');
      doc.authStatus[i]='auth-created';save();
    }
    if((await sql(sqlSeedD(m))).prepare!==true)throw new Error('Seed D non confirmé.');
    validerEtatD(await sql(sqlEtatD(m)),'prepared',m);
    for(const [i,a] of m.membres.entries()) {
      const session=await req(`${STAGING_URL}/auth/v1/token?grant_type=password`,{method:'POST',key:env.STAGING_SUPABASE_ANON_KEY,body:{email:a.email,password:passwords[i]}});
      if(typeof session?.access_token!=='string'||!session.access_token||!utilisateurDValide(session.user,m,i))throw new Error('Session D non confirmée.');
    }
    // Aucun JWT dans le manifeste ou GITHUB_ENV, mots de passe uniquement canal privé.
    appendFileSync(env.GITHUB_ENV,`LOAD_CANDIDATURES_JSON=${JSON.stringify({...m,identites:m.membres.map((a,i)=>({...a,password:passwords[i]}))})}\n`,{mode:0o600});
    doc.status='prepared';doc.authStatus.fill('prepared');save();log('D2 préparé : trois identités test, une mission, aucun contrat ni qualification vérifiée.');return {identites:3,missions:1};
  }
  if(!existsSync(c.path)){if(action==='cleanup')return {skipped:true};throw new Error('Manifeste D absent.');}
  try{doc=JSON.parse(readFileSync(c.path,'utf8'));}catch{throw new Error('Manifeste D illisible.');}
  validerManifesteD(doc,m.runId,m.jour);
  if(action==='verify')return validerEtatD(await sql(sqlEtatD(m)),'apres',m);
  // Prévalider toutes les identités avant le premier DELETE ; erreurs réseau
  // et classifications ambiguës ne sont jamais converties en absence.
  const users=[];for(const [i,a] of m.membres.entries()) {
    const u=await req(url(a),{absent:true});
    if(u&&!utilisateurDValide(u,m,i))throw new Error('Auth D altérée : aucune suppression.');
    if(u&&doc.authStatus[i]==='not-started')throw new Error('Identité D non commencée déjà présente.');users.push(u);
  }
  const initial=[...doc.authStatus];doc.status='cleanup-started';save();
  await sql(sqlEtatD(m,true));
  const echecs=[];
  for(const [i,a] of m.membres.entries()) {
    if(!users[i]&&initial[i]==='planned'){echecs.push(i);continue;} // POST perdu peut arriver tardivement : pas de faux zéro.
    try {
      if(users[i]) {
        const u=await req(url(a),{absent:true});
        if(u){if(!utilisateurDValide(u,m,i)||u.app_metadata.load_cleanup_pending!==true)throw new Error('Garde finale D absente.');
          doc.authStatus[i]='cleanup-started';save();await req(url(a),{method:'DELETE',body:{should_soft_delete:false}});}
      }
      doc.authStatus[i]='cleaned';save();
    } catch {echecs.push(i);}
  }
  if(echecs.length)throw new Error(`Nettoyage D incomplet, slots ${echecs.join(',')} ; manifeste conservé pour reprise.`);
  const etat=validerEtatD(await sql(sqlEtatD(m)),'cleaned',m);doc.status='cleaned';save();log('D2 nettoyé : zéros confirmés, audits conservés.');return etat;
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href){try{const r=await executerD({action:process.argv[2]});console.log(JSON.stringify(r));}catch(e){console.error(e.message);process.exitCode=1;}}
