import { mkdir, writeFile } from 'node:fs/promises';
import { test, expect, type Page } from '@playwright/test';

const userId = '69000000-0000-4000-8000-000000000071';
const missionId = '69000000-0000-4000-8000-000000000072';
async function compteNeuf(page: Page, type: 'SOIGNANT' | 'ETABLISSEMENT', offres = false) {
  const errors: string[] = []; page.on('pageerror', e => errors.push(e.message));
  await page.addInitScript(() => localStorage.setItem('cookie-consent', 'refused'));
  // Ces comptes sont simulés : aucune télémétrie de fixture ne part vers Sentry.
  await page.route(/https:\/\/[^/]+\.ingest\.[^/]+\.sentry\.io\/api\/[^/]+\/envelope\//,
    route => route.fulfill({ json: {} }));
  const user = { id: userId, email: 'recette-navigation@example.invalid', aud: 'authenticated', role: 'authenticated', email_confirmed_at: new Date().toISOString(), app_metadata: {}, user_metadata: {}, identities: [] };
  const session = { user, token_type: 'bearer', access_token: 'fixture-auth', refresh_token: 'fixture-refresh', expires_in: 3600, expires_at: Math.floor(Date.now()/1000)+3600 };
  const parcours = { user_id: userId, type_compte: type, donnees: type === 'SOIGNANT' ? {profession: 'IDE'} as Record<string, unknown> : {nom: 'Résidence Camille'}, modifie_le: new Date().toISOString() };
  const mutations: string[] = [];
  const debut = new Date(Date.now()+7*86400000).toISOString();
  const fin = new Date(Date.now()+7*86400000+8*3600000).toISOString();
  const mission = { id: missionId, cree_le: new Date().toISOString(), intitule: 'Remplacement infirmier de jour', profession_requise: 'IDE', description: 'Renfort équipe de jour.', debut_le: debut, fin_le: fin, duree_heures: 8, nb_creneaux: 1, taux_horaire_base: 30, total_brut: 240, net_estime: 240, net_a_payer: 240, mode_remuneration: 'TAUX_HORAIRE', statut: 'OUVERTE', mode_attribution: 'CANDIDATURE', type_contrat_recherche: 'SALARIE', etablissement_id: '69000000-0000-4000-8000-000000000073', etablissements: {id: '69000000-0000-4000-8000-000000000073', nom: 'Résidence Camille', type:'EHPAD', adresse_ville:'Paris', adresse_code_postal:'75001'}, creneaux: [{id:'creneau',mission_id:missionId,debut,fin,est_pause:false,type_creneau:'PREVISIONNEL'}] };
  await page.route('**/auth/v1/**', async route => {
    const url = new URL(route.request().url());
    await route.fulfill({json: url.pathname.endsWith('/user') ? user : session});
  });
  await page.route('**/rest/v1/**', async route => {
    const req = route.request(); const url = new URL(req.url()); const nom = url.pathname.split('/').pop()!;
    if (!['GET','HEAD','OPTIONS'].includes(req.method()) && !url.pathname.includes('/rpc/')) mutations.push(nom);
    let data: unknown = [];
    if (nom === 'fn_get_my_role') data = {role:'INCONNU',etablissement_id:null};
    else if (nom === 'parcours_inscription') data = req.headers().accept?.includes('object') ? parcours : [parcours];
    else if (nom === 'fn_demarrer_inscription') data = parcours;
    else if (nom === 'fn_enregistrer_parcours_inscription') { Object.assign(parcours.donnees, req.postDataJSON().p_donnees); data = parcours; }
    else if (nom === 'fn_modifier_favori_inscription') {
      const {p_mission_id,p_actif} = req.postDataJSON();
      const ids = new Set(parcours.donnees.missionsSauvegardees as string[] || []);
      if (p_actif) ids.add(p_mission_id); else ids.delete(p_mission_id);
      parcours.donnees.missionsSauvegardees = [...ids]; data = null;
    }
    else if (nom === 'fn_explorer_missions_inscription') data = offres ? [mission] : [];
    else if (nom === 'fn_mon_profil_soignant_complet' || nom === 'fn_mon_etablissement_complet') data = {error:'Profil introuvable'};
    else if (nom === 'fn_compte_auth_actif') data = true;
    else if (nom === 'fn_onboarding_soignant_statut') data = null;
    else if (/candidatur|creer_mission|enregistrer_swipe/.test(nom) && req.method() === 'POST') { mutations.push(nom); data = []; }
    else if (req.headers().accept?.includes('object')) data = null;
    await route.fulfill({json:data, headers:{'content-range':'0-0/0'}});
  });
  await page.route('**/functions/v1/**', route => route.fulfill({json: {}}));
  return { parcours, mutations, errors };
}
async function inscrire(page: Page, type: 'SOIGNANT' | 'ETABLISSEMENT') {
  await page.goto(`/inscription/${type === 'SOIGNANT' ? 'soignant' : 'etablissement'}`);
  await page.getByLabel('Email', {exact:true}).fill('recette-navigation@example.invalid');
  await page.getByLabel('Mot de passe', {exact:true}).fill('Mot!Solide-Recette2026');
  if (type === 'SOIGNANT') await page.getByLabel('Profession', {exact:true}).selectOption('IDE');
  else await page.getByLabel('Nom de l’établissement', {exact:true}).fill('Résidence Camille');
  await page.getByRole('checkbox',{name:/CGU/}).check();
  if (type === 'ETABLISSEMENT') await page.getByRole('checkbox',{name:/conditions générales de vente/}).check();
  await page.getByRole('button',{name:'Créer mon compte',exact:true}).click();
}
async function preuve(page: Page, nom: string, testInfo: any) {
  await expect(page.locator('.page-transition')).toHaveClass(/page-enter/);
  await expect(page.locator('.page-transition')).toHaveCSS('opacity', '1');
  if (process.env.RECETTE_DIR) {
    await mkdir(process.env.RECETTE_DIR, {recursive:true});
    await writeFile(`${process.env.RECETTE_DIR}/${nom}.txt`, await page.locator('body').ariaSnapshot());
    if (/explorer-vide|detail-libre|etablissement-brouillon/.test(nom)) await page.screenshot({path:`${process.env.RECETTE_DIR}/${nom}.png`,fullPage:true,animations:'disabled'});
  }
  await testInfo.attach(`${nom}-aria`, {body:await page.locator('body').ariaSnapshot(),contentType:'text/plain'});
  await testInfo.attach(`${nom}-capture`, {body:await page.screenshot({fullPage:true,animations:'disabled'}),contentType:'image/png'});
}

