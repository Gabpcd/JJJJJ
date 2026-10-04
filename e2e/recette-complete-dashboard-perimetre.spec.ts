import { test, expect, type Page, type TestInfo, type Request } from '@playwright/test';
import { simulerEtablissement, stabiliserLectures, ids, email } from './helpers/recette-complete-etablissement';
import { chargerHtmlLocal } from './helpers/recette-complete-mission';

const entetes = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*' };
type Mode = 'valide' | 'indisponible' | 'minimal' | 'divergent' | 'absent';

async function preparer(page: Page, modeInitial: Mode) {
  const context = page.context();
  const horsPage: string[] = [];
  // Ferme aussi la première requête d'une éventuelle popup.
  await context.route('**/*', async route => {
    horsPage.push(`${route.request().method()} ${new URL(route.request().url()).pathname}`);
    await route.abort();
  });
  const { etat } = await simulerEtablissement(page, modeInitial === 'minimal' ? 'minimal' : 'complet');
  await page.addInitScript(() => { delete (Navigator.prototype as { serviceWorker?: unknown }).serviceWorker; });
  let mode = modeInitial;
  let numero = 0;
  const roles: { index: number; statut: number; mode: Mode; retardee?: boolean; abandonnee?: boolean }[] = [];
  type LectureRetenue = { demarree: boolean; terminee: boolean; attente: Promise<void>; liberer: () => void };
  let prochaineLectureRetenue: LectureRetenue | null = null;
  const lecturesRetenues: LectureRetenue[] = [];
  const consoleMessages: { type: string; texte: string }[] = [];
  page.on('console', message => consoleMessages.push({ type: message.type(), texte: message.text() }));
  const user = { id: ids.user, email, aud: 'authenticated', role: 'authenticated', email_confirmed_at: new Date().toISOString(),
    app_metadata: modeInitial === 'minimal' ? {} : { role: 'ADMIN_ETABLISSEMENT' }, user_metadata: {}, identities: [] };
  await page.route('**/auth/v1/**', async route => {
    const nom = new URL(route.request().url()).pathname.split('/').pop();
    if (!['token', 'user'].includes(nom!)) return route.fallback();
    await route.fulfill({ json: nom === 'user' ? user : { user, token_type: 'bearer', access_token: 'fixture-auth', refresh_token: 'fixture-refresh', expires_in: 3600, expires_at: Math.floor(Date.now() / 1000) + 3600 }, headers: entetes });
  });
  await page.route('**/rest/v1/rpc/fn_get_my_role', async route => {
    if (route.request().method() === 'OPTIONS') return route.fulfill({ status: 204, body: '', headers: entetes });
    const index = numero++, courant = mode;
    // Une phase explicite cible la lecture provoquée par Réessayer, jamais le
    // nombre de hooks montés avant qu'une autre réponse remplisse leur cache.
    const retenue = prochaineLectureRetenue;
    prochaineLectureRetenue = null;
    if (retenue) {
      retenue.demarree = true;
      await retenue.attente;
      const resultat = { index, statut: 503, mode: courant, retardee: true, abandonnee: false };
      try {
        await route.fulfill({ status: 503, json: { message: 'Ancienne lecture du périmètre indisponible' }, headers: entetes });
      } catch (error) {
        // La seconde reprise annule normalement la première requête. Toute
        // autre erreur du harnais reste un échec, et l'abandon est tracé.
        if (!route.request().failure()) throw error;
      } finally {
        resultat.abandonnee = route.request().failure() !== null;
        roles.push(resultat);
        retenue.terminee = true;
      }
      return;
    }
    const echec = courant === 'indisponible' || courant === 'divergent';
    await new Promise(resolve => setTimeout(resolve, echec ? 1200 : 100));
    roles.push({ index, statut: echec ? 503 : 200, mode: courant });
    if (echec) return route.fulfill({ status: 503, json: { message: 'Indisponibilité simulée du périmètre' }, headers: entetes });
    if (courant === 'absent') return route.fulfill({ json: { role: 'ADMIN_ETABLISSEMENT', etablissement_id: null }, headers: entetes });
    await route.fallback();
  });
  const rpcAutorises = new Set(['fn_get_my_role', 'fn_audit_connexion', 'fn_update_presence', 'fn_ecrire_audit_safe', 'fn_mes_permissions_etab', 'fn_messages_non_lus', 'fn_compte_auth_actif', 'fn_param_bool', 'fn_stats_dashboard_etablissement', 'fn_mes_soignants_etablissement', 'fn_lister_missions_a_noter_etab', 'fn_mes_credits_etab', 'fn_mon_score_etab', 'fn_mon_etablissement_complet', 'fn_capacite_alertes_recherches', 'fn_mode_exercice']);
  const refus: string[] = [];
  await page.route('**/*', async route => {
    const req = route.request(), url = new URL(req.url());
    if (!['127.0.0.1', 'localhost'].includes(url.hostname)) return route.fallback();
    if (/\/(auth|rest|functions|storage)\/v1\//.test(url.pathname)) {
      const nom = url.pathname.split('/').pop()!;
      const autorise = req.method() === 'OPTIONS' ||
        (url.pathname.includes('/auth/v1/') && ['token', 'user'].includes(nom)) ||
        (url.pathname.includes('/rest/v1/rpc/') && rpcAutorises.has(nom)) ||
        (url.pathname.includes('/rest/v1/') && ['GET', 'HEAD'].includes(req.method()));
      if (!autorise) { refus.push(`${req.method()} ${url.pathname}`); return route.abort(); }
      return route.fallback();
    }
    if (req.isNavigationRequest()) {
      const response = await chargerHtmlLocal(route, 0);
      if (response.status() >= 300 && response.status() < 400) { refus.push(`REDIRECTION ${url.pathname}`); return route.abort(); }
      const html = (await response.text()).replace(/<link\b(?=[^>]*\brel=["'](?:preconnect|dns-prefetch)["'])[^>]*>/gi, '');
      return route.fulfill({ response, body: html });
    }
    return route.fallback();
  });
  return { etat, roles, consoleMessages, horsPage, refus, changer: (nouveau: Mode) => { mode = nouveau; },
    retenirProchaineLecture: () => {
      if (prochaineLectureRetenue) throw new Error('Une lecture attend déjà son déclenchement');
      let liberer!: () => void;
      const attente = new Promise<void>(resolve => { liberer = resolve; });
      const lecture = { demarree: false, terminee: false, attente, liberer };
      prochaineLectureRetenue = lecture;
      lecturesRetenues.push(lecture);
      return lecture;
    },
    libererLectures: () => lecturesRetenues.forEach(lecture => lecture.liberer()),
  };
}

async function connecter(page: Page) {
  await page.goto('/connexion');
  await page.getByLabel('Email', { exact: true }).fill(email);
  await page.getByLabel('Mot de passe', { exact: true }).fill('Mot!Solide-Recette2026');
  const bouton = page.getByRole('button', { name: 'Se connecter', exact: true });
  if (test.info().project.use.hasTouch) await bouton.tap(); else await bouton.click();
  await expect(page).toHaveURL(/\/etablissement\/tableau-de-bord$/);
}
async function pret(page: Page) {
  await expect(page.getByTestId('dashboard-etablissement-ready')).toBeAttached({ timeout: 5000 });
  await expect(page.locator('#main-content')).not.toBeEmpty();
  await expect(page.getByRole('heading', { name: 'Établissement non rattaché' })).toHaveCount(0);
  await stabiliserLectures(page);
}
async function manque(page: Page) {
  await expect(page.getByRole('heading', { name: 'Établissement non rattaché' })).toBeVisible({ timeout: 5000 });
  await expect(page.getByTestId('dashboard-etablissement-ready')).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'Préparer une mission', exact: true })).toHaveCount(0);
  await expect(page.locator('#main-content')).not.toBeEmpty();
  await stabiliserLectures(page);
}
async function capturer(page: Page, info: TestInfo, nom: string) {
  const cible = page.locator('#main-content');
  await info.attach(`${nom}-aria`, { body: await cible.ariaSnapshot(), contentType: 'text/plain' });
  await page.screenshot({ path: info.outputPath(`${nom}.png`), animations: 'disabled', scale: 'css' });
}
async function reessayer(page: Page) {
  const bouton = page.getByRole('button', { name: 'Réessayer', exact: true });
  if (test.info().project.use.hasTouch) await bouton.tap(); else await bouton.click();
  await pret(page);
}

