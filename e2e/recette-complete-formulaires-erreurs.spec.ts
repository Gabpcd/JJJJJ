import {test,expect} from '@playwright/test';
import {creerMissionSimulee,ids} from './helpers/recette-complete-mission';

// Déclarations et refus synthétiques : aucun paiement, litige ou email réel.
for (const {parcours,role} of [
  {parcours:'paiement',role:'ADMIN_ETABLISSEMENT'},
  {parcours:'litige',role:'ADMIN_ETABLISSEMENT'},
  {parcours:'annulation',role:'ADMIN_ETABLISSEMENT'},
  {parcours:'litige',role:'SOIGNANT'},
] as const) {
  test(`${parcours}${role==='SOIGNANT'?' soignant':''} : refus, saisie conservée, réessai et rechargement`,async({context,page},info)=>{
    const simulation=creerMissionSimulee();const {state}=simulation;
    if(parcours!=='annulation') {
      state.mission.statut='TERMINEE';state.mission.soignant_assigne_id=ids.soignant;
      state.mission.type_contrat_applique='LIBERAL';state.presence={valide_par_etablissement:true};
      simulation.simulerEmissionFacture();
    }
    await simulation.installer(context,role);
    // Capacité explicitement absente dans ce banc sans push/PWA. Le blocage
    // Playwright reste actif ; aucun avertissement de console n'est filtré.
    await context.addInitScript(()=>{
      if(!Reflect.deleteProperty(Object.getPrototypeOf(navigator),'serviceWorker') || 'serviceWorker' in navigator)
        throw new Error('La simulation exige un navigateur sans Service Worker.');
    });
    if(role==='SOIGNANT') {
      state.facture.emise_le='2026-09-30T09:00:00Z';state.facture.verification_echeance_le='2026-10-02T09:00:00Z';
      await page.route('**/rest/v1/rpc/fn_mes_factures_honoraires',route=>route.fulfill({json:[state.facture]}));
      await page.route('**/rest/v1/rpc/fn_mes_bulletins_paie',route=>route.fulfill({json:[]}));
      await page.route('**/rest/v1/rpc/fn_lister_copies_bulletins',route=>route.fulfill({json:[]}));
    }
    await page.route('https://fonts.googleapis.com/**',route=>route.fulfill({contentType:'text/css',body:''}));
    await page.route('https://js.stripe.com/**',route=>route.fulfill({contentType:'application/javascript',body:'window.Stripe = function(){ return {}; };'}));
    await page.clock.setFixedTime(new Date('2026-09-30T10:00:00Z'));
    page.setDefaultTimeout(12_000);
    const erreursConsole:string[]=[];const avertissementsConsole:string[]=[];
    page.on('console',m=>{if(m.type()==='error')erreursConsole.push(m.text());if(m.type()==='warning')avertissementsConsole.push(m.text());});
    const tentatives:Record<string,unknown>[]=[];let autorise=false;let enregistre=false;let terminer:(()=>void)|undefined;
    const refus='Impossible de traiter la demande. Vous pouvez réessayer.';
    const rpc=parcours==='paiement'?'fn_declarer_paiement_facture_soignant':parcours==='litige'?'fn_ouvrir_litige_rate_limited':'fn_annuler_mission_etab';
    const reference='RECETTE-2026-001';const detail='Une différence doit être vérifiée avant de continuer la recette.';
    await page.route(`**/rest/v1/rpc/${rpc}`,async route=>{
      tentatives.push(route.request().postDataJSON());
      if(!autorise)return route.fulfill({json:{success:false,error:refus}});
      await new Promise<void>(resolve=>{terminer=resolve;});
      expect(enregistre).toBe(false);enregistre=true;
      if(parcours==='annulation')state.mission.statut='ANNULEE_PAR_ETABLISSEMENT';
      if(role==='SOIGNANT')state.facture.statut_litige='EN_ATTENTE_LITIGE';
      return route.fulfill({json:{success:true,litige_id:'71000000-0000-4000-8000-000000000090',soignant_id:ids.soignant,mission_intitule:state.mission.intitule,indemnite_montant:0}});
    });
    // La liste après annulation demande count:exact. L'API mock utilise un
    // autre port : Content-Range doit être exposé à fetch, comme PostgREST.
    if(parcours==='annulation')await page.route('**/rest/v1/mission_creneaux?**',route=>{
      if(!route.request().headers().prefer?.includes('count=exact'))return route.fallback();
      const url=new URL(route.request().url());
      expect(route.request().method()).toBe('GET');
      expect(url.searchParams.get('mission_id')).toBe(`in.(${ids.mission})`);
      expect(url.searchParams.get('offset')).toBe('0');expect(url.searchParams.get('limit')).toBe('500');
      return route.fulfill({json:state.creneaux,headers:{'access-control-allow-origin':'*','access-control-expose-headers':'content-range','content-range':'0-0/1'}});
    });
    if(parcours==='litige')await page.route('**/rest/v1/litiges?**',route=>route.fulfill({json:enregistre?[{mission_id:ids.mission,facture_id:state.facture.id}]:[]}));
    if(parcours==='paiement')await page.route('**/rest/v1/rpc/fn_obligations_financieres',route=>{
      if(!enregistre)return route.fallback();
      return route.fulfill({json:{total_du:0,total_soignants_du:0,total_commissions_du:0,nb_missions_non_payees:0,factures_impayees:[],missions_non_payees:[],missions_non_facturees:[],paiements_soignants_confirmes:[],factures_commission_historique:[],paiements_soignants_en_attente:[{
        paiement_id:'71000000-0000-4000-8000-000000000091',mission_id:ids.mission,mission_intitule:state.mission.intitule,soignant_nom:'Camille Recette',soignant_profession:'MEDECIN',methode:'VIREMENT',reference_virement:reference,date_paiement:'2026-09-30',montant_net:640,
      }]}});
    });
    try {
      await page.goto(role==='SOIGNANT'?'/soignant/mes-gains?tab=factures':parcours==='annulation'?`/etablissement/missions/${ids.mission}`:'/etablissement/facturation');
      await page.getByRole('button',{name:role==='SOIGNANT'?/^(Erreur|Signaler une erreur)$/:parcours==='paiement'?'Déclarer un paiement':parcours==='litige'?'Contester':'Annuler',exact:true}).click();
      const dialog=page.getByRole('dialog');
      if(parcours==='paiement') {
        await dialog.locator('#declarer-reference').fill(reference);
        await dialog.locator('#declarer-attestation').check();
      }else if(parcours==='litige') {
        await expect(dialog.getByLabel('Facture concernée')).toHaveValue(state.facture.id);
        await dialog.getByRole('button',{name:'Suivant',exact:true}).click();
        await dialog.getByLabel('Décrivez précisément le problème').fill(detail);
        await dialog.getByRole('button',{name:'Suivant',exact:true}).click();
      }else {
        await expect(dialog.getByText('La mission ne sera plus proposée aux soignants.',{exact:true})).toBeVisible();
        // Une modale chargée depuis une page lazy ne doit pas précharger
        // à nouveau le script d'entrée qui a déjà lancé cette page.
        expect(await page.evaluate(()=>{
          const entrees=new Set([...document.querySelectorAll<HTMLScriptElement>('script[type="module"][src]')].map(script=>script.src));
          return [...document.querySelectorAll<HTMLLinkElement>('link[rel="modulepreload"]')].filter(link=>entrees.has(link.href)).map(link=>link.href);
        })).toEqual([]);
        await expect(dialog.getByText(/notifié immédiatement|push \+ email/)).toHaveCount(0);
        await dialog.getByLabel(/Motif de l'annulation/).selectOption('AUTRE');
        await dialog.getByLabel(/Explication détaillée/).fill(detail);
      }
      if(parcours==='litige')await expect(dialog.getByText('Le suivi du litige est disponible dans l’app.',{exact:true})).toBeVisible();
      const envoyer=dialog.getByRole('button',{name:parcours==='paiement'?'Valider la déclaration':parcours==='litige'?"Confirmer l'ouverture du litige":'Confirmer l’annulation',exact:true});
      await envoyer.click();
      await expect(page.getByText(refus,{exact:true})).toBeVisible();
      expect(enregistre).toBe(false);expect(tentatives).toHaveLength(1);expect(state.emails).toEqual([]);
      await expect(dialog).toHaveCSS('opacity','1');
      await page.screenshot({path:info.outputPath(`${parcours}-refus-inline.png`)});
      await expect(dialog.getByRole('alert')).toHaveText(refus);
      await expect(page.getByRole('button',{name:'Close toast',exact:true})).toHaveCount(0);
      await expect(page.getByRole('button',{name:'Fermer la notification',exact:true})).toHaveCount(0);
      await expect(envoyer).toBeEnabled();
      if(parcours==='paiement') {
        await expect(dialog.locator('#declarer-reference')).toHaveValue(reference);
        await expect(dialog.locator('#declarer-montant')).toHaveValue('640.00');
        await expect(dialog.locator('#declarer-date')).toHaveValue('2026-09-30');
        await expect(dialog.locator('#declarer-attestation')).toBeChecked();
      }else if(parcours==='litige') {
        await dialog.getByRole('button',{name:'Précédent',exact:true}).click();
        await expect(dialog.getByLabel('Décrivez précisément le problème')).toHaveValue(detail);
        await dialog.getByRole('button',{name:'Précédent',exact:true}).click();
        await expect(dialog.getByLabel('Facture concernée')).toHaveValue(state.facture.id);
        await expect(dialog.locator('input[value="PAIEMENT"]')).toBeChecked();
        await dialog.getByRole('button',{name:'Suivant',exact:true}).click();
        await dialog.getByRole('button',{name:'Suivant',exact:true}).click();
      }else {
        await expect(dialog.getByLabel(/Motif de l'annulation/)).toHaveValue('AUTRE');
        await expect(dialog.getByLabel(/Explication détaillée/)).toHaveValue(detail);
      }
      autorise=true;
      await envoyer.click();
      await expect.poll(()=>tentatives.length).toBe(2);
      const occupé=dialog.getByRole('button',{name:parcours==='paiement'?'Envoi…':parcours==='litige'?"Confirmer l'ouverture du litige":'Confirmer l’annulation',exact:true});
      await expect(occupé).toBeDisabled();
      await dialog.getByRole('button',{name:'Fermer',exact:true}).click();
      await expect(dialog).toBeVisible();expect(enregistre).toBe(false);expect(state.emails).toEqual([]);
      terminer!();
      await expect(dialog).toBeHidden();expect(tentatives).toHaveLength(2);
      const payload=parcours==='paiement'?{p_facture_honoraire_id:state.facture.id,p_montant:640,p_methode:'VIREMENT',p_reference:reference,p_date_paiement:'2026-09-30',p_attestation_sur_l_honneur:true}:parcours==='litige'?{p_mission_id:ids.mission,p_type_litige:'DESACCORD_MONTANT_FACTURE',p_motif:`[PAIEMENT] ${detail}`,p_facture_id:state.facture.id}:{p_mission_id:ids.mission,p_motif_categorie:'AUTRE',p_texte_libre:detail};
      for(const tentative of tentatives)expect(tentative).toEqual(payload);
      await expect(page.getByText(parcours==='paiement'?'Paiement déclaré — en attente de confirmation du soignant':parcours==='litige'?"Litige ouvert. Vous pouvez suivre son traitement dans l’app.":'Mission annulée.',{exact:true})).toBeVisible();
      const resultat=role==='SOIGNANT'?page.getByText('Correction en cours',{exact:true}):parcours==='paiement'?page.getByText('Paiements en attente (1)',{exact:true}):parcours==='litige'?page.getByText('Litige en cours sur un paiement',{exact:true}):page.getByText('Annulée',{exact:true});
      await expect(resultat).toBeVisible();
      await page.reload();
      await expect(resultat).toBeVisible();expect(tentatives).toHaveLength(2);
      if(parcours==='paiement')expect(state.emails).toHaveLength(1);else expect(state.emails).toEqual([]);
      await resultat.scrollIntoViewIfNeeded();
      await page.screenshot({path:info.outputPath(`${parcours}-apres-reload.png`)});
      expect(state.unknown).toEqual([]);expect(state.errors).toEqual([]);expect(state.external).toEqual([]);expect(erreursConsole).toEqual([]);expect(avertissementsConsole).toEqual([]);
    }finally{
      terminer?.();
      await info.attach('preuve-formulaire',{body:JSON.stringify({parcours,role,rpc,tentatives,autorise,enregistre,emails:state.emails,unknown:state.unknown,errors:state.errors,external:state.external,erreursConsole,avertissementsConsole}),contentType:'application/json'});
    }
  });
}
