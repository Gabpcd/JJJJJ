import { mkdir, writeFile } from 'node:fs/promises';
import { test, expect, type Page } from '@playwright/test';

// Parcours complets de plusieurs écrans ; chaque assertion garde son délai court.
test.setTimeout(120_000);

const userId = '69000000-0000-4000-8000-000000000071';
const missionId = '69000000-0000-4000-8000-000000000072';
async function compteNeuf(page: Page, type: 'SOIGNANT' | 'ETABLISSEMENT', offres = false) {
  await page.route('**/*', route => {
    const url = new URL(route.request().url());
    return ['127.0.0.1', 'localhost'].includes(url.hostname) ? route.continue() : route.abort();
  });
  const etat = { profil: null as Record<string, unknown> | null, documents: [] as unknown[], regles: [] as unknown[], publicMode: 'error' as 'error' | 'vide' | 'offres', parrainage: {filleuls: [] as unknown[]} };
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
    await route.fulfill({json: url.pathname.endsWith('/user') ? user : session, headers:{'access-control-allow-origin':'*','access-control-allow-headers':'*'}});
  });
  await page.route('**/rest/v1/**', async route => {
    const req = route.request(); const url = new URL(req.url()); const nom = url.pathname.split('/').pop()!;
    if (!['GET','HEAD','OPTIONS'].includes(req.method()) && !url.pathname.includes('/rpc/')) mutations.push(nom);
    if (/^(presences|contrats_mission|fn_lister_membres_etab|fn_rechercher_soignants_etab|fn_mes_filleuls_etab|fn_mes_credits_etab|fn_mon_score_etab|fn_litiges_etablissement|fn_stats_rh_etablissement|fn_analytics_etablissement)$/.test(nom)) lecturesProtegees.push(nom);
    let data: unknown = [];
    if (nom === 'fn_missions_publiques_recherche') {
      if (etat.publicMode === 'error') return route.fulfill({status:503,json:{message:'Service indisponible'}});
      data = etat.publicMode === 'vide' ? [] : [{...mission,ville:'Paris',code_postal:'75011',total_count:1}];
    }
    else if (nom === 'soignants') data = req.headers().accept?.includes('object') ? etat.profil : etat.profil ? [etat.profil] : [];
    else if (nom === 'documents_requis_par_profession') data = etat.regles;
    else if (nom === 'documents_soignants') data = etat.documents;
    else if (nom === 'fn_obtenir_mes_parrainages') data = etat.parrainage;
    else if (nom === 'fn_mode_exercice') data = {niveau:'AUTORISE',categorie:'prive',source_force:'CONFORMITE_JOLENE',source_libelle:'Fixture de recette',source_url:null};
    else if (nom === 'fn_verifier_coherence_documents') data = {coherent:true};
    else if (nom === 'fn_get_my_role') data = roleCompte;
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
  return { parcours, mutations, errors, roleCompte, lecturesProtegees, etat, mission };
}
async function inscrire(page: Page, type: 'SOIGNANT' | 'ETABLISSEMENT', dejaOuvert = false) {
  if (!dejaOuvert) await page.goto(`/inscription/${type === 'SOIGNANT' ? 'soignant' : 'etablissement'}`);
  await page.getByLabel('Email', {exact:true}).fill('recette-navigation@example.invalid');
  await page.getByLabel('Mot de passe', {exact:true}).fill('Mot!Solide-Recette2026');
  if (type === 'SOIGNANT') await page.getByLabel('Profession', {exact:true}).selectOption('IDE');
  else await page.getByLabel('Nom de l’établissement', {exact:true}).fill('Résidence Camille');
  await page.getByRole('checkbox',{name:/CGU/}).check();
  if (type === 'ETABLISSEMENT') await page.getByRole('checkbox',{name:/conditions générales de vente/}).check();
  await page.getByRole('button',{name:'Créer mon compte',exact:true}).click();
}

async function preuve(page: Page, nom: string, testInfo: any) {
  const mainAria = await page.locator('main').count() ? await page.locator('main').ariaSnapshot() : '';
  const aria = mainAria || await page.locator('body').ariaSnapshot();
  await testInfo.attach(nom + '-aria', {body: aria, contentType:'text/plain'});
  const dir = process.env.RECETTE_DIR
    ? `${process.env.RECETTE_DIR}/${testInfo.project.name}`
    : testInfo.outputPath('preuves');
  await mkdir(dir,{recursive:true});
  await writeFile(`${dir}/${nom}.txt`,aria);
  const capture = `${dir}/${nom}.png`;
  await page.screenshot({path:capture,fullPage:true,animations:'disabled'});
  await testInfo.attach(nom + '-capture', {path:capture,contentType:'image/png'});
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true);
}

