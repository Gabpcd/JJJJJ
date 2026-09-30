import { test, expect } from '@playwright/test';
import { creerCandidaturesDeuxAs, identifiants, maintenant } from './helpers/recette-candidatures-deux-as';
import { deposerCandidatureD, relireCandidaturesD } from '../scripts/ci/recette-candidatures-staging.mjs';
import { requeteFrontendD, STAGING_URL } from '../scripts/ci/candidatures-ui-contract.mjs';

test('runner D2 : boutons réels, deux candidatures, recharges et relecture établissement sous garde réseau', async ({ browser }, info) => {
  const simulation=creerCandidaturesDeuxAs(),{state}=simulation;
  const m={missionId:identifiants.mission,marker:state.mission.intitule,debut:state.mission.debut_le,fin:state.mission.fin_le,
    membres:[...state.soignants.map((s,slot)=>({slot,userId:s.id,email:s.email,prenom:s.prenom,nom:s.nom})),
      {slot:2,userId:identifiants.etablissement,email:'clinique@example.invalid',prenom:'Clinique',nom:'Simulation'}]};
  const refus: string[]=[];
  for(const [slot,acteur]of (['as1','as2','etablissement'] as const).entries()) {
    const context=await browser.newContext({...info.project.use});
    await simulation.installer(context,acteur);
    await context.route('**/*',async route=>{
      const r=route.request(),u=new URL(r.url());
      if(/^\/(auth|rest|functions|storage)\//.test(u.pathname)) {
        const autorisee=requeteFrontendD({url:STAGING_URL+u.pathname+u.search,method:r.method(),body:r.postData()?r.postDataJSON():undefined},m.membres[slot],m);
        if(!autorisee){refus.push(`${r.method()} ${u.pathname}`);return route.abort();}
      }
      return route.fallback();
    });
    const page=await context.newPage();await page.clock.setFixedTime(new Date(maintenant));
    try {
      const options={expect,capturer:async(etape: string)=>{if(etape==='recharge')await page.locator('main').screenshot({path:info.outputPath(`slot-${slot}-recharge.png`),animations:'disabled'});}};
      if(slot<2)await deposerCandidatureD(page,m,options);else await relireCandidaturesD(page,m,options);
    }finally{await context.close();}
  }
  expect(refus).toEqual([]);simulation.verifierBornes();
  expect(state.candidatures).toHaveLength(2);
  expect(state.candidatures.every(c=>c.message===m.marker&&c.statut==='EN_ATTENTE')).toBe(true);
  expect(state.calls.filter(c=>c.name==='fn_confirmer_action_planning_v1')).toHaveLength(2);
});