test('compte soignant neuf : vraie navigation même sans mission, profil facultatif', async ({page}, testInfo) => {
  await page.setViewportSize({width:390,height:844});
  const {mutations} = await compteNeuf(page,'SOIGNANT');
  const errors: string[]=[]; page.on('pageerror', e=>errors.push(e.message));
  await inscrire(page,'SOIGNANT');
  await expect(page).toHaveURL(/soignant\/recherche-missions/);
  await expect(page.getByRole('heading',{name:'Explorer',exact:true})).toBeVisible();
  await expect(page.getByRole('button',{name:'Liste',exact:true})).toHaveCount(0);
  await page.getByRole('tab',{name:'Liste',exact:true}).click();
  await expect(page.getByText(/Aucune mission/).first()).toBeVisible();
  await preuve(page,'explorer-vide',testInfo);
  for (const [label, url] of [['Accueil','tableau-de-bord'],['Mes missions','missions'],['Revenus','mes-gains'],['Profil','mon-compte']] as const) {
    await page.getByRole('button',{name:label,exact:true}).last().click();
    await expect(page).toHaveURL(new RegExp(`/soignant/${url}`));
    await expect(page.locator('main')).toBeVisible();
    await expect(page.getByText('Compléter mes informations',{exact:true})).toHaveCount(0);
    await expect(page.getByRole('button',{name:'Finaliser mon inscription'})).toHaveCount(0);
    await preuve(page,url,testInfo);
  }
  await page.reload();
  await expect(page).toHaveURL(/soignant\/mon-compte/);
  await expect(page.getByRole('button',{name:'Explorer',exact:true}).last()).toBeVisible();
  expect(mutations).toEqual([]); expect(errors).toEqual([]);
});

