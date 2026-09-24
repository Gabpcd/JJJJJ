import {test,expect,type Page} from '@playwright/test';
import {simulerEtablissement,entrer,preuve,ids,mission,allerA,stabiliserLectures} from './helpers/recette-complete-etablissement';

test.setTimeout(480_000);
const baseURL=process.env.PLAYWRIGHT_BASE_URL||'http://127.0.0.1:8890';
// Inventaire App.tsx : toutes les routes canoniques de l'espace établissement.
export const routesEtablissement = [
 ['tableau-de-bord','Publiez votre première mission','Tableau de bord'],
 ['mon-compte','Activité'],['activer','Activer mon établissement'],
 ['parametres','Paramètres de l’établissement'],
 ['parametres/notifications','Préférences de notifications'],
 ['parametres/recherches-sauvegardees','Aucune recherche sauvegardée pour l\'instant.'],
 ['soignants','Aucun soignant ne correspond à vos critères.','Annuaire des soignants'],
 [`soignants/${ids.soignant}`,'Profil soignant indisponible.','Profil soignant'],
 ['missions','Publiez votre première mission'],['missions/creer','Publier une mission'],
 [`missions/${ids.mission}`,'Mission introuvable'],
 [`missions/${ids.mission}/modifier`,'Planning indisponible'],
 ['presences','Aucune présence à valider','Présences'],
 ['contrats','Aucun contrat','Contrats'],
 ['facturation','Aucune obligation financière en cours','Facturation'],
 [`facturation/${ids.facture}`,'Facture indisponible'],
 ['export-paie','Aucune période salariée validée','Export paie'],
 ['rh','Tableau RH'],['notifications','Tout est lu !'],
 ['premium','Tout Jolene est inclus dans votre commission'],
 ['chorus-config','Configuration Chorus Pro'],
 ['pool-urgence','Aucun soignant dans le pool'],
 ['mes-favoris','Aucun soignant favori'],
 ['parrainage','ETB-RECETTE','Parrainage entre établissements'],
 ['equipe','Invitez vos collaborateurs','Mon équipe'],
 ['score','Pas encore de score','Score qualité'],
 ['evaluations-a-faire','Aucune évaluation en attente'],
 ['messagerie','Aucune conversation'],
 ['litiges','Aucun litige en cours','Litiges et contestations'],
 ['mes-reclamations','Aucune réclamation'],
 [`presences/mission/${ids.mission}`,'Mission introuvable'],
] as const;
export const aliasesEtablissement = [
 ['finaliser-inscription','activer'],['verification','activer'],
 ['profil','parametres?tab=profil'],['analytics','rh?tab=analytics'],
 ['assurance','contrats'],['mon-groupe','parametres?tab=groupe'],
 ['exclusions','parametres?tab=exclusions'],['api','parametres?tab=securite'],
 ['dashboard','tableau-de-bord'],['contrat-plateforme','contrats'],
 ['obligations','facturation'],['reclamations','litiges?tab=reclamations'],
] as const;

async function pasDeDebordement(page:Page){
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=document.documentElement.clientWidth+1),'aucun débordement horizontal').toBe(true);
}

