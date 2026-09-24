import { expect, type Page, type Request, type TestInfo } from '@playwright/test';
import { mkdir, writeFile } from 'node:fs/promises';

export const ids = {user:'79000000-0000-4000-8000-000000000071', etab:'79000000-0000-4000-8000-000000000071', mission:'79000000-0000-4000-8000-000000000072', soignant:'79000000-0000-4000-8000-000000000074', facture:'79000000-0000-4000-8000-000000000075'};
export const email = 'recette-etablissement@example.invalid';
export type ModeCompte = 'minimal' | 'complet';
const lectures = new WeakMap<Page, {enCours:Set<Request>;dernierEvenement:number}>();

/** networkidle peut déjà être acquis sur le document avant sa navigation SPA. */
export async function stabiliserLectures(page:Page){
 const suivi=lectures.get(page);
 if(!suivi)return;
 await expect.poll(()=>suivi.enCours.size===0&&Date.now()-suivi.dernierEvenement>=500,{message:'Toutes les lectures API sont achevées avant de remplacer le document'}).toBe(true);
}
export async function allerA(page:Page, chemin:string){
 await stabiliserLectures(page);
 await page.goto(chemin);
}
export const etablissement = {id:ids.etab,nom:'Résidence Camille — recette',type:'EHPAD',email_contact:email,telephone:'0100000000',siret:'12345678900011',adresse_rue:'10 rue de la Recette',adresse_ville:'Paris',adresse_code_postal:'75001',latitude:48.86,longitude:2.35,statut_verification:'VERIFIE',est_verifie:true,peut_publier_missions:true,contrat_service_signe:true,contrat_service_statut:'SIGNE',code_parrainage:'ETB-RECETTE',groupe_id:null,logo_url:null};
export const mission = {id:ids.mission,etablissement_id:ids.etab,intitule:'Renfort IDE — recette complète',description:'Mission de simulation sans publication réelle.',profession_requise:'IDE',statut:'OUVERTE',debut_le:'2026-10-15T05:00:00.000Z',fin_le:'2026-10-15T17:00:00.000Z',duree_heures:12,nb_creneaux:1,taux_horaire_base:30,total_brut:360,net_a_payer:360,net_estime:360,mode_remuneration:'TAUX_HORAIRE',mode_attribution:'CANDIDATURE',type_contrat_recherche:'SALARIE',type_contrat_applique:'SALARIE',cree_le:'2026-09-24T09:00:00.000Z',est_urgente:false,soignant_assigne_id:null,etablissements:etablissement};
export const creneau = {id:'79000000-0000-4000-8000-000000000076',mission_id:ids.mission,debut:mission.debut_le,fin:mission.fin_le,type_creneau:'PREVISIONNEL',est_pause:false};

