import { test, expect } from '@playwright/test';
import { simulerSoignant, entrer, aller, recharger, preuve, sansDebordement, attendreAPI, ids, mission, simulations } from './helpers/recette-complete-soignant';

test.use({actionTimeout:15_000});

test.afterEach(async({page},info)=>{const state=simulations.get(page);if(state)await info.attach('appels-api-simules',{body:JSON.stringify(state,null,2),contentType:'application/json'});});

const groupes = [
 [ ['tableau-de-bord','Bienvenue|Bonjour|Explorer|Tes missions'], ['mon-compte','Mon compte|Mon profil'], ['profil','Profil principal'], ['recherche-missions','Explorer'], ['missions','Mes missions'] ],
 [ ['mes-documents','Mes documents'], ['disponibilites','Mes disponibilités'], ['conformite','Historique de conformité'], ['presences','Mes présences|Présences'], ['mes-gains','Revenus'] ],
 [ ['score','Mon score de fiabilité'], ['evaluations','Mes évaluations reçues'], ['prevoyance','Prévoyance'], ['attestation-heures',"Attestation d.heures travaillées"], ['passer-en-liberal','parcours libéral|profil professionnel'] ],
 [ ['exclusions','Pool urgence|Mes exclusions'], ['premium','100% gratuit pour les soignants'], ['charges','Charges sociales'], ['notifications','Notifications'], ['parrainage','Parrainage'] ],
 [ ['messagerie','Messages|Messagerie'], ['litiges','Litiges & contestations'], ['stripe-connect','Stripe Connect|Paiements'], ['classement','Classement soignants'], ['mandat-facturation','Mandat non applicable|Activité professionnelle à compléter'] ],
 [ ['parametres/notifications','Préférences de notifications'], ['parametres/recherches-sauvegardees','Mes recherches sauvegardées'], ['pool-urgence','Pool urgence'], ['mes-favoris','Mes établissements favoris'] ],
] as const;

for(const [mode,entree] of [['minimal','inscription'],['minimal','connexion'],['complet','connexion']] as const) for(const [index,routes] of groupes.entries()) {
 test(`SOIGNANT ${mode} — pages ${index+1} après ${entree}`, async({page},info)=>{
  const state=await simulerSoignant(page,mode);
  await entrer(page,entree);
  for(const [route,contenu] of routes)await test.step(route,async()=>{
   await aller(page,`/soignant/${route}`);
   await expect(page.locator('main')).toContainText(new RegExp(route==='profil'&&mode==='minimal'?'Vos informations professionnelles':contenu,'i'));
   await expect(page.locator('main')).not.toContainText(/Une erreur inattendue|Something went wrong/);
   await sansDebordement(page);
   await preuve(page,`${mode}-${entree}-${route.replaceAll('/','-')}`,info);
  });
  expect(state.unknown,'Aucun endpoint simulé implicitement').toEqual([]);
  expect(state.errors,'Aucune exception JavaScript').toEqual([]);
 });
}

