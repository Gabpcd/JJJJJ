import {test,expect} from '@playwright/test';
import {creerMissionSimulee,ids} from './helpers/recette-complete-mission';

// Réponses synthétiques uniquement. Les autorisations et la publication réelle
// sont vérifiées par notation-reverse-transactionnelle.test.sql sous ROLLBACK.
for(const role of ['ADMIN_ETABLISSEMENT','SOIGNANT'] as const) {
  test(`notation ${role} : refus explicite, réessai autorisé et rechargement`,async({context,page},info)=>{
    const simulation=creerMissionSimulee();const {state}=simulation;
    state.mission.statut='TERMINEE';state.mission.soignant_assigne_id=ids.soignant;
    state.mission.type_contrat_applique='LIBERAL';
    await simulation.installer(context,role);
    // Police externe remplacée par une CSS locale vide : aucun appel Google.
    await page.route('https://fonts.googleapis.com/**',route=>route.fulfill({contentType:'text/css',body:''}));
    await page.clock.setFixedTime(new Date('2026-09-30T10:00:00Z'));
    page.setDefaultTimeout(12_000);
    const erreursConsole:string[]=[];
    page.on('console',message=>{if(message.type()==='error')erreursConsole.push(message.text());});
    let autorise=false;let enregistre=false;
    const tentatives:Record<string,unknown>[]=[];
    const sens=role==='SOIGNANT'?'SOIGNANT_VERS_ETAB':'ETAB_VERS_SOIGNANT';
    const refus='Accès non autorisé à cette mission.';
    await page.route('**/rest/v1/rpc/fn_creer_notation_mission',async route=>{
      const body=route.request().postDataJSON();tentatives.push(body);
      if(!autorise)return route.fulfill({json:{success:false,error:refus}});
      expect(enregistre).toBe(false);
      enregistre=true;
      return route.fulfill({json:{success:true,id:'71000000-0000-4000-8000-000000000057',tardive:false}});
    });
    await page.route('**/rest/v1/rpc/fn_score_etab_public',route=>route.fulfill({json:null}));
    await page.route('**/rest/v1/rpc/fn_user_id_pour_etablissement',route=>route.fulfill({json:ids.etablissement}));
    await page.route('**/rest/v1/notations_missions?**',route=>route.fulfill({
      json:enregistre?{id:'71000000-0000-4000-8000-000000000057'}:null,
    }));
    await page.route('**/rest/v1/rpc/fn_lister_missions_a_noter_etab',route=>route.fulfill({json:{success:true,missions:enregistre?[]:[{
      mission_id:ids.mission,intitule:state.mission.intitule,debut_le:state.mission.debut_le,fin_le:state.mission.fin_le,
      soignant_id:ids.soignant,soignant_prenom:state.soignant.prenom,soignant_nom:state.soignant.nom,
      soignant_profession:state.soignant.profession,duree_heures:8,taux_horaire_base:80,jours_depuis_fin:6,
    }]}}));
    try {
      await page.goto(role==='SOIGNANT'?`/soignant/missions/${ids.mission}`:'/etablissement/evaluations-a-faire');
      if(role==='SOIGNANT') {
        await page.getByRole('button',{name:"Noter l'établissement",exact:true}).click();
        await expect(page.getByRole('heading',{name:"Noter l'établissement",exact:true})).toBeVisible();
        const etoiles=page.getByRole('button',{name:'Note 5 étoiles',exact:true});
        await expect(etoiles).toHaveCount(4);
        for(let i=0;i<4;i++)await etoiles.nth(i).click();
      } else {
        await expect(page.getByText('1 mission à évaluer',{exact:true})).toBeVisible();
        await page.getByRole('button',{name:'Évaluer',exact:true}).click();
        await expect(page.getByRole('heading',{name:'Évaluer le soignant',exact:true})).toBeVisible();
        for(const critere of ['Ponctualité','Qualité technique','Relationnel équipe','Conformité protocole'])
          await page.getByRole('button',{name:`${critere} : 5/5`,exact:true}).click();
      }
      const envoyer=page.getByRole('button',{name:role==='SOIGNANT'?'Envoyer la notation':"Envoyer l'évaluation",exact:true});
      await envoyer.click();
      await expect(page.getByText(refus,{exact:true})).toBeVisible();
      await expect(envoyer).toBeEnabled();
      expect(enregistre).toBe(false);expect(tentatives).toHaveLength(1);
      await page.screenshot({path:info.outputPath(`notation-${role}-refus.png`)});
      // L'autorisation revenue est une réponse simulée ; le formulaire réessaie
      // explicitement, sans clic sous un toast, contournement ou double appel.
      autorise=true;
      if(role==='ADMIN_ETABLISSEMENT') {
        await expect(page.getByRole('dialog').getByRole('alert')).toHaveText(refus);
        await expect(page.getByRole('button',{name:'Fermer la notification',exact:true})).toHaveCount(0);
      } else await page.getByRole('button',{name:'Close toast',exact:true}).click();
      await envoyer.click();
      await expect(page.getByText(role==='SOIGNANT'?'Notation enregistrée ✨':'Évaluation enregistrée. Merci !',{exact:true})).toBeVisible();
      await expect(page.getByRole('dialog')).toBeHidden();
      expect(tentatives).toHaveLength(2);
      for(const payload of tentatives)expect(payload).toEqual({
        p_mission_id:ids.mission,p_sens:sens,p_critere_1:5,p_critere_2:5,p_critere_3:5,p_critere_4:5,p_commentaire:null,
      });
      const resultat=page.getByText(role==='SOIGNANT'?'Notation envoyée':'Aucune évaluation en attente',{exact:true});
      await expect(resultat).toBeVisible();
      await page.reload();
      await expect(resultat).toBeVisible();
      expect(tentatives).toHaveLength(2);
      await resultat.scrollIntoViewIfNeeded();
      await page.screenshot({path:info.outputPath(`notation-${role}-apres-reload.png`)});
      expect(state.unknown).toEqual([]);expect(state.errors).toEqual([]);expect(state.external).toEqual([]);expect(erreursConsole).toEqual([]);
    } finally {
      await info.attach('preuve-notation',{body:JSON.stringify({role,sens,autorise,enregistre,tentatives,errors:state.errors,unknown:state.unknown,external:state.external,erreursConsole}),contentType:'application/json'});
    }
  });
}
