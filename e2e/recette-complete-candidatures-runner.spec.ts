import { test, expect } from '@playwright/test';
import { creerCandidaturesDeuxAs, identifiants, maintenant } from './helpers/recette-candidatures-deux-as';
import { deposerCandidatureD, relireCandidaturesD, observerErreursNavigateurD, diagnosticD, projeterErreurNavigateurD } from '../scripts/ci/recette-candidatures-staging.mjs';
import { requeteFrontendD, STAGING_URL } from '../scripts/ci/candidatures-ui-contract.mjs';

test('runner D2 : boutons réels, deux candidatures, recharges et relecture établissement sous garde réseau', async ({ browser }, info) => {
  const simulation=creerCandidaturesDeuxAs(),{state}=simulation;
  // Le seed réel donne le même marker à la mission et à son établissement.
  state.etablissement.nom=state.mission.intitule;
  const m={missionId:identifiants.mission,marker:state.mission.intitule,debut:state.mission.debut_le,fin:state.mission.fin_le,
    membres:[...state.soignants.map((s,slot)=>({slot,userId:s.id,email:s.email,prenom:s.prenom,nom:s.nom,password:'Mot-de-passe-fictif-recette-D2'})),
      {slot:2,userId:identifiants.etablissement,email:'etablissement@example.invalid',prenom:'Clinique',nom:'Simulation',password:'Mot-de-passe-fictif-recette-D2'}]};
  const refus: string[]=[],metadonneesDashboard: number[]=[];
  for(const [slot,acteur]of (['as1','as2','etablissement'] as const).entries()) {
    const context=await browser.newContext({...info.project.use});
    await simulation.installer(context,acteur);
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
        if(u.pathname==='/rest/v1/missions'&&u.searchParams.get('id')?.startsWith('in.')) {
          expect(r.method()).toBe('GET');expect([...u.searchParams.keys()].sort()).toEqual(['id','select']);
          expect(u.searchParams.get('id')).toBe(`in.(${m.missionId})`);expect(u.searchParams.get('select')).toBe('id,nb_creneaux');metadonneesDashboard.push(slot);
        }
      }
      return route.fallback();
    });
    const page=await context.newPage();await page.clock.setFixedTime(new Date(maintenant));
    try {
      // Les trois identités passent par le formulaire et leur vrai dashboard,
      // comme le pilote ; aucune session préinjectée sur cette page.
      await page.goto('/connexion');
      await page.getByLabel('Email',{exact:true}).fill(m.membres[slot].email);
      await page.getByLabel('Mot de passe',{exact:true}).fill('Mot-de-passe-fictif-recette-D2');
      await page.getByRole('button',{name:'Se connecter',exact:true}).click();
      await expect(page).toHaveURL(slot<2?/\/soignant\/tableau-de-bord$/:/\/etablissement\/tableau-de-bord$/);
      await expect.poll(()=>slot<2?activites:consultations).toBe(1);
      await page.waitForLoadState('networkidle');
      const diagnostic=diagnosticD();
      const options={expect,phase:(p: string)=>diagnostic.phase(p,slot),action:(a: string)=>diagnostic.action(a),capturer:async(etape: string)=>{
        if(slot<2){expect(documents).toBe(etape==='recharge'?2:1);expect(audits).toBe(1);expect(activites).toBe(1);}
        else {
          expect(audits).toBe(1);expect(consultations).toBe(1);expect(activites).toBe(0);
          for(const s of state.soignants)await expect(page.getByText(`${s.prenom} ${s.nom}`,{exact:false})).toHaveCount(0);
        }
        if(etape==='recharge')await page.locator('main').screenshot({path:info.outputPath(`slot-${slot}-recharge.png`),animations:'disabled'});
      }};
      if(slot<2)await deposerCandidatureD(page,m,options);else await relireCandidaturesD(page,m,options);
    }finally{await context.close();}
  }
  expect(refus).toEqual([]);simulation.verifierBornes();
  expect(metadonneesDashboard).toEqual([0,1]);
  expect(state.candidatures).toHaveLength(2);
  expect(state.candidatures.every(c=>c.message===m.marker&&c.statut==='EN_ATTENTE')).toBe(true);
  expect(state.calls.filter(c=>c.name==='fn_confirmer_action_planning_v1')).toHaveLength(2);
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
