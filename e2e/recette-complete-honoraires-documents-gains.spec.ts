import { expect, test, type BrowserContextOptions, type Locator, type Page, type TestInfo } from '@playwright/test';
import { simulerSoignant, entrer, aller, recharger, attendreAPI, ids, mission } from './helpers/recette-complete-soignant';
import { simulerEtablissement, entrer as entrerEtablissement, allerA, stabiliserLectures, ids as etabIds, etablissement } from './helpers/recette-complete-etablissement';
import { creerSuiviSimule } from './helpers/recette-complete-suivi-mission';
import { ids as detailIds } from './helpers/recette-complete-mission';
import { stabiliserActionsNationales } from './helpers/recette-complete-actions-nationales';

// Contrats de réponses simulées : aucun calcul SQL, paiement, génération de
// document ni appel cloud. Les montants attendus sont écrits explicitement.
// Les six scénarios sont repris par les cinq projets de la configuration.
test.use({ trace: 'off', video: 'off' });
type Ligne = Record<string, any>;
type ModeLecture = 'complet' | 'page-manquante' | 'count-absent';
const maintenant = new Date('2026-10-15T10:00:00Z');
const documentaire = (page: Page) => page.getByRole('region', { name: 'Honoraires facturés', exact: true });
const euro = (montant: string) => new RegExp(`^${montant.replace('.', ',')}\\s*€$`);
const numero = (n: number) => `69000000-0000-4000-8000-${String(100 + n).padStart(12, '0')}`;
const cors = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*',
  'access-control-allow-methods': 'GET,HEAD,POST,OPTIONS', 'access-control-expose-headers': 'content-range' };
const observations = new Map<TestInfo, unknown>();
test.afterEach(async ({}, info) => {
  await info.attach('contrat-simule-et-transport', { body: JSON.stringify(observations.get(info) ?? {}, null, 2), contentType: 'application/json' });
  observations.delete(info);
});

const rpcLecture = new Set([
  'fn_get_my_role', 'fn_compte_auth_actif', 'fn_mon_profil_soignant_complet', 'fn_mon_etablissement_complet',
  'fn_dashboard_soignant_complet', 'fn_dashboard_etablissement_complet', 'fn_obtenir_missions_swipe',
  'fn_stats_dashboard_etablissement',
  'fn_apercu_marche_profession', 'fn_messages_non_lus', 'fn_param_bool', 'fn_est_bloque',
  'fn_note_moyenne', 'fn_badge_stats', 'fn_mes_evenements_score', 'fn_onboarding_soignant_statut',
  'fn_types_exercice_autorises', 'fn_etablissements_safe', 'fn_etablissement_public',
  'fn_mes_factures_honoraires', 'fn_mes_bulletins_paie', 'fn_mes_avances_factor', 'fn_mes_paiements_escrow',
  'fn_mes_revenus_connect', 'fn_cumul_annuel_paie', 'fn_compteur_heures_soignant',
  'fn_obligations_financieres', 'fn_paiements_etablissement', 'fn_mes_factures', 'fn_mes_permissions_etab',
  'fn_bfa_info', 'fn_capacite_alertes_recherches', 'fn_soignant_pour_etablissement',
  'fn_etablissement_pour_mission', 'fn_mes_soignants_etablissement', 'fn_mode_exercice',
  'fn_litige_pour_mission', 'fn_presences_detail_mission', 'fn_suivi_escrow_mission', 'fn_lister_copies_bulletins',
  'fn_alerte_cddu_repetitif', 'fn_etat_pointage_mission', 'fn_mode_paiement_mission',
  'fn_score_etab_public', 'fn_interlocuteurs_conversations', 'fn_user_id_pour_etablissement',
]);
const rpcInerte = new Set(['fn_audit_connexion', 'fn_maj_activite_soignant', 'fn_ecrire_audit_safe',
  'fn_update_presence', 'fn_obtenir_conversation', 'fn_marquer_messages_lus']);