for (const viewport of [{width:390,height:844},{width:1440,height:900}]) {
  test(`détail mission : rémunération prioritaire et montants préservés ${viewport.width}`, async ({page},testInfo) => {
    await page.setViewportSize(viewport);
    const {mission,mutations,errors} = await compteNeuf(page,'SOIGNANT',true);
    await inscrire(page,'SOIGNANT');
    await expect(page.getByRole('heading',{name:'Explorer',exact:true})).toBeVisible();
    for (const mode of ['SALARIE','LIBERAL','RETROCESSION'] as const) {
      Object.assign(mission,{
        type_contrat_recherche:mode === 'SALARIE' ? 'SALARIE' : 'LIBERAL',
        mode_remuneration:mode === 'RETROCESSION' ? 'RETROCESSION' : 'TAUX_HORAIRE',
        retrocession_pct:mode === 'RETROCESSION' ? 80 : null,
        net_estime:240,total_brut:240,net_a_payer:240,
      });
      await page.waitForLoadState('networkidle');
      await page.goto(`/soignant/missions/${missionId}`);
      await expect(page.getByRole('heading',{name:'Remplacement infirmier de jour',exact:true})).toBeVisible();
      const remuneration = page.getByRole('region',{name:'Rémunération de la mission',exact:true});
      await expect(remuneration).toHaveCount(1);
      await expect(remuneration).toBeVisible();
      if(mode === 'SALARIE') {
        await expect(remuneration.getByText('Net salarié estimé avant PAS*',{exact:true})).toBeVisible();
        await expect(remuneration.getByText(/240,00\s*€/,{exact:true})).toBeVisible();
        await expect(remuneration).toContainText("Le montant net exact à payer figure sur le bulletin officiel établi par l'établissement employeur.");
      } else if(mode === 'LIBERAL') {
        await expect(remuneration.getByText('Contrat libéral',{exact:true})).toBeVisible();
        await expect(remuneration.getByText('Brut honoraires soignant',{exact:true})).toBeVisible();
        await expect(remuneration.getByText(/240,00\s*€/,{exact:true}).last()).toBeVisible();
      } else {
        await expect(remuneration.getByText('80%',{exact:true})).toBeVisible();
        await expect(remuneration).toContainText('Remplacement de cabinet — rétrocession d’honoraires'.replace('’',"'"));
        await expect(remuneration.getByText(/Décomposition financière/)).toHaveCount(0);
      }
      const titre = await page.getByRole('heading',{level:1}).boundingBox();
      const finance = await remuneration.boundingBox();
      const etablissement = await page.getByRole('heading',{name:'Résidence Camille',exact:true}).boundingBox();
      if (viewport.width < 1024) expect(finance!.y).toBeGreaterThan(titre!.y);
      else expect(finance!.x).toBeGreaterThan(titre!.x);
      expect(finance!.y).toBeLessThan(etablissement!.y);
      expect(finance!.y).toBeLessThan(viewport.height / 2);
      const montant = mode === 'RETROCESSION'
        ? remuneration.getByText('80%',{exact:true})
        : remuneration.getByText(/240,00\s*€/,{exact:true}).last();
      expect((await montant.boundingBox())!.y).toBeLessThan(viewport.height - 84);
      await preuve(page,`detail-${mode.toLowerCase()}-${viewport.width}`,testInfo);
    }
    expect(mutations).toEqual([]);
    expect(errors).toEqual([]);
  });
}