test('SOIGNANT — navigation réelle des cinq onglets et sous-onglets après inscription',async({page},info)=>{
 const state=await simulerSoignant(page,'minimal');await entrer(page,'inscription');
 const items=[['Explorer','recherche-missions'],['Mes missions','missions'],['Revenus','mes-gains'],['Profil','mon-compte'],['Accueil','tableau-de-bord']];
 for(const [name,path]of items){
  await attendreAPI(page);
  const nav=page.getByRole('navigation',{name:'Navigation mobile'});
  const button=nav.getByRole('button',{name,exact:true});
  if(await button.isVisible())await button.click();else {
   const desktopName=name==='Explorer'?'Trouver une mission':name==='Profil'?'Mon compte':name;
   if(!(await page.getByRole('navigation',{name:'Sidebar',exact:true}).getByRole('button',{name:desktopName,exact:true}).isVisible())&&name==='Explorer')await page.getByRole('navigation',{name:'Sidebar',exact:true}).getByRole('button',{name:'Missions',exact:true}).click();
   await page.getByRole('navigation',{name:'Sidebar',exact:true}).getByRole('button',{name:desktopName,exact:true}).click();
  }
  await expect(page).toHaveURL(new RegExp(`/soignant/${path}$`));
  await expect(page.locator('main')).toContainText(path==='tableau-de-bord'?/Bonjour|Bonsoir/:path==='mon-compte'?'Mon profil':name);
  await preuve(page,`navigation-${path}`,info);
 }
 await aller(page,'/soignant/mes-documents');
 for(const name of ['Justificatifs','Contrats','DPAE']){await page.getByRole('tab',{name,exact:true}).click();await expect(page.getByRole('tab',{name,exact:true})).toHaveAttribute('aria-selected','true');await expect(page.getByRole('tabpanel')).toBeVisible();await preuve(page,`minimal-documents-${name}`,info);}
 let lecturesParcoursRetardees=0;
 await page.route('**/rest/v1/parcours_inscription?**',async route=>{
  lecturesParcoursRetardees++;
  // Reproduit la lecture encore en vol observée en CI, sans filtrer son erreur.
  await new Promise(resolve=>setTimeout(resolve,600));
  await route.fallback();
 });
 await aller(page,'/soignant/profil');
 await expect(page.getByRole('heading',{name:'Vos informations professionnelles'})).toBeVisible();
 // Le titre est monté avant la lecture du parcours. Un Retour immédiat annule
 // cette requête sous WebKit et produit une vraie erreur d'accès réseau.
 await attendreAPI(page);
 expect(lecturesParcoursRetardees).toBeGreaterThan(0);
 await page.getByRole('button',{name:'Retour',exact:true}).click();
 await expect(page).not.toHaveURL(/inscription\/soignant\/informations/);
 await aller(page,'/soignant/missions');
 for(const tab of await page.getByRole('tab').all()){await attendreAPI(page);await tab.click();await expect(tab).toHaveAttribute('aria-selected','true');await expect(page.getByRole('tabpanel')).toContainText(/Aucune|Aucun/);}
 await aller(page,'/soignant/presences');
 for(const tab of await page.getByRole('tab').all()){await attendreAPI(page);await tab.click();await expect(tab).toHaveAttribute('aria-selected','true');await expect(page.getByRole('tabpanel')).toContainText(/Aucune|Aucun/);}
 await aller(page,'/soignant/litiges');
 for(const tab of await page.getByRole('tab').all()){await attendreAPI(page);await tab.click();await expect(tab).toHaveAttribute('aria-selected','true');await expect(page.getByRole('tabpanel')).toBeVisible();}
 await attendreAPI(page);
 expect(state.unknown).toEqual([]);expect(state.errors).toEqual([]);
});

const aliases=[['swipe-missions','recherche-missions?vue=swipe'],['mes-matches','missions'],['documents','mes-documents?tab=justificatifs'],['planning','missions?tab=a-venir'],['calendrier-sync','missions?tab=a-venir'],['reputation','profil'],['mes-factures-honoraires','mes-gains?tab=factures'],['mes-avances','mes-gains?tab=avances'],['bulletins-paie','mes-gains?tab=bulletins'],['historique-missions','missions?tab=passees'],['fiabilite','score'],['fiabilite-legacy','score'],['parcours-3200h','passer-en-liberal'],['dpae','mes-documents?tab=dpae'],['reclamations','litiges?tab=reclamations'],['contrats','mes-documents?tab=contrats'],['parametres-complet','mon-compte'],['parametres','mon-compte']];
for(const [index,group]of [aliases.slice(0,9),aliases.slice(9)].entries())test(`SOIGNANT — alias ${index+1}`,async({page},info)=>{
 const state=await simulerSoignant(page);state.profile.type_exercice='MIXTE';state.profile.statut_liberal='ACTIF';await entrer(page,'connexion');
 for(const [route,target]of group){await aller(page,`/soignant/${route}`);await expect(page).toHaveURL(url=>url.pathname+url.search===`/soignant/${target}`);await expect(page.locator('main')).toBeVisible();await preuve(page,`alias-${route}`,info);}
 expect(state.unknown).toEqual([]);expect(state.errors).toEqual([]);
});

test('SOIGNANT — disponibilités enregistrées et rollback en cas d’erreur',async({page},info)=>{
 const state=await simulerSoignant(page);await entrer(page,'connexion');await aller(page,'/soignant/disponibilites');
 const jour=page.getByRole('button',{name:'Jour',exact:true}).and(page.locator(':not([disabled])')).first();
 await expect(jour).toHaveAttribute('aria-pressed','false');await jour.click();await expect(jour).toHaveAttribute('aria-pressed','true');
 await expect.poll(()=>state.calls.filter(c=>c.name==='fn_definir_disponibilite').length).toBe(1);
 const call=state.calls.find(c=>c.name==='fn_definir_disponibilite')!;expect(call.body).toEqual({p_jour:expect.any(String),p_creneau:'JOURNEE',p_disponible:true});
 await recharger(page);await expect(jour).toHaveAttribute('aria-pressed','true');state.failures.add('fn_definir_disponibilite');await jour.click();
 await expect(jour).toHaveAttribute('aria-pressed','true');await expect(page.getByRole('alert')).toContainText(/Erreur: Service de simulation indisponible|Une erreur est survenue. Veuillez réessayer./);
 await preuve(page,'disponibilites-rollback',info);expect(state.unknown).toEqual([]);expect(state.errors).toEqual([]);
});

