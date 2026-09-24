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
  return { parcours, mutations, errors, roleCompte, lecturesProtegees, etat };
}
async function inscrire(page: Page, type: 'SOIGNANT' | 'ETABLISSEMENT', dejaOuvert = false) {
  if (!dejaOuvert) await page.goto(`/inscription/${type === 'SOIGNANT' ? 'soignant' : 'etablissement'}`);
  await page.getByLabel('Email', {exact:true}).fill('recette-navigation@example.invalid');
  await page.getByLabel('Mot de passe', {exact:true}).fill('Mot!Solide-Recette2026');
  if (type === 'SOIGNANT') await page.getByLabel('Profession', {exact:true}).selectOption('IDE');
  else await page.getByLabel('Nom de l’établissement', {exact:true}).fill('Résidence Camille');
  await page.getByRole('checkbox',{name:/CGU/}).check();
  if (type === 'ETABLISSEMENT') await page.getByRole('checkbox',{name:/conditions générales de vente/}).check();
  // Le titre Explorer précède ses effets de lecture. Attendre la vraie réponse
  // évite de détruire le document WebKit pendant ces requêtes au premier goto.
  const explorationPrete = type === 'SOIGNANT'
    ? page.waitForResponse(response => response.url().includes('/rest/v1/rpc/fn_explorer_missions_inscription'))
    : null;
  await page.getByRole('button',{name:'Créer mon compte',exact:true}).click();
  if (explorationPrete) await (await explorationPrete).finished();
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
  test(`soignant minimal : documents et parrainage, erreurs et reprise ${viewport.width}`, async ({page},testInfo) => {
    await page.setViewportSize(viewport);
    const {etat,mutations,errors} = await compteNeuf(page,'SOIGNANT');
    await inscrire(page,'SOIGNANT');
    await expect(page).toHaveURL(/soignant\/recherche-missions/);
    await expect(page.getByRole('heading',{name:'Explorer',exact:true})).toBeVisible();
    await page.waitForLoadState('networkidle');
    await page.goto('/soignant/mes-documents');
    await expect(page.getByRole('heading',{name:'Votre dossier, quand vous en aurez besoin'})).toBeVisible();
    await expect(page.getByRole('button',{name:'Préparer mon dossier',exact:true})).toBeVisible();
    await expect(page.locator('main').getByRole('alert')).toHaveCount(0);
    await preuve(page,`documents-minimal-${viewport.width}`,testInfo);
    await page.getByRole('tab',{name:'Contrats',exact:true}).click();
    await expect(page.getByText('Aucun contrat',{exact:true})).toBeVisible();
    await page.getByRole('tab',{name:'DPAE',exact:true}).click();
    await expect(page.getByRole('heading',{name:'Aucun contrat salarié signé',exact:true})).toBeVisible();
    await page.getByRole('tab',{name:'Justificatifs',exact:true}).click();
    await expect(page.getByRole('heading',{name:'Votre dossier, quand vous en aurez besoin'})).toBeVisible();
    await page.getByRole('button',{name:'Explorer les missions',exact:true}).click();
    await expect(page).toHaveURL(/soignant\/recherche-missions/);
    await expect(page.getByRole('heading',{name:'Explorer',exact:true})).toBeVisible();

    await page.route('**/rest/v1/soignants**', route => route.fulfill({status:503,json:{message:'Service indisponible'}}));
    await page.waitForLoadState('networkidle');
    await page.goto('/soignant/mes-documents');
    await expect(page.locator('main').getByRole('alert')).toContainText('Documents indisponibles');
    await expect(page.getByText(/Tous tes documents obligatoires sont à jour/)).toHaveCount(0);
    await preuve(page,`documents-erreur-${viewport.width}`,testInfo);
    await page.unroute('**/rest/v1/soignants**');
    etat.profil = {profession:'IDE',type_exercice:'SALARIE',rpps_verifie:true};
    etat.regles = [{id:'r1',profession:'IDE',type_document:'CARTE_IDENTITE',est_critique:true,type_exercice_requis:'TOUS'}];
    etat.documents = [{id:'d1',type_document:'CARTE_IDENTITE',nom_fichier:'identite-test.pdf',statut_verification:'VERIFIE',valide_jusqua:null,televerse_le:'2026-09-01T09:00:00Z'}];
    await page.getByRole('button',{name:'Réessayer',exact:true}).click();
    await expect(page.getByText(/identite-test.pdf/)).toBeVisible();
    await expect(page.getByText(/Tous tes documents obligatoires sont à jour/)).toBeVisible();
    await preuve(page,`documents-reprise-${viewport.width}`,testInfo);

    etat.profil = null;
    await page.waitForLoadState('networkidle');
    await page.goto('/soignant/parrainage');
    await expect(page.getByRole('heading',{name:'Votre lien de parrainage n’est pas encore disponible'})).toBeVisible();
    await expect(page.getByRole('button',{name:'Copier le lien',exact:true})).toHaveCount(0);
    await expect(page.getByRole('img',{name:/QR code/})).toHaveCount(0);
    await expect(page.locator('[href*="?ref="]')).toHaveCount(0);
    await preuve(page,`parrainage-minimal-${viewport.width}`,testInfo);
    await page.route('**/rest/v1/rpc/fn_obtenir_mes_parrainages', route => route.fulfill({status:503,json:{message:'Service indisponible'}}));
    await page.waitForLoadState('networkidle');
    await page.reload();
    await expect(page.getByRole('alert')).toContainText('Parrainage indisponible');
    await expect(page.getByRole('button',{name:'Copier le lien',exact:true})).toHaveCount(0);
    await page.unroute('**/rest/v1/rpc/fn_obtenir_mes_parrainages');
    etat.profil = {code_parrainage:'JO-ABC123',badge_ambassadeur:false};
    etat.parrainage.filleuls = [{filleul_id:'f1',prenom:'Alice',statut:'INSCRIT',gmv_cumule_filleul:320,reste_gmv_avant_prime:180,seuil_gmv:500}];
    await page.getByRole('button',{name:'Réessayer',exact:true}).click();
    await expect(page.getByRole('button',{name:'Copier le lien',exact:true})).toBeVisible();
    await expect(page.getByRole('img',{name:/QR code/})).toBeVisible();
    await expect(page.getByText('Plus que 180 € de missions avant vos primes')).toBeVisible();
    for(const name of ['WhatsApp','SMS','Email','LinkedIn']) {
      const href = await page.getByRole('link',{name,exact:true}).getAttribute('href');
      expect(decodeURIComponent(href!)).toContain('https://jolene.app/inscription/soignant?ref=JO-ABC123');
    }
    await preuve(page,`parrainage-reprise-${viewport.width}`,testInfo);
    expect(mutations).toEqual([]);
    expect(errors).toEqual([]);
  });

  test(`recherche publique : panne, vide, résultats et critères conservés ${viewport.width}`, async ({page},testInfo) => {
    await page.setViewportSize(viewport);
    const {etat,mutations,errors} = await compteNeuf(page,'SOIGNANT',true);
    await page.goto('/');
    await expect(page.getByRole('alert')).toContainText('Recherche indisponible');
    await expect(page.getByText(/Pas de mission pour le moment/)).toHaveCount(0);
    await preuve(page,`recherche-publique-erreur-${viewport.width}`,testInfo);
    etat.publicMode='vide';
    await page.getByRole('button',{name:'Réessayer',exact:true}).click();
    await expect(page.getByText(/Pas de mission pour le moment/)).toBeVisible();
    await expect(page.getByRole('alert')).toHaveCount(0);
    await preuve(page,`recherche-publique-vide-${viewport.width}`,testInfo);
    etat.publicMode='offres';
    await page.getByRole('combobox',{name:'Profession à rechercher',exact:true}).click();
    await page.getByTestId('profession-option-IDE').click();
    await page.getByLabel('Ville ou code postal',{exact:true}).fill('Paris');
    await expect(page.getByText('Remplacement infirmier de jour',{exact:true})).toBeVisible();
    await expect(page.getByRole('status')).toHaveCount(0);
    await preuve(page,`recherche-publique-resultats-${viewport.width}`,testInfo);
    await page.getByRole('button',{name:'Créez votre compte pour postuler →',exact:true}).click();
    await expect(page).toHaveURL(/inscription\/soignant\?profession=IDE&ville=Paris/);
    await expect(page.getByLabel('Profession',{exact:true})).toHaveValue('IDE');
    await inscrire(page,'SOIGNANT',true);
    await expect(page).toHaveURL(/soignant\/recherche-missions/);
    await expect(page.getByRole('heading',{name:'Explorer',exact:true})).toBeVisible();
    await expect(page.getByText('Paris',{exact:false}).first()).toBeVisible();
    await page.getByRole('button',{name:/^Filtres/}).click();
    await expect(page.getByLabel('Ville ou code postal',{exact:false})).toHaveValue('Paris');
    await preuve(page,`explorer-filtres-conserves-${viewport.width}`,testInfo);
    expect(mutations).toEqual([]);
    expect(errors).toEqual([]);
  });
}
