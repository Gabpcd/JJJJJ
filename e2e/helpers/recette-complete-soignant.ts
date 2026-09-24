import { expect, type Page, type TestInfo } from '@playwright/test';
import { mkdir, writeFile } from 'node:fs/promises';

export const ids = { user: '69000000-0000-4000-8000-000000000071', mission: '69000000-0000-4000-8000-000000000072', etab: '69000000-0000-4000-8000-000000000073', serie: '69000000-0000-4000-8000-000000000074' };
export const email = 'recette-soignant@example.invalid';
export type Mode = 'minimal' | 'complet';
export const profil = {
 id: ids.user, email, prenom: 'Camille', nom: 'Recette', profession: 'IDE', type_exercice: 'SALARIE', statut_liberal: 'NON',
 telephone: '0100000000', date_naissance: '1990-01-01', numero_rpps: '10000000000', rpps_verifie: true, tous_documents_valides: true,
 adresse_rue: '10 rue de la Recette', adresse_ville: 'Paris', adresse_code_postal: '75001', adresse_lat: 48.8566, adresse_lng: 2.3522,
 rayon_deplacement_km: 30, ville_recherche: 'Paris', bio: 'Profil fictif utilisé uniquement pour la recette.', specialites: [],
 types_contrat_acceptes: '["SALARIE"]', type_contrat_recherche: 'SALARIE', consentement_gps: false, disponible_urgence: false,
 urgence_rayon_km: 30, pool_urgence_sms_opt_in: false, sms_alertes_actives: false, total_missions_terminees: 0, score_fiabilite: 50,
 niveau: 'BRONZE', en_periode_probatoire: true, heures_cumulees: 0, code_parrainage: 'RECETTE', badge_ambassadeur: false,
 regime_fiscal: null, regime_fiscal_confirme: false, avatar_url: null, est_compte_test: true, psc_sub: null,
};
export const etablissement = { id: ids.etab, nom: 'Résidence Camille — simulation', type: 'EHPAD', adresse_ville: 'Paris', adresse_code_postal: '75001', adresse_lat: 48.8566, adresse_lng: 2.3522 };
const debut = new Date(Date.now() + 7 * 86400000).toISOString();
const fin = new Date(Date.now() + 7 * 86400000 + 8 * 3600000).toISOString();
export const mission = { id: ids.mission, cree_le: new Date().toISOString(), intitule: 'Renfort infirmier — simulation', description: 'Mission fictive pour contrôler les écrans.', profession_requise: 'IDE', debut_le: debut, fin_le: fin, duree_heures: 8, nb_creneaux: 1, taux_horaire_base: 30, total_brut: 240, net_estime: 240, net_a_payer: 240, mode_remuneration: 'TAUX_HORAIRE', statut: 'OUVERTE', mode_attribution: 'CANDIDATURE', type_contrat_recherche: 'SALARIE', type_contrat_applique: 'SALARIE', etablissement_id: ids.etab, etablissements: etablissement, serie_id: ids.serie, soignant_assigne_id: null, creneaux: [{ id: '69000000-0000-4000-8000-000000000075', mission_id: ids.mission, debut, fin, est_pause: false, type_creneau: 'PREVISIONNEL' }] };