test('SOIGNANT — erreurs Documents et Parrainage puis récupération',async({page},info)=>{
 const state=await simulerSoignant(page);await entrer(page,'connexion');state.failures.add('documents_soignants');await aller(page,'/soignant/mes-documents');
 await expect(page.locator('main')).toContainText(/Impossible de charger|indisponibles|indisponible/);await preuve(page,'documents-erreur',info);
 state.failures.clear();await page.getByRole('button',{name:/Réessayer/}).click();await expect(page.locator('main')).not.toContainText(/Impossible de charger/);
 state.failures.add('fn_obtenir_mes_parrainages');await aller(page,'/soignant/parrainage');await expect(page.getByRole('heading',{name:'Parrainage indisponible'})).toBeVisible();await preuve(page,'parrainage-erreur',info);
 state.failures.clear();await page.getByRole('button',{name:/Réessayer/}).click();await expect(page.getByText('RECETTE',{exact:true})).toBeVisible();
 expect(state.unknown).toEqual([]);expect(state.errors).toEqual([]);
});

test('SOIGNANT — Explorer peuplé, détail et retour sans candidature automatique',async({page},info)=>{
 const state=await simulerSoignant(page,'minimal');state.offers=true;await entrer(page,'inscription');await aller(page,'/soignant/recherche-missions');
 await expect(page.getByRole('button',{name:/Mission IDE.*Toucher pour le détail/})).toBeVisible();await preuve(page,'explorer-peuple',info,true);
 await page.getByRole('button',{name:/Mission IDE.*Toucher pour le détail/}).click();await expect(page.getByRole('dialog')).toBeVisible();
 await expect(page.getByRole('dialog')).toContainText('Dates et horaires travaillés');await info.attach('swipe-detail-aria',{body:await page.getByRole('dialog').ariaSnapshot(),contentType:'text/plain'});
 await page.getByRole('button',{name:'Fermer',exact:true}).click();await expect(page.getByRole('dialog')).not.toBeVisible();
 await page.getByRole('tab',{name:'Liste',exact:true}).click();await page.getByText(mission.intitule,{exact:true}).click();await expect(page).toHaveURL(new RegExp(`/soignant/missions/${ids.mission}$`));
 await expect(page.locator('main')).toContainText(mission.description);await preuve(page,'detail-peuple',info,true);
 await expect(page.getByRole('button',{name:/Compléter mon profil|Compléter mon dossier|Candidater/}).first()).toBeVisible();
 expect(state.calls.filter(c=>/confirmer_action|creer_candidature|enregistrer_swipe/.test(c.name))).toEqual([]);
 await page.goBack();await expect(page).toHaveURL(/recherche-missions$/);await expect(page.getByRole('tab',{name:'Liste',exact:true})).toHaveAttribute('aria-selected','true');
 expect(state.unknown).toEqual([]);expect(state.errors).toEqual([]);
});

test('SOIGNANT — profil complet, préférences, confidentialité et coordonnées',async({page},info)=>{
 const state=await simulerSoignant(page);await entrer(page,'connexion');await aller(page,'/soignant/profil');
 for(const name of ['Profil principal','Préférences','Confidentialité']){
  const tab=page.getByRole('tab',{name,exact:true});await tab.click();await expect(tab).toHaveAttribute('aria-selected','true');await expect(page.getByRole('tabpanel')).toBeVisible();await preuve(page,`complet-profil-${name}`,info);
 }
 await aller(page,'/soignant/mon-compte');await page.getByRole('button',{name:'Coordonnées bancaires',exact:true}).click();await expect(page.getByRole('heading',{name:'Paiements & coordonnées bancaires',exact:true})).toBeInViewport();
 await page.getByRole('button',{name:'Contacter Jolene',exact:true}).click();await expect(page.getByRole('dialog')).toBeVisible();await expect(page.getByRole('dialog')).toContainText(/Contacter|support|aide/i);await preuve(page,'compte-contact',info);
 expect(state.unknown).toEqual([]);expect(state.errors).toEqual([]);
});