test('consultation libre puis candidature : dossier demandé seulement au clic, retour possible', async ({page}, testInfo) => {
  await page.setViewportSize({width:390,height:844});
  const {parcours,mutations,errors}=await compteNeuf(page,'SOIGNANT',true);
  await inscrire(page,'SOIGNANT');
  await expect(page).toHaveURL(/soignant\/recherche-missions/);
  await page.getByRole('tab',{name:'Liste',exact:true}).click();
  await page.getByRole('button',{name:'Sauvegarder cette mission',exact:true}).first().click();
  await expect(page.getByRole('button',{name:'Retirer de mes missions sauvegardées'}).first()).toHaveAttribute('aria-pressed','true');
  expect(parcours.donnees.missionsSauvegardees).toEqual([missionId]);
  await page.goto('/soignant/mes-favoris');
  await expect(page.getByRole('heading',{name:'⭐ Missions sauvegardées (1)'})).toBeVisible();
  await page.getByText('Remplacement infirmier de jour',{exact:true}).first().click();
  await expect(page).toHaveURL(new RegExp(`/soignant/missions/${missionId}`));
  await expect(page.getByRole('heading',{name:'Remplacement infirmier de jour'})).toBeVisible();
  await preuve(page,'detail-libre',testInfo);
  await page.getByRole('button',{name:'Candidater',exact:true}).first().click();
  await expect(page).toHaveURL(/inscription\/completer/);
  await expect(page.getByRole('textbox',{name:'Prénom *',exact:true})).toBeVisible();
  expect(parcours.donnees.missionChoisie).toBe(missionId);
  expect(mutations).toEqual([]); expect(errors).toEqual([]);
  await page.getByRole('button',{name:'Retour',exact:true}).click();
  await expect(page).toHaveURL(/soignant\/recherche-missions/);
});

for (const viewport of [{width:390,height:844},{width:1440,height:900}]) {
  test(`établissement neuf : espace et brouillon avant vérification ${viewport.width}`, async ({page},testInfo)=>{
    await page.setViewportSize(viewport);
    const {parcours,mutations,errors}=await compteNeuf(page,'ETABLISSEMENT');
    await inscrire(page,'ETABLISSEMENT');
    await expect(page).toHaveURL(/etablissement\/tableau-de-bord/);
    await expect(page.locator('main')).toBeVisible();
    await preuve(page,`etablissement-accueil-${viewport.width}`,testInfo);
    for (const route of ['missions','messagerie','mon-compte']) {
      await page.goto(`/etablissement/${route}`);
      await expect(page.locator('main')).toBeVisible();
      await expect(page).toHaveURL(new RegExp(`/etablissement/${route}$`));
      await preuve(page,`etablissement-${route}-${viewport.width}`,testInfo);
    }
    await page.goto('/etablissement/parametres?tab=profil');
    await expect(page).toHaveURL(/inscription\/completer/);
    await page.getByRole('button',{name:'Retour',exact:true}).click();
    await expect(page).toHaveURL(/etablissement\/tableau-de-bord/);
    await page.getByRole('button',{name:viewport.width < 768 ? 'Publier' : 'Publier une mission',exact:true}).last().click();
    await expect(page.getByRole('heading',{name:/Publier une mission/})).toBeVisible();
    await page.getByLabel(/Intitulé/).fill('Renfort de nuit');
    await expect(page.getByText(/Veuillez compléter votre SIRET/)).toHaveCount(0);
    await expect(page.getByText(/Votre contrat de service n.est pas encore signé/)).toHaveCount(0);
    await preuve(page,`etablissement-brouillon-${viewport.width}`,testInfo);
    await page.getByRole('button',{name:/^Publier la mission/}).click();
    await expect(page).toHaveURL(/inscription\/completer/);
    expect((parcours.donnees.missionFormulaire as any)?.intitule).toBe('Renfort de nuit');
    expect(mutations).toEqual([]); expect(errors).toEqual([]);
    await page.getByRole('button',{name:'Retour',exact:true}).click();
    await expect(page).toHaveURL(/etablissement\/tableau-de-bord/);
    await page.getByRole('button',{name:viewport.width < 768 ? 'Publier' : 'Publier une mission',exact:true}).last().click();
    await expect(page.getByLabel(/Intitulé/)).toHaveValue('Renfort de nuit');
  });
}


