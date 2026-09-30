import { test, expect } from '@playwright/test';
import { creerCandidaturesDeuxAs, identifiants, maintenant } from './helpers/recette-candidatures-deux-as';
import { deposerCandidatureD, preparerCandidatureD, rechargerCandidatureD, concurrenceCandidaturesD, envoyerCandidaturesConcurrentesD, relireCandidaturesD, observerErreursNavigateurD, diagnosticD, projeterErreurNavigateurD } from '../scripts/ci/recette-candidatures-staging.mjs';
import { requeteFrontendD, budgetEcrituresD, rpcEcritureD, STAGING_URL } from '../scripts/ci/candidatures-ui-contract.mjs';

test('runner D2 : deux interfaces concurrentes, deux candidatures, recharges et relecture établissement sous garde réseau', async ({ browser }, info) => {
  const simulation=creerCandidaturesDeuxAs(),{state}=simulation;
  // Le seed réel donne le même marker à la mission et à son établissement.
  state.etablissement.nom=state.mission.intitule;
  const m={missionId:identifiants.mission,marker:state.mission.intitule,debut:state.mission.debut_le,fin:state.mission.fin_le,
    membres:[...state.soignants.map((s,slot)=>({slot,userId:s.id,email:s.email,prenom:s.prenom,nom:s.nom,password:'Mot-de-passe-fictif-recette-D2'})),
      {slot:2,userId:identifiants.etablissement,email:'etablissement@example.invalid',prenom:'Clinique',nom:'Simulation',password:'Mot-de-passe-fictif-recette-D2'}]};
  const refus: string[]=[],metadonneesDashboard: number[]=[],contextes: import('@playwright/test').BrowserContext[]=[];
  const diagnostic=diagnosticD(),concurrence=concurrenceCandidaturesD();let actifs=0,maximum=0;
  const ouvrir=async(slot:number)=>{
    const acteur=(['as1','as2','etablissement'] as const)[slot],d=diagnostic.pourSlot(slot),budget=budgetEcrituresD(m.membres[slot]);
    const context=await browser.newContext({...info.project.use});contextes.push(context);
    await simulation.installer(context,acteur);observerErreursNavigateurD(context,slot,d);
    let activites=0,audits=0,consultations=0,documents=0;
    await context.addInitScript(()=>{if(location.pathname==='/connexion')sessionStorage.removeItem('sb-127-auth-token');});
    await context.route('**/rest/v1/rpc/{fn_audit_connexion,fn_maj_activite_soignant,fn_ecrire_audit_safe}',route=>{
      const nom=new URL(route.request().url()).pathname.split('/').pop();
      if(nom==='fn_audit_connexion')audits++;else if(nom==='fn_ecrire_audit_safe')consultations++;else activites++;
      return route.fulfill({json:{success:true}});
    });
    await context.route('**/*',async route=>{
      const r=route.request(),u=new URL(r.url());
      if(r.resourceType()==='document'&&r.isNavigationRequest())documents++;
      if(/^\/(auth|rest|functions|storage)\//.test(u.pathname)) {
        const autorisee=requeteFrontendD({url:STAGING_URL+u.pathname+u.search,method:r.method(),body:r.postData()?r.postDataJSON():undefined},m.membres[slot],m);
        if(!autorisee){refus.push(`${r.method()} ${u.pathname}`);return route.abort();}
        const rpc=u.pathname.split('/').pop()!;
        if(r.method()==='POST'&&(rpcEcritureD.has(rpc)||u.pathname==='/auth/v1/token'))budget.consommer(u.pathname==='/auth/v1/token'?'auth-token':rpc);
        if(r.method()==='POST'&&rpc==='fn_confirmer_action_planning_v1')return concurrence.transporter(slot,async()=>{
          maximum=Math.max(maximum,++actifs);
          try{
            // La réponse simulée est livrée directement : fallback() rend la
            // main avant le handler suivant et ne mesure pas son transport.
            const body=r.postDataJSON();state.calls.push({acteur,name:rpc,method:r.method(),body});
            expect(state.candidatures.some(c=>c.soignant_id===m.membres[slot].userId)).toBe(false);
            const candidature={id:`dc300000-0000-4000-8000-00000000003${slot+1}`,mission_id:m.missionId,
              soignant_id:m.membres[slot].userId,message:body.p_message,statut:'EN_ATTENTE',cree_le:maintenant,choix_contrat:'SALARIE'};
            state.candidatures.push(candidature);
            await route.fulfill({json:{success:true,candidature_id:candidature.id,choix_contrat:'SALARIE',profession_requise:'AS',docs_a_completer:true,documents_requis_pour:'SALARIE'}});
          }finally{actifs--;}
        });
        if(u.pathname==='/rest/v1/missions'&&u.searchParams.get('id')?.startsWith('in.')) {
          expect(r.method()).toBe('GET');expect([...u.searchParams.keys()].sort()).toEqual(['id','select']);
          expect(u.searchParams.get('id')).toBe(`in.(${m.missionId})`);expect(u.searchParams.get('select')).toBe('id,nb_creneaux');metadonneesDashboard.push(slot);
        }
      }
      return route.fallback();
    });
    const page=await context.newPage();await page.clock.setFixedTime(new Date(maintenant));
    {
      // Les trois identités passent par le formulaire et leur vrai dashboard,
      // comme le pilote ; aucune session préinjectée sur cette page.
      await page.goto('/connexion');
      await page.getByLabel('Email',{exact:true}).fill(m.membres[slot].email);
      await page.getByLabel('Mot de passe',{exact:true}).fill('Mot-de-passe-fictif-recette-D2');
      await page.getByRole('button',{name:'Se connecter',exact:true}).click();
      await expect(page).toHaveURL(slot<2?/\/soignant\/tableau-de-bord$/:/\/etablissement\/tableau-de-bord$/);
      await expect.poll(()=>slot<2?activites:consultations).toBe(1);
      await page.waitForLoadState('networkidle');
      const options={expect,phase:(p: string)=>d.phase(p),action:(a: string)=>d.action(a),echec:(error:Error)=>d.exceptionFinale(error),capturer:async(etape: string)=>{
        if(slot<2){expect(documents).toBe(etape==='recharge'?2:1);expect(audits).toBe(1);expect(activites).toBe(1);}
        else {
          expect(documents).toBe(etape==='recharge'?2:1);
          expect(audits).toBe(1);expect(consultations).toBe(1);expect(activites).toBe(0);
          for(const s of state.soignants)await expect(page.getByText(`${s.prenom} ${s.nom}`,{exact:false})).toHaveCount(0);
        }
        expect(diagnostic.resultat().erreurs).toBe(0);
        if(etape==='recharge')await page.locator('main').screenshot({path:info.outputPath(`slot-${slot}-recharge.png`),animations:'disabled',scale:'css'});
      }};
      return {slot,page,context,options,budget};
    }
  };
  try {
    const participants=[];
    for(const slot of [0,1]){const p=await ouvrir(slot);participants.push(p);await preparerCandidatureD(p.page,m,p.options);}
    expect(state.candidatures).toHaveLength(0);expect(actifs).toBe(0);
    const preuve=await envoyerCandidaturesConcurrentesD(participants,concurrence);
    expect(maximum).toBe(2);expect(preuve.chevauchementMs).toBeGreaterThan(0);expect(preuve.slots.map(r=>r.slot)).toEqual([0,1]);
    await info.attach('chevauchement-simule.json',{body:JSON.stringify(preuve),contentType:'application/json'});
    for(const p of participants){await rechargerCandidatureD(p.page,p.options);expect(p.budget.complet()).toBe(true);await p.context.close();}
    const etab=await ouvrir(2);await relireCandidaturesD(etab.page,m,etab.options);expect(etab.budget.complet()).toBe(true);await etab.context.close();
  }finally{concurrence.annuler();await Promise.allSettled(contextes.map(c=>c.close()));}
  expect(diagnostic.resultat().erreurs).toBe(0);
  expect(refus).toEqual([]);simulation.verifierBornes();
  expect(metadonneesDashboard).toEqual([0,1]);
  expect(state.candidatures).toHaveLength(2);
  expect(new Set(state.candidatures.map(c=>c.id)).size).toBe(2);
  for(const soignant of state.soignants)expect(state.candidatures.filter(c=>c.soignant_id===soignant.id)).toHaveLength(1);
  expect(state.candidatures.every(c=>c.message===m.marker&&c.statut==='EN_ATTENTE')).toBe(true);
  expect(state.calls.filter(c=>c.name==='fn_confirmer_action_planning_v1')).toHaveLength(2);
});