test('SOIGNANT — justificatif présent, onglets de documents et simulations de paie',async({page},info)=>{
 const state=await simulerSoignant(page);
 state.tables.set('documents_requis_par_profession',[{id:'identite',profession:'IDE',type_document:'CARTE_IDENTITE',type_exercice_requis:'TOUS',est_critique:true}]);
 state.tables.set('documents_soignants',[{id:'document-recette',soignant_id:ids.user,type_document:'CARTE_IDENTITE',nom_fichier:'identite-recette.pdf',statut_verification:'VERIFIE',televerse_le:'2026-09-01T09:00:00Z',valide_jusqua:null,supprime_le:null}]);
 await entrer(page,'connexion');await aller(page,'/soignant/mes-documents');await expect(page.getByText(/identite-recette\.pdf/)).toBeVisible();await preuve(page,'documents-presents',info);
 for(const name of ['Contrats','DPAE']){await page.getByRole('tab',{name,exact:true}).click();await expect(page.getByRole('tabpanel')).toContainText(/Aucun contrat/);await preuve(page,`documents-complet-${name}`,info);}
 await aller(page,'/soignant/mes-gains');const brut=page.getByRole('button',{name:/Brut ·/});await expect(brut).toBeVisible();
 const b=await brut.evaluate(el=>{const card=el.getBoundingClientRect();return [...el.querySelectorAll('span,p')].map(e=>({right:e.getBoundingClientRect().right,cardRight:card.right}));});expect(b.every(v=>v.right<=v.cardRight)).toBe(true);
 await page.getByRole('tab',{name:'Simulations',exact:true}).click();await expect(page.getByRole('tabpanel')).toContainText(/Aucun|Aucune/);await preuve(page,'revenus-simulations-vide',info);
 expect(state.unknown).toEqual([]);expect(state.errors).toEqual([]);
});

test('SOIGNANT — recherches présentes : modifier, alerte, appliquer les filtres',async({page},info)=>{
 const state=await simulerSoignant(page);state.offers=true;
 state.overrides.set('fn_lister_mes_filtres_sauvegardes',[{id:'recherche-recette',nom:'Paris de jour',audience:'SOIGNANT_RECHERCHE_MISSIONS',filtres:{villeRecherche:'Paris',profession:'IDE',horaire:'JOUR'},alerte_active:false,frequence_alerte:'QUOTIDIENNE',dernier_check_le:'2026-09-23T12:00:00Z',nb_resultats_dernier_check:1}]);
 await entrer(page,'connexion');await aller(page,'/soignant/parametres/recherches-sauvegardees');await expect(page.getByRole('heading',{name:'Paris de jour'})).toBeVisible();
 await page.getByRole('button',{name:'Activer alertes',exact:true}).click();await expect(page.getByRole('button',{name:'Désactiver alertes',exact:true})).toBeVisible();
 await page.getByRole('button',{name:'Modifier',exact:true}).click();await expect(page.getByRole('dialog')).toBeVisible();await preuve(page,'recherche-modale',info);
 await page.getByRole('dialog').getByLabel('Nom').fill('Paris IDE — matin');await page.getByRole('dialog').getByRole('button',{name:/Enregistrer/}).click();await expect(page.getByRole('heading',{name:'Paris IDE — matin'})).toBeVisible();
 await page.getByRole('button',{name:'Aller à la recherche',exact:true}).click();await expect(page).toHaveURL(/soignant\/recherche-missions$/);const questionnaire=page.getByRole('dialog',{name:'5 questions pour un deck qui te ressemble'});await expect(questionnaire).toBeVisible();await questionnaire.getByRole('button',{name:'Plus tard',exact:true}).click();await expect(questionnaire).not.toBeVisible();await page.getByRole('tab',{name:'Liste',exact:true}).click();await expect(page.getByText(mission.intitule,{exact:true})).toBeVisible();
 const mutation=state.calls.find(c=>c.name==='fn_modifier_filtre_sauvegarde'&&c.body.p_nom);expect(mutation?.body.p_nom).toBe('Paris IDE — matin');
 expect(state.unknown).toEqual([]);expect(state.errors).toEqual([]);
});

test('SOIGNANT — préférences notifications enregistrées et relues',async({page},info)=>{
 const state=await simulerSoignant(page);await entrer(page,'connexion');await aller(page,'/soignant/parametres/notifications');
 const emailSwitch=page.getByRole('switch',{name:/Email/i}).first();await expect(emailSwitch).toBeChecked();await emailSwitch.click();await expect(emailSwitch).not.toBeChecked();
 await page.getByRole('button',{name:'Enregistrer',exact:true}).click();await expect(page.getByText('Préférences enregistrées',{exact:true})).toBeVisible();
 expect(state.calls.find(c=>c.name==='fn_modifier_preferences_notifications')?.body.p_canal_email).toBe(false);
 await recharger(page);await expect(emailSwitch).not.toBeChecked();await preuve(page,'notifications-preferences-relues',info);
 expect(state.unknown).toEqual([]);expect(state.errors).toEqual([]);
});