for(const entree of ['connexion','inscription'] as const){
 for(const mode of ['minimal','complet'] as const){
 test(`${entree} ${mode} : chaque rubrique et alias établissement`,async({page},info)=>{
  const {etat}=await simulerEtablissement(page,entree==='inscription'?'minimal':mode);
  await entrer(page,entree);
  if(entree==='inscription'&&mode==='complet'){
   // Le formulaire de complétion est recetté séparément. Ce scénario couvre
   // ensuite les pages dans l'état renvoyé après création du profil serveur.
   etat.mode='complet';await stabiliserLectures(page);await page.reload();
   await expect(page.getByTestId('dashboard-etablissement-ready')).toBeAttached();
   await stabiliserLectures(page);
  }
  for(const route of routesEtablissement){
   const [path,complet,minimal]=route;
   await test.step(path,async()=>{
    await allerA(page,`/etablissement/${path}`);
    try{
     if(mode==='minimal'&&['activer','parametres'].includes(path)){
      await expect(page).toHaveURL(/\/inscription\/completer$/);
      await expect(page.getByRole('button',{name:'Enregistrer mon établissement',exact:true})).toBeVisible();
     }else await expect(page.locator('main').getByText(mode==='minimal'&&minimal?minimal:complet,{exact:true}).first()).toBeVisible();
     await expect(page.getByRole('status',{name:'Chargement en cours',exact:true})).toHaveCount(0);
     await pasDeDebordement(page);
    }catch(error){expect.soft(false,`${mode} /${path}: ${String(error)}`).toBe(true);}
    await stabiliserLectures(page);
    await preuve(page,`${entree}-${mode}-${path.replaceAll('/','-')}`,info);
   });
  }
  for(const [source,cible]of aliasesEtablissement){
   await allerA(page,`/etablissement/${source}`);
   const destination=mode==='minimal'&&['finaliser-inscription','verification','profil'].includes(source)?'inscription/completer':`etablissement/${cible}`;
   await expect.soft(page).toHaveURL(`${baseURL}/${destination}`);
   if(destination==='inscription/completer'){
    await expect(page.getByRole('button',{name:'Enregistrer mon établissement',exact:true})).toBeVisible();
   }else if(cible.startsWith('parametres')){
    const tab=source==='api'?'Sécurité & RGPD':source==='profil'?'Profil':'Opérations';
    await expect(page.getByRole('tab',{name:tab,exact:true})).toHaveAttribute('aria-selected','true');
   }else if(cible.startsWith('rh')){
    if(mode==='complet')await expect(page.getByRole('tab',{name:'Analytics',exact:true})).toHaveAttribute('aria-selected','true');
    else await expect(page.getByRole('link',{name:'Préparer une mission',exact:true})).toBeVisible();
   }else if(cible.startsWith('litiges')){
    if(mode==='complet')await expect(page.getByRole('tab',{name:'Réclamations générales',exact:true})).toHaveAttribute('aria-selected','true');
    else await expect(page.getByRole('link',{name:'Préparer une mission',exact:true})).toBeVisible();
   }else{
    const attendu=routesEtablissement.find(([path])=>path===cible)!;
    await expect(page.locator('main').getByText(mode==='minimal'&&attendu[2]?attendu[2]:attendu[1],{exact:true}).first()).toBeVisible();
   }
   // Les alias montent aussi les lectures secondaires de la page cible.
   // Ne pas détruire leur document avant leur résolution dans le banc WebKit.
   await stabiliserLectures(page);
  }
  await info.attach('endpoints-et-erreurs',{body:JSON.stringify(etat,(_,v)=>v instanceof Set?[...v]:v instanceof Map?Object.fromEntries(v):v,2),contentType:'application/json'});
  expect(etat.inconnues,'tous les endpoints sont explicitement simulés').toEqual([]);
  expect(etat.erreurs,'aucune exception de rendu').toEqual([]);
  expect(etat.ecritures,'aucune action métier non préparée').toEqual([]);
 });
 }
}

