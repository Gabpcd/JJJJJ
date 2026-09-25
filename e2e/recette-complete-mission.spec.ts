import {test,expect} from '@playwright/test';
import {creerMissionSimulee,ids,now,preuveMission} from './helpers/recette-complete-mission';

test('mission libérale : candidature, deux signatures, pauses, validation et facture simulée',async({browser,context,page},info)=>{
  const simulation=creerMissionSimulee();const {state}=simulation;
  page.setDefaultTimeout(12_000);
  await simulation.installer(context,'SOIGNANT');
  await page.clock.setFixedTime(new Date(now));
  const etabContext=await browser.newContext({...info.project.use});
  await simulation.installer(etabContext,'ADMIN_ETABLISSEMENT');
  const etab=await etabContext.newPage();etab.setDefaultTimeout(12_000);await etab.clock.setFixedTime(new Date(now));
  try {
    await page.goto(`/soignant/missions/${ids.mission}`);
    await expect(page.getByRole('heading',{name:state.mission.intitule,exact:true})).toBeVisible();
    await expect(page.getByRole('button',{name:/Vérifier et postuler/})).toBeEnabled();
    await preuveMission(page,info,'01-mission-avant-candidature');
    await page.getByRole('button',{name:/Vérifier et postuler/}).click();
    await page.getByRole('button',{name:'Envoyer ma candidature',exact:true}).dblclick();
    await expect(page.getByText('✅ Candidature envoyée — En attente de réponse',{exact:true})).toBeVisible();
    await expect(page.getByRole('dialog',{name:'Vérifie ton engagement'})).toBeHidden();
    expect(state.calls.filter(c=>c.name==='fn_confirmer_action_planning_v1')).toHaveLength(1);
    expect(state.calls.find(c=>c.name==='fn_confirmer_action_planning_v1')?.body).toMatchObject({
      p_mission_id:ids.mission,p_action:'POSTULER',
      p_creneaux_confirmes:[{debut:state.mission.debut_le,fin:state.mission.fin_le}],
    });
    expect(state.candidature.statut).toBe('EN_ATTENTE');
    await preuveMission(page,info,'02-candidature-envoyee');

    await etab.goto(`/etablissement/missions/${ids.mission}`);
    await expect(etab.getByRole('heading',{name:'Candidatures (1)',exact:true})).toBeVisible();
    await etab.getByRole('button',{name:'Accepter cette candidature',exact:true}).click();
    await etab.getByRole('button',{name:'Confirmer et assigner',exact:true}).click();
    await expect.poll(()=>state.contratCree).toBe(true);
    expect(state.mission.statut).toBe('ASSIGNEE');
    expect(state.candidature.statut).toBe('ACCEPTEE');
    expect(state.calls.find(c=>c.name==='fn_traiter_candidature_planning_v1')?.body).toMatchObject({
      p_candidature_id:ids.candidature,p_decision:'ACCEPTEE',
      p_creneaux_confirmes:[{debut:state.mission.debut_le,fin:state.mission.fin_le}],
    });
    await preuveMission(etab,info,'03-candidature-acceptee');

    for (const [acteur,role] of [[page,'soignant'],[etab,'etablissement']] as const) {
      if(role==='etablissement') await acteur.getByRole('button',{name:'Ouvrir et signer le contrat',exact:true}).click();
      else await acteur.goto(`/contrat/${ids.contrat}`);
      await expect(acteur.getByRole('heading',{name:'Contrat SIM-2026-0001',exact:true})).toBeVisible();
      await expect(acteur.getByText(/8 heures à 80,00 €, soit 640,00 €/)).toBeVisible();
      const sms=acteur.getByRole('button',{name:'Recevoir le code SMS pour signer',exact:true});
      await expect(sms).toBeDisabled();
      await acteur.getByRole('checkbox',{name:/J'ai lu l'intégralité du contrat/}).check();
      await sms.click();
      await acteur.getByRole('textbox',{name:'Code SMS à 6 chiffres'}).fill('123456');
      await acteur.getByRole('button',{name:'Signer',exact:true}).click();
      await expect.poll(()=>state.contrat['signature_'+role]).toBe(true);
      await expect(acteur.getByText(role==='soignant'?/Soignant\(e\) : ✅ Signé/:/Établissement : ✅ Signé/)).toBeVisible();
      await preuveMission(acteur,info,'04-signature-'+role);
    }
    expect(state.signatures).toHaveLength(2);
    expect(state.contrat.statut).toBe('SIGNE_COMPLET');
    await etab.goto(`/contrat/${ids.contrat}/certificat`);
    await expect(etab.getByText('✓ Code SMS vérifié',{exact:true})).toHaveCount(2);
    await preuveMission(etab,info,'05-certificat-deux-signatures');
    const telechargement=etab.waitForEvent('download');
    await etab.getByRole('button',{name:'Télécharger PDF',exact:true}).click();
    const certificat=await telechargement;
    expect(certificat.suggestedFilename()).toBe('certificat-signature-SIM-2026-0001.pdf');
    await certificat.saveAs(info.outputPath('certificat-signature-simulation.pdf'));
    await info.attach('certificat-pdf',{path:info.outputPath('certificat-signature-simulation.pdf'),contentType:'application/pdf'});

    await page.goto('/soignant/presences?tab=aujourdhui');
    await expect(page.getByRole('textbox',{name:'Code de pointage à 6 chiffres'})).toBeVisible();
    await page.getByRole('textbox',{name:'Code de pointage à 6 chiffres'}).fill('000000');
    await page.getByRole('button',{name:'Pointer mon arrivée',exact:true}).click();
    await expect(page.getByText('Code de pointage invalide ou expiré. Demande le code actuel à l’établissement.',{exact:true})).toBeVisible();
    expect(state.segments).toHaveLength(0);
    const scans=[
      ['2026-09-24T07:00:00Z','Pointer mon arrivée'],
      ['2026-09-24T11:00:00Z','Pointer mon départ / pause'],
      ['2026-09-24T11:30:00Z','Pointer mon arrivée / ma reprise'],
      ['2026-09-24T15:00:00Z','Pointer mon départ / pause'],
    ] as const;
    for (const [time,action] of scans) {
      await page.clock.setFixedTime(new Date(time));state.scanTimes.push(time);
      await page.getByRole('textbox',{name:'Code de pointage à 6 chiffres'}).fill('654321');
      await page.getByRole('button',{name:action,exact:true}).click();
      await expect.poll(()=>state.scanTimes.length).toBe(0);
      if(time==='2026-09-24T15:00:00Z') await page.getByRole('button',{name:'Plus tard',exact:true}).click();
      await expect(page.getByRole('textbox',{name:'Code de pointage à 6 chiffres'})).toHaveValue('');
    }
    expect(state.segments).toHaveLength(2);
    expect(state.segments.map(s=>[s.debut,s.fin])).toEqual([
      ['2026-09-24T07:00:00Z','2026-09-24T11:00:00Z'],['2026-09-24T11:30:00Z','2026-09-24T15:00:00Z'],
    ]);
    await preuveMission(page,info,'06-pointages-pause-reprise-fin');

    await etab.clock.setFixedTime(new Date('2026-09-24T15:15:00Z'));
    await etab.goto('/etablissement/presences?tab=a_valider');
    await expect(etab.getByRole('tab',{name:'À valider: 1 présences',exact:true})).toBeVisible();
    // La vue carte expose directement les étoiles ; la table ouvre le dialogue de notation.
    if(await etab.getByRole('button',{name:'Valider',exact:true}).count()) await etab.getByRole('button',{name:'Valider',exact:true}).click();
    await etab.getByRole('radio',{name:'5 étoiles',exact:true}).click();
    await etab.getByRole('button',{name:'Valider et noter',exact:true}).click();
    await expect.poll(()=>state.presence.valide_par_etablissement).toBe(true);
    await expect(etab.getByRole('tab',{name:'À valider: 0 présences',exact:true})).toBeVisible();
    expect(state.notes).toHaveLength(1);
    await preuveMission(etab,info,'07-presence-validee');
    await etab.goto(`/etablissement/missions/${ids.mission}`);
    await etab.getByRole('button',{name:'Terminer la mission',exact:true}).first().click();
    await etab.getByRole('dialog').getByRole('button',{name:'Terminer la mission',exact:true}).click();
    await expect.poll(()=>state.mission.statut).toBe('TERMINEE');
    simulation.simulerEmissionFacture();
    await page.goto('/soignant/mes-gains?tab=factures');
    await expect(page.getByText('SIM-HON-2026-0001',{exact:true})).toBeVisible();
    await expect(page.getByText('640,00 €',{exact:true}).first()).toBeVisible();
    await preuveMission(page,info,'08-facture-honoraires-emise');
    await page.getByRole('tab',{name:'Aperçu',exact:true}).click();
    await expect(page.getByText('640,00 €',{exact:true}).first()).toBeVisible();
    await preuveMission(page,info,'09-revenus-attendus');
    await etab.goto('/etablissement/facturation');
    await expect(etab.getByText('SIM-HON-2026-0001',{exact:true})).toBeVisible();
    await expect(etab.getByText('640,00 €',{exact:true}).first()).toBeVisible();
    await expect(etab.getByText('Contrat libéral',{exact:true})).toBeVisible();
    await preuveMission(etab,info,'10-facturation-etablissement');
    expect(state.unknown).toEqual([]);
    expect(state.errors).toEqual([]);
  } finally {
    await info.attach('journal-simulation',{body:JSON.stringify(state,null,2),contentType:'application/json'});
    await etabContext.close();
  }
});