test('SOIGNANT — listes peuplées et filtres locaux notifications, classement et parrainage',async({page},info)=>{
 const state=await simulerSoignant(page);
 state.tables.set('notifications',[{id:'notification-recette',destinataire_id:ids.user,titre:'Votre document est vérifié',corps:'La pièce simulée a été examinée.',type:'DOCUMENT_VALIDE',lien:'/soignant/mes-documents',lue:false,cree_le:new Date().toISOString()}]);
 state.overrides.set('fn_top_soignants',[{id:'classement-recette',prenom:'Alice',nom:'Simulation',profession:'IDE',note_moyenne:4.8,total_missions_terminees:12,score_fiabilite:90,niveau:'OR',total_evaluations:8}]);
 state.overrides.set('fn_obtenir_mes_parrainages',{filleuls:[{filleul_id:'filleul-recette',prenom:'Noémie',cree_le:'2026-09-20T10:00:00Z',premiere_mission_le:null,statut:'INSCRIT',gmv_cumule_filleul:0,reste_gmv_avant_prime:1000,seuil_gmv:1000,seuil_atteint:false}]});
 await entrer(page,'connexion');await aller(page,'/soignant/notifications');await expect(page.getByText('Votre document est vérifié',{exact:true})).toBeVisible();
 await page.locator('main').getByRole('button',{name:'Missions',exact:true}).click();await expect(page.getByText('Votre document est vérifié',{exact:true})).not.toBeVisible();
 await page.locator('main').getByRole('button',{name:'Documents',exact:true}).click();await expect(page.getByText('Votre document est vérifié',{exact:true})).toBeVisible();await preuve(page,'notifications-peuplees-filtrees',info);
 await page.getByText('Votre document est vérifié',{exact:true}).click();await expect(page).toHaveURL(/mes-documents$/);await expect(page.getByRole('heading',{name:'Mes documents',exact:true})).toBeVisible();await preuve(page,'notification-destination-documents',info);
 await aller(page,'/soignant/classement');await expect(page.getByText(/Alice/)).toBeVisible();await page.getByLabel('Filtrer par profession').selectOption('IDE');await expect.poll(()=>state.calls.filter(c=>c.name==='fn_top_soignants').at(-1)?.body.p_profession).toBe('IDE');await preuve(page,'classement-peuple',info);
 await aller(page,'/soignant/parrainage');await expect(page.getByText('Noémie',{exact:true})).toBeVisible();await expect(page.getByText('RECETTE',{exact:true})).toBeVisible();await preuve(page,'parrainage-peuple',info);
 expect(state.unknown).toEqual([]);expect(state.errors).toEqual([]);
});