test('onglets établissement, droits et reprise après panne',async({page},info)=>{
 const {etat}=await simulerEtablissement(page);
 await entrer(page,'connexion');
 await allerA(page,'/etablissement/missions');
 for(const [nom,vide]of [['Ouvertes','Aucune mission ouverte'],['Assignées','Aucune mission assignée'],['Actives','Aucune mission active'],['Terminées','Aucune mission terminée'],['Expirées','Aucune mission expirée'],['Annulées','Aucune mission annulée'],['Litiges','Aucun litige']]){
  await page.getByRole('button',{name:`${nom} (0)`,exact:true}).click();
  await expect(page.getByText(vide,{exact:true})).toBeVisible();
 }
 await allerA(page,'/etablissement/messagerie');
 await page.getByRole('tab',{name:'Archivées',exact:true}).click();
 await expect(page.getByText('Aucune conversation archivée',{exact:true})).toBeVisible();
 await page.getByRole('tab',{name:'Actives',exact:true}).click();
 await expect(page.getByText('Aucune conversation',{exact:true})).toBeVisible();
 await allerA(page,'/etablissement/notifications');
 for(const nom of ['Toutes','Missions','Documents','Finance','Système']){
  await page.locator('main').getByRole('button',{name:nom,exact:true}).click();
  await expect(page.getByText('Tout est lu !',{exact:true})).toBeVisible();
 }
 await allerA(page,'/etablissement/presences');
 for(const [nom,vide]of [['À valider: 0 présences','Aucune présence à valider'],['En cours: 0 présences','Aucune mission en cours'],['Validées: 0 présences','Aucune présence validée'],['Alertes: 0 anomalies','Aucune alerte']]){
  await page.getByRole('tab',{name:nom,exact:true}).click();
  await expect(page.getByRole('tab',{name:nom,exact:true})).toHaveAttribute('aria-selected','true');
  await expect(page.getByText(vide,{exact:true})).toBeVisible();
 }
 await preuve(page,'onglets-presences',info);
 await allerA(page,'/etablissement/contrats');
 for(const [nom,vide]of [['En attente','Aucun contrat en attente'],['Signés','Aucun contrat'],['Annulés','Aucun contrat'],['Tous','Aucun contrat']]){
  await page.getByRole('button',{name:nom,exact:true}).click();
  await expect(page.getByText(vide,{exact:true})).toBeVisible();
 }
 await allerA(page,'/etablissement/rh');
 await page.getByRole('tab',{name:/Indicateurs|Analytics/}).click();
 await expect(page.getByRole('heading',{name:'Indicateurs de performance'})).toBeVisible();
 await page.getByRole('button',{name:'12 mois',exact:true}).click();
 await expect(page.getByText('Sur 12 mois glissants',{exact:true})).toBeVisible();
 await preuve(page,'onglet-analytics',info);
 await allerA(page,'/etablissement/litiges');
 await page.getByRole('tab',{name:'Réclamations générales',exact:true}).click();
 await expect(page.getByText('Aucune réclamation pour le moment.',{exact:true})).toBeVisible();
 await preuve(page,'onglet-reclamations',info);
 await allerA(page,'/etablissement/parametres');
 for(const [nom,texte]of [['Profil','Informations générales'],['Facturation','Mode de paiement de la commission'],['Opérations','Tolérance pointage GPS'],['Notifications','Tout est lu !'],['Sécurité & RGPD','Données personnelles (RGPD)']]){
  await page.getByRole('tab',{name:nom,exact:true}).click();
  await expect(page.getByRole('tab',{name:nom,exact:true})).toHaveAttribute('aria-selected','true');
  await expect(page.locator('main').getByText(texte,{exact:false}).first()).toBeVisible();
  await pasDeDebordement(page);
  await preuve(page,`onglet-parametres-${nom.replaceAll(' ','-').replaceAll('/','-')}`,info);
 }
 etat.permissions='REFUSE';await allerA(page,'/etablissement/equipe');
 await expect(page.getByText("Vous n'êtes pas membre de cette équipe.",{exact:true})).toBeVisible();
 await expect(page.getByRole('button',{name:'Inviter un membre'})).toHaveCount(0);
 await preuve(page,'equipe-droits-refuses',info);
 etat.pannes.add('contrats_mission');await allerA(page,'/etablissement/contrats');
 await expect(page.getByRole('alert')).toContainText('Contrats indisponibles');
 await expect(page.getByText('Aucun contrat',{exact:true})).toHaveCount(0);
 etat.pannes.delete('contrats_mission');await page.getByRole('button',{name:'Réessayer',exact:true}).click();
 await expect(page.getByText('Aucun contrat',{exact:true})).toBeVisible();
 expect(etat.inconnues).toEqual([]);expect(etat.erreurs).toEqual([]);expect(etat.ecritures).toEqual([]);
});