test('signature OTP : session expirée, code incorrect, code expiré et reprise sans double signature',async({context,page},info)=>{
  const {state,installer}=creerMissionSimulee();
  state.contratCree=true;state.mission.statut='ASSIGNEE';state.mission.soignant_assigne_id=ids.soignant;
  await installer(context,'SOIGNANT');await page.clock.setFixedTime(new Date(now));page.setDefaultTimeout(12_000);
  try {
    await page.goto(`/contrat/${ids.contrat}`);
    const sms=page.getByRole('button',{name:'Recevoir le code SMS pour signer',exact:true});
    await page.getByRole('checkbox',{name:/J'ai lu l'intégralité du contrat/}).check();
    state.otpError='NON_AUTHENTIFIE';
    await sms.click();
    await expect(page.getByText('Session expirée. Reconnectez-vous puis réessayez.',{exact:true})).toBeVisible();
    expect(state.sms).toHaveLength(0);expect(state.signatures).toHaveLength(0);
    await preuveMission(page,info,'otp-session-expiree');
    // Restauration de session simulée, puis nouvelle tentative réelle par le même bouton UI.
    await page.reload();
    await page.getByRole('checkbox',{name:/J'ai lu l'intégralité du contrat/}).check();
    state.failOnce='fn_envoyer_otp_signature';await sms.click();
    await expect(page.getByText('Une erreur est survenue. Veuillez réessayer.',{exact:true})).toBeVisible();
    await sms.click();
    const code=page.getByRole('textbox',{name:'Code SMS à 6 chiffres'});
    const signer=page.getByRole('button',{name:'Signer',exact:true});
    await code.fill('000000');await signer.click();
    await expect(page.getByText('Code incorrect. 4 tentatives restantes.',{exact:true})).toBeVisible();
    expect(state.signatures).toHaveLength(0);
    state.otpError='OTP_EXPIRE';await code.fill('123456');await signer.click();
    await expect(page.getByText('Le code SMS a expiré (10 min). Demandez un nouveau code.',{exact:true})).toBeVisible();
    expect(state.signatures).toHaveLength(0);
    await preuveMission(page,info,'otp-invalide-expire');
    await page.getByRole('button',{name:'Renvoyer le code',exact:true}).click();
    await expect(code).toHaveValue('');
    await code.fill('123456');await signer.dblclick();
    await expect(page.getByText(/Soignant\(e\) : ✅ Signé/)).toBeVisible();
    expect(state.signatures).toHaveLength(1);
    expect(state.contrat.statut).toBe('SIGNE_SOIGNANT');
    expect(state.calls.filter(c=>c.name==='fn_signer_contrat_otp')).toHaveLength(3);
    await preuveMission(page,info,'otp-reprise-signature-unique');
    expect(state.unknown).toEqual([]);expect(state.errors).toEqual([]);
  } finally {
    await info.attach('journal-simulation',{body:JSON.stringify(state,null,2),contentType:'application/json'});
  }
});