test('SOIGNANT — compte minimal déconnecté, route protégée et reconnexion',async({page},info)=>{
 const state=await simulerSoignant(page,'minimal');await entrer(page,'inscription');await aller(page,'/soignant/mon-compte');
 await page.locator('main').getByRole('button',{name:/déconnecter/i}).click();await expect(page).not.toHaveURL(/\/soignant\//);
 await aller(page,'/soignant/mes-documents');await expect(page).toHaveURL(/\/connexion/);await expect(page.getByRole('button',{name:'Se connecter',exact:true})).toBeVisible();
 await entrer(page,'connexion');await expect(page.locator('main')).toContainText(/Bonjour|Bonsoir|Explorer/);await preuve(page,'minimal-reconnexion',info);
 expect(state.calls.some(c=>c.name==='logout')).toBe(true);expect(state.unknown).toEqual([]);expect(state.errors).toEqual([]);
});

test('SOIGNANT — session expirée : retour connexion et contenu protégé absent',async({page},info)=>{
 const state=await simulerSoignant(page);await entrer(page,'connexion');state.authExpired=true;await page.evaluate(()=>{for(const storage of [sessionStorage,localStorage])for(const key of Object.keys(storage)){if(key.startsWith('sb-')&&key.endsWith('-auth-token')){const session=JSON.parse(storage.getItem(key)!);session.expires_at=Math.floor(Date.now()/1000)-3600;storage.setItem(key,JSON.stringify(session));}}});await recharger(page);
 await expect(page).toHaveURL(/\/connexion/);await expect(page.getByRole('button',{name:'Se connecter',exact:true})).toBeVisible();await expect(page.getByText('Bonjour, Camille',{exact:true})).not.toBeVisible();await preuve(page,'session-expiree',info);
 expect(state.unknown).toEqual([]);expect(state.errors).toEqual([]);
});

test('SOIGNANT — série de missions et détail des présences : sélection locale et retour',async({page},info)=>{
 const state=await simulerSoignant(page);state.offers=true;state.tables.set('missions',[{...mission,description:mission.description+` [SERIE_ID:${ids.serie}]`}]);
 await entrer(page,'connexion');await aller(page,`/soignant/missions/serie/${ids.serie}`);await expect(page.getByRole('heading',{name:mission.intitule,exact:true})).toBeVisible();
 await expect(page.locator('main')).toContainText('1 mission disponible sur 1');const selection=page.locator('main').getByRole('checkbox');await expect(selection).toBeChecked();await selection.uncheck();await expect(selection).not.toBeChecked();await preuve(page,'serie-selection-locale',info);
 expect(state.calls.some(c=>/confirmer_action|accepter_mission/.test(c.name))).toBe(false);
 state.tables.set('missions',[{...mission,statut:'ASSIGNEE',soignant_assigne_id:ids.user}]);await aller(page,`/soignant/presences/mission/${ids.mission}`);await expect(page.getByRole('heading',{name:mission.intitule,exact:true})).toBeVisible();await expect(page.locator('main')).toContainText(/Aucun créneau de travail effectif/);await preuve(page,'detail-presences-planifiees',info);
 const retour=(page.viewportSize()?.width??1440)<768?page.getByRole('banner').getByRole('button',{name:'Retour',exact:true}):page.locator('main').getByRole('button',{name:'Retour',exact:true});await retour.click();await expect(page).toHaveURL(new RegExp(`/soignant/missions/serie/${ids.serie}$`));await expect(page.getByRole('heading',{name:'Pack introuvable',exact:true})).toBeVisible();await preuve(page,'serie-devenue-vide',info);
 expect(state.unknown).toEqual([]);expect(state.errors).toEqual([]);
});

test('SOIGNANT — erreur de lecture disponibilités et conformité sans faux état vide',async({page},info)=>{
 const state=await simulerSoignant(page);await entrer(page,'connexion');state.failures.add('disponibilites_soignant');await aller(page,'/soignant/disponibilites');
 await expect(page.getByRole('alert')).toContainText('Disponibilités indisponibles');await expect(page.getByRole('button',{name:'Jour',exact:true})).toHaveCount(0);await preuve(page,'disponibilites-erreur-lecture',info);
 state.failures.clear();await page.getByRole('button',{name:'Réessayer',exact:true}).click();await expect(page.getByRole('button',{name:'Jour',exact:true}).first()).toBeVisible();
 state.failures.add('conformite_travail');await aller(page,'/soignant/conformite');await expect(page.getByRole('alert')).toContainText('Conformité indisponible');await expect(page.getByText('Aucun contrôle de conformité',{exact:true})).not.toBeVisible();await preuve(page,'conformite-erreur-lecture',info);
 state.failures.clear();await page.getByRole('button',{name:'Réessayer',exact:true}).click();await expect(page.getByText('Aucun contrôle de conformité',{exact:true})).toBeVisible();expect(state.unknown).toEqual([]);expect(state.errors).toEqual([]);
});

test('SOIGNANT — modification de bio enregistrée puis relue',async({page},info)=>{
 const state=await simulerSoignant(page);await entrer(page,'connexion');await aller(page,'/soignant/profil');await page.getByRole('tab',{name:'Préférences',exact:true}).click();
 await page.getByRole('textbox',{name:/Bio|Présentation/i}).fill('Disponibilité de simulation mise à jour.');await page.getByRole('button',{name:'Enregistrer les modifications',exact:true}).click();
 await expect(page.getByText('Profil mis à jour avec succès !',{exact:true})).toBeVisible();expect(state.profile.bio).toBe('Disponibilité de simulation mise à jour.');
 await recharger(page);await page.getByRole('tab',{name:'Préférences',exact:true}).click();await expect(page.getByRole('textbox',{name:/Bio|Présentation/i})).toHaveValue('Disponibilité de simulation mise à jour.');await preuve(page,'profil-bio-modifiee',info);expect(state.unknown).toEqual([]);expect(state.errors).toEqual([]);
});

test('SOIGNANT — document : choix fichier, échec téléversement, annulation et suppression simulée',async({page},info)=>{
 const state=await simulerSoignant(page);state.profile.rpps_verifie=false;
 state.tables.set('documents_requis_par_profession',[{id:'identite',profession:'IDE',type_document:'CARTE_IDENTITE',type_exercice_requis:'TOUS',est_critique:true}]);
 state.tables.set('documents_soignants',[{id:'document-recette',soignant_id:ids.user,type_document:'CARTE_IDENTITE',nom_fichier:'identite-recette.pdf',statut_verification:'VERIFIE',televerse_le:'2026-09-01T09:00:00Z',valide_jusqua:null,supprime_le:null}]);
 await entrer(page,'connexion');await aller(page,'/soignant/mes-documents');await expect(page.getByText(/identite-recette\.pdf/)).toBeVisible();await page.getByRole('button',{name:'Remplacer',exact:true}).click();await expect(page.getByRole('dialog')).toBeVisible();
 const fichier={name:'simulation.pdf',mimeType:'application/pdf',buffer:Buffer.from('%PDF-1.4\n1 0 obj\n<< /Type /Catalog >>\nendobj\ntrailer\n<< /Root 1 0 R >>\n%%EOF')};
 await page.getByRole('dialog').locator('input[type=file][accept^="application/pdf"]').setInputFiles(fichier);await expect(page.getByRole('dialog')).toContainText('simulation.pdf');state.failures.add('storage_upload');
 await page.getByRole('dialog').getByRole('button',{name:'Téléverser',exact:true}).click();await expect(page.getByText(/Téléversement impossible/)).toBeVisible();expect(state.calls.some(c=>c.name==='fn_remplacer_document_soignant')).toBe(false);await preuve(page,'documents-upload-erreur',info);
 await page.getByRole('button',{name:'Fermer la fenêtre de téléversement'}).click();await expect(page.getByText(/identite-recette\.pdf/)).toBeVisible();
 await page.getByRole('button',{name:'Supprimer',exact:true}).click();await expect(page.getByRole('dialog',{name:'Supprimer ce document ?'})).toBeVisible();await page.getByRole('dialog').getByRole('button',{name:'Annuler',exact:true}).click();await expect(page.getByText(/identite-recette\.pdf/)).toBeVisible();
 await page.getByRole('button',{name:'Supprimer',exact:true}).click();await page.getByRole('dialog').getByRole('button',{name:'Supprimer',exact:true}).click();await expect(page.getByText('Document supprimé.',{exact:true})).toBeVisible();await expect(page.getByText(/identite-recette\.pdf/)).not.toBeVisible();
 expect(state.tables.get('documents_soignants')![0].supprime_le).toEqual(expect.any(String));expect(state.unknown).toEqual([]);expect(state.errors).toEqual([]);
});

test('SOIGNANT — conformité peuplée : export copié et refus presse-papier',async({page},info)=>{
 const state=await simulerSoignant(page);state.tables.set('conformite_travail',[{id:'controle-recette',soignant_id:ids.user,type_controle:'REPOS_11H',resultat:'CONFORME',controle_le:new Date().toISOString(),motif_derogation:null,missions:{intitule:mission.intitule,debut_le:mission.debut_le,fin_le:mission.fin_le,etablissement_id:ids.etab}}]);
 await page.addInitScript(()=>{Object.defineProperty(navigator,'clipboard',{configurable:true,value:{writeText:async(text:string)=>{(window as any).__copieRecette=text;}}});});
 await entrer(page,'connexion');await aller(page,'/soignant/conformite');await expect(page.locator('main')).toContainText(mission.intitule);await page.getByRole('button',{name:'Exporter',exact:true}).click();await expect(page.getByText('Historique copié dans le presse-papier',{exact:true})).toBeVisible();
 expect(await page.evaluate(()=>(window as any).__copieRecette)).toContain(`REPOS_11H | CONFORME | ${mission.intitule}`);
 await page.evaluate(()=>{navigator.clipboard.writeText=async()=>{throw new Error('Permission refusée pour la simulation');};});await page.getByRole('button',{name:'Exporter',exact:true}).click();await expect(page.getByText('Impossible de copier l’historique. Réessayez.',{exact:true})).toBeVisible();await preuve(page,'conformite-export-refuse',info);expect(state.unknown).toEqual([]);expect(state.errors).toEqual([]);
});

test('SOIGNANT — favoris présents : détail et retrait confirmé',async({page},info)=>{
 const state=await simulerSoignant(page);state.offers=true;state.tables.set('missions_sauvegardees',[{mission_id:ids.mission,missions:mission,cree_le:new Date().toISOString()}]);
 state.overrides.set('fn_mes_favoris_etablissements',[{etablissement_id:ids.etab,nom:'Résidence Camille — simulation',type_etablissement:'EHPAD',ville:'Paris',nb_missions_ouvertes:1,cree_le:new Date().toISOString()}]);
 await entrer(page,'connexion');await aller(page,'/soignant/mes-favoris');await expect(page.getByRole('heading',{name:/Missions sauvegardées \(1\)/})).toBeVisible();await page.getByRole('button',{name: new RegExp(mission.intitule)}).click();await expect(page).toHaveURL(new RegExp(`/missions/${ids.mission}$`));await page.goBack();await expect(page.getByText(mission.intitule,{exact:true})).toBeVisible();
 await page.locator('section').filter({has:page.getByRole('heading',{name:/Missions sauvegardées/})}).getByRole('button',{name:'Retirer',exact:true}).click();await expect(page.getByText('Mission retirée de tes favoris',{exact:true})).toBeVisible();await expect(page.getByText(mission.intitule,{exact:true})).not.toBeVisible();
 await preuve(page,'favoris-mission-retiree',info);expect(state.tables.get('missions_sauvegardees')).toEqual([]);
 page.once('dialog',dialog=>dialog.accept());await page.getByRole('article').getByRole('button',{name:'Retirer',exact:true}).click();await expect(page.getByText('Aucun établissement favori',{exact:true})).toBeVisible();expect(state.overrides.get('fn_mes_favoris_etablissements')).toEqual([]);expect(state.unknown).toEqual([]);expect(state.errors).toEqual([]);
});

test('SOIGNANT — simulateur prévoyance, périodes attestation et exclusions reçues',async({page},info)=>{
 const state=await simulerSoignant(page);await entrer(page,'connexion');await aller(page,'/soignant/prevoyance');await page.getByLabel('Ton revenu mensuel net (€)').fill('5000');await page.getByLabel('Niveau de couverture',{exact:true}).selectOption('OR');await expect(page.getByText(/4\s*000\s*€/)).toBeVisible();await preuve(page,'prevoyance-simulation',info);
 await aller(page,'/soignant/attestation-heures');for(const name of ['Ce mois','Mois dernier','Ce trimestre','Cette année']){await page.getByRole('button',{name,exact:true}).click();await expect(page.getByRole('button',{name:"Générer l'attestation",exact:true})).toBeDisabled();}await preuve(page,'attestation-periode-vide',info);
 await aller(page,'/soignant/exclusions');await page.getByRole('button',{name:'Reçues (0)',exact:true}).click();await expect(page.getByText('Aucune exclusion reçue',{exact:true})).toBeVisible();await page.getByRole('button',{name:'Envoyées (0)',exact:true}).click();await expect(page.getByText('Aucune exclusion',{exact:true})).toBeVisible();
 expect(state.unknown).toEqual([]);expect(state.errors).toEqual([]);
});

test('SOIGNANT — pack indisponible503 puis retour aux missions, et lecture sans profil',async({page},info)=>{
 const state=await simulerSoignant(page,'minimal');await entrer(page,'inscription');state.failures.add('missions');await aller(page,`/soignant/missions/serie/${ids.serie}`);
 await expect(page.getByRole('alert')).toContainText('Pack indisponible');await expect(page.getByText('Pack introuvable',{exact:true})).not.toBeVisible();await preuve(page,'serie-erreur503',info);
 state.failures.clear();state.offers=true;state.tables.set('missions',[{...mission,description:mission.description+` [SERIE_ID:${ids.serie}]`}]);await page.getByRole('button',{name:'Réessayer',exact:true}).click();await expect(page.getByRole('heading',{name:mission.intitule,exact:true})).toBeVisible();await expect(page.getByRole('button',{name:'Préparer mon profil pour candidater',exact:true})).toBeVisible();await expect(page.getByRole('button',{name:/Accepter la sélection/})).toHaveCount(0);await preuve(page,'serie-minimal-lecture',info);expect(state.calls.some(c=>c.name==='fn_confirmer_action_planning_v1')).toBe(false);expect(state.unknown).toEqual([]);expect(state.errors).toEqual([]);
});

test('SOIGNANT MIXTE — factures, charges sans activité, mandat et Stripe en compte de test',async({page},info)=>{
 const state=await simulerSoignant(page);state.profile.type_exercice='MIXTE';state.profile.statut_liberal='ACTIF';await entrer(page,'connexion');
 await aller(page,'/soignant/mes-gains');await page.getByRole('tab',{name:'Factures',exact:true}).click();await expect(page.getByRole('tabpanel')).toContainText(/Aucune facture/);await preuve(page,'mixte-factures-vides',info);
 await aller(page,'/soignant/charges');await expect(page.getByRole('heading',{name:'Mes charges sociales',exact:true})).toBeVisible();await expect(page.getByText('Tes charges apparaîtront ici',{exact:true})).toBeVisible();await expect(page.getByRole('heading',{name:'Ton régime fiscal',exact:true})).toBeVisible();await preuve(page,'mixte-charges-vides',info);
 await aller(page,'/soignant/stripe-connect');await expect(page.getByRole('status')).toContainText('Stripe désactivé sur ce compte de test');await expect(page.getByRole('button',{name:'Connecter mon compte bancaire',exact:true})).toHaveCount(0);await preuve(page,'mixte-stripe-test',info);
 await aller(page,'/soignant/mandat-facturation');await expect(page.getByRole('heading',{name:'Mandat de facturation',exact:true})).toBeVisible();await expect(page.getByRole('main')).toHaveCount(1);await expect(page.getByRole('button',{name:'Signer électroniquement le mandat',exact:true})).toBeDisabled();await sansDebordement(page);await preuve(page,'mixte-mandat-lecture',info);
 await page.getByRole('button',{name:'Fermer',exact:true}).click();await expect(page).toHaveURL(/stripe-connect$/);
 expect(state.calls.some(c=>/signer_mandat|stripe-connect-onboarding/.test(c.name))).toBe(false);expect(state.unknown).toEqual([]);expect(state.errors).toEqual([]);
});