for (const mode of ['valide', 'indisponible', 'minimal', 'divergent'] as const) {
  test(`dashboard périmètre ${mode} : contenu, reprise et rechargement`, async ({ page }, info) => {
    const banc = await preparer(page, mode);
    try {
      await connecter(page);
      if (mode === 'minimal') {
        await pret(page);
        await expect(page.getByRole('heading', { name: 'Préparez votre première mission' })).toBeVisible();
        await expect(page.getByText('À compléter avant publication')).toBeVisible();
        expect(banc.etat.appels).not.toContain('POST fn_stats_dashboard_etablissement');
        await capturer(page, info, 'preparation');
        const bouton = page.getByRole('button', { name: 'Préparer une mission', exact: true });
        if (info.project.use.hasTouch) await bouton.tap(); else await bouton.click();
        await expect(page).toHaveURL(/\/etablissement\/missions\/creer$/);
        await stabiliserLectures(page);
        await page.goBack();
        await pret(page);
      } else if (mode === 'indisponible') {
        await manque(page);
        expect(banc.roles.some(r => r.statut === 503)).toBe(true);
        expect(banc.etat.appels).not.toContain('POST fn_stats_dashboard_etablissement');
        await capturer(page, info, 'rattachement-indisponible');
        banc.changer('valide');
        await reessayer(page);
      } else if (mode === 'divergent') {
        await manque(page);
        expect(banc.roles.some(r => r.statut === 503)).toBe(true);
        expect(banc.etat.appels).not.toContain('POST fn_stats_dashboard_etablissement');
        const ancien = banc.retenirProchaineLecture();
        banc.changer('valide');
        const bouton = page.getByRole('button', { name: 'Réessayer', exact: true });
        if (info.project.use.hasTouch) await bouton.tap(); else await bouton.click();
        await expect.poll(() => ancien.demarree, { timeout: 5000 }).toBe(true);
        // Le rôle signé conserve un état explicite pendant cette lecture. Une
        // seconde reprise réelle obtient le scope valide sans attendre l'ancienne.
        await expect(page.getByRole('heading', { name: 'Établissement non rattaché' })).toBeVisible();
        if (info.project.use.hasTouch) await bouton.tap(); else await bouton.click();
        await expect.poll(() => banc.roles.some(r => r.mode === 'valide' && r.statut === 200), { timeout: 5000 }).toBe(true);
        await expect(page.getByTestId('dashboard-etablissement-ready')).toBeAttached({ timeout: 5000 });
        await expect(page.locator('#main-content')).not.toBeEmpty();
        ancien.liberer();
        await expect.poll(() => ancien.terminee, { timeout: 5000 }).toBe(true);
        expect(banc.roles.filter(r => r.retardee && r.statut === 503)).toHaveLength(1);
        await pret(page);
        await capturer(page, info, 'concurrence-reprise');
      } else {
        await pret(page);
        // Un scope précédemment valide n'autorise pas à garder la page après sa perte.
        banc.changer('absent');
        await page.reload();
        await manque(page);
        await capturer(page, info, 'rattachement-perdu');
        banc.changer('valide');
        await reessayer(page);
      }
      await stabiliserLectures(page);
      await page.reload();
      await pret(page);
      await capturer(page, info, 'apres-rechargement');
      expect(banc.etat.erreurs).toEqual([]);
      expect(banc.etat.inconnues).toEqual([]);
      expect(banc.etat.ecritures).toEqual([]);
      expect(banc.etat.operations).toEqual([]);
      expect(banc.horsPage).toEqual([]);
      expect(banc.refus).toEqual([]);
      const erreursConsole = banc.consoleMessages.filter(m => m.type === 'error');
      // Seule la réponse 503 explicitement injectée peut produire une erreur réseau.
      expect(erreursConsole.filter(m => !/Failed to load resource.*503/.test(m.texte))).toEqual([]);
      if (erreursConsole.length) expect(banc.roles.some(r => r.statut === 503)).toBe(true);
    } finally {
      banc.libererLectures();
      await info.attach('reseau-et-console', { body: JSON.stringify({ roles: banc.roles, appels: banc.etat.appels, ecritures: banc.etat.ecritures, operations: banc.etat.operations, inconnues: banc.etat.inconnues, erreurs: banc.etat.erreurs, refus: banc.refus, horsPage: banc.horsPage, console: banc.consoleMessages }, null, 2), contentType: 'application/json' });
    }
  });
}