test('mission présente : détail, recommandations, modification et retour',async({page},info)=>{
 const {etat}=await simulerEtablissement(page);etat.donnees=true;
 await entrer(page,'connexion');
 await allerA(page,'/etablissement/missions');
 await page.getByText(mission.intitule,{exact:true}).first().click();
 await expect(page).toHaveURL(`/etablissement/missions/${ids.mission}`);
 await expect(page.getByRole('heading',{name:mission.intitule,exact:true})).toBeVisible();
 await expect(page.getByText(/360/).first()).toBeVisible();
 await preuve(page,'mission-presente-detail',info);
 await page.getByRole('tab',{name:'Soignants recommandés',exact:true}).click();
 await expect(page.getByText('Aucun soignant disponible pour cette profession.',{exact:true})).toBeVisible();
 await allerA(page,`/etablissement/missions/${ids.mission}/modifier`);
 await expect(page.getByLabel('Intitulé *',{exact:true})).toHaveValue(mission.intitule);
 await expect(page.getByLabel(/Première date affichée/)).toHaveValue('2026-10-15');
 await expect(page.getByLabel('Début du créneau 1 du 2026-10-15',{exact:true})).toHaveValue('07:00');
 await expect(page.getByLabel('Fin du créneau 1 du 2026-10-15',{exact:true})).toHaveValue('19:00');
 await preuve(page,'mission-modification',info);
 expect(etat.inconnues).toEqual([]);expect(etat.erreurs).toEqual([]);expect(etat.ecritures).toEqual([]);
});

test('actions établissement : recherche, invitation simulée, préférences et Chorus indisponible',async({page},info)=>{
 const {etat}=await simulerEtablissement(page);await entrer(page,'connexion');
 await allerA(page,'/etablissement/parametres/recherches-sauvegardees');
 await page.getByRole('button',{name:'Créer une recherche',exact:true}).click();
 await expect(page).toHaveURL(/\/etablissement\/soignants$/);
 await expect(page.getByText('Aucun soignant ne correspond à vos critères.',{exact:true})).toBeVisible();
 await allerA(page,'/etablissement/equipe');
 await page.getByRole('button',{name:'Inviter un membre',exact:true}).first().click();
 const dialog=page.getByRole('dialog');
 await expect(dialog.getByRole('button',{name:"Envoyer l'invitation",exact:true})).toBeDisabled();
 await dialog.getByLabel('Adresse e-mail *',{exact:true}).fill('recette-collegue@example.invalid');
 await dialog.getByLabel(/Rôle proposé/).selectOption('POINTAGE_ONLY');
 await expect(dialog.getByRole('button',{name:"Envoyer l'invitation",exact:true})).toBeInViewport();
 await preuve(page,'formulaire-invitation',info);
 await dialog.getByRole('button',{name:"Envoyer l'invitation",exact:true}).click();
 await expect(page.getByRole('heading',{name:'Invitations en attente (1)',exact:true})).toBeVisible();
 await expect(page.getByText('recette-collegue@example.invalid',{exact:true})).toBeVisible();
 expect(etat.operations.find(x=>x.nom==='fn_inviter_membre_etab')?.payload).toEqual({p_email:'recette-collegue@example.invalid',p_role:'POINTAGE_ONLY'});
 await preuve(page,'invitation-simulee-liste',info);
 await allerA(page,'/etablissement/parametres/notifications');
 await expect(page.getByRole('switch',{name:'Email',exact:true})).toHaveAttribute('aria-checked','true');
 await page.getByRole('switch',{name:'Email',exact:true}).click();
 await page.getByRole('button',{name:'Enregistrer',exact:true}).click();
 await expect(page.getByText('Préférences enregistrées',{exact:true})).toBeVisible();
 await stabiliserLectures(page);await page.reload();
 await expect(page.getByRole('switch',{name:'Email',exact:true})).toHaveAttribute('aria-checked','false');
 expect(etat.operations.find(x=>x.nom==='fn_modifier_preferences_notifications')?.payload).toMatchObject({p_canal_email:false,p_canal_push:true,p_canal_sms:false,p_canal_in_app:true});
 await preuve(page,'preferences-notifications-sauvegardees',info);
 await allerA(page,'/etablissement/chorus-config');
 await page.getByLabel(/Numéro de structure Chorus/).fill('818 613 663 00017');
 await page.getByRole('button',{name:'Vérifier',exact:true}).click();
 await expect(page.getByLabel(/Numéro de structure Chorus/)).toHaveValue('81861366300017');
 await expect(page.getByText('Le service Chorus Pro est momentanément indisponible.',{exact:true})).toBeVisible();
 await expect(page.getByText('Structure introuvable sur Chorus Pro',{exact:true})).toHaveCount(0);
 expect(etat.operations.find(x=>x.nom==='chorus-pro-verify')?.payload).toEqual({identifiant:'81861366300017',detail:true,services:true});
 await preuve(page,'chorus-panne-explicite',info);
 expect(etat.inconnues).toEqual([]);expect(etat.erreurs).toEqual([]);expect(etat.ecritures).toEqual([]);
});

