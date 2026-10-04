import { expect, test, type Locator, type Page, type TestInfo } from '@playwright/test';
import { ids, preuve, simulerEtablissement, stabiliserLectures } from './helpers/recette-complete-etablissement';

// Recette du vrai App/LayoutAdmin, avec services externes bloqués.
// Les opérations métier restent interdites, même sur les dossiers fictifs.
// Les réponses HTTP et identités ci-dessous sont exclusivement synthétiques.
const A = '79100000-0000-4000-8000-000000000001';
const B = '79100000-0000-4000-8000-000000000002';
const E = '79100000-0000-4000-8000-000000000003';
const nomA = 'Alix Dossier Alpha', nomB = 'Béatrice Dossier Bêta';
const nomE = 'Établissement Cadre Complet';
const soignant = (id: string, prenom: string, nom: string, diplome_verifie: boolean) => ({
  id, prenom, nom, profession: 'AS', email: `${id}@example.invalid`, telephone: null,
  date_naissance: null, numero_rpps: null, numero_adeli: null, adresse_lat: null,
  adresse_lng: null, score_fiabilite: null, prevoyance_inscrit: false,
  prevoyance_fournisseur: null, eligible_conversion_3200h: false,
  cree_le: '2026-10-01T12:00:00Z', rayon_deplacement_km: 30,
  modifie_le: '2026-10-01T12:00:00Z', derniere_activite_le: null,
  diplome_verifie, statut_verification_aria: 'EN_ATTENTE', rpps_verifie: false,
  tous_documents_valides: false, identite_verifiee: true, est_compte_test: true,
  total_missions_terminees: 0, total_missions_annulees: 0, heures_cumulees: 0,
  total_retards_pointage: 0, total_absences: 0, type_contrat: 'SALARIE',
});
const soignants = [soignant(A, 'Alix', 'Dossier Alpha', false), soignant(B, 'Béatrice', 'Dossier Bêta', true)];
const etablissement = {
  id: E, nom: nomE, est_compte_test: true, email_contact: 'cadre-complet@example.invalid',
  telephone_contact: null, siret: '00000000000000', finess: null, type: 'EHPAD',
  statut_verification: 'VERIFIE', est_verifie: true, adresse_rue: '1 rue fictive',
  adresse_code_postal: '00000', adresse_ville: 'Ville témoin', adresse_departement: null,
  adresse_lat: null, adresse_lng: null, cree_le: '2026-10-01T12:00:00Z',
  formule_abonnement: null, taux_commission_negocie: null, delai_paiement_jours: null,
  mode_facturation: null, mode_paiement_commission: null, convention_collective: null,
  chorus_pro_actif: false, rist_plafond_actif: false, taux_majoration_nuit_pourcent: null,
  taux_majoration_dimanche_pourcent: null, taux_majoration_ferie_pourcent: null,
};
const document = (nom: string, statut: string, revoque_le: string | null = null) => ({
  id: nom, type_document: 'DIPLOME', statut_verification: statut, revoque_le,
  supprime_le: null, nom_fichier: `${nom}.pdf`, televerse_le: '2026-10-01T12:00:00Z', valide_jusqua: null,
});
const documents: Record<string, ReturnType<typeof document>[]> = {
  [A]: [document('alpha-verifie', 'VERIFIE'), document('alpha-attente', 'EN_ATTENTE')],
  [B]: [document('beta-revoque', 'VERIFIE', '2026-10-02T12:00:00Z'), document('beta-rejete', 'REJETE')],
};
const titre = (page: Page, nom: string) => page.getByRole('heading', { name: nom, exact: true });
const tab = (page: Page, nom: string) => page.getByRole('tab', { name: nom, exact: true });