for (const navigation of ['onglet', 'document'] as const) {
  test(`dashboard lecture abandonnée : ${navigation}, retour et rechargement`, async ({ page }, info) => {
    const banc = await preparer(page, 'valide');
    let requeteRetenue: Request | undefined;
    let requeteBandeauRetenue: Request | undefined;
    let liberer!: () => void;
    let terminee = false;
    let bandeauTermine = false;
    let lecturesStats = 0;
    let lecturesBandeau = 0;
    let profilAvantDepart: { statut: number; termine: boolean } | null = null;
    const retenue = new Promise<void>(resolve => { liberer = resolve; });
    await page.route('**/rest/v1/etablissements?**', async route => {
      const requete = route.request();
      if (requete.method() !== 'GET' || new URL(requete.url()).searchParams.get('select') !== 'contrat_service_signe') return route.fallback();
      lecturesBandeau++;
      if (lecturesBandeau > 1) return route.fallback();
      requeteBandeauRetenue = requete;
      await retenue;
      try {
        // Une ancienne réponse non signée ne doit pas réafficher un bandeau au
        // retour ; les lectures suivantes retrouvent le vrai état signé du banc.
        await route.fulfill({ json: { contrat_service_signe: false }, headers: entetes });
      } catch (error) {
        if (!requete.failure()) throw error;
      } finally { bandeauTermine = true; }
    });
    await page.route('**/rest/v1/rpc/fn_stats_dashboard_etablissement', async route => {
      if (route.request().method() === 'OPTIONS') return route.fallback();
      lecturesStats++;
      if (lecturesStats > 1) return route.fallback();
      requeteRetenue = route.request();
      await retenue;
      try {
        await route.fulfill({ json: { missions_ouvertes: 123 }, headers: entetes });
      } catch (error) {
        if (!route.request().failure()) throw error;
      } finally { terminee = true; }
    });
    try {
      // Le document doit quitter les deux lectures retenues, pas une lecture
      // encore en cours du cadre. Préenregistrer avant le montage du dashboard.
      const reponseProfil = navigation === 'document' ? page.waitForResponse(response => {
        const url = new URL(response.url());
        return response.request().method() === 'GET' && url.pathname === '/rest/v1/etablissements'
          && url.searchParams.get('select') === 'nom,logo_url'
          && url.searchParams.get('id') === `eq.${ids.etab}`;
      }) : null;
      await connecter(page);
      await expect.poll(() => Boolean(requeteRetenue)).toBe(true);
      await expect.poll(() => Boolean(requeteBandeauRetenue)).toBe(true);
      await expect(page.getByTestId('dashboard-etablissement-ready')).toHaveCount(0);
      if (navigation === 'onglet') {
        const sidebar = page.getByRole('navigation', { name: 'Sidebar', exact: true });
        const barre = await sidebar.isVisible() ? sidebar : page.getByRole('navigation', { name: 'Navigation mobile', exact: true });
        await barre.getByRole('button', { name: 'Missions', exact: true }).click();
      } else {
        const profil = await reponseProfil!;
        expect(profil.status()).toBe(200);
        expect(await profil.finished()).toBeNull();
        profilAvantDepart = { statut: profil.status(), termine: true };
        expect(requeteRetenue!.failure()).toBeNull();
        expect(requeteBandeauRetenue!.failure()).toBeNull();
        expect({ terminee, bandeauTermine, lecturesStats, lecturesBandeau }).toEqual({
          terminee: false, bandeauTermine: false, lecturesStats: 1, lecturesBandeau: 1,
        });
        // Reproduire aussi le remplacement complet qui a annulé la RPC en CI.
        await page.goto('/etablissement/missions');
      }
      await expect(page).toHaveURL(/\/etablissement\/missions$/);
      await expect.poll(() => Boolean(requeteRetenue?.failure()), { message: 'La lecture quittée doit être annulée' }).toBe(true);
      await expect.poll(() => Boolean(requeteBandeauRetenue?.failure()), { message: 'La lecture du bandeau quitté doit aussi être annulée' }).toBe(true);
      liberer();
      await expect.poll(() => terminee).toBe(true);
      await expect.poll(() => bandeauTermine).toBe(true);
      await stabiliserLectures(page);
      await capturer(page, info, `depart-${navigation}`);
      const avantRetour = lecturesBandeau;
      const reponseBandeauRetour = page.waitForResponse(response => response.request().method() === 'GET'
        && new URL(response.url()).pathname.endsWith('/rest/v1/etablissements')
        && new URL(response.url()).searchParams.get('select') === 'contrat_service_signe'
        && response.status() === 200);
      await page.goBack();
      await pret(page);
      expect(await (await reponseBandeauRetour).json()).toEqual([expect.objectContaining({ contrat_service_signe: true })]);
      expect(lecturesStats).toBeGreaterThanOrEqual(2);
      expect(lecturesBandeau).toBeGreaterThan(avantRetour);
      await expect(page.getByTestId('onboarding-etab-banner')).toHaveCount(0);
      await expect(page.getByText(/Certaines données n'ont pas pu être chargées/)).toHaveCount(0);
      const avantRechargement = lecturesBandeau;
      const reponseBandeauRecharge = page.waitForResponse(response => response.request().method() === 'GET'
        && new URL(response.url()).pathname.endsWith('/rest/v1/etablissements')
        && new URL(response.url()).searchParams.get('select') === 'contrat_service_signe'
        && response.status() === 200);
      await page.reload();
      await pret(page);
      expect(await (await reponseBandeauRecharge).json()).toEqual([expect.objectContaining({ contrat_service_signe: true })]);
      expect(lecturesBandeau).toBeGreaterThan(avantRechargement);
      await expect(page.getByTestId('onboarding-etab-banner')).toHaveCount(0);
      await capturer(page, info, `retour-${navigation}-recharge`);
      expect(banc.consoleMessages.filter(m => m.type === 'error')).toEqual([]);
      expect(banc.etat.erreurs).toEqual([]);
      expect(banc.etat.inconnues).toEqual([]);
      expect(banc.horsPage).toEqual([]);
      expect(banc.refus).toEqual([]);
    } finally {
      liberer(); banc.libererLectures();
      await info.attach('lecture-abandonnee', { body: JSON.stringify({ navigation, profilAvantDepart, lecturesStats, lecturesBandeau, annulation: requeteRetenue?.failure(), annulationBandeau: requeteBandeauRetenue?.failure(), console: banc.consoleMessages, erreurs: banc.etat.erreurs }, null, 2), contentType: 'application/json' });
    }
  });
}

test('dashboard lecture active : une vraie panne reste visible puis se rétablit au rechargement', async ({ page }, info) => {
  const banc = await preparer(page, 'valide');
  banc.etat.pannes.add('fn_stats_dashboard_etablissement');
  try {
    await connecter(page);
    await pret(page);
    await expect(page.getByText(/Certaines données n'ont pas pu être chargées/)).toBeVisible();
    await capturer(page, info, 'panne-stats-active');
    const erreursAttendues = banc.consoleMessages.filter(m => m.type === 'error');
    expect(erreursAttendues.some(m => m.texte.includes('[DashboardEtab] Erreur stats RPC') && m.texte.includes('Service de recette indisponible'))).toBe(true);
    expect(erreursAttendues.filter(m => !m.texte.includes('[DashboardEtab] Erreur stats RPC') && !/Failed to load resource.*503/.test(m.texte))).toEqual([]);
    banc.etat.pannes.delete('fn_stats_dashboard_etablissement');
    const apresPanne = banc.consoleMessages.length;
    await page.reload();
    await pret(page);
    await expect(page.getByText(/Certaines données n'ont pas pu être chargées/)).toHaveCount(0);
    await capturer(page, info, 'panne-stats-reprise');
    expect(banc.consoleMessages.slice(apresPanne).filter(m => m.type === 'error')).toEqual([]);
    expect(banc.etat.erreurs).toEqual([]);
    expect(banc.etat.inconnues).toEqual([]);
    expect(banc.horsPage).toEqual([]);
    expect(banc.refus).toEqual([]);
  } finally { banc.libererLectures(); }
});
