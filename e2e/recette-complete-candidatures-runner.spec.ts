import { test, expect } from '@playwright/test';
import { creerCandidaturesDeuxAs, identifiants, maintenant } from './helpers/recette-candidatures-deux-as';
import { deposerCandidatureD, relireCandidaturesD, observerErreursNavigateurD, diagnosticD } from '../scripts/ci/recette-candidatures-staging.mjs';
import { requeteFrontendD, STAGING_URL } from '../scripts/ci/candidatures-ui-contract.mjs';

test('runner D2 : boutons réels, deux candidatures, recharges et relecture établissement sous garde réseau', async ({ browser }, info) => {
  const simulation=creerCandidaturesDeuxAs(),{state}=simulation;
  const m={missionId:identifiants.mission,marker:state.mission.intitule,debut:state.mission.debut_le,fin:state.mission.fin_le,
    membres:[...state.soignants.map((s,slot)=>({slot,userId:s.id,email:s.email,prenom:s.prenom,nom:s.nom})),
      {slot:2,userId:identifiants.etablissement,email:'clinique@example.invalid',prenom:'Clinique',nom:'Simulation'}]};
  const refus: string[]=[],metadonneesDashboard: number[]=[];
  for(const [slot,acteur]of (['as1','as2','etablissement'] as const).entries()) {
    const context=await browser.newContext({...info.project.use});
    await simulation.installer(context,acteur);
    await context.route('**/*',async route=>{
      const r=route.request(),u=new URL(r.url());
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
      if(slot<2) {
        await page.goto('/soignant/tableau-de-bord');
        await expect(page.getByRole('heading',{name:`Bonjour, ${m.membres[slot].prenom}`,exact:true})).toBeVisible();
        await expect(page.getByText('1 mission près de chez toi — tu peux déjà postuler.',{exact:true})).toBeVisible();
        await page.waitForLoadState('networkidle');
      }
      const diagnostic=diagnosticD();
      const options={expect,phase:(p: string)=>diagnostic.phase(p,slot),action:(a: string)=>diagnostic.action(a),capturer:async(etape: string)=>{if(etape==='recharge')await page.locator('main').screenshot({path:info.outputPath(`slot-${slot}-recharge.png`),animations:'disabled'});}};
      if(slot<2)await deposerCandidatureD(page,m,options);else await relireCandidaturesD(page,m,options);
    }finally{await context.close();}
  }
  expect(refus).toEqual([]);simulation.verifierBornes();
  expect(metadonneesDashboard).toEqual([0,1]);
  expect(state.candidatures).toHaveLength(2);
  expect(state.candidatures.every(c=>c.message===m.marker&&c.statut==='EN_ATTENTE')).toBe(true);
  expect(state.calls.filter(c=>c.name==='fn_confirmer_action_planning_v1')).toHaveLength(2);
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