test('runner D2 : navigation établissement préserve deux lectures dashboard tardives',async({browser},info)=>{
  const simulation=creerCandidaturesDeuxAs(),{state}=simulation;
  state.etablissement.nom=state.mission.intitule;
  for(const [i,s] of state.soignants.entries())state.candidatures.push({id:`dc300000-0000-4000-8000-00000000003${i+1}`,
    mission_id:state.mission.id,soignant_id:s.id,message:'RECETTE D simulation tardive',statut:'EN_ATTENTE',cree_le:maintenant,choix_contrat:'SALARIE'});
  const m={missionId:identifiants.mission,marker:state.mission.intitule,membres:[...state.soignants.map((s,slot)=>({slot,userId:s.id,email:s.email,prenom:s.prenom,nom:s.nom})),
    {slot:2,userId:identifiants.etablissement,email:'etablissement@example.invalid',password:'Mot-de-passe-fictif-recette-D2'}]};
  const context=await browser.newContext({...info.project.use});await simulation.installer(context,'etablissement');
  await context.addInitScript(()=>{if(location.pathname==='/connexion')sessionStorage.removeItem('sb-127-auth-token');});
  let liberer!:()=>void;const reponses=new Promise<void>(resolve=>{liberer=resolve;});
  const debuts:string[]=[],fins:string[]=[],refus:string[]=[];let documents=0,audits=0,consultations=0;
  await context.route('**/rest/v1/rpc/{fn_audit_connexion,fn_ecrire_audit_safe}',route=>{
    if(new URL(route.request().url()).pathname.endsWith('fn_audit_connexion'))audits++;else consultations++;
    return route.fulfill({json:{success:true}});
  });
  await context.route('**/rest/v1/rpc/{fn_mon_score_etab,fn_bfa_info}',async route=>{
    const nom=new URL(route.request().url()).pathname.split('/').pop()!;debuts.push(nom);
    await reponses;await route.fallback();fins.push(nom);
  });
  await context.route('**/*',route=>{
    const r=route.request(),u=new URL(r.url());
    if(r.resourceType()==='document'&&r.isNavigationRequest())documents++;
    if(/^\/(auth|rest|functions|storage)\//.test(u.pathname)&&!requeteFrontendD({url:STAGING_URL+u.pathname+u.search,method:r.method(),body:r.postData()?r.postDataJSON():undefined},m.membres[2],m)){
      refus.push(`${r.method()} ${u.pathname}`);return route.abort();
    }
    return route.fallback();
  });
  const diagnostic=diagnosticD();observerErreursNavigateurD(context,2,diagnostic);
  const page=await context.newPage();await page.clock.setFixedTime(new Date(maintenant));
  try {
    await page.goto('/connexion');await page.getByLabel('Email',{exact:true}).fill(m.membres[2].email);
    await page.getByLabel('Mot de passe',{exact:true}).fill('Mot-de-passe-fictif-recette-D2');
    await page.getByRole('button',{name:'Se connecter',exact:true}).click();await expect(page).toHaveURL(/\/etablissement\/tableau-de-bord$/);
    await expect.poll(()=>consultations).toBe(1);
    // Stress explicite : ces réponses restent en vol pendant le vrai clic.
    // Aucun sleep ni accélération du réseau ne remplace cette barrière.
    await expect.poll(()=>debuts.length).toBe(2);expect(fins).toEqual([]);
    await relireCandidaturesD(page,m,{expect,action:nom=>{
      if(nom==='etablissement_compteur'&&fins.length===0){expect(documents).toBe(1);liberer();}
    },capturer:async etape=>{
      await expect.poll(()=>fins.length).toBe(2);expect(documents).toBe(etape==='recharge'?2:1);
      expect(diagnostic.resultat().erreurs).toBe(0);
    }});
    expect(debuts.sort()).toEqual(['fn_bfa_info','fn_mon_score_etab']);expect(fins.sort()).toEqual(debuts);
    expect(audits).toBe(1);expect(consultations).toBe(1);expect(refus).toEqual([]);simulation.verifierBornes();
    expect(state.candidatures).toHaveLength(2);expect(state.calls.filter(c=>c.name==='fn_confirmer_action_planning_v1')).toEqual([]);
    await info.attach('lectures-dashboard-conservees',{body:JSON.stringify({debuts,fins,documents,audits,consultations,diagnostic:diagnostic.resultat()}),contentType:'application/json'});
  }finally{liberer();await context.close();}
});