test('le swipe demande le dossier au clic candidature, sans envoyer une candidature', async ({page})=>{
  await page.setViewportSize({width:390,height:844});
  const {parcours,mutations,errors}=await compteNeuf(page,'SOIGNANT',true);
  await inscrire(page,'SOIGNANT');
  await expect(page).toHaveURL(/soignant\/recherche-missions/);
  await page.getByRole('button',{name:'Vérifier le planning avant de postuler à cette mission'}).click();
  await expect(page.getByRole('heading',{name:'Vos informations professionnelles'})).toBeVisible();
  expect(parcours.donnees.missionChoisie).toBe(missionId);
  expect(mutations).toEqual([]); expect(errors).toEqual([]);
});

test('le message anglais de Supabase devient une erreur française dans le formulaire',async ({page})=>{
  await compteNeuf(page,'SOIGNANT');
  await page.route('**/auth/v1/signup**',route=>route.fulfill({status:422,json:{code:'weak_password',msg:'Password is known to be weak and easy to guess, please choose a different one.'}}));
  await inscrire(page,'SOIGNANT');
  await expect(page.getByRole('alert')).toHaveText('Ce mot de passe est trop facile à deviner ou a déjà été divulgué. Choisissez un autre mot de passe.');
  await expect(page.getByLabel('Email',{exact:true})).toHaveValue('recette-navigation@example.invalid');
});


test('une panne de recherche se distingue d’une absence de missions et permet de réessayer', async ({page})=>{
  await compteNeuf(page,'SOIGNANT');
  await page.route('**/rest/v1/rpc/fn_explorer_missions_inscription',route=>route.fulfill({status:503,json:{message:'Service unavailable'}}));
  await inscrire(page,'SOIGNANT');
  await expect(page).toHaveURL(/soignant\/recherche-missions/);
  await page.getByRole('tab',{name:'Liste',exact:true}).click();
  await expect(page.getByRole('alert')).toContainText('Les missions n’ont pas pu être chargées.');
  await expect(page.getByRole('heading',{name:'Aucune mission trouvée'})).toHaveCount(0);
  await page.unroute('**/rest/v1/rpc/fn_explorer_missions_inscription');
  await page.getByRole('button',{name:'Réessayer',exact:true}).click();
  await expect(page.getByRole('heading',{name:'Aucune mission trouvée'})).toBeVisible();
});

test('la carte reste utilisable après une panne et après une visite de la liste', async ({page})=>{
  await compteNeuf(page,'SOIGNANT');
  await inscrire(page,'SOIGNANT');
  await page.getByRole('tab',{name:'Carte',exact:true}).click();
  await expect(page.locator('.leaflet-map-pane')).toHaveCount(1);
  await page.route('**/rest/v1/rpc/fn_explorer_missions_inscription',route=>route.fulfill({status:503,json:{message:'Service unavailable'}}));
  await page.getByRole('button',{name:'🔥 Urgentes',exact:true}).click();
  await expect(page.getByRole('alert')).toContainText('Les missions n’ont pas pu être chargées.');
  await expect(page.getByText('Aucune mission à afficher sur la carte.',{exact:true})).toHaveCount(0);
  await page.unroute('**/rest/v1/rpc/fn_explorer_missions_inscription');
  await page.getByRole('button',{name:'Réessayer',exact:true}).click();
  await expect(page.getByRole('alert')).toHaveCount(0);
  await expect(page.locator('.leaflet-map-pane')).toHaveCount(1);
  await expect(page.getByText('Aucune mission à afficher sur la carte.',{exact:true})).toBeVisible();
  await page.getByRole('tab',{name:'Liste',exact:true}).click();
  await expect(page.locator('.leaflet-map-pane')).toHaveCount(0);
  await page.getByRole('tab',{name:'Carte',exact:true}).click();
  await expect(page.locator('.leaflet-map-pane')).toHaveCount(1);
  await expect(page.getByRole('button',{name:'Zoom avant'})).toBeVisible();
});