test('menu du compte établissement : toutes les destinations et retour',async({page},info)=>{
 const {etat}=await simulerEtablissement(page);await entrer(page,'connexion');
 const liens=[
 ['Présences à valider','presences?tab=a_valider'],['Contrats','contrats'],['Annuaire des soignants','soignants'],['Soignants favoris','mes-favoris'],['Pool urgence','pool-urgence'],['Messagerie','messagerie'],
 ['Gérer mon équipe','equipe'],['Pilotage RH & statistiques','rh'],['Export paie','export-paie'],['Score qualité','score'],['Parrainage','parrainage'],['Offre Premium','premium'],
 ['Mon établissement','parametres?tab=profil'],['Facturation & contrat','parametres?tab=facturation'],['Mes factures','facturation'],['Litiges & contestations','litiges'],['Opérations','parametres?tab=operations'],['Notifications','parametres?tab=notifications'],['Sécurité & RGPD','parametres?tab=securite'],
 ] as const;
 await allerA(page,'/etablissement/mon-compte');
 for(const [label,path]of liens){
  await page.locator('main').getByRole('button',{name:label,exact:true}).click();
  await expect(page).toHaveURL(`${baseURL}/etablissement/${path}`);
  await expect(page.locator('main').getByRole('heading').first()).toBeVisible();
  await stabiliserLectures(page);
  await page.goBack();
  await expect(page.getByRole('heading',{name:'Activité',exact:true})).toBeVisible();
 }
 await preuve(page,'menu-retour-19-destinations',info);
 expect(etat.inconnues).toEqual([]);expect(etat.erreurs).toEqual([]);expect(etat.ecritures).toEqual([]);
});