test('runner D2 : titre mission unique même lorsque le nom établissement est identique',async({browser},info)=>{
  const simulation=creerCandidaturesDeuxAs(),{state}=simulation;
  state.etablissement.nom=state.mission.intitule;
  const context=await browser.newContext({...info.project.use});
  await simulation.installer(context,'as1');const page=await context.newPage();
  await page.clock.setFixedTime(new Date(maintenant));
  try {
    await page.goto(`/soignant/missions/${identifiants.mission}`);
    const titres=page.getByRole('heading',{name:state.mission.intitule,exact:true});
    await expect(titres).toHaveCount(2);
    let erreur:unknown;
    try{await expect(titres).toBeVisible();}catch(e){erreur=e;}
    expect(erreur).toBeInstanceOf(Error);
    expect((erreur as Error).message).toContain('strict mode violation');
    const projection=projeterErreurNavigateurD({source:'exception_finale',texte:(erreur as Error).message,classe:(erreur as Error).name,location:undefined,stack:undefined});
    expect(projection.categorie).toBe('strict_mode');
    const titreMission=page.getByRole('heading',{level:1,name:state.mission.intitule,exact:true});
    await expect(titreMission).toHaveCount(1);await expect(titreMission).toBeVisible();
    await info.attach('matcher-ambigu-projete',{body:JSON.stringify({headings:2,h1:1,projection}),contentType:'application/json'});
    simulation.verifierBornes();expect(state.candidatures).toEqual([]);
  }finally{await context.close();}
});