async function fermerReseau(page: Page, identite?: { id: string; email: string }) {
  const interdits: string[] = [], erreurs: string[] = [], inertes: string[] = [], lectures: string[] = [];
  page.on('console', message => { if (message.type() === 'error') erreurs.push(message.text()); });
  page.on('pageerror', error => erreurs.push(error.message));
  await page.clock.setFixedTime(maintenant);
  // Une route de page ne voit pas la première requête d'une popup. Aucun
  // nouvel onglet ni worker réseau n'appartient à ces parcours en lecture.
  await page.context().route('**/*', async route => {
    const req = route.request(), url = new URL(req.url());
    let pageRequete: Page | undefined;
    try { pageRequete = req.frame().page(); } catch { /* Requête sans frame : refus fermé. */ }
    if (pageRequete !== page || !['127.0.0.1', 'localhost'].includes(url.hostname)
      || /^\/(functions|storage)\/v1\//.test(url.pathname)) {
      interdits.push(`CONTEXTE ${req.method()} ${url.origin}${url.pathname}`);
      return route.abort();
    }
    return route.fallback();
  });
  await page.route('**/*', async route => {
    const req = route.request(), url = new URL(req.url()), nom = url.pathname.split('/').at(-1)!;
    const refuser = () => { interdits.push(`${req.method()} ${url.origin}${url.pathname}`); return route.abort(); };
    // L'import de stripe-js sur Facturation charge ce script même sans ouvrir
    // un paiement. Réponse locale inerte ; aucune requête fournisseur ne part.
    if (req.method() === 'GET' && req.resourceType() === 'script'
      && url.href === 'https://js.stripe.com/clover/stripe.js') {
      inertes.push('script-stripe-simule');
      return route.fulfill({ contentType: 'application/javascript', body: 'window.Stripe = function(){ return {}; };' });
    }
    if (!['127.0.0.1', 'localhost'].includes(url.hostname) || /^\/(functions|storage)\/v1\//.test(url.pathname)) return refuser();
    if (req.isNavigationRequest() && req.resourceType() === 'document') {
      const response = await route.fetch({ maxRedirects: 0 });
      if (response.status() >= 300 && response.status() < 400) {
        interdits.push(`REDIRECTION ${response.status()} ${url.origin}${url.pathname}`);
        return route.abort();
      }
      return route.fulfill({ response, body: (await response.text())
        .replace(/<link\b(?=[^>]*\brel=["'](?:preconnect|dns-prefetch)["'])[^>]*>/gi, '')
        .replace(/<link\b(?=[^>]*\bhref=["']https:\/\/fonts\.googleapis\.com\/)[^>]*>/gi, '') });
    }
    if (url.pathname.startsWith('/auth/v1/')) {
      if (req.method() === 'OPTIONS') return route.fallback();
      if (!(nom === 'user' && req.method() === 'GET') && !(nom === 'token' && req.method() === 'POST')) return refuser();
      if (nom === 'token' && identite) {
        // L'horloge navigateur est en octobre ; les sessions créées avec
        // l'horloge Node réelle ne doivent pas expirer artificiellement.
        return route.fulfill({ headers: cors, json: {
          access_token: 'fixture-auth', refresh_token: 'fixture-refresh', token_type: 'bearer', expires_in: 86400,
          expires_at: Math.floor(maintenant.getTime() / 1000) + 86400,
          user: { ...identite, aud: 'authenticated', role: 'authenticated', app_metadata: {}, user_metadata: {},
            email_confirmed_at: '2026-09-01T08:00:00Z', identities: [] },
        } });
      }
    }
    if (url.pathname.startsWith('/rest/v1/')) {
      if (req.method() === 'OPTIONS') return route.fallback();
      if (url.pathname.startsWith('/rest/v1/rpc/')) {
        if (req.method() !== 'POST') return refuser();
        if (rpcInerte.has(nom)) {
          // Ces appels automatiques de présence/conversation/audit sont
          // explicitement sans effet ; ils ne deviennent pas des lectures SQL.
          inertes.push(nom);
          return route.fulfill({ headers: cors, json: nom === 'fn_obtenir_conversation'
            ? '71000000-0000-4000-8000-000000000007' : null });
        }
        if (!rpcLecture.has(nom)) return refuser();
      } else if (!['GET', 'HEAD'].includes(req.method())) return refuser();
      lectures.push(`${req.method()} ${nom}`);
    }
    return route.fallback();
  });
  return { interdits, erreurs, inertes, lectures, verifier() {
    expect(interdits, 'Aucun accès fournisseur ni mutation métier').toEqual([]);
    expect(erreurs, 'Aucune erreur console filtrée').toEqual([]);
  } };
}

async function activer(element: Locator, info: TestInfo) {
  await element.scrollIntoViewIfNeeded();
  if (info.project.use.hasTouch) await element.tap(); else await element.click();
}
async function preuve(page: Page, info: TestInfo, cible: Locator, nom: string) {
  await expect(cible).toBeVisible();
  await cible.evaluate(element => element.scrollIntoView({ block: 'center', inline: 'nearest' }));
  await expect.poll(() => cible.evaluate(element => {
    const r = element.getBoundingClientRect();
    if (r.left < -1 || r.right > innerWidth + 1 || r.top < 0 || r.bottom > innerHeight) return false;
    // Les coins arrondis de l'alerte sont transparents : sonder le milieu
    // des quatre bords et le centre vérifie une superposition réelle.
    const x = (r.left + r.right) / 2, y = (r.top + r.bottom) / 2;
    return [[x, r.top + 3], [x, r.bottom - 3], [r.left + 3, y], [r.right - 3, y], [x, y]]
      .every(([x, y]) => { const hit = document.elementFromPoint(x, y); return hit === element || (hit !== null && element.contains(hit)); });
  }), { message: 'La portion financière reste visible sans barre fixe superposée' }).toBe(true);
  expect(await page.evaluate(() => document.documentElement.scrollWidth - innerWidth)).toBeLessThanOrEqual(1);
  await info.attach(nom, { body: await page.locator('main').ariaSnapshot(), contentType: 'text/plain' });
  await page.screenshot({ path: info.outputPath(`${nom}.png`), fullPage: false, animations: 'disabled', scale: 'css' });
}
async function periode(page: Page, info: TestInfo, nom: string) {
  await activer(page.getByRole('combobox', { name: 'Période des revenus', exact: true }), info);
  await activer(page.getByRole('option', { name: nom, exact: true }), info);
}
async function montantDocumentaire(page: Page, montant: string, label: string) {
  const region = documentaire(page);
  await expect(region).toBeVisible();
  await expect(region.getByText(`Honoraires facturés TTC · ${label}`, { exact: true })).toBeVisible();
  await expect(region.getByText(euro(montant), { exact: true })).toBeVisible();
}
function documents(avoir = false) {
  const commun = { mission_id: ids.mission, soignant_id: ids.user, etablissement_id: ids.etab,
    mission_intitule: 'Mission fictive — planning distinct des documents', etablissement_nom: 'Clinique fictive F1',
    type_document: 'FACTURE', montant_tva: 0, taux_tva: 0, taux_horaire_snapshot: 20,
    statut_litige: 'NORMAL', exoneration_tva: true, est_facture_finale_mission: false,
    periode_debut: '2026-09-21', periode_fin: '2026-09-27', date_echeance: '2026-10-30' };
  return [
    { ...commun, id: numero(1), numero_facture: 'SIM-ORIGINALE-80', statut: 'REMPLACEE', nature_correction: 'ORIGINALE',
      montant_ht: 80, montant_ttc: 80, montant_signe: 80, quantite_heures_snapshot: 4,
      date_emission: '2026-09-25', cree_le: '2026-09-25T09:00:00Z' },
    { ...commun, id: numero(2), numero_facture: 'SIM-REMPLACEMENT-60', statut: 'EMISE', nature_correction: 'REMPLACEMENT',
      facture_precedente_id: numero(1), montant_ht: 60, montant_ttc: 60, montant_signe: 60, quantite_heures_snapshot: 3,
      date_emission: '2026-09-30', cree_le: '2026-09-30T09:00:00Z' },
    { ...commun, id: numero(3), numero_facture: 'SIM-PERIODE-80', statut: avoir ? 'PAYEE' : 'EMISE', nature_correction: 'ORIGINALE',
      montant_ht: 80, montant_ttc: 80, montant_signe: 80, quantite_heures_snapshot: 4,
      periode_debut: '2026-09-28', periode_fin: '2026-10-04', date_emission: '2026-10-05', cree_le: '2026-10-05T09:00:00Z' },
    ...(avoir ? [{ ...commun, id: numero(4), numero_facture: 'AV-SIM-20', statut: 'EMISE', type_document: 'AVOIR',
      nature_correction: 'AVOIR', facture_origine_id: numero(3), facture_precedente_id: numero(3),
      montant_ht: 20, montant_ttc: 20, montant_signe: -20, quantite_heures_snapshot: 1,
      periode_debut: '2026-09-28', periode_fin: '2026-10-04', date_emission: '2026-10-06', cree_le: '2026-10-06T09:00:00Z' }] : []),
  ];
}
function creneaux(missionId: string) {
  return ['2026-09-21', '2026-09-28'].flatMap((jour, n) => ['PREVISIONNEL', 'EFFECTIF'].map(type => ({
    id: `creneau-${n}-${type}`, mission_id: missionId, debut: `${jour}T08:00:00Z`, fin: `${jour}T12:00:00Z`,
    est_pause: false, type_creneau: type,
  })));
}
const planning = { statut: 'TERMINEE', type_contrat_applique: 'LIBERAL', type_contrat_recherche: 'LIBERAL',
  intitule: 'Mission fictive — planning distinct des documents', debut_le: '2026-09-21T08:00:00Z', fin_le: '2026-09-28T12:00:00Z',
  duree_heures: 8, nb_creneaux: 2, taux_horaire_base: 20, total_brut: 160, net_a_payer: 160, net_estime: 160,
  montant_commission_ht: 24, montant_commission_tva: 4.8, montant_commission_ttc: 28.8, taux_commission: 15,
  presences: [{ valide_par_etablissement: false, valide_auto_72h_le: null, valide_le: null }],
};

async function preparerGains(page: Page, info: TestInfo, avoir = false) {
  const etat = await simulerSoignant(page);
  // La suggestion de parrainage a déjà été lue par cet acteur fictif ;
  // le scénario avoir ne teste pas ce parcours distinct.
  await page.addInitScript(() => localStorage.setItem('jolene_prompt_parrainage_1er_paiement', '1'));
  Object.assign(etat.profile, { type_exercice: 'LIBERAL', statut_liberal: 'ACTIF', rpps_verifie: false, tous_documents_valides: false });
  const lignesMission = [{ ...mission, ...planning, soignant_assigne_id: ids.user, creneaux: creneaux(ids.mission) }];
  etat.tables.set('missions', lignesMission);
  etat.tables.set('paiements_soignant', []);
  const lecture = { mode: 'complet' as ModeLecture, pieces: documents(avoir), pages: [] as { mode: string; offset: number; ids: string[]; total: number | null }[] };
  const publier = () => {
    etat.tables.set('factures_honoraires', lecture.pieces);
    etat.overrides.set('fn_mes_factures_honoraires', lecture.pieces);
  };
  publier();
  await page.route('**/rest/v1/mission_creneaux?*', async route => {
    if (route.request().method() === 'OPTIONS') return route.fallback();
    const url = new URL(route.request().url());
    expect(url.searchParams.get('mission_id')).toContain(ids.mission);
    const lignes = creneaux(ids.mission);
    return route.fulfill({ headers: { ...cors, 'content-range': `0-${lignes.length - 1}/${lignes.length}` }, json: lignes });
  });
  await page.route('**/rest/v1/factures_honoraires?*', async route => {
    const req = route.request(), url = new URL(req.url());
    if (req.method() === 'OPTIONS') return route.fallback();
    // Les métadonnées de l'onglet Factures restent gérées par le helper commun.
    // Seule la lecture exhaustive du nouveau KPI subit le plafond de serveur.
    if (!url.searchParams.get('select')?.split(',').includes('date_emission')) return route.fallback();
    expect(req.method()).toBe('GET');
    expect(req.headers().authorization).toBe('Bearer fixture-auth');
    expect(url.searchParams.get('soignant_id')).toBe(`eq.${ids.user}`);
    expect(req.headers().prefer).toContain('count=exact');
    expect(url.searchParams.get('order')).toMatch(/^id\.asc/);
    const offset = Number(url.searchParams.get('offset') ?? 0);
    expect(Number.isSafeInteger(offset) && offset >= 0).toBe(true);
    const lignes = lecture.mode === 'page-manquante' && offset > 0 ? [] : lecture.pieces.slice(offset, offset + 1);
    const total = lecture.mode === 'count-absent' ? null : lecture.pieces.length;
    lecture.pages.push({ mode: lecture.mode, offset, ids: lignes.map(l => l.id), total });
    return route.fulfill({ headers: { ...cors, ...(total === null ? {} : {
      'content-range': lignes.length ? `${offset}-${offset}/${total}` : `*/${total}`,
    }) }, json: lignes });
  });
  const reseau = await fermerReseau(page, { id: ids.user, email: 'recette-soignant@example.invalid' });
  observations.set(info, { simulation: true, sqlExecute: false, cloud: false, lectures: lecture.pages,
    mission: lignesMission[0], appels: etat.calls, inertes: reseau.inertes, interdits: reseau.interdits, erreurs: reseau.erreurs });
  return { etat, lecture, publier, async ouvrir() {
    await entrer(page, 'connexion'); await aller(page, '/soignant/mes-gains?tab=apercu');
  }, async verifier() {
    await attendreAPI(page);
    expect(etat.unknown).toEqual([]); expect(etat.errors).toEqual([]); reseau.verifier();
    expect(lignesMission[0].presences).toEqual(planning.presences);
    expect(lignesMission[0].net_a_payer).toBe(160);
  } };
}

test('honoraires documentaires — clôture, mois d’émission, pagination et zéro prouvé après recharge', async ({ page }, info) => {
  const banc = await preparerGains(page, info); await banc.ouvrir();
  for (const reload of [false, true]) {
    if (reload) await recharger(page);
    await montantDocumentaire(page, '80.00', 'octobre 2026');
    await periode(page, info, 'septembre 2026');
    await montantDocumentaire(page, '60.00', 'septembre 2026');
    await expect(page.getByText('Totaux et export en attente de validation', { exact: true })).toBeVisible();
    await periode(page, info, 'Tous les mois');
    await montantDocumentaire(page, '140.00', 'Tout temps');
    await expect(page.getByRole('button', { name: /Honoraires prévisionnels · Tout temps/ })).toContainText(/160,00\s*€/);
    await expect(documentaire(page)).not.toContainText(/160,00|220,00/);
    await preuve(page, info, documentaire(page), `facture140-planning160-${reload ? 'recharge' : 'initial'}`);
  }
  expect(banc.lecture.pages.slice(0, 3).map(p => p.offset)).toEqual([0, 1, 2]);
  expect(banc.lecture.pages.slice(0, 3).flatMap(p => p.ids)).toEqual(documents().map(p => p.id));
  const debutZero = banc.lecture.pages.length;
  // Le profil a changé de régime, mais son historique comporte toujours une
  // mission libérale hors du mois courant : il ne doit pas perdre le vrai zéro.
  Object.assign(banc.etat.profile, { type_exercice: 'SALARIE', statut_liberal: null });
  banc.lecture.pieces = []; banc.publier(); await recharger(page);
  await montantDocumentaire(page, '0.00', 'octobre 2026');
  await periode(page, info, 'Tous les mois');
  await montantDocumentaire(page, '0.00', 'Tout temps');
  await expect(page.getByRole('button', { name: /Honoraires prévisionnels · Tout temps/ })).toContainText(/160,00\s*€/);
  expect(banc.lecture.pages[debutZero]).toEqual({ mode: 'complet', offset: 0, ids: [], total: 0 });
  await preuve(page, info, documentaire(page), 'zero-documentaire-prouve');
  Object.assign(banc.etat.profile, { type_exercice: 'LIBERAL', statut_liberal: 'ACTIF' });
  banc.lecture.pieces = documents(); banc.publier(); await recharger(page);
  await periode(page, info, 'Tous les mois'); await montantDocumentaire(page, '140.00', 'Tout temps');
  await activer(documentaire(page).getByRole('button'), info);
  await expect(page).toHaveURL(/tab=factures$/);
  await expect(page.getByText('SIM-REMPLACEMENT-60', { exact: true })).toBeVisible();
  await banc.verifier();
});

test('honoraires documentaires — avoir signé déduit sans déplacer sa date ni recompter l’originale', async ({ page }, info) => {
  const banc = await preparerGains(page, info, true); await banc.ouvrir();
  for (const reload of [false, true]) {
    if (reload) await recharger(page);
    await montantDocumentaire(page, '60.00', 'octobre 2026');
    await periode(page, info, 'septembre 2026'); await montantDocumentaire(page, '60.00', 'septembre 2026');
    await periode(page, info, 'Tous les mois'); await montantDocumentaire(page, '120.00', 'Tout temps');
    await expect(documentaire(page)).not.toContainText(/140,00|160,00|200,00|240,00/);
    await preuve(page, info, documentaire(page), `avoir20-deduit-${reload ? 'recharge' : 'initial'}`);
  }
  expect(banc.lecture.pages.slice(0, 4).map(p => p.offset)).toEqual([0, 1, 2, 3]);
  expect(banc.lecture.pieces.find(p => p.type_document === 'AVOIR')).toMatchObject({ montant_ttc: 20, montant_signe: -20, date_emission: '2026-10-06' });
  await banc.verifier();
});

for (const [mode, message] of [
  ['page-manquante', 'Le chargement des documents est incomplet. Rechargez la page.'],
  ['count-absent', 'Le total des documents ne peut pas être vérifié. Rechargez la page.'],
] as const) {
  test(`honoraires documentaires — ${mode} refuse le total partiel puis permet Réessayer et rechargement`, async ({ page }, info) => {
    const banc = await preparerGains(page, info); banc.lecture.mode = mode; await banc.ouvrir();
    const alerte = page.getByRole('alert').filter({ hasText: 'Impossible de charger tous les revenus' });
    await expect(alerte).toContainText(message);
    await expect(documentaire(page)).toHaveCount(0);
    await expect(page.getByRole('button', { name: /Honoraires prévisionnels/ })).toHaveCount(0);
    await preuve(page, info, alerte, `${mode}-sans-faux-total`);
    await preuve(page, info, alerte.getByText(message, { exact: true }), `${mode}-texte-visible`);
    await preuve(page, info, alerte.getByRole('button', { name: 'Réessayer', exact: true }), `${mode}-bouton-atteignable`);
    expect(banc.lecture.pages.map(p => p.offset)).toEqual(mode === 'page-manquante' ? [0, 1] : [0]);
    banc.lecture.mode = 'complet';
    await activer(alerte.getByRole('button', { name: 'Réessayer', exact: true }), info);
    await expect(alerte).toHaveCount(0);
    await periode(page, info, 'Tous les mois'); await montantDocumentaire(page, '140.00', 'Tout temps');
    await preuve(page, info, documentaire(page), `${mode}-reprise`);
    await recharger(page); await periode(page, info, 'Tous les mois'); await montantDocumentaire(page, '140.00', 'Tout temps');
    await banc.verifier();
  });
}

test('honoraires documentaires — établissement 70,80 et 94,40 à régler, estimation de commission 24 séparée', async ({ page, browser }, info) => {
  const { etat } = await simulerEtablissement(page);
  const pieces = documents().filter(p => p.statut !== 'REMPLACEE').map(p => ({ ...p, etablissement_id: etabIds.etab, soignant_id: etabIds.soignant }));
  etat.overrides.set('fn_mon_etablissement_complet', { ...etablissement, type: 'CLINIQUE_PRIVEE', est_compte_test: true,
    statut_verification: 'EN_ATTENTE', est_verifie: false, peut_publier_missions: false });
  const obligations = pieces.map((p, i) => ({ mission_id: ids.mission, facture_honoraires_id: p.id, payment_key: p.id,
    intitule: i === 0 ? 'Période rectifiée septembre' : 'Période suivante octobre', soignant_id: etabIds.soignant,
    soignant_nom: 'Camille Recette', soignant_profession: 'IDE', soignant_stripe_connect: true,
    type_contrat_applique: 'LIBERAL', type_contrat_recherche: 'LIBERAL', heures: i === 0 ? 3 : 4,
    net_a_payer: i === 0 ? 60 : 80, montant_commission_ht: i === 0 ? 9 : 12, montant_commission_ttc: i === 0 ? 10.8 : 14.4,
    periode_debut: p.periode_debut, periode_fin: p.periode_fin, est_facture_finale_mission: false, jours_depuis_fin: 1 }));
  const commissions = pieces.map((p, i) => ({ id: numero(11 + i), facture_id: numero(11 + i), facture_honoraire_id: p.id,
    numero_facture: `SIM-COMMISSION-${i + 1}`, etablissement_id: etabIds.etab, statut: 'EMISE', type_document: 'FACTURE',
    montant_ht: i === 0 ? 9 : 12, montant_tva: i === 0 ? 1.8 : 2.4, montant_ttc: i === 0 ? 10.8 : 14.4,
    nombre_missions: 1, periode_debut: p.periode_debut, periode_fin: p.periode_fin, date_emission: p.date_emission,
    date_echeance: '2026-10-30', est_secteur_public: false, chorus_pro_statut: 'NON_APPLICABLE' }));
  etat.overrides.set('fn_obligations_financieres', { total_du: 165.2, total_soignants_du: 140, total_commissions_du: 25.2,
    nb_missions_non_payees: 2, missions_non_payees: obligations, factures_impayees: commissions,
    paiements_soignants_en_attente: [], paiements_soignants_confirmes: [] });
  etat.overrides.set('fn_mes_factures', commissions);
  etat.overrides.set('factures_honoraires', pieces);
  const reseau = await fermerReseau(page, { id: etabIds.user, email: 'recette-etablissement@example.invalid' });
  observations.set(info, { simulation: true, cloud: false, obligations, lectures: etat.appels,
    inertes: reseau.inertes, interdits: reseau.interdits, erreurs: reseau.erreurs });
  await entrerEtablissement(page, 'connexion'); await allerA(page, '/etablissement/facturation?tab=payer');
  for (const reload of [false, true]) {
    if (reload) { await stabiliserLectures(page); await page.reload(); }
    await expect(page.getByText('Total à régler', { exact: true }).locator('..')).toContainText(/165,20\s*€/);
    for (const [n, montant, commission] of [[0, '70.80', '10.80'], [1, '94.40', '14.40']] as const) {
      const card = page.locator('.card-base').filter({ has: page.getByRole('button', { name: obligations[n].intitule, exact: true }) });
      await expect(card.getByText(euro(montant), { exact: true })).toBeVisible();
      await expect(card).toContainText(`dont ${commission.replace('.', ',')} € commission Jolene`);
      await expect(card.getByText(pieces[n].numero_facture, { exact: true })).toBeVisible();
      await expect(card).not.toContainText(/160,00|188,80/);
      await preuve(page, info, card, `cout-piece-${n}-${reload ? 'recharge' : 'initial'}`);
    }
  }
  await stabiliserLectures(page);
  expect(etat.inconnues).toEqual([]); expect(etat.erreurs).toEqual([]); expect(etat.ecritures).toEqual([]); expect(etat.operations).toEqual([]); reseau.verifier();
  // La deuxième surface lit les agrégats de mission, pas la réponse des obligations.
  const use: typeof info.project.use & Pick<BrowserContextOptions, 'screen'> = info.project.use;
  const contexte = await browser.newContext({ viewport: use.viewport, screen: use.screen, deviceScaleFactor: use.deviceScaleFactor,
    isMobile: use.isMobile, hasTouch: use.hasTouch, userAgent: use.userAgent, locale: 'fr-FR', timezoneId: 'Europe/Paris', serviceWorkers: 'block' });
  try {
    const { state, installer } = creerSuiviSimule();
    Object.assign(state.mission, planning, { soignant_assigne_id: detailIds.soignant, profession_requise: 'IDE' });
    Object.assign(state.soignant, { profession: 'IDE', est_compte_test: true, rpps_verifie: false, tous_documents_valides: false });
    Object.assign(state.etablissement, { est_compte_test: true, taux_commission_negocie: 15 });
    state.creneaux.splice(0, state.creneaux.length, ...creneaux(detailIds.mission));
    await installer(contexte, 'ADMIN_ETABLISSEMENT');
    const detail = await contexte.newPage();
    await detail.route('**/rest/v1/rpc/fn_mode_paiement_mission', async route => {
      expect(route.request().method()).toBe('POST');
      expect(route.request().postDataJSON()).toEqual({ p_mission_id: detailIds.mission });
      // Ce RPC historique lit encore l'estimation mission : il ne constitue
      // pas une preuve du solde documentaire ni d'un paiement de 160 euros.
      return route.fulfill({ headers: cors, json: { mode_recommande: 'VIREMENT_NOTE_HONORAIRES',
        type_contrat_applique: 'LIBERAL', type_exercice: 'LIBERAL', stripe_connect_actif: false,
        rib_partage: false, iban_last4: null, montant_soignant: 160, montant_soignant_estime: false,
        total_brut: 160, net_estime: 160, commission_ht: 24, commission_ttc: 28.8, total: 188.8 } });
    });
    const transport = await fermerReseau(detail);
    await detail.goto(new URL(`/etablissement/missions/${detailIds.mission}`, page.url()).href);
    for (const reload of [false, true]) {
      if (reload) { await stabiliserActionsNationales(detail); await detail.reload(); }
      const evaluation = detail.getByRole('heading', { name: 'Mission terminée 🎉', exact: true });
      await expect(evaluation).toBeVisible();
      await activer(evaluation.locator('..').getByRole('button', { name: 'Fermer', exact: true }), info);
      await expect(evaluation).toHaveCount(0);
      await expect(detail.getByText(/^Commission prévisionnelle : 28,80\s*€ TTC — Consultez vos factures pour les montants et échéances\.$/)).toBeVisible();
      await expect(detail.getByText(/Facturée en fin de mois/)).toHaveCount(0);
      const titre = detail.getByText('Commission Jolene prévisionnelle', { exact: true });
      await expect(titre).toBeVisible();
      const bloc = titre.locator('../..');
      await expect(bloc).toContainText('24,00 € HT + TVA 20 %');
      await expect(bloc).toContainText('28,80 € TTC');
      await expect(bloc).toContainText('Calcul : 15% HT × 160,00 € honoraires bruts');
      await expect(bloc).toContainText('Estimation du planning');
      await expect(bloc).not.toContainText('21,00 € HT');
      const libelle = await titre.boundingBox();
      const valeur = await bloc.getByText('28,80 € TTC', { exact: true }).boundingBox();
      expect(libelle).not.toBeNull(); expect(valeur).not.toBeNull();
      expect(valeur!.y >= libelle!.y + libelle!.height
        || valeur!.x >= libelle!.x + libelle!.width + 8,
      'Le libellé de commission et son montant restent séparés').toBe(true);
      await preuve(detail, info, bloc, `commission-previsionnelle-${reload ? 'recharge' : 'initial'}`);
    }
    await stabiliserActionsNationales(detail);
    transport.verifier(); expect(state.unknown).toEqual([]); expect(state.external).toEqual([]); expect(state.errors).toEqual([]);
    expect(state.signatures).toEqual([]); expect(state.emails).toEqual([]); expect(state.sms).toEqual([]);
    await info.attach('detail-mission-simule', { body: JSON.stringify({ mission: state.mission, appels: state.calls,
      inertes: transport.inertes, interdits: transport.interdits, erreurs: transport.erreurs }), contentType: 'application/json' });
  } finally { await contexte.close(); }
});

test('honoraires documentaires — cohorte O, échéance de novembre sans retard en octobre', async ({ page }, info) => {
  const { etat } = await simulerEtablissement(page);
  const piece = { ...documents()[2], id: numero(31), numero_facture: 'SIM-O-SEMAINE-38',
    etablissement_id: etabIds.etab, soignant_id: etabIds.soignant,
    periode_debut: '2026-09-14', periode_fin: '2026-09-20', numero_semaine_iso: 38, annee_iso: 2026,
    date_emission: '2026-10-04', cree_le: '2026-10-04T09:00:00Z', date_echeance: '2026-11-03' };
  const obligation = { mission_id: ids.mission, facture_honoraires_id: piece.id, payment_key: piece.id,
    intitule: 'Mission fictive O — semaine 38', soignant_id: etabIds.soignant, soignant_nom: 'Camille Recette',
    soignant_profession: 'IDE', soignant_stripe_connect: true, type_contrat_applique: 'LIBERAL', type_contrat_recherche: 'LIBERAL',
    heures: 159, net_a_payer: 80, montant_commission_ht: 12, montant_commission_ttc: 14.4,
    periode_debut: piece.periode_debut, periode_fin: piece.periode_fin, est_facture_finale_mission: false, jours_depuis_fin: 14 };
  const commission = { id: numero(32), facture_id: numero(32), facture_honoraire_id: piece.id,
    numero_facture: 'SIM-O-COMMISSION', etablissement_id: etabIds.etab, statut: 'EMISE', type_document: 'FACTURE',
    montant_ht: 12, montant_tva: 2.4, montant_ttc: 14.4, nombre_missions: 1,
    periode_debut: piece.periode_debut, periode_fin: piece.periode_fin, date_emission: piece.date_emission,
    date_echeance: piece.date_echeance, est_secteur_public: false, chorus_pro_statut: 'NON_APPLICABLE' };
  etat.overrides.set('fn_mon_etablissement_complet', { ...etablissement, type: 'CLINIQUE_PRIVEE', est_compte_test: true,
    statut_verification: 'EN_ATTENTE', est_verifie: false, peut_publier_missions: false });
  etat.overrides.set('fn_obligations_financieres', { total_du: 94.4, total_soignants_du: 80, total_commissions_du: 14.4,
    nb_missions_non_payees: 1, missions_non_payees: [obligation], factures_impayees: [commission],
    paiements_soignants_en_attente: [], paiements_soignants_confirmes: [] });
  etat.overrides.set('fn_mes_factures', [commission]);etat.overrides.set('factures_honoraires', [piece]);
  const reseau = await fermerReseau(page, { id: etabIds.user, email: 'recette-etablissement@example.invalid' });
  await page.clock.setFixedTime(new Date('2026-10-04T12:00:00Z'));
  observations.set(info, { simulation: true, cloud: false, obligation, piece, commission, lectures: etat.appels,
    inertes: reseau.inertes, interdits: reseau.interdits, erreurs: reseau.erreurs });
  await entrerEtablissement(page, 'connexion');await allerA(page, '/etablissement/facturation?tab=payer');
  for (const reload of [false, true]) {
    if (reload) { await stabiliserLectures(page);await page.reload(); }
    const card = page.locator('.card-base').filter({ has: page.getByRole('button', { name: obligation.intitule, exact: true }) });
    await expect(card.getByText('Échéance : 3 novembre 2026', { exact: true })).toBeVisible();
    await expect(card).not.toContainText(/retard|159.*pointées/);
    await expect(card).toContainText('4 h facturées');await expect(card).toContainText('dont 14,40 € commission Jolene');
    await expect(card.getByText(euro('94.40'), { exact: true })).toBeVisible();
    await expect(card.getByText(piece.numero_facture, { exact: true })).toBeVisible();
    await preuve(page, info, card, `echeance-o-${reload ? 'recharge' : 'initial'}`);
  }
  await stabiliserLectures(page);
  expect(etat.inconnues).toEqual([]);expect(etat.erreurs).toEqual([]);expect(etat.ecritures).toEqual([]);expect(etat.operations).toEqual([]);reseau.verifier();
});

// Le moteur peut faire défiler le padding et l'interligne sans masquer le
// texte. Mesurer la boîte typographique aux styles calculés évite de supposer
// une métrique de police identique sous macOS et sur le runner Linux.
async function mesurerLigne(motif: Locator, extremite: 'premiere' | 'derniere') {
  return motif.evaluate((element, extremite) => {
    const champ = element as HTMLTextAreaElement, css = getComputedStyle(champ);
    const debut = extremite === 'premiere' ? 0 : champ.value.lastIndexOf('\n') + 1;
    const fin = extremite === 'premiere' ? champ.value.indexOf('\n') : champ.value.length;
    const miroir = document.createElement('div'), ligne = document.createElement('span');
    for (const cle of ['font-family', 'font-size', 'font-weight', 'font-style', 'font-variant',
      'line-height', 'letter-spacing', 'word-spacing', 'text-transform', 'text-indent', 'tab-size'])
      miroir.style.setProperty(cle, css.getPropertyValue(cle));
    const largeur = champ.clientWidth - parseFloat(css.paddingLeft) - parseFloat(css.paddingRight);
    Object.assign(miroir.style, { position: 'fixed', top: '0', left: '-10000px',
      width: `${largeur}px`, margin: '0', padding: '0', border: '0', boxSizing: 'content-box',
      whiteSpace: 'pre-wrap', overflowWrap: 'break-word', visibility: 'hidden', pointerEvents: 'none' });
    miroir.setAttribute('aria-hidden', 'true');
    ligne.textContent = champ.value.slice(debut, fin < 0 ? champ.value.length : fin);
    miroir.append(document.createTextNode(champ.value.slice(0, debut)), ligne);
    document.body.append(miroir);
    try {
      const r = champ.getBoundingClientRect(), m = miroir.getBoundingClientRect(), t = ligne.getBoundingClientRect();
      const clip = { haut: r.top + champ.clientTop, bas: r.top + champ.clientTop + champ.clientHeight };
      const haut = clip.haut + parseFloat(css.paddingTop) - champ.scrollTop + t.top - m.top;
      const bas = haut + t.height;
      return { extremite, scrollTop: champ.scrollTop, paddingTop: parseFloat(css.paddingTop),
        interligne: parseFloat(css.lineHeight), haut, bas, clip,
        visible: t.width > 0 && t.height > 0 && haut >= clip.haut && bas <= clip.bas };
    } finally { miroir.remove(); }
  }, extremite);
}

test('menus et dialogue — position conservée, Select imbriqué et clavier sans création de litige', async ({ page }, info) => {
  const banc = await preparerGains(page, info); await banc.ouvrir();
  const body = page.locator('body');
  const select = page.getByRole('combobox', { name: 'Période des revenus', exact: true });
  await select.scrollIntoViewIfNeeded();
  const avant = await page.evaluate(() => scrollY);
  expect(avant, 'Le menu est réellement ouvert après défilement de la page').toBeGreaterThan(0);
  await activer(select, info);
  await expect(body).toHaveAttribute('data-scroll-locked', '1');
  const memeMois = page.getByRole('option', { name: 'Ce mois', exact: true });
  await expect(memeMois).toBeInViewport();
  await activer(memeMois, info);
  await expect(body).not.toHaveAttribute('data-scroll-locked');
  await expect.poll(() => page.evaluate(() => scrollY)).toBe(avant);
  await montantDocumentaire(page, '80.00', 'octobre 2026');
  await preuve(page, info, select, 'menu-ferme-position-conservee');

  // Douze missions synthétiques uniquement pour éprouver le défilement du
  // Select déjà présent dans un dialogue. La RPC de création reste interdite.
  banc.etat.tables.set('missions', Array.from({ length: 12 }, (_, index) => ({
    ...mission, ...planning, id: numero(40 + index), soignant_assigne_id: ids.user,
    intitule: `Mission de recette ${String(index + 1).padStart(2, '0')}`,
  })));
  await aller(page, '/soignant/litiges');
  await activer(page.getByRole('button', { name: 'Ouvrir un litige', exact: true }), info);
  const dialogue = page.getByRole('dialog', { name: 'Ouvrir un nouveau litige', exact: true });
  await expect(dialogue).toBeVisible();
  await expect(body).toHaveAttribute('data-scroll-locked', '1');
  const positionDialogue = await page.evaluate(() => scrollY);
  await activer(dialogue.getByRole('combobox'), info);
  await expect(body).toHaveAttribute('data-scroll-locked', '2');
  const derniere = page.getByRole('option', { name: /^Mission de recette 12/ });
  await derniere.scrollIntoViewIfNeeded();
  await expect(derniere).toBeInViewport();
  await activer(derniere, info);
  await expect(body).toHaveAttribute('data-scroll-locked', '1');
  await expect(dialogue.getByRole('combobox')).toContainText('Mission de recette 12');

  const motif = dialogue.getByPlaceholder('Décris le problème rencontré (minimum 10 caractères)...');
  await activer(motif, info);
  const brouillon = Array.from({ length: 18 }, (_, index) => `Recette ${index + 1} non envoyée.`).join('\n');
  await motif.fill(brouillon);
  for (let n = 0; n < 25; n++) await motif.press('ArrowUp');
  await expect.poll(() => motif.evaluate(element => (element as HTMLTextAreaElement).selectionStart)).toBe(0);
  await expect(motif).toBeFocused();
  const haut = await mesurerLigne(motif, 'premiere');
  expect(haut.visible, 'La première ligne reste entièrement dans le champ').toBe(true);
  await page.screenshot({ path: info.outputPath('dialogue-clavier-premiere-ligne.png'), fullPage: false, animations: 'disabled', scale: 'css' });
  // Témoin négatif de la mesure : une vraie ligne masquée doit être refusée.
  // Seul le scroll interne est déplacé puis restauré ; ni style ni texte ne changent.
  let masque;
  try {
    await motif.evaluate((element, decalage) => { element.scrollTop += decalage; }, 2 * haut.interligne);
    masque = await mesurerLigne(motif, 'premiere');
    expect(masque.visible).toBe(false);
  } finally {
    await motif.evaluate((element, scroll) => { element.scrollTop = scroll; }, haut.scrollTop);
  }
  expect((await mesurerLigne(motif, 'premiere')).visible).toBe(true);
  for (let n = 0; n < 25; n++) await motif.press('ArrowDown');
  await expect.poll(() => motif.evaluate(element => (element as HTMLTextAreaElement).selectionStart)).toBe(brouillon.length);
  await expect.poll(() => motif.evaluate(element => element.scrollTop)).toBeGreaterThan(haut.scrollTop);
  await expect(motif).toHaveValue(brouillon);
  await expect(motif).toBeFocused();
  const bas = await mesurerLigne(motif, 'derniere');
  expect(bas.visible, 'La dernière ligne reste visible après la navigation clavier').toBe(true);
  await info.attach('geometrie-champ-clavier', { body: JSON.stringify({ haut, masque, bas }, null, 2), contentType: 'application/json' });
  await expect.poll(() => page.evaluate(() => scrollY)).toBe(positionDialogue);
  await info.attach('dialogue-select-clavier-sans-envoi', { body: await dialogue.ariaSnapshot(), contentType: 'text/plain' });
  await page.screenshot({ path: info.outputPath('dialogue-select-clavier-sans-envoi.png'), fullPage: false, animations: 'disabled', scale: 'css' });
  await activer(dialogue.getByRole('button', { name: 'Annuler', exact: true }), info);
  await expect(dialogue).toHaveCount(0);
  await expect(body).not.toHaveAttribute('data-scroll-locked');
  await expect.poll(() => page.evaluate(() => scrollY)).toBe(positionDialogue);
  await expect(page.getByText('Aucun litige', { exact: true })).toBeVisible();
  await banc.verifier();
});