test('annuaire : sauvegarder, retrouver puis réappliquer tous les filtres sans activer d’alerte',async({page},info)=>{
 const {etat}=await simulerEtablissement(page);await entrer(page,'connexion');
 await allerA(page,'/etablissement/soignants');
 await expect(page.getByText('Aucun soignant ne correspond à vos critères.',{exact:true})).toBeVisible();
 if(!await page.getByLabel('Profession',{exact:true}).isVisible())await page.getByRole('button',{name:'Filtres',exact:true}).click();
 await page.getByLabel('Profession',{exact:true}).selectOption('IDE');
 await page.getByLabel("Type d'exercice",{exact:true}).selectOption('SALARIE');
 for(const [label,valeur]of [['Ville','Paris'],['Recherche libre','gériatrie'],['Distance max (km)','30'],['Note ≥','4.5'],['Score ≥','80'],['Expérience min (années)','3']])await page.getByLabel(label,{exact:true}).fill(valeur);
 await page.getByRole('checkbox',{name:'Disponible pour urgences'}).check();
 await page.getByRole('checkbox',{name:'Documents complets',exact:true}).check();
 await page.getByRole('button',{name:'Sauvegarder cette recherche',exact:true}).click();
 const dialog=page.getByRole('dialog');
 await dialog.getByLabel('Nom de la recherche',{exact:true}).fill('IDE Paris — recette');
 await expect(dialog).toContainText('Elle ne crée pas d’alerte email.');
 await expect(dialog.getByRole('switch')).toHaveCount(0);
 await expect(dialog.getByRole('button',{name:'Enregistrer',exact:true})).toBeInViewport();
 await preuve(page,'annuaire-sauvegarde-sans-alerte',info);
 await dialog.getByRole('button',{name:'Enregistrer',exact:true}).click();
 await expect(page.getByRole('button',{name:/^IDE Paris — recette/})).toBeVisible();
 const filtres={profession:'IDE',type_exercice:'SALARIE',ville:'Paris',distance_max_km:'30',note_min:'4.5',score_min:'80',experience_min:'3',disponible_urgence:true,documents_valides:true,recherche_texte:'gériatrie'};
 expect(etat.operations.find(o=>o.nom==='fn_creer_filtre_sauvegarde')?.payload).toEqual({p_nom:'IDE Paris — recette',p_audience:'ETAB_RECHERCHE_SOIGNANTS',p_filtres:filtres,p_alerte_active:false,p_frequence_alerte:'QUOTIDIENNE'});
 await page.getByRole('button',{name:'Recherches sauvegardées',exact:true}).click();
 await expect(page.getByRole('heading',{name:'IDE Paris — recette',exact:true})).toBeVisible();
 await preuve(page,'annuaire-recherche-retrouvee',info);
 await page.getByRole('button',{name:'Aller à la recherche',exact:true}).click();
 await expect(page).toHaveURL(/\/etablissement\/soignants\?/);
 await expect(page.getByLabel('Profession',{exact:true})).toHaveValue('IDE');
 await expect(page.getByLabel("Type d'exercice",{exact:true})).toHaveValue('SALARIE');
 for(const [label,valeur]of [['Ville','Paris'],['Recherche libre','gériatrie'],['Distance max (km)','30'],['Note ≥','4.5'],['Score ≥','80'],['Expérience min (années)','3']])await expect(page.getByLabel(label,{exact:true})).toHaveValue(valeur);
 await expect(page.getByRole('checkbox',{name:'Disponible pour urgences'})).toBeChecked();
 await expect(page.getByRole('checkbox',{name:'Documents complets',exact:true})).toBeChecked();
 await expect.poll(()=>etat.operations.filter(o=>o.nom==='fn_rechercher_soignants_etab').at(-1)?.payload).toMatchObject({p_profession:'IDE',p_type_exercice:'SALARIE',p_ville:'Paris',p_distance_max_km:30,p_note_min:4.5,p_score_min:80,p_experience_min:3,p_disponible_urgence:true,p_documents_valides:true,p_recherche_texte:'gériatrie'});
 expect(await page.evaluate(()=>sessionStorage.getItem('jolene.filtres_a_appliquer'))).toBeNull();
 await pasDeDebordement(page);await preuve(page,'annuaire-filtres-reappliques',info);
 expect(etat.inconnues).toEqual([]);expect(etat.erreurs).toEqual([]);expect(etat.ecritures).toEqual([]);
});