async function preparer(page: Page, options: { refuser?: boolean; retarder?: boolean } = {}) {
  const preview = new URL(process.env.PLAYWRIGHT_BASE_URL || 'http://127.0.0.1:8890');
  expect(['127.0.0.1', 'localhost']).toContain(preview.hostname);
  const { etat } = await simulerEtablissement(page);
  etat.overrides.set('fn_get_my_role', { role: 'ADMIN_PLATEFORME' });
  etat.overrides.set('fn_admin_mes_acces', { acces_total: true, groupes: [] });
  const suivi = {
    refuser: !!options.refuser, retarder: !!options.retarder, attente: false,
    reponseLivree: false, documentsA: 0, refus: 0, navigations: 0,
    lectures: [] as string[], interdits: [] as string[], console: [] as { type: string; texte: string; url: string }[],
    autoriserReponse: () => {},
  };
  const livraison = new Promise<void>(resolve => { suivi.autoriserReponse = resolve; });
  page.on('request', req => { if (req.isNavigationRequest() && req.resourceType() === 'document') suivi.navigations++; });
  page.on('console', msg => { if (msg.type() === 'error' || msg.type() === 'warning') suivi.console.push({ type: msg.type(), texte: msg.text(), url: msg.location().url }); });
  const rpcInertes = new Set(['fn_get_my_role', 'fn_admin_mes_acces', 'fn_compte_auth_actif', 'fn_messages_non_lus', 'fn_update_presence', 'fn_audit_connexion', 'fn_ecrire_audit_safe']);
  await page.route('**/*', async route => {
    const req = route.request(), url = new URL(req.url()), nom = url.pathname.split('/').pop()!;
    if (!/\/(auth|rest|functions|storage)\/v1\//.test(url.pathname)) return route.fallback();
    if (!['127.0.0.1', 'localhost'].includes(url.hostname)) return route.fallback();
    const repondre = (json: unknown, status = 200) => route.fulfill({ status, json,
      headers: { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': 'GET,POST,OPTIONS' } });
    if (req.method() === 'OPTIONS') return route.fulfill({ status: 204, body: '', headers: { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': 'GET,POST,OPTIONS' } });
    const rpc = url.pathname.startsWith('/rest/v1/rpc/');
    const auth = url.pathname.startsWith('/auth/v1/');
    if (url.pathname.startsWith('/functions/') || url.pathname.startsWith('/storage/') ||
      (!['GET', 'HEAD'].includes(req.method()) && !(rpc && req.method() === 'POST' && (rpcInertes.has(nom) || nom === 'fn_admin_recherche_globale')) && !(auth && nom === 'token'))) {
      suivi.interdits.push(`${req.method()} ${url.pathname}`);
      return repondre({ code: 'RECETTE_SANS_ACTION', message: 'Action hors recette.' }, 501);
    }
    if (rpc && nom === 'fn_admin_recherche_globale') {
      expect(req.postDataJSON()).toEqual({ p_query: 'Béatrice' });
      return repondre({ utilisateurs: [{ ...soignants[1], type: 'soignant', ville: null }], missions: [], factures: [] });
    }
    if (!url.pathname.startsWith('/rest/v1/') || rpc) return route.fallback();
    const filtre = (cle: string) => url.searchParams.get(cle)?.replace(/^eq\./, '');
    const id = filtre('id');
    const lignes = (rows: unknown[]) => repondre(req.headers().accept?.includes('object') ? rows[0] ?? null : rows);
    if (nom === 'soignants') return lignes(id ? soignants.filter(s => s.id === id) : soignants);
    if (nom === 'etablissements') return lignes(id ? [etablissement].filter(e => e.id === id) : [etablissement]);
    if (nom === 'documents_soignants') {
      const dossier = filtre('soignant_id');
      expect([A, B]).toContain(dossier);
      expect(url.searchParams.get('supprime_le')).toBe('is.null');
      suivi.lectures.push(`documents:${dossier}`);
      if (dossier === A) {
        suivi.documentsA++;
        if (suivi.refuser) { suivi.refus++; return repondre({ code: '42501', message: 'Lecture refusée — simulation.' }, 403); }
        if (suivi.retarder) { suivi.attente = true; await livraison; }
      }
      await repondre(documents[dossier!]);
      if (dossier === A && suivi.retarder) suivi.reponseLivree = true;
      return;
    }
    if (nom === 'documents_requis_par_profession') {
      expect(filtre('profession')).toBe('AS');
      return repondre([{ type_document: 'DIPLOME', est_critique: true }]);
    }
    if (nom === 'emails_envoyes') return lignes([]);
    if (nom === 'missions' && (filtre('soignant_assigne_id') || filtre('etablissement_id'))) return repondre([]);
    return route.fallback();
  });
  await page.addInitScript(({ id }) => {
    sessionStorage.setItem('sb-127-auth-token', JSON.stringify({
      user: { id, email: 'admin-recette@example.invalid', email_confirmed_at: '2026-10-01T12:00:00Z', app_metadata: { role: 'ADMIN_PLATEFORME' }, user_metadata: {}, aud: 'authenticated', role: 'authenticated' },
      access_token: 'simulation-admin', refresh_token: 'simulation-admin-refresh', token_type: 'bearer',
      expires_in: 3600, expires_at: Math.floor(Date.now() / 1000) + 3600,
    }));
  }, { id: ids.user });
  await page.goto('/admin/utilisateurs');
  await expect(titre(page, 'Gestion utilisateurs')).toBeVisible();
  await stabiliserLectures(page);
  return { etat, suivi };
}

// Mesure le vrai cadre fixe, distinct du header éditorial de chaque page.
async function accessible(page: Page, controle: Locator) {
  await controle.scrollIntoViewIfNeeded();
  await expect(controle).toBeVisible();
  await expect.poll(() => controle.evaluate(el => {
    const r = el.getBoundingClientRect();
    const visible = (selector: string) => [...document.querySelectorAll(selector)].find(e => e.getClientRects().length > 0);
    const haut = visible('.admin-shell > header')?.getBoundingClientRect().bottom ?? 0;
    const bas = visible('nav[aria-label="Navigation mobile admin"]')?.getBoundingClientRect().top ?? innerHeight;
    const x = r.left + r.width / 2, y = r.top + r.height / 2;
    const hit = document.elementFromPoint(x, y);
    return r.top >= haut - 1 && r.bottom <= bas + 1 && r.left >= -1 && r.right <= innerWidth + 1 && !!hit && el.contains(hit);
  }), { message: 'Le contrôle reste dans le viewport et au-dessus du contenu, hors header/navigation fixes' }).toBe(true);
}
async function onglet(page: Page, nom: string) {
  await accessible(page, tab(page, nom));
  await tab(page, nom).click();
  await expect(tab(page, nom)).toHaveAttribute('aria-selected', 'true');
  await expect(page.getByRole('tabpanel', { name: nom, exact: true })).toBeVisible();
}
async function ouvrir(page: Page, nom: string, etab = false) {
  await expect(titre(page, 'Gestion utilisateurs')).toBeVisible();
  if (etab) await page.getByRole('tab', { name: /^Établissements/ }).click();
  await page.getByRole('textbox', { name: 'Rechercher un utilisateur', exact: true }).fill(nom);
  const details = page.getByRole('tabpanel').getByRole('button', { name: 'Détails', exact: true });
  await expect(details).toHaveCount(1);
  await accessible(page, details);
  await details.click();
}
async function retour(page: Page) {
  const bouton = page.getByRole('button', { name: 'Retour', exact: true });
  await accessible(page, bouton); await bouton.click();
  await expect(titre(page, 'Gestion utilisateurs')).toBeVisible();
}
async function bilan(page: Page, ctx: Awaited<ReturnType<typeof preparer>>, info: TestInfo, nom: string) {
  await stabiliserLectures(page);
  expect(ctx.etat.inconnues).toEqual([]); expect(ctx.etat.erreurs).toEqual([]);
  expect(ctx.etat.ecritures).toEqual([]); expect(ctx.suivi.interdits).toEqual([]);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1)).toBe(true);
  await info.attach(`${nom}-transport`, { body: JSON.stringify({ ...ctx.suivi, autoriserReponse: undefined, appels: ctx.etat.appels }, null, 2), contentType: 'application/json' });
  // Le blocage Playwright remplace register() par une réponse sans objet.
  // Classer uniquement le couple observé ; conserver sa trace et sa cardinalité.
  const blocageSW = 'Service Worker registration blocked by Playwright';
  const suiteSW = (msg: typeof ctx.suivi.console[number]) => {
    if (msg.type !== 'warning') return false;
    const premiereLigne = msg.texte.split('\n')[0];
    const messageAttendu = /^SW registration failed: TypeError: undefined is not an object \(evaluating '[\w$]+\.addEventListener'\)$/.test(premiereLigne)
      || premiereLigne === "SW registration failed: TypeError: Cannot read properties of undefined (reading 'addEventListener')";
    try {
      const url = new URL(msg.url);
      return messageAttendu && url.origin === new URL(process.env.PLAYWRIGHT_BASE_URL || 'http://127.0.0.1:8890').origin
        && /^\/assets\/index-[\w-]+\.js$/.test(url.pathname);
    } catch { return false; }
  };
  const blocages = ctx.suivi.console.filter(m => m.type === 'warning' && m.texte === blocageSW);
  const suites = ctx.suivi.console.filter(suiteSW);
  expect(blocages.length).toBeLessThanOrEqual(ctx.suivi.navigations);
  expect(suites.length).toBeLessThanOrEqual(blocages.length);
  const consoleInattendue = ctx.suivi.console.filter(msg => {
    if (info.project.use.serviceWorkers === 'block' && msg.type === 'warning' &&
      (msg.texte === blocageSW || suiteSW(msg))) return false;
    if (!ctx.suivi.refus || !/Failed to load resource.*403/.test(msg.texte)) return true;
    try {
      const url = new URL(msg.url);
      return !(['127.0.0.1', 'localhost'].includes(url.hostname) && url.pathname === '/rest/v1/documents_soignants' && url.searchParams.get('soignant_id') === `eq.${A}`);
    } catch { return true; }
  });
  expect(consoleInattendue).toEqual([]);
  await preuve(page, nom, info);
  await info.attach(`${nom}-cadre-visible`, { body: await page.screenshot({ fullPage: false, animations: 'disabled' }), contentType: 'image/png' });
}

test('admin intégré — liste, onglets soignant, rechargement et retour', async ({ page }, info) => {
  const ctx = await preparer(page);
  await ouvrir(page, nomA); await expect(titre(page, nomA)).toBeVisible();
  await accessible(page, titre(page, nomA));
  await onglet(page, 'Fiabilité');
  await expect(page.getByRole('tabpanel')).toContainText('1 pièce vérifiée');
  await expect(page.getByRole('tabpanel')).toContainText('1 pièce en attente');
  await page.getByRole('button', { name: 'Consulter les documents', exact: true }).click();
  await expect(tab(page, 'Documents')).toHaveAttribute('aria-selected', 'true');
  await expect(page.getByRole('tabpanel')).toContainText('alpha-verifie.pdf');
  await onglet(page, 'Missions'); await expect(page.getByRole('tabpanel')).toContainText('Aucune mission.');
  await onglet(page, 'Fiche complète'); await expect(page.getByRole('tabpanel')).toContainText(soignants[0].email);
  await onglet(page, 'Actions admin'); await expect(page.getByRole('tabpanel')).toContainText('Actions administrateur');
  await onglet(page, 'Vue d’ensemble');
  await stabiliserLectures(page); await page.reload();
  await expect(titre(page, nomA)).toBeVisible(); await expect(tab(page, 'Vue d’ensemble')).toHaveAttribute('aria-selected', 'true');
  await onglet(page, 'Documents'); await expect(page.getByRole('tabpanel')).toContainText('alpha-attente.pdf');
  await bilan(page, ctx, info, 'admin-integre-soignant-reload');
  await retour(page); await expect(page.getByRole('textbox', { name: 'Rechercher un utilisateur' })).toBeVisible();
});

test('admin intégré — menu du cadre, établissement, reprise et changement de dossier', async ({ page }, info) => {
  const ctx = await preparer(page);
  if (page.viewportSize()!.width < 768) {
    const plus = page.getByRole('button', { name: 'Plus', exact: true });
    await expect(plus).toBeVisible(); await plus.click();
    const menu = page.getByRole('dialog', { name: 'Autres espaces admin' });
    await expect(menu).toBeVisible(); await expect(plus).toHaveAttribute('aria-expanded', 'true');
    await info.attach('menu-admin-mobile', { body: await page.screenshot({ animations: 'disabled' }), contentType: 'image/png' });
    await page.keyboard.press('Escape'); await expect(menu).toHaveCount(0); await expect(plus).toBeFocused();
    // Le retour pointeur validé ci-dessus devient le départ du parcours clavier.
    await page.keyboard.press('Enter'); await expect(menu).toBeVisible();
    await expect.poll(() => menu.evaluate(el => el.contains(document.activeElement))).toBe(true);
    await page.keyboard.press('Escape'); await expect(menu).toHaveCount(0); await expect(plus).toBeFocused();
    await expect(page.locator('.admin-shell > header')).toBeVisible();
  } else await expect(page.getByRole('navigation', { name: 'Espaces de travail admin' })).toBeVisible();
  await ouvrir(page, nomE, true); await expect(titre(page, nomE)).toBeVisible();
  await accessible(page, titre(page, nomE));
  await expect(tab(page, 'Documents')).toHaveCount(0); await expect(tab(page, 'Fiabilité')).toHaveCount(0);
  await onglet(page, 'Missions'); await expect(page.getByRole('tabpanel')).toContainText('Aucune mission.');
  await onglet(page, 'Actions admin'); await expect(page.getByRole('tabpanel')).toContainText('Actions administrateur');
  await onglet(page, 'Fiche complète'); await expect(page.getByRole('tabpanel')).toContainText(etablissement.email_contact);
  await stabiliserLectures(page); await page.reload(); await expect(titre(page, nomE)).toBeVisible();
  await expect(tab(page, 'Vue d’ensemble')).toHaveAttribute('aria-selected', 'true');
  await bilan(page, ctx, info, 'admin-integre-etablissement-reload');
  await retour(page); await ouvrir(page, nomB); await expect(titre(page, nomB)).toBeVisible();
  await onglet(page, 'Fiabilité'); await expect(page.getByRole('tabpanel')).toContainText('1 pièce révoquée');
  await expect(page.getByRole('tabpanel')).not.toContainText('1 pièce vérifiée');
  await bilan(page, ctx, info, 'admin-integre-retour-autre-dossier');
});

test('admin intégré — refus documentaire visible puis reprise explicite', async ({ page }, info) => {
  const ctx = await preparer(page, { refuser: true });
  await ouvrir(page, nomA); await expect(titre(page, nomA)).toBeVisible();
  await onglet(page, 'Documents');
  await expect(page.getByRole('tabpanel').getByRole('alert')).toContainText('Documents indisponibles.');
  await expect(page.getByRole('button', { name: 'Envoyer un rappel', exact: true })).toHaveCount(0);
  await preuve(page, 'admin-integre-refus-documents', info);
  expect(ctx.suivi.refus).toBe(1); ctx.suivi.refuser = false;
  const reessayer = page.getByRole('button', { name: 'Réessayer les documents', exact: true });
  await accessible(page, reessayer); await reessayer.click();
  await expect(page.getByRole('tabpanel')).toContainText('alpha-verifie.pdf');
  await expect(page.getByRole('tabpanel').getByRole('alert')).toHaveCount(0);
  expect(ctx.suivi.documentsA).toBe(2);
  await onglet(page, 'Fiabilité'); await expect(page.getByRole('tabpanel')).toContainText('1 pièce vérifiée');
  await stabiliserLectures(page); await page.reload(); await expect(titre(page, nomA)).toBeVisible();
  await onglet(page, 'Documents'); await expect(page.getByRole('tabpanel')).toContainText('alpha-verifie.pdf');
  expect(ctx.suivi.refus).toBe(1);
  await bilan(page, ctx, info, 'admin-integre-reprise-documents');
});

test('admin intégré — réponse tardive du dossier précédent sans rechargement', async ({ page }, info) => {
  const ctx = await preparer(page, { retarder: true });
  try {
    const origineDocument = await page.evaluate(() => performance.timeOrigin);
    await ouvrir(page, nomA); await expect.poll(() => ctx.suivi.attente).toBe(true);
    // La palette réelle change :id sur la même route React pendant la lecture A.
    await page.getByRole('button', { name: /^Rechercher/ }).click();
    await page.getByRole('combobox', { name: 'Rechercher une page ou une donnée d’administration' }).fill('Béatrice');
    await page.getByRole('option').filter({ hasText: nomB }).click();
    await expect(titre(page, nomB)).toBeVisible();
    await onglet(page, 'Documents'); await expect(page.getByRole('tabpanel')).toContainText('beta-revoque.pdf');
    ctx.suivi.autoriserReponse(); await expect.poll(() => ctx.suivi.reponseLivree).toBe(true);
    await stabiliserLectures(page);
    expect(await page.evaluate(() => performance.timeOrigin)).toBe(origineDocument);
    expect(ctx.suivi.navigations).toBe(1);
    await expect(titre(page, nomB)).toBeVisible(); await expect(titre(page, nomA)).toHaveCount(0);
    await expect(tab(page, 'Documents')).toHaveAttribute('aria-selected', 'true');
    await expect(page.getByRole('tabpanel')).not.toContainText('alpha-verifie.pdf');
    await expect(page.getByRole('tabpanel')).toContainText('beta-rejete.pdf');
    await onglet(page, 'Fiabilité'); await expect(page.getByRole('tabpanel')).toContainText('1 pièce révoquée');
    await expect(page.getByRole('tabpanel')).not.toContainText('1 pièce vérifiée');
    await bilan(page, ctx, info, 'admin-integre-reponse-tardive');
  } finally { ctx.suivi.autoriserReponse(); }
});
