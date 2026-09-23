import { mkdir, writeFile } from 'node:fs/promises';
import { test, expect, type Page } from '@playwright/test';

// Parcours complets de plusieurs écrans ; chaque assertion garde son délai court.
test.setTimeout(120_000);

const userId = '69000000-0000-4000-8000-000000000071';
const missionId = '69000000-0000-4000-8000-000000000072';
async function compteNeuf(page: Page, type: 'SOIGNANT' | 'ETABLISSEMENT', offres = false) {
  const roleCompte = {role:'INCONNU',etablissement_id:null as string | null};
  const lecturesProtegees: string[] = [];
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
    if (/^(presences|contrats_mission|fn_lister_membres_etab|fn_rechercher_soignants_etab|fn_mes_filleuls_etab|fn_mes_credits_etab|fn_mon_score_etab|fn_litiges_etablissement|fn_stats_rh_etablissement|fn_analytics_etablissement)$/.test(nom)) lecturesProtegees.push(nom);
    let data: unknown = [];
    if (nom === 'fn_get_my_role') data = roleCompte;
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
  return { parcours, mutations, errors, roleCompte, lecturesProtegees };
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

const rubriques = [
  ['presences', 'Présences'], ['contrats', 'Contrats'], ['rh', 'Tableau RH'],
  ['export-paie', 'Export paie'], ['soignants', 'Annuaire des soignants'],
  ['equipe', 'Mon équipe'], ['parrainage', 'Parrainage entre établissements'],
  ['score', 'Score qualité'], ['litiges', 'Litiges et contestations'], ['facturation', 'Facturation'],
] as const;

async function conserverPreuve(page: Page, nom: string, testInfo: any) {
  const aria = await page.locator('main').ariaSnapshot();
  await testInfo.attach(nom + '-aria', {body: aria, contentType: 'text/plain'});
  const dossier = process.env.RECETTE_DIR
    ? `${process.env.RECETTE_DIR}/${testInfo.project.name}`
    : testInfo.outputPath('preuves');
  await mkdir(dossier, {recursive: true});
  await writeFile(`${dossier}/${nom}.txt`, aria);
  const capture = `${dossier}/${nom}.png`;
  await page.screenshot({path:capture,fullPage:!nom.includes('formulaire'),animations:'disabled'});
  await testInfo.attach(nom + '-capture', {path:capture,contentType:'image/png'});
}

for (const viewport of [{width:390,height:844},{width:1440,height:900}]) {
  test(`compte établissement minimal : toutes les rubriques aboutissent ${viewport.width}`, async ({page},testInfo) => {
    await page.setViewportSize(viewport);
    const {lecturesProtegees,mutations,errors} = await compteNeuf(page,'ETABLISSEMENT');
    await inscrire(page,'ETABLISSEMENT');
    await expect(page).toHaveURL(/etablissement\/tableau-de-bord/);
    await expect(page.getByTestId('dashboard-etablissement-ready')).toBeAttached();
    for (const [route, titre] of rubriques) {
      await page.goto(`/etablissement/${route}`);
      await expect(page.getByRole('heading',{level:1,name:titre,exact:true})).toBeVisible();
      await expect(page.getByRole('link',{name:'Préparer une mission',exact:true})).toBeVisible();
      await expect(page.getByRole('link',{name:'Compléter mon établissement',exact:true})).toBeVisible();
      await expect(page.locator('main').getByRole('alert')).toHaveCount(0);
      await expect(page.getByRole('status',{name:'Chargement en cours',exact:true})).toHaveCount(0);
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true);
      await conserverPreuve(page,`etablissement-${route}-${viewport.width}`,testInfo);
    }
    await page.getByRole('link',{name:'Préparer une mission',exact:true}).click();
    await expect(page.getByLabel(/Intitulé/)).toBeVisible();
    await expect(page.getByTestId('introduction-mission')).toHaveCount(1);
    await expect(page.getByTestId('introduction-mission')).not.toContainText('Brouillon repris');
    expect((await page.getByLabel(/Intitulé/).boundingBox())!.y).toBeLessThan(480);
    await conserverPreuve(page,`etablissement-formulaire-neuf-${viewport.width}`,testInfo);
    await page.getByLabel(/Intitulé/).fill('Mission conservée après exploration');
    await page.getByRole('button',{name:/^Publier la mission/}).click();
    await expect(page).toHaveURL(/inscription\/completer/);
    await page.getByRole('button',{name:'Retour',exact:true}).click();
    await expect(page).toHaveURL(/etablissement\/tableau-de-bord/);
    await expect(page.getByTestId('dashboard-etablissement-ready')).toBeAttached();
    await page.goto('/etablissement/facturation');
    await page.getByRole('link',{name:'Préparer une mission',exact:true}).click();
    await expect(page.getByLabel(/Intitulé/)).toHaveValue('Mission conservée après exploration');
    await expect(page.getByTestId('introduction-mission')).toHaveCount(1);
    await expect(page.getByTestId('introduction-mission')).toContainText('Brouillon repris — Mission conservée après exploration');
    await conserverPreuve(page,`etablissement-formulaire-repris-${viewport.width}`,testInfo);
    expect(lecturesProtegees).toEqual([]);
    expect(mutations).toEqual([]);
    expect(errors).toEqual([]);
  });

  test(`établissement identifié : vrais états vides et refus de permissions ${viewport.width}`, async ({page},testInfo) => {
    await page.setViewportSize(viewport);
    const {roleCompte,errors} = await compteNeuf(page,'ETABLISSEMENT');
    await inscrire(page,'ETABLISSEMENT');
    await expect(page).toHaveURL(/etablissement\/tableau-de-bord/);
    await expect(page.getByTestId('dashboard-etablissement-ready')).toBeAttached();
    await page.goto('/etablissement/contrats');
    await expect(page.getByRole('link',{name:'Compléter mon établissement',exact:true})).toBeVisible();
    roleCompte.role = 'ADMIN_ETABLISSEMENT';
    roleCompte.etablissement_id = '69000000-0000-4000-8000-000000000073';
    await page.reload();
    await expect(page.getByText('Aucun contrat',{exact:true})).toBeVisible();
    await expect(page.getByRole('link',{name:'Compléter mon établissement',exact:true})).toHaveCount(0);
    await conserverPreuve(page,`etablissement-contrats-identifie-${viewport.width}`,testInfo);
    await page.route('**/rest/v1/rpc/fn_lister_membres_etab', route => route.fulfill({json:{success:false,error_code:'NON_AUTORISE'}}));
    await page.goto('/etablissement/equipe');
    await expect(page.getByText("Vous n'êtes pas membre de cette équipe.")).toBeVisible();
    await expect(page.getByRole('button',{name:'Inviter un membre'})).toHaveCount(0);
    await conserverPreuve(page,`etablissement-equipe-refus-${viewport.width}`,testInfo);
    await page.route('**/rest/v1/contrats_mission**', route => route.fulfill({status:503,json:{message:'Service indisponible'}}));
    await page.goto('/etablissement/contrats');
    await expect(page.getByRole('alert')).toContainText('Contrats indisponibles');
    await expect(page.getByText('Aucun contrat',{exact:true})).toHaveCount(0);
    await page.unroute('**/rest/v1/contrats_mission**');
    await page.getByRole('button',{name:'Réessayer',exact:true}).click();
    await expect(page.getByText('Aucun contrat',{exact:true})).toBeVisible();
    roleCompte.etablissement_id = null;
    await page.reload();
    await expect(page.getByRole('alert')).toContainText('Établissement non rattaché');
    await expect(page.getByRole('link',{name:'Compléter mon établissement',exact:true})).toHaveCount(0);
    await conserverPreuve(page,`etablissement-rattachement-manquant-${viewport.width}`,testInfo);
    expect(errors).toEqual([]);
  });
}