test('annuaire et profil présent : informations exactes, retour et reprise après 503',async({page},info)=>{
 const {etat}=await simulerEtablissement(page);
 const soignant={id:ids.soignant,prenom:'Camille',nom:'Recette',nom_initiale:'R.',profession:'IDE',type_exercice:'SALARIE',score_fiabilite:92,note_moyenne:4.5,nb_evaluations:2,total_missions_terminees:4,annees_experience:6,specialites:['Gériatrie'],bio:'Profil entièrement simulé pour la recette.',bio_extrait:'Profil entièrement simulé pour la recette.',avatar_url:null,rpps_verifie:true,tous_documents_valides:true,disponible_urgence:false,ville:'Paris',distance_km:8,telephone:null};
 etat.overrides.set('fn_rechercher_soignants_etab',{soignants:[soignant],count_total:1});
 etat.overrides.set('fn_soignant_pour_etablissement',soignant);
 etat.overrides.set('fn_note_moyenne',{moyenne:4.5,total:2});
 await entrer(page,'connexion');await allerA(page,'/etablissement/soignants');
 await expect(page.getByText('1 soignant disponible',{exact:true})).toBeVisible();
 await expect(page.getByText('Paris · 8 km',{exact:true})).toBeVisible();
 const ajouter=page.getByRole('button',{name:'Ajouter ce soignant aux favoris',exact:true});
 await expect(ajouter).toBeEnabled();
 etat.pannes.add('favoris_etab_soignant');await ajouter.click();
 await expect(page.getByText('Impossible d’ajouter ce soignant aux favoris. Veuillez réessayer.',{exact:true})).toBeVisible();
 await expect(ajouter).toHaveAttribute('aria-pressed','false');
 etat.pannes.delete('favoris_etab_soignant');await ajouter.click();
 await expect(page.getByRole('button',{name:'Retirer ce soignant des favoris',exact:true})).toHaveAttribute('aria-pressed','true');
 await stabiliserLectures(page);await stabiliserLectures(page);await page.reload();
 const retirer=page.getByRole('button',{name:'Retirer ce soignant des favoris',exact:true});
 await expect(retirer).toHaveAttribute('aria-pressed','true');
 etat.pannes.add('favoris_etab_soignant');await retirer.click();
 await expect(page.getByText('Impossible de retirer ce soignant des favoris. Veuillez réessayer.',{exact:true})).toBeVisible();
 await expect(retirer).toHaveAttribute('aria-pressed','true');
 await preuve(page,'favori-retrait-refuse-conserve',info);
 etat.pannes.delete('favoris_etab_soignant');await retirer.click();
 await expect(ajouter).toHaveAttribute('aria-pressed','false');
 expect(etat.operations.find(o=>o.nom==='favori-ajoute')?.payload).toEqual({etablissement_id:ids.etab,soignant_id:ids.soignant});
 expect(etat.operations.find(o=>o.nom==='favori-retire')?.payload).toMatchObject({etablissement_id:`eq.${ids.etab}`,soignant_id:`eq.${ids.soignant}`});
 await page.getByRole('button',{name:'Voir le profil de Camille R.',exact:true}).click();
 await expect(page.getByRole('heading',{name:'Camille Recette',exact:true})).toBeVisible();
 await expect(page.getByText('4.5/5 (2)',{exact:true})).toBeVisible();
 await expect(page.getByText('6 ans',{exact:true})).toBeVisible();
 await expect(page.getByText('Complets',{exact:true})).toBeVisible();
 await expect(page.getByText('Visible le jour J uniquement',{exact:true})).toBeVisible();
 await expect(page.getByRole('link',{name:'Appeler le soignant',exact:true})).toHaveCount(0);
 await expect(page.getByText('Aucune mission partagée avec votre établissement pour le moment.',{exact:true})).toBeVisible();
 await pasDeDebordement(page);await preuve(page,'profil-soignant-present',info);
 await page.getByRole('button',{name:'Retour',exact:true}).click();
 await expect(page.getByRole('heading',{name:'Annuaire soignants',exact:true})).toBeVisible();
 etat.pannes.add('fn_soignant_pour_etablissement');
 await page.getByRole('button',{name:'Voir le profil de Camille R.',exact:true}).click();
 await expect(page.getByRole('alert')).toContainText('Impossible de charger ce profil');
 await expect(page.getByText('Profil soignant indisponible.',{exact:true})).toHaveCount(0);
 await preuve(page,'profil-soignant-503',info);
 etat.pannes.delete('fn_soignant_pour_etablissement');await page.getByRole('button',{name:'Réessayer',exact:true}).click();
 await expect(page.getByRole('heading',{name:'Camille Recette',exact:true})).toBeVisible();
 await expect(page.getByRole('alert')).toHaveCount(0);
 expect(etat.inconnues).toEqual([]);expect(etat.erreurs).toEqual([]);expect(etat.ecritures).toEqual([]);
});