test('mission salariée : DPAE fictive, deux signatures et certificat',async({browser,context,page},info)=>{
  const {state,installer}=creerMissionSimulee();
  state.contratCree=true;state.mission.statut='ASSIGNEE';state.mission.soignant_assigne_id=ids.soignant;
  state.mission.type_contrat_applique='SALARIE';state.mission.type_contrat_recherche='SALARIE';
  state.mission.type_paiement_soignant='BULLETIN_PAIE';state.contrat.type_contrat='SALARIE';
  // Le régime contractuel salarié doit primer sur le profil libéral du professionnel.
  state.contrat.contenu_html='<article><h2>Contrat salarié fictif de recette</h2><p>Camille Recette — Clinique Simulation</p><p>24 septembre 2026 : 09:00 à 17:00 — 8 heures, brut prévisionnel 640,00 €.</p></article>';
  await installer(context,'ADMIN_ETABLISSEMENT');page.setDefaultTimeout(12_000);
  await page.clock.setFixedTime(new Date(now));
  const soignantContext=await browser.newContext({...info.project.use});
  await installer(soignantContext,'SOIGNANT');const soignant=await soignantContext.newPage();
  soignant.setDefaultTimeout(12_000);await soignant.clock.setFixedTime(new Date(now));
  try {
    await page.goto(`/contrat/${ids.contrat}`);
    await expect(page.getByText('DPAE obligatoire — Mission salariée',{exact:true})).toBeVisible();
    await page.getByRole('button',{name:'Préparer les données DPAE',exact:true}).click();
    await expect(page.getByRole('link',{name:'Transmettre sur Net-Entreprises',exact:true})).toHaveAttribute('href','https://www.net-entreprises.fr/declaration-prealable-embauche/');
    const enregistrer=page.getByRole('button',{name:'Enregistrer le numéro DPAE',exact:true});
    await expect(enregistrer).toBeDisabled();
    const numero=page.getByRole('textbox',{name:/Après transmission par vos soins/});
    await numero.fill('court!');await enregistrer.click();
    await expect(page.getByText('Format invalide : 8 à 30 caractères alphanumériques (lettres et chiffres) requis. Aucun espace ni ponctuation.',{exact:true})).toBeVisible();
    expect(state.contrat.dpae_numero).toBeUndefined();
    await numero.fill('SIM202600001');await enregistrer.click();
    await expect(page.getByText('DPAE déclarée',{exact:true})).toBeVisible();
    expect(state.contrat.dpae_numero).toBe('SIM202600001');
    expect(state.emails).toHaveLength(1);
    await preuveMission(page,info,'salarie-dpae-enregistree');
    for(const acteur of [page,soignant]) {
      await acteur.goto(`/contrat/${ids.contrat}`);
      await acteur.getByRole('checkbox',{name:/J'ai lu l'intégralité du contrat/}).check();
      await acteur.getByRole('button',{name:'Recevoir le code SMS pour signer',exact:true}).click();
      await acteur.getByRole('textbox',{name:'Code SMS à 6 chiffres'}).fill('123456');
      await acteur.getByRole('button',{name:'Signer',exact:true}).click();
      await expect(acteur.getByText('✅ Vous avez déjà signé ce contrat',{exact:true})).toBeVisible();
    }
    expect(state.contrat.statut).toBe('SIGNE_COMPLET');expect(state.signatures).toHaveLength(2);
    await page.goto(`/contrat/${ids.contrat}/certificat`);
    await expect(page.getByText('✓ Code SMS vérifié',{exact:true})).toHaveCount(2);
    await preuveMission(page,info,'salarie-certificat-deux-signatures');
    expect(state.unknown).toEqual([]);expect(state.errors).toEqual([]);
  } finally {
    await info.attach('journal-simulation',{body:JSON.stringify(state,null,2),contentType:'application/json'});
    await soignantContext.close();
  }
});