test('runner D2 : erreurs navigateur projetées sans divulgation et toujours bloquantes', async ({ browser }, info) => {
  const context=await browser.newContext({...info.project.use}),diagnostic=diagnosticD();
  await context.route('**/*',route=>route.abort());await context.routeWebSocket('**/*',socket=>socket.close());
  observerErreursNavigateurD(context,0,diagnostic);const page=await context.newPage();diagnostic.phase('postuler',1);
  try {
    await page.evaluate(()=>{console.error('WebSocket CANARI_SECRET_JWT');console.error('The operation was aborted CANARI_PASSWORD');setTimeout(()=>{throw new TypeError('Failed to fetch CANARI_IDENTITE');},0);
      setTimeout(()=>{const error=new Error('/CANARI_PASSWORD@api.invalid/path?jwt=CANARI_SECRET_JWT due to access control checks.');error.name='Fetch API cannot load https';throw error;},0);});
    await expect.poll(()=>diagnostic.resultat().erreurs).toBe(4);
    const resultat=diagnostic.resultat();expect(resultat.erreurs).toBeGreaterThan(0);
    expect(resultat.erreursNavigateur.map(e=>e.categorie).sort()).toEqual(['chargement_reseau','controle_origine','requete_abandonnee','websocket']);
    expect(resultat.erreursNavigateur.every(e=>e.slotEmetteur===0&&e.slotPhase===1)).toBe(true);
    expect(resultat.erreursNavigateur.every(e=>Number.isInteger(e.premierMs)&&e.premierMs>=0&&e.dernierMs>=e.premierMs&&e.dernierMs<=1_800_000)).toBe(true);
    expect(JSON.stringify(resultat)).not.toMatch(/CANARI|SECRET_JWT|PASSWORD|IDENTITE/);
    diagnostic.action('mission_titre');let erreurCapturee=false;
    try{await expect(page.getByText('CANARI_IDENTITE_ABSENTE',{exact:true})).toBeVisible({timeout:50});}
    catch(error){erreurCapturee=true;diagnostic.exceptionFinale(error);}
    expect(erreurCapturee).toBe(true);
    const fin=diagnostic.resultat();expect(fin.erreurs).toBe(4);
    expect(fin.erreurFinale).toMatchObject({source:'exception_finale',action:'mission_titre',categorie:'delai_attente',emplacement:null});
    expect(JSON.stringify(fin)).not.toMatch(/CANARI|SECRET_JWT|PASSWORD|IDENTITE/);
  }finally{await context.close();}
});