/** Chaque table/RPC est déclarée : toute requête inconnue échoue et sera rapportée. */
export async function simulerEtablissement(page:Page, modeInitial:ModeCompte = 'complet') {
 const suivi={enCours:new Set<Request>(),dernierEvenement:0};
 lectures.set(page,suivi);
 page.on('request',requete=>{if(/\/(auth|rest|functions|storage)\/v1\//.test(requete.url())){suivi.enCours.add(requete);suivi.dernierEvenement=Date.now();}});
 const terminer=(requete:Request)=>{if(suivi.enCours.delete(requete))suivi.dernierEvenement=Date.now();};
 page.on('requestfinished',terminer);page.on('requestfailed',terminer);
 const etat = {mode:modeInitial, donnees:false, permissions:'PROPRIETAIRE', erreurs:[] as string[], inconnues:[] as string[], ecritures:[] as string[], appels:[] as string[], operations:[] as {nom:string;payload:Record<string,unknown>}[], pannes:new Set<string>(), overrides:new Map<string,unknown>()};
 const parcours = {user_id:ids.user,type_compte:'ETABLISSEMENT',donnees:{nom:etablissement.nom} as Record<string,unknown>,modifie_le:new Date().toISOString()};
 const invitations:Record<string,unknown>[]=[];
 const recherches:Record<string,unknown>[]=[];
 let favori = false;
 const preferences={global:{canal_email:true,canal_push:true,canal_sms:false,canal_in_app:true},par_evenement:[]};
 const user = {id:ids.user,email,aud:'authenticated',role:'authenticated',email_confirmed_at:new Date().toISOString(),app_metadata:{},user_metadata:{},identities:[]};
 const session = {user,token_type:'bearer',access_token:'fixture-auth',refresh_token:'fixture-refresh',expires_in:3600,expires_at:Math.floor(Date.now()/1000)+3600};
 const emptyTables = new Set(['presences','contrats_mission','litiges','notifications','messages_chat','presence_status','typing_status','paliers_commission','evaluations','notations_missions','candidatures','stripe_transfers','paiements_mission','factures_honoraires','paiements_soignant','parrainages_etablissements','chorus_pro_config','exclusions','favoris_etab_soignant','bulletins_paie','reclamations','stripe_connect_onboarding','documents_etablissements','heures_externes_soignants']);
 const emptyRpcs = new Set(['fn_mes_soignants_etablissement','fn_rechercher_soignants_etab','fn_mes_filleuls_etab','fn_litiges_etablissement','fn_mes_reclamations','fn_lister_missions_a_noter_etab','fn_lister_conversations_messagerie','fn_mes_favoris_soignants','fn_pool_urgence_etablissement','fn_mes_factures','fn_lister_mes_filtres_sauvegardes','fn_lister_api_keys','fn_lister_notations_recues','fn_mes_evenements_score','fn_recommander_soignants','fn_presences_detail_mission','fn_explorer_missions_inscription']);
 page.on('pageerror', e=>etat.erreurs.push(e.message));
 await page.addInitScript(()=>localStorage.setItem('cookie-consent','refused'));
 await page.routeWebSocket('**/*', socket=>socket.close());
 await page.route('**/*', async route=>{
  const req=route.request(), url=new URL(req.url()), nom=url.pathname.split('/').pop()!;
  const repondre=(args:Parameters<typeof route.fulfill>[0])=>route.fulfill({...args,headers:{'access-control-allow-origin':'*','access-control-allow-headers':'*','access-control-allow-methods':'GET,POST,PATCH,DELETE,OPTIONS','access-control-expose-headers':'content-range',...args?.headers}});
  if(url.hostname==='fonts.googleapis.com') return repondre({contentType:'text/css',body:''});
  if(url.hostname==='js.stripe.com') return repondre({contentType:'application/javascript',body:'window.Stripe = function(){ return {}; };'});
  if (url.hostname!=='127.0.0.1' && url.hostname!=='localhost') {
   // Aucun effet réseau externe, même si une URL de paiement ou de télémétrie est déclenchée.
   etat.inconnues.push(`EXTERNE ${req.method()} ${url.origin}${url.pathname}`);return route.abort();
  }
  if (!/\/(auth|rest|functions|storage)\/v1\//.test(url.pathname)) {
   if(req.isNavigationRequest()&&req.resourceType()==='document'){
    // Les hints DNS/TLS échappent au routage HTTP, même avec une API locale.
    const response=await route.fetch();
    const html=(await response.text()).replace(/<link\b(?=[^>]*\brel=["'](?:preconnect|dns-prefetch)["'])[^>]*>/gi,'');
    return route.fulfill({response,body:html});
   }
   return route.continue();
  }
  if(req.method()==='OPTIONS')return repondre({status:204,body:''});
  etat.appels.push(`${req.method()} ${nom}`);
  if (url.pathname.includes('/auth/v1/')) {
   if (['token','signup','user','logout'].includes(nom)) return repondre({json:nom==='user'?user:nom==='logout'?{}:session});
  } else if(url.pathname==='/functions/v1/chorus-pro-verify'){
   etat.operations.push({nom,payload:req.postDataJSON()});
   return repondre({json:{apiError:true,error:'Le service Chorus Pro est momentanément indisponible.'}});
  } else if (url.pathname.includes('/rest/v1/')) {
   if(['missions','mission_creneaux','etablissements','soignants','parcours_inscription'].includes(nom)&&!['GET','HEAD'].includes(req.method())){
    etat.ecritures.push(`${req.method()} ${nom}`);
    etat.inconnues.push(`${req.method()} ${url.pathname}`);
    return repondre({status:501,json:{message:`Mutation non préparée: ${nom}`}});
   }
   if(etat.pannes.has(nom))return repondre({status:503,json:{message:'Service de recette indisponible'}});
   if(etat.overrides.has(nom)) return repondre({json:etat.overrides.get(nom)});
   let data:unknown;let connu=true;
   const object=req.headers().accept?.includes('object');
   if(nom==='fn_get_my_role')data={role:etat.mode==='minimal'?'INCONNU':'ADMIN_ETABLISSEMENT',etablissement_id:etat.mode==='minimal'?null:ids.etab};
   else if(nom==='parcours_inscription')data=object?parcours:[parcours];
   else if(nom==='fn_demarrer_inscription')data=parcours;
   else if(nom==='fn_enregistrer_parcours_inscription'){Object.assign(parcours.donnees,req.postDataJSON().p_donnees);data=parcours;}
   else if(nom==='fn_mon_etablissement_complet')data=etat.mode==='minimal'?{error:'Profil introuvable'}:etablissement;
   else if(nom==='etablissements'){const existe=etat.mode==='complet'&&(!url.searchParams.get('id')||url.searchParams.get('id')===`eq.${ids.etab}`);data=existe?(object?etablissement:[etablissement]):(object?null:[]);}
   else if(nom==='soignants')data=object?null:[];
   else if(nom==='favoris_etab_soignant'){
    if(req.method()==='POST'){const p=req.postDataJSON();etat.operations.push({nom:'favori-ajoute',payload:p});favori=true;data=null;}
    else if(req.method()==='DELETE'){etat.operations.push({nom:'favori-retire',payload:Object.fromEntries(url.searchParams)});favori=false;data=null;}
    else if(req.method()==='GET'){const row={id:'favori-recette',etablissement_id:ids.etab,soignant_id:ids.soignant};data=object?(favori?row:null):(favori?[row]:[]);}
    else connu=false;
   }
   else if(nom==='missions'){
    let rows=etat.donnees?[mission]:[];
    const statut=url.searchParams.get('statut');
    if(statut?.startsWith('eq.')&&statut.slice(3)!==mission.statut)rows=[];
    if(statut?.startsWith('in.')&&!statut.includes(mission.statut))rows=[];
    data=object?(rows[0]??null):rows;
   }
   else if(nom==='mission_creneaux')data=etat.donnees?[creneau]:[];
   else if(nom==='fn_compte_auth_actif')data=true;
   else if(nom==='fn_messages_non_lus')data=0;
   else if(nom==='notifications'&&req.method()==='PATCH')data=null;
   else if(nom==='fn_bfa_info')data={eligible:false};
   else if(nom==='fn_param_bool')data=false;
   else if(nom==='fn_mes_reclamations')data={success:true,reclamations:[]};
   else if(nom==='fn_lister_api_keys')data={success:true,keys:[]};
   else if(nom==='fn_lister_mes_filtres_sauvegardes')data=recherches.filter(r=>r.audience===req.postDataJSON().p_audience);
   else if(nom==='fn_creer_filtre_sauvegarde'){const p=req.postDataJSON();etat.operations.push({nom,payload:p});recherches.push({id:'recherche-recette',nom:p.p_nom,audience:p.p_audience,filtres:p.p_filtres,alerte_active:p.p_alerte_active,frequence_alerte:p.p_frequence_alerte,dernier_check_le:new Date().toISOString(),cree_le:new Date().toISOString(),mis_a_jour_le:new Date().toISOString(),nb_resultats_dernier_check:0});data={success:true,id:'recherche-recette'};}
   else if(nom==='fn_modifier_filtre_sauvegarde'){const p=req.postDataJSON();etat.operations.push({nom,payload:p});const r=recherches.find(r=>r.id===p.p_id);if(r){if(p.p_nom)r.nom=p.p_nom;if(typeof p.p_alerte_active==='boolean')r.alerte_active=p.p_alerte_active;}data={success:!!r};}
   else if(nom==='fn_rechercher_soignants_etab'){etat.operations.push({nom,payload:req.postDataJSON()});data={soignants:[],count_total:0};}
   else if(nom==='fn_mode_exercice')data={niveau:'AUTORISE',categorie:'prive',source_libelle:'Configuration de recette',source_force:'CONFORMITE_JOLENE',source_url:null};
   else if(nom==='fn_note_moyenne')data={moyenne:null,total:0};
   else if(nom==='fn_update_presence'||nom==='fn_ecrire_audit_safe'||nom==='fn_audit_connexion')data=null;
   else if(nom==='fn_mon_profil_soignant_complet'||nom==='fn_soignant_pour_etablissement')data=null;
   else if(nom==='fn_litige_pour_mission'||nom==='fn_onboarding_soignant_statut')data=null;
   else if(nom==='fn_stats_dashboard_etablissement')data={missions_ouvertes:etat.donnees?1:0,missions_assignees:0,missions_en_cours:0,missions_terminees:0,candidatures_en_attente:0,candidatures_recentes:[],missions_assignees_detail:[],pool_urgence_count:0,messages_non_lus:0,missions_a_payer:0,missions_terminees_ce_mois:0,soignants_ce_mois:0,commissions_impayees:0,nb_factures_impayees:0,litiges_ouverts:0};
   else if(nom==='fn_stats_rh_etablissement')data={terminees_total:0,terminees_mois_prec:0,cout_total_termine:0,cout_moyen_heure:0,taux_remplissage:0,soignants_total:0,assignees_total:0,cout_previsionnel_total:0,top_soignants:[],missions_par_mois:[],cout_par_profession:[],mois_en_cours:'septembre',mois_precedent:'août'};
   else if(nom==='fn_analytics_etablissement')data={taux_remplissage:0,cout_heure_moyen:0,turnover_pourcent:0,missions_par_mois:[],top_professions:[],soignants_recurrents:[]};
   else if(nom==='fn_mon_score_etab')data={score_qualite:null,niveau:null,composantes:{notation_pct:null,nb_notations:0,paiement_pct:null,nb_factures:0,nb_litiges_perdus:0}};
   else if(nom==='fn_mes_credits_etab')data={total_disponible_eur:0,total_applique_eur:0,credits:[]};
   else if(nom==='fn_lister_membres_etab')data=etat.permissions==='REFUSE'?{success:false,error_code:'NON_AUTORISE'}:{success:true,role_courant:etat.permissions,membres:[],invitations};
   else if(nom==='fn_mes_permissions_etab')data={success:true,role:etat.permissions,permissions:Object.fromEntries(['gerer_equipe','supprimer_compte','profil_etab','paiement','lecture_paiement','missions','candidatures','contrats','pointage','rh','lecture'].map(k=>[k,etat.permissions==='PROPRIETAIRE']))};
   else if(nom==='fn_obligations_financieres')data={total_du:0,missions_a_payer:[],factures_impayees:[]};
   else if(nom==='fn_paiements_etablissement')data={paiements:[],factures:[],missions:[]};
   else if(nom==='fn_obtenir_mes_preferences_notifications')data=preferences;
   else if(nom==='fn_modifier_preferences_notifications'){const p=req.postDataJSON();etat.operations.push({nom,payload:p});Object.assign(preferences.global,{canal_email:p.p_canal_email,canal_push:p.p_canal_push,canal_sms:p.p_canal_sms,canal_in_app:p.p_canal_in_app});data={success:true};}
   else if(nom==='fn_inviter_membre_etab'){const p=req.postDataJSON();etat.operations.push({nom,payload:p});invitations.push({id:'invitation-recette',email_invite:p.p_email,role_propose:p.p_role,statut:'EN_ATTENTE',invite_le:new Date().toISOString(),expire_le:new Date(Date.now()+7*86400000).toISOString()});data={success:true};}
   else if(nom==='fn_detail_facture')data={error:'Facture introuvable'};
   else if(emptyRpcs.has(nom))data=[];
   else if(emptyTables.has(nom)&&['GET','HEAD'].includes(req.method()))data=object?null:[];
   else connu=false;
   if(connu&&data===null&&object&&!nom.startsWith('fn_')) return repondre({status:406,json:{code:'PGRST116',message:'Cannot coerce the result to a single JSON object',details:'The result contains 0 rows'}});
   if(connu)return repondre({json:data,headers:{'content-range':Array.isArray(data)&&data.length?`0-${data.length-1}/${data.length}`:'*/0'}});
  }
  if(!['GET','HEAD'].includes(req.method()))etat.ecritures.push(`${req.method()} ${nom}`);
  etat.inconnues.push(`${req.method()} ${url.pathname}`);
  return repondre({status:501,json:{message:`Endpoint non simulé: ${nom}`}});
 });
 return {etat,parcours,recherches};
}
export async function entrer(page:Page, entree:'connexion'|'inscription'){
 await page.goto(entree==='connexion'?'/connexion':'/inscription/etablissement');
 await page.getByLabel('Email',{exact:true}).fill(email);
 await page.getByLabel('Mot de passe',{exact:true}).fill('Mot!Solide-Recette2026');
 if(entree==='inscription'){
  await page.getByLabel('Nom de l’établissement',{exact:true}).fill(etablissement.nom);
  await page.getByRole('checkbox',{name:/CGU/}).check();
  await page.getByRole('checkbox',{name:/conditions générales de vente/}).check();
 }
 await page.getByRole('button',{name:entree==='connexion'?'Se connecter':'Créer mon compte',exact:true}).click();
 await expect(page).toHaveURL(/\/etablissement\/tableau-de-bord$/);
 await expect(page.getByTestId('dashboard-etablissement-ready')).toBeAttached();
 // Attendre les lectures secondaires avant le changement de document suivant.
 // Sans cela WebKit remonte des erreurs de fetch de l'ancien document détruit.
 await stabiliserLectures(page);
}
export async function preuve(page:Page, nom:string, testInfo:TestInfo){
 const dir=process.env.RECETTE_DIR?`${process.env.RECETTE_DIR}/${testInfo.project.name}`:testInfo.outputPath('preuves');
 await mkdir(dir,{recursive:true});
 const surface=await page.getByRole('dialog').count()?page.getByRole('dialog'):await page.locator('main').count()?page.locator('main'):page.locator('body');
 const aria=await surface.ariaSnapshot();
 await writeFile(`${dir}/${nom}.txt`,aria);
 await testInfo.attach(nom+'-aria',{body:aria,contentType:'text/plain'});
 // ARIA pour chaque état ; captures des rubriques iPad et actions importantes.
 // Les défauts de tous les formats ont aussi la capture automatique Playwright.
 if(testInfo.project.name.startsWith('ipad-') && (!/^(connexion|inscription)-/.test(nom)||nom.startsWith('connexion-complet-'))){
  await page.screenshot({path:`${dir}/${nom}.png`,fullPage:true,animations:'disabled'});
 }
}