test('recherches établissement : gestion centrale sans nouvelles alertes et conservation des alertes existantes',async({page},info)=>{
 const {etat,recherches}=await simulerEtablissement(page);
 const commun={audience:'ETAB_RECHERCHE_SOIGNANTS',filtres:{profession:'IDE',ville:'Paris'},frequence_alerte:'QUOTIDIENNE',dernier_check_le:'2026-09-24T10:00:00Z',nb_resultats_dernier_check:0};
 recherches.push({...commun,id:'inactive',nom:'Recherche sans alerte',alerte_active:false},{...commun,id:'active',nom:'Ancienne alerte',alerte_active:true});
 await entrer(page,'connexion');await allerA(page,'/etablissement/parametres/recherches-sauvegardees');
 await expect(page.getByText('Retrouvez vos filtres sans nouvelle alerte email',{exact:true})).toBeVisible();
 await expect(page.getByRole('button',{name:'Activer alertes',exact:true})).toHaveCount(0);
 const inactive=page.getByRole('listitem').filter({has:page.getByRole('heading',{name:'Recherche sans alerte',exact:true})});
 await inactive.getByRole('button',{name:'Modifier',exact:true}).click();
 const dialog=page.getByRole('dialog');
 await expect(dialog.getByRole('switch')).toHaveCount(0);
 await dialog.getByLabel('Nom',{exact:true}).fill('Recherche renommée sans alerte');
 await preuve(page,'recherche-centrale-sans-activation',info);
 await dialog.getByRole('button',{name:'Enregistrer',exact:true}).click();
 await expect(page.getByRole('heading',{name:'Recherche renommée sans alerte',exact:true})).toBeVisible();
 expect(etat.operations.filter(o=>o.nom==='fn_modifier_filtre_sauvegarde').at(-1)?.payload).toEqual({p_id:'inactive',p_nom:'Recherche renommée sans alerte'});
 const active=page.getByRole('listitem').filter({has:page.getByRole('heading',{name:'Ancienne alerte',exact:true})});
 await active.getByRole('button',{name:'Modifier',exact:true}).click();
 await expect(dialog.getByRole('switch',{name:'Alertes email',exact:true})).toHaveAttribute('aria-checked','true');
 await dialog.getByLabel('Nom',{exact:true}).fill('Ancienne alerte renommée');
 await dialog.getByRole('button',{name:'Enregistrer',exact:true}).click();
 await expect(page.getByRole('heading',{name:'Ancienne alerte renommée',exact:true})).toBeVisible();
 expect(etat.operations.filter(o=>o.nom==='fn_modifier_filtre_sauvegarde').at(-1)?.payload).toEqual({p_id:'active',p_nom:'Ancienne alerte renommée'});
 expect(recherches.find(r=>r.id==='active')?.alerte_active).toBe(true);
 await page.getByRole('button',{name:'Désactiver alertes',exact:true}).click();
 await expect(page.getByRole('button',{name:'Désactiver alertes',exact:true})).toHaveCount(0);
 await expect(page.getByRole('button',{name:'Activer alertes',exact:true})).toHaveCount(0);
 expect(etat.operations.filter(o=>o.nom==='fn_modifier_filtre_sauvegarde').at(-1)?.payload).toEqual({p_id:'active',p_alerte_active:false});
 expect(recherches.every(r=>r.alerte_active===false)).toBe(true);
 await preuve(page,'recherche-centrale-alerte-desactivee',info);
 expect(etat.inconnues).toEqual([]);expect(etat.erreurs).toEqual([]);expect(etat.ecritures).toEqual([]);
});