type Row = Record<string, any>;
export const simulations = new WeakMap<Page, {unknown:string[];errors:string[];calls:unknown[]}>();
const reseaux = new WeakMap<Page, { enCours:Set<unknown>; dernierMouvement:number }>();
/** Contrats de lecture explicites : un nom absent produit une erreur 501 et fait échouer la recette. */
export async function simulerSoignant(page: Page, mode: Mode = 'complet') {
 const reseau = { enCours:new Set<unknown>(), dernierMouvement:Date.now() };
 reseaux.set(page,reseau);
 page.on('request',request=>{if(/\/(auth|rest|functions|storage)\/v1\//.test(request.url())){reseau.enCours.add(request);reseau.dernierMouvement=Date.now();}});
 for(const event of ['requestfinished','requestfailed'] as const) page.on(event,request=>{if(reseau.enCours.delete(request))reseau.dernierMouvement=Date.now();});
 const state = { mode, authExpired:false, offers: false, profile: { ...profil } as Row, unknown: [] as string[], errors: [] as string[], calls: [] as {name:string;method:string;body:any;url:string}[], failures: new Set<string>(), overrides: new Map<string,unknown>(), tables: new Map<string,Row[]>(), preferences: {global:{canal_email:true,canal_push:true,canal_sms:false,canal_in_app:true},par_evenement:[] as any[]} };
 const parcours = { user_id: ids.user, type_compte: 'SOIGNANT', donnees: { profession: 'IDE' } as Row, modifie_le: new Date().toISOString() };
 const liberal = { id: 'recette-parcours', soignant_id: ids.user, demarre_le: new Date().toISOString(), termine_le: null, parcours_kine: null, etapes: {} as Row, cree_le: new Date().toISOString(), mis_a_jour_le: new Date().toISOString() };
 const user = { id: ids.user, email, aud: 'authenticated', role: 'authenticated', email_confirmed_at: new Date().toISOString(), app_metadata: {}, user_metadata: {}, identities: [] };
 const session = { user, token_type: 'bearer', access_token: 'fixture-auth', refresh_token: 'fixture-refresh', expires_in: 3600, expires_at: Math.floor(Date.now()/1000)+3600 };
 const emptyTables = ['admins_groupe_sante','attestations_heures_externes','bulletins_paie','candidatures','conformite_travail','contrats_mission','contrats_travail_missions','conversations','cotisations_sociales','disponibilites_soignant','documents_requis_par_profession','documents_soignants','evaluations','exclusions','factures_honoraires','heures_externes_soignants','justificatifs','liste_attente_premium','litiges','mandats_facturation_signatures','messages_chat','messages_litige','missions_sauvegardees','notations_missions','notifications','paiements_soignant','presence_status','presences','prevoyance_liste_attente','reclamations','specialites_medicales','stripe_connect_onboarding','swipes','typing_status'];
 for(const table of emptyTables)state.tables.set(table, []);
 const emptyRpcs = new Set(['fn_evolution_score_soignant','fn_mes_evaluations_recues','fn_lister_notations_recues','fn_mes_exclusions_recues','fn_mes_favoris_etablissements','fn_mes_avances_factor','fn_mes_bulletins_paie','fn_mes_dpae','fn_mes_factures_honoraires','fn_mes_paiements_escrow','fn_pool_urgence_missions_pour_soignant_UNUSED','fn_interlocuteurs_conversations','fn_lister_conversations_messagerie','fn_lister_mes_filtres_sauvegardes','fn_top_soignants','fn_mes_reclamations','fn_mes_litiges','fn_presences_detail_mission']);
 const nullRpcs = new Set(['fn_onboarding_soignant_statut','fn_mon_token_calendrier','fn_litige_pour_mission','fn_mon_breakdown_actuel','fn_consulter_mon_iban']);
 const auditRpcs = new Set(['fn_audit_connexion','fn_maj_activite_soignant','fn_ecrire_audit_safe','fn_update_presence']);
 page.on('pageerror', e => state.errors.push(e.message));
 await page.addInitScript(() => localStorage.setItem('cookie-consent','refused'));
 await page.routeWebSocket('**/*', socket => socket.close());
 await page.route('**/*', async route => {
  const req=route.request(), url=new URL(req.url()), name=url.pathname.split('/').pop()!;
  const fulfill = (options: Parameters<typeof route.fulfill>[0]) => route.fulfill({...options,headers:{'access-control-allow-origin':'*','access-control-allow-headers':'*','access-control-allow-methods':'GET,POST,PATCH,DELETE,HEAD,OPTIONS',...options?.headers}});
  if(!['127.0.0.1','localhost'].includes(url.hostname)) return route.abort();
  if(!/\/(auth|rest|functions|storage)\/v1\//.test(url.pathname)){
   if(req.isNavigationRequest()&&req.resourceType()==='document'){
    // Les hints DNS/TLS échappent au routage HTTP, même avec une API locale.
    const response=await route.fetch();
    const html=(await response.text()).replace(/<link\b(?=[^>]*\brel=["'](?:preconnect|dns-prefetch)["'])[^>]*>/gi,'');
    return route.fulfill({response,body:html});
   }
   return route.continue();
  }
  const body=req.postData()?.startsWith('{') ? req.postDataJSON() : null;
  if(req.method()==='OPTIONS')return fulfill({status:200,body:''});
  state.calls.push({name,method:req.method(),body,url:url.pathname+url.search});
  const ecrituresTables:Record<string,string[]>={missions_sauvegardees:['DELETE'],documents_soignants:['PATCH'],notifications:['PATCH'],soignants:['PATCH']};
  if(url.pathname.startsWith('/rest/v1/')&&!url.pathname.startsWith('/rest/v1/rpc/')&&!['GET','HEAD'].includes(req.method())&&!ecrituresTables[name]?.includes(req.method())){
   state.unknown.push(`${req.method()} ${url.pathname}`);
   return fulfill({status:501,json:{message:`Écriture de table non simulée : ${name}`,code:'RECETTE_INCONNU'}});
  }
  if(state.failures.has('storage_upload')&&url.pathname.startsWith('/storage/v1/object/'))return fulfill({status:503,json:{message:'Téléversement de simulation indisponible'}});
  if(state.failures.has(name))return fulfill({status:503,json:{message:'Service de simulation indisponible',code:'RECETTE_503'}});
  if(state.overrides.has(name))return fulfill({json:state.overrides.get(name)});
  if(state.authExpired&&url.pathname.includes('/auth/v1/'))return fulfill({status:401,json:{message:'Session expirée',code:'bad_jwt'}});
  if(url.pathname.includes('/auth/v1/')&&['token','signup','user','logout'].includes(name)) return fulfill({json:name==='user'?user:name==='logout'?{}:session});
  let data:unknown; let known=true;
  if(url.pathname.includes('/rest/v1/rpc/')) {
   if(name==='fn_get_my_role')data={role:state.mode==='minimal'?'INCONNU':'SOIGNANT',etablissement_id:null};
   else if(name==='fn_compte_auth_actif')data=true;
   else if(name==='fn_demarrer_inscription')data=parcours;
   else if(name==='fn_enregistrer_parcours_inscription'){Object.assign(parcours.donnees,body.p_donnees);data=parcours;}
   else if(name==='fn_mon_profil_soignant_complet')data=state.mode==='minimal'?{error:'Profil introuvable'}:state.profile;
   else if(name==='fn_explorer_missions_inscription'||name==='fn_obtenir_missions_swipe')data=state.offers?[mission]:[];
   else if(name==='fn_dashboard_soignant_complet')data={profil:state.profile,missions_ouvertes:[],mes_missions:[],documents:[],heures_semaine:0,gains_mois:{net_total:0,brut_total:0,nb_missions:0},gains_6mois:[],missions_semaine_cal:[],propositions:[],heures_totales_terminees:0,missions_oubliees_count:0,notifs_non_lues:0};
   else if(name==='fn_apercu_marche_profession')data={nb_missions:0,taux_max:null,zone:'France'};
   else if(name==='fn_note_moyenne')data={moyenne:null,total:0};
   else if(name==='fn_badge_stats')data={total_missions:0,score_fiabilite:50,heures_cumulees:0,annulations:0,missions_nuit:0,missions_weekend:0,max_missions_meme_etab:0,retards:0};
   else if(name==='fn_mes_evenements_score')data={evenements:[]};
   else if(name==='fn_mes_notations_recues_avec_stats')data={success:true,notations:[],stats:{total_evaluations:0,note_moyenne:null},evolution_6m:[],etabs_disponibles:[],total:0};
   else if(name==='fn_messages_non_lus')data=0;
   else if(name==='fn_param_bool'||name==='fn_est_bloque')data=false;
   else if(name==='fn_types_exercice_autorises')data=['SALARIE','LIBERAL','MIXTE'];
   else if(name==='fn_verifier_coherence_documents')data={coherent:true};
   else if(name==='fn_soignant_dpae_complet')data={complet:true};
   else if(name==='fn_obtenir_mes_parrainages')data={filleuls:[]};
   else if(name==='fn_obtenir_mes_preferences_notifications')data=state.preferences;
   else if(name==='fn_get_or_create_parcours_liberal')data=liberal;
   else if(name==='fn_compteur_heures_soignant')data={heures_jolene:0,heures_externes_validees:0,heures_externes_en_attente:0,heures_totales:0,eligible_free_transition:false};
   else if(name==='fn_pool_urgence_missions_pour_soignant')data={missions:[],pool_actif:false,rayon_km:30,sms_opt_in:false};
   else if(name==='fn_mes_revenus_connect')data={total_recu:0,total_en_attente:0,paiements:[]};
   else if(name==='fn_cumul_annuel_paie')data={brut:0,net:0};
   else if(name==='fn_etablissement_public')data=etablissement;
   else if(name==='fn_etablissements_safe')data=[etablissement];
   else if(name==='fn_score_etab_public')data=null;
   else if(name==='fn_etat_pointage_mission')data={statut:'NON_COMMENCE'};
   else if(name==='fn_modifier_mon_profil'){for(const [key,value]of Object.entries(body)){if(key==='p_types_contrat')state.profile.types_contrat_acceptes=JSON.stringify(value);else state.profile[key.slice(2)]=value;}data={success:true};}
   else if(name==='fn_definir_disponibilite'){
    const rows=state.tables.get('disponibilites_soignant')!.filter(r=>!(r.jour===body.p_jour&&r.creneau===body.p_creneau));
    if(body.p_disponible)rows.push({jour:body.p_jour,creneau:body.p_creneau});state.tables.set('disponibilites_soignant',rows);data={success:true};
   }
   else if(name==='fn_modifier_preferences_notifications'){state.preferences={global:{canal_email:body.p_canal_email,canal_push:body.p_canal_push,canal_sms:body.p_canal_sms,canal_in_app:body.p_canal_in_app},par_evenement:body.p_par_evenement};data={success:true};}
   else if(name==='fn_toggle_favori_etablissement'){const rows=state.overrides.get('fn_mes_favoris_etablissements') as Row[];state.overrides.set('fn_mes_favoris_etablissements',rows.filter(r=>r.etablissement_id!==body.p_etablissement_id));data={success:true};}
   else if(name==='fn_modifier_filtre_sauvegarde'){const row=(state.overrides.get('fn_lister_mes_filtres_sauvegardes') as Row[]).find(r=>r.id===body.p_id)!;for(const [key,value]of Object.entries(body)){if(key!=='p_id')row[key.slice(2)]=value;}data={success:true};}
   else if(name==='fn_maj_etape_parcours'){liberal.etapes[body.p_etape_cle]=body.p_valeur;data=liberal;}
   else if(nullRpcs.has(name)||auditRpcs.has(name))data=null;
   else if(emptyRpcs.has(name))data=[];
   else known=false;
  } else if(url.pathname.includes('/rest/v1/')) {
   let rows:Row[]|undefined;
   if(name==='soignants')rows=state.mode==='minimal'?[]:[state.profile];
   else if(name==='parcours_inscription')rows=state.mode==='minimal'?[parcours]:[];
   else if(name==='missions')rows=state.tables.get('missions')??(state.offers?[mission]:[]);
   else if(name==='mission_creneaux')rows=state.offers?mission.creneaux:[];
   else if(name==='etablissements')rows=[etablissement];
   else rows=state.tables.get(name);
   if(rows && ['GET','HEAD'].includes(req.method())){
    rows=rows.filter(row=>[...url.searchParams.entries()].every(([key,value])=>{
     if(['select','order','limit','offset','or','and'].includes(key)||key.includes('.'))return true;
     const [op,...rest]=value.split('.');const val=rest.join('.');
     if(op==='ilike')return String(row[key]??'').toLowerCase().includes(val.replaceAll('%','').toLowerCase());
     if(op==='eq')return String(row[key])===val;
     if(op==='neq')return String(row[key])!==val;
     if(op==='is')return val==='null'?row[key]==null:String(row[key])===val;
     if(op==='in')return val.replace(/^\(|\)$/g,'').split(',').includes(String(row[key]));
     if(['gte','lte','gt','lt'].includes(op))return row[key]!=null && (op==='gte'?row[key]>=val:op==='lte'?row[key]<=val:op==='gt'?row[key]>val:row[key]<val);
     return true;
    }));
    const count=rows.length;const offset=Number(url.searchParams.get('offset')||0);const limit=Number(url.searchParams.get('limit')||rows.length);rows=rows.slice(offset,offset+limit);
    data=req.headers().accept?.includes('object')?(rows[0]??null):rows;
    return fulfill({json:data,headers:{'content-range':count?`0-${count-1}/${count}`:'*/0'}});
   }else if(name==='missions_sauvegardees'&&req.method()==='DELETE'){state.tables.set(name,state.tables.get(name)!.filter(r=>'eq.'+r.mission_id!==url.searchParams.get('mission_id')));data=[];}
   else if(name==='documents_soignants'&&req.method()==='PATCH'){for(const row of state.tables.get(name)!.filter(r=>'eq.'+r.id===url.searchParams.get('id')))Object.assign(row,body);data=[];}
   else if(name==='notifications'&&req.method()==='PATCH'){for(const row of state.tables.get(name)!)Object.assign(row,body);data=[];}
   else if(name==='soignants'&&req.method()==='PATCH'){Object.assign(state.profile,body);data=state.profile;}
   else known=false;
  } else if(url.pathname.endsWith('/functions/v1/stripe-connect-status'))data={statut:'NON_DEMANDE'};
  else known=false;
  if(known)return fulfill({json:data});
  state.unknown.push(`${req.method()} ${url.pathname}`);
  return fulfill({status:501,json:{message:`Endpoint non simulé : ${name}`,code:'RECETTE_INCONNU'}});
 });
 simulations.set(page,state);
 return state;
}

async function attendreAPI(page:Page) {
 const reseau=reseaux.get(page);
 if(reseau)await expect.poll(()=>reseau.enCours.size===0&&Date.now()-reseau.dernierMouvement>=500,{message:'Requêtes API terminées avant une nouvelle navigation'}).toBe(true);
}

export async function aller(page:Page,url:string) {
 await attendreAPI(page);
 await page.goto(url);
}

export async function recharger(page:Page) {
 await attendreAPI(page);
 await page.reload();
}

export async function entrer(page:Page, entree:'connexion'|'inscription') {
 await aller(page,entree==='connexion'?'/connexion':'/inscription/soignant');
 await page.getByLabel('Email',{exact:true}).fill(email);
 await page.getByLabel('Mot de passe',{exact:true}).fill('Mot!Solide-Recette2026');
 if(entree==='inscription') {await page.getByLabel('Profession',{exact:true}).selectOption('IDE');await page.getByRole('checkbox',{name:/CGU/}).check();}
 await page.getByRole('button',{name:entree==='connexion'?'Se connecter':'Créer mon compte',exact:true}).click();
 await expect(page).toHaveURL(/\/soignant\/(tableau-de-bord|recherche-missions)$/);
 await expect(page.locator('#app-route-content')).toBeVisible();
 await expect(page.locator('main').getByRole('heading',{level:1})).toContainText(/Explorer|Bonjour|Bonsoir/);
 if(new URL(page.url()).pathname==='/soignant/recherche-missions') {
  // Le titre précède le montage lazy du deck : attendre ses données avant une
  // navigation document complète évite d'interrompre le bootstrap Auth WebKit.
  await expect(page.getByRole('heading',{name:'Aucune nouvelle mission à parcourir',exact:true}).or(page.getByRole('button',{name:/Mission IDE.*Toucher pour le détail/}))).toBeVisible();
 }
 // `waitForLoadState` peut être déjà satisfait par le document /connexion
 // avant sa transition SPA. Mesurer les requêtes actuelles empêche le goto
 // suivant d'annuler une dernière revalidation Auth encore en cours.
 await attendreAPI(page);
 await page.waitForLoadState('networkidle');
}
export async function preuve(page:Page, name:string, info:TestInfo, screenshot=false) {
 const dir=process.env.RECETTE_DIR?`${process.env.RECETTE_DIR}/${info.project.name}`:info.outputPath('preuves');await mkdir(dir,{recursive:true});
 await page.waitForLoadState('networkidle');
 await attendreAPI(page);
 const aria=await page.locator('main').ariaSnapshot();await writeFile(`${dir}/${name}.txt`,aria);await info.attach(`${name}-aria`,{body:aria,contentType:'text/plain'});
 if(screenshot||info.project.name.startsWith('ipad'))await page.screenshot({path:`${dir}/${name}.png`,fullPage:true,animations:'disabled'});
}
export async function sansDebordement(page:Page){expect(await page.evaluate(()=>({document:document.documentElement.scrollWidth,viewport:innerWidth}))).toEqual(expect.objectContaining({document:expect.any(Number)}));expect(await page.evaluate(()=>document.documentElement.scrollWidth-innerWidth)).toBeLessThanOrEqual(1);}
