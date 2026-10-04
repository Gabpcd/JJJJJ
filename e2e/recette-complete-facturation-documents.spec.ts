import { test as base, expect, chromium, type Page, type Locator, type TestInfo } from '@playwright/test';
import { readFile, writeFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { creerBanc, genererDocuments, verifierXml, sha256, ids } from '../tests/helpers/facturation-documents-harness.mjs';
import { simulerSoignant, entrer as entrerSoignant, aller, recharger } from './helpers/recette-complete-soignant';
import { simulerEtablissement, entrer as entrerEtablissement, allerA, stabiliserLectures, ids as idsEtab, etablissement } from './helpers/recette-complete-etablissement';
import { creerSuiviSimule } from './helpers/recette-complete-suivi-mission';
import { ids as idsMission, chargerHtmlLocal } from './helpers/recette-complete-mission';
import { stabiliserActionsNationales } from './helpers/recette-complete-actions-nationales';

// Vrais générateurs et vrais boutons. Seules les IO sont fictives et fermées.
// Le XML est analysé dans le banc Node : aucun bouton XML n'existe dans l'UI.
const require = createRequire(import.meta.url);
type Banc = Awaited<ReturnType<typeof genererDocuments>>;
// PDF.js 6 requires ReadableStream's async iterator, absent from the installed
// WebKit. Analyse the downloaded bytes in a separate Chromium, without changing
// the application page or the WebKit download path under test.
const test = base.extend<{ analyse: Page }>({ analyse: async ({}, use) => {
  const browser = await chromium.launch({ executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH });
  const context = await browser.newContext({ viewport: { width: 800, height: 1000 }, serviceWorkers: 'block' });
  const inconnus: string[] = [], erreurs: string[] = [];
  try {
    await context.route('**/*', async route => {
      const url = new URL(route.request().url());
      if (url.origin === 'http://127.0.0.1:8905' && url.pathname === '/analyse') return route.fulfill({ contentType: 'text/html', body: '<!doctype html><title>Analyse locale PDF</title>' });
      const name = url.pathname.split('/').pop();
      if (url.origin === 'http://127.0.0.1:8905' && url.pathname.startsWith('/__recette_pdfjs/') && ['pdf.mjs', 'pdf.worker.mjs'].includes(name!)) {
        return route.fulfill({ contentType: 'text/javascript', body: await readFile(require.resolve(`pdfjs-dist/legacy/build/${name}`)) });
      }
      inconnus.push(route.request().url()); return route.abort();
    });
    const page = await context.newPage();
    page.on('pageerror', e => erreurs.push(e.message));
    page.on('console', m => { if (m.type() === 'error') erreurs.push(m.text()); });
    await page.goto('http://127.0.0.1:8905/analyse'); await use(page);
    expect(inconnus).toEqual([]); expect(erreurs).toEqual([]);
  } finally { await browser.close(); }
} });
async function encadrer(page: Page, banc: Banc, refusHttpAttendus: Record<string, number> = {}) {
  const interdits: string[] = [], erreurs: string[] = [], lectures: string[] = [];
  page.on('console', message => {
    if (message.type() !== 'error') return;
    // Browsers report the deliberate HTTP refusal as a resource error. Match
    // only its exact fake endpoint/status; application errors still fail.
    const url = message.location().url, status = refusHttpAttendus[url];
    if (status && /^Failed to load resource:/.test(message.text()) && message.text().includes(String(status))) return;
    erreurs.push(message.text());
  });
  await page.clock.setFixedTime(new Date('2026-09-30T10:00:00Z'));
  await page.addInitScript(() => Object.defineProperty(window, 'Stripe', { value: () => { throw Error('Paiement interdit dans cette recette'); } }));
  await page.context().routeWebSocket('**/*', socket => socket.close());
  // Also close popups/other pages: page-scoped mocks do not cover them.
  await page.context().route('**/*', async route => {
    const url = new URL(route.request().url());
    if (!['127.0.0.1', 'localhost'].includes(url.hostname) || /^\/(functions|storage)\//.test(url.pathname)) {
      interdits.push(`CONTEXTE ${route.request().method()} ${url.origin}${url.pathname}`); return route.abort();
    }
    // Let the existing context-scoped mission fixture answer local API reads.
    return route.fallback();
  });
  await page.route('**/*', async route => {
    const req = route.request(), url = new URL(req.url());
    const json = (data: unknown) => route.fulfill({ json: data, headers: { 'access-control-allow-origin': '*' } });
    if (!['127.0.0.1', 'localhost'].includes(url.hostname)) {
      interdits.push(`${req.method()} ${url.origin}${url.pathname}`); return route.abort();
    }
    if (url.pathname === '/rest/v1/factures_honoraires' && req.method() === 'GET' && url.searchParams.has('id')) {
      const f = banc.factures.find(f => `eq.${f.id}` === url.searchParams.get('id'));
      expect(f).toBeTruthy(); lectures.push(`facture:${f.id}`); return json(f);
    }
    const sign = '/storage/v1/object/sign/jolene-documents/';
    if (url.pathname.startsWith(sign)) {
      const key = decodeURIComponent(url.pathname.slice(sign.length));
      const document = banc.documents.get(key); expect(document).toBeTruthy();
      if (req.method() === 'POST') {
        expect(req.postDataJSON()).toEqual({ expiresIn: 300 }); lectures.push(`signature:${key}`);
        return json({ signedURL: `/object/sign/jolene-documents/${key}?token=recette-fictive` });
      }
      if (req.method() === 'GET' && url.search === '?token=recette-fictive') {
        lectures.push(`octets:${key}`);
        return route.fulfill({ contentType: document.contentType, body: document.bytes, headers: { 'access-control-allow-origin': '*' } });
      }
    }
    if (/^\/(functions|storage)\//.test(url.pathname)) {
      interdits.push(`${req.method()} ${url.pathname}`); return route.abort();
    }
    if (req.isNavigationRequest() && req.resourceType() === 'document') {
      const response = await chargerHtmlLocal(route, 0);
      expect(response.status()).toBe(200);
      return route.fulfill({ response, body: (await response.text())
        .replace(/<link\b(?=[^>]*\brel=["'](?:preconnect|dns-prefetch)["'])[^>]*>/gi, '')
        .replace(/<link\b(?=[^>]*\bhref=["']https:\/\/fonts\.googleapis\.com\/)[^>]*>/gi, '') });
    }
    return route.fallback();
  });
  return { lectures, verifier() { expect(interdits).toEqual([]); expect(erreurs).toEqual([]); } };
}

async function analyserPdf(page: Page, bytes: Buffer, info: TestInfo, nom: string) {
  const resultat = await page.evaluate(async ({ octets, moduleUrl }) => {
    const pdfjs = await import(/* @vite-ignore */ moduleUrl);
    pdfjs.GlobalWorkerOptions.workerSrc = '/__recette_pdfjs/pdf.worker.mjs';
    const chargement = pdfjs.getDocument({ data: new Uint8Array(octets), useSystemFonts: true, isEvalSupported: false });
    const pdf = await chargement.promise;
    const pages: string[] = [], images: string[] = [], debordements: { page: number; texte: string; x: number; y: number; largeur: number }[] = [];
    for (let i = 1; i <= pdf.numPages; i++) {
      const p = await pdf.getPage(i), content = await p.getTextContent();
      pages.push(content.items.map((item: { str?: string }) => item.str || '').join(' '));
      for (const item of content.items) {
        if (item.str?.trim() && (item.transform[4] < 0 || item.transform[4] + item.width > p.getViewport({ scale: 1 }).width + 0.5
          || item.transform[5] < 0 || item.transform[5] + item.height > p.getViewport({ scale: 1 }).height + 0.5)) {
          debordements.push({ page: i, texte: item.str, x: item.transform[4], y: item.transform[5], largeur: item.width });
        }
      }
      {
        const canvas = document.createElement('canvas'), viewport = p.getViewport({ scale: 1 });
        canvas.width = viewport.width; canvas.height = viewport.height;
        await p.render({ canvasContext: canvas.getContext('2d'), viewport }).promise;
        images.push(canvas.toDataURL('image/png').split(',')[1]);
      }
    }
    const nombrePages = pdf.numPages; await chargement.destroy(); return { pages, nombrePages, debordements, images };
  }, { octets: [...bytes], moduleUrl: new URL('/__recette_pdfjs/pdf.mjs', page.url()).href });
  await info.attach(`${nom}-texte`, { body: resultat.pages.join('\n\n'), contentType: 'text/plain' });
  await info.attach(`${nom}-pdf`, { body: bytes, contentType: 'application/pdf' });
  if (info.project.name === 'ordinateur') for (const [i, image] of resultat.images.entries()) {
    await writeFile(info.outputPath(`${nom}-page-${i + 1}.png`), Buffer.from(image, 'base64'));
  }
  expect(resultat.nombrePages).toBeGreaterThan(0);
  expect(resultat.debordements, 'Aucun texte ne doit sortir de la page PDF').toEqual([]);
  return resultat.pages.join(' ').replace(/\s+/g, ' ');
}
async function telecharger(page: Page, bouton: Locator, numero: string, tactile = false) {
  const pending = page.waitForEvent('download');
  if (tactile) await bouton.tap(); else await bouton.click();
  const download = await pending;
  expect(download.suggestedFilename()).toBe(`${numero}.pdf`); expect(await download.failure()).toBeNull();
  const stream = await download.createReadStream(); expect(stream).toBeTruthy();
  const chunks: Buffer[] = []; for await (const chunk of stream!) chunks.push(Buffer.from(chunk));
  await download.delete(); return Buffer.concat(chunks);
}
async function aria(page: Page, info: TestInfo, nom: string) {
  await info.attach(nom, { body: await page.locator('main').ariaSnapshot(), contentType: 'text/plain' });
}

for (const unicode of [false, true]) test(`Documents F1 soignant${unicode ? ' Unicode' : ''} : facture et avoir générés, téléchargés et cohérents après recharge`, async ({ page, analyse }, info) => {
  const numeros = unicode ? {
    numeroFacture: 'JOL-11111111111141118111111111111111-2026-100000',
    numeroAvoir: 'AV-11111111111141118111111111111111-2026-100000',
  } : {};
  const banc = await genererDocuments({ unicode, ...numeros }), etat = await simulerSoignant(page), reseau = await encadrer(page, banc);
  const nom = `${banc.soignant.prenom} ${banc.soignant.nom}`;
  Object.assign(etat.profile, { type_exercice: 'LIBERAL', statut_liberal: 'EN_COURS', rpps_verifie: false, tous_documents_valides: false });
  const rows = banc.factures.map(f => ({ ...f, mission_intitule: banc.mission.intitule, etablissement_nom: banc.etablissement.nom, statut_litige: 'NORMAL' }));
  etat.overrides.set('fn_mes_factures_honoraires', rows); etat.tables.set('factures_honoraires', rows);
  await entrerSoignant(page, 'connexion'); await aller(page, '/soignant/mes-gains?tab=factures');
  await page.getByRole('tab', { name: 'Factures', exact: true }).click();
  await expect(page.getByText(rows[0].numero_facture, { exact: true })).toBeVisible();
  await aria(page, info, 'avant-telechargement');
  for (const reload of [false, true]) {
    if (reload) await recharger(page);
    for (const f of rows) {
      await expect(page.getByText(f.numero_facture, { exact: true })).toBeVisible();
      const desktop = page.getByRole('row').filter({ hasText: f.numero_facture }).getByRole('button', { name: 'PDF', exact: true });
      const mobile = page.locator('.card-base').filter({ has: page.getByText(f.numero_facture, { exact: true }) }).getByRole('button', { name: 'Télécharger le PDF', exact: true });
      const bytes = await telecharger(page, await desktop.isVisible() ? desktop : mobile, f.numero_facture);
      expect(sha256(bytes)).toBe(sha256(banc.documents.get(f.pdf_s3_key).bytes));
      if (!reload) {
        const texte = await analyserPdf(analyse, bytes, info, f.numero_facture);
        expect(texte).toContain(f.numero_facture); expect(texte).toContain(nom);
        expect(texte).toContain(banc.etablissement.nom);
        expect(texte).toContain(banc.soignant.adresse_rue);
        // The exact identity appears in bold in the seller block and in the
        // normal font in the subrogation text; both fonts must preserve it.
        expect(texte.split(nom).length - 1).toBeGreaterThanOrEqual(2);
        const total = ((f.type_document === 'AVOIR' ? -1 : 1) * f.montant_ttc).toFixed(2);
        expect(texte).toContain(`TOTAL ${total} EUR 0.00 EUR ${total} EUR`);
        expect(texte).toContain(`Quantite : ${f.quantite_heures_snapshot.toFixed(2)} h`);
        expect(texte).toContain('Prix unitaire HT : 20.00 EUR/h');
        expect(texte).toContain(f.type_document === 'AVOIR' ? 'Jolene AVOIR Numero :' : "Jolene FACTURE D'HONORAIRES Numero :");
        expect(texte).toContain('SIRET : 11111111111111'); expect(texte).toContain('SIRET : 22222222222222');
        expect(texte).toContain("Date d'emission : 2026-09-30"); expect(texte).toContain("Date d'echeance : 2026-10-30");
        expect(texte).toContain(verifierXml(banc.documents.get(f.facturx_xml_url).bytes, f,
          f.type_document === 'AVOIR' ? rows[0] : undefined, nom, banc.etablissement.nom).mention);
        if (f.type_document === 'AVOIR') expect(texte).toContain(`Avoir emis sur facture n. ${rows[0].numero_facture} du 2026-09-30`);
        else expect(texte).toContain('Periode du 2026-09-21 au 2026-09-27');
      }
    }
    await expect(page.getByRole('tabpanel')).toContainText(/80,00\s*€/);
    await expect(page.getByRole('tabpanel')).toContainText(/-20,00\s*€/);
  }
  await aria(page, info, 'apres-telechargement-et-recharge');
  await page.screenshot({ path: info.outputPath('soignant-documents.png'), fullPage: false, scale: 'css' });
  await info.attach('registre-documentaire', { body: JSON.stringify(banc.versions, null, 2), contentType: 'application/json' });
  expect(reseau.lectures.filter(x => x.startsWith('octets:'))).toHaveLength(4);
  expect(etat.unknown).toEqual([]); expect(etat.errors).toEqual([]);
  expect(etat.calls.filter(c => /emettre|preparer_facture|accepter_document|generate-invoice|checkout/.test(c.name))).toEqual([]);
  reseau.verifier();
  // Stress de mise en page, indépendant de la UI : identité composée et longue
  // description existante. Le handler doit conserver la mention entière et le
  // pied de page, y compris lorsqu'une seconde page devient nécessaire.
  if (info.project.name === 'ordinateur') {
    const long = await genererDocuments({ pagination: true, unicode, ...numeros });
    for (const f of long.factures) {
      const texte = await analyserPdf(analyse, long.documents.get(f.pdf_s3_key).bytes, info, `pagination-${f.type_document}`);
      const nomLong = `${long.soignant.prenom} ${long.soignant.nom}`;
      expect(texte).toContain(nomLong);
      expect(texte).toContain('Jolene SASU - Mandataire de facturation');
      expect(texte).toContain(verifierXml(long.documents.get(f.facturx_xml_url).bytes, f,
        f.type_document === 'AVOIR' ? long.factures[0] : undefined, nomLong, long.etablissement.nom).mention);
    }
  }
});

test('Documents F1 établissement : commission réelle de période téléchargée après recharge', async ({ page, analyse }, info) => {
  const banc = await genererDocuments(), { etat } = await simulerEtablissement(page), reseau = await encadrer(page, banc);
  const commission = { id: ids.commission, facture_id: ids.commission, facture_honoraire_id: ids.facture, mission_id: ids.mission,
    etablissement_id: idsEtab.etab, numero_facture: 'F1-COMMISSION-SEMAINE', statut: 'EMISE', type_document: 'FACTURE',
    montant_ht: 12, montant_tva: 2.4, montant_ttc: 14.4, nombre_missions: 1, periode_debut: '2026-09-21', periode_fin: '2026-09-27',
    date_emission: '2026-09-30', date_echeance: '2026-10-30', est_secteur_public: false, chorus_pro_statut: 'NON_APPLICABLE' };
  etat.overrides.set('fn_mon_etablissement_complet', { ...etablissement, type: 'CLINIQUE_PRIVEE', est_compte_test: true });
  etat.overrides.set('fn_obligations_financieres', { total_du: 14.4, missions_a_payer: [], factures_impayees: [commission] });
  etat.overrides.set('fn_mes_factures', [commission]); etat.overrides.set('factures', commission);
  await page.route('**/rest/v1/missions?*', async route => {
    const url = new URL(route.request().url());
    expect(['127.0.0.1', 'localhost']).toContain(url.hostname);
    if (url.searchParams.get('id') !== `eq.${ids.mission}`) return route.fallback();
    expect(route.request().method()).toBe('GET');
    return route.fulfill({ json: [{ ...banc.mission, etablissement_id: idsEtab.etab, taux_commission_fige: 15 }], headers: { 'access-control-allow-origin': '*' } });
  });
  etat.overrides.set('soignants', [banc.soignant]);
  let lecturesPlanningCommission = 0;
  await page.route('**/rest/v1/mission_creneaux?*', async route => {
    const req = route.request(), url = new URL(req.url());
    expect(['127.0.0.1', 'localhost']).toContain(url.hostname);
    expect(req.method()).toBe('GET');
    expect(url.searchParams.get('mission_id')).toBe(`in.(${ids.mission})`);
    expect(url.searchParams.get('est_pause')).toBe('eq.false');
    expect(req.headers().prefer).toContain('count=exact');
    expect(url.searchParams.get('offset')).toBe('0');
    expect(url.searchParams.get('limit')).toBe('500');
    lecturesPlanningCommission += 1;
    // Même une liste vide doit attester son total PostgREST ; sans cet en-tête,
    // le générateur refuse à juste titre un planning impossible à vérifier.
    return route.fulfill({ json: [], headers: {
      'access-control-allow-origin': '*', 'access-control-expose-headers': 'content-range',
      'content-range': '*/0',
    } });
  });
  await entrerEtablissement(page, 'connexion'); await allerA(page, '/etablissement/facturation?tab=commissions');
  await expect(page.getByText(commission.numero_facture, { exact: true })).toBeVisible(); await aria(page, info, 'avant-commission');
  for (const reload of [false, true]) {
    if (reload) { await stabiliserLectures(page); await page.reload(); }
    await expect(page.getByText(commission.numero_facture, { exact: true })).toBeVisible();
    const bytes = await telecharger(page, page.getByRole('button', { name: 'PDF', exact: true }).first(), commission.numero_facture);
    const texte = await analyserPdf(analyse, bytes, info, `commission-${reload ? 'recharge' : 'initial'}`);
    expect(texte).toContain(commission.numero_facture); expect(texte).toContain('FACTURE COMMISSION');
    expect(texte).toContain('12,00'); expect(texte).toContain('2,40'); expect(texte).toContain('14,40');
    expect(texte).toContain('80,00'); expect(texte).toContain("Élodie L'Été");
  }
  await aria(page, info, 'apres-commission-et-recharge');
  await page.screenshot({ path: info.outputPath('etablissement-commission.png'), fullPage: false, scale: 'css' });
  expect(lecturesPlanningCommission).toBe(2);
  expect(etat.inconnues).toEqual([]); expect(etat.erreurs).toEqual([]); expect(etat.ecritures).toEqual([]); expect(etat.operations).toEqual([]);
  reseau.verifier();
});

test('Documents F1 établissement : une facture absente interdit le paiement, y compris après recharge', async ({ page }, info) => {
  // Le vrai handler reste témoin du refus Unicode. L'interface ne doit plus
  // appeler un paiement mission-only ni générer implicitement sa facture.
  const banc = creerBanc(); banc.soignant.prenom = '李';
  const refus = await banc.genererFacture(), payload = await refus.json();
  expect(refus.status).toBe(422); expect(banc.documents.size).toBe(0); expect(banc.factures).toEqual([]);
  expect(banc.appels.filter(a => a.method !== 'GET' && a.path !== '/rest/v1/rpc/fn_verifier_pre_facturation')).toEqual([]);
  const { etat } = await simulerEtablissement(page);
  const reseau = await encadrer(page, banc);
  etat.overrides.set('fn_mon_etablissement_complet', { ...etablissement, type: 'CLINIQUE_PRIVEE', est_compte_test: true });
  etat.overrides.set('fn_obligations_financieres', { total_du: 94.4, factures_impayees: [], missions_non_payees: [{
    mission_id: ids.mission, intitule: banc.mission.intitule, type_contrat_applique: 'LIBERAL',
    soignant_stripe_connect: true, soignant_nom: "李 L'Été", soignant_profession: 'IDE',
    heures: 4, net_a_payer: 80, montant_commission_ttc: 14.4, jours_depuis_fin: 1,
    debut_le: '2026-09-21', fin_le: '2026-09-27',
  }] });
  await entrerEtablissement(page, 'connexion');
  await allerA(page, '/etablissement/facturation?tab=payer');
  for (const reload of [false, true]) {
    if (reload) { await stabiliserLectures(page); await page.reload(); }
    await expect(page.getByRole('alert').filter({ hasText: 'Facture identifiée requise' })).toBeVisible();
    await expect(page.getByText('Montant payable non établi', { exact: true })).toBeVisible();
    await expect(page.getByRole('button', { name: /Payer via Stripe|Déclarer un paiement/ })).toHaveCount(0);
    await expect(page.getByText("李 L'Été", { exact: true })).toBeVisible();
    await expect(page.getByText(/U\+674E|Facture honoraires générée automatiquement|Paiement confirmé/)).toHaveCount(0);
  }
  await aria(page, info, 'piece-absente-apres-recharge');
  await info.attach('refus-reel-handler', { body: JSON.stringify(payload, null, 2), contentType: 'application/json' });
  await page.screenshot({ path: info.outputPath('piece-absente.png'), fullPage: false, scale: 'css', animations: 'disabled' });
  expect(etat.inconnues).toEqual([]); expect(etat.erreurs).toEqual([]); expect(etat.ecritures).toEqual([]); expect(etat.operations).toEqual([]);
  reseau.verifier();
});

// Same archived bytes as the document suite; the adapter maps only fixture UUIDs
// to the authenticated mission actors. No mission completion or payment occurs.
for (const remplacement of [false, true]) for (const surface of ['a-payer', 'detail-etablissement', 'detail-soignant'] as const) {
  test(`${remplacement ? 'Remplacement' : 'Accès'} F1 EN_COURS ${surface} : documents archivés accessibles, refus de téléchargement puis reprise`, async ({ page, context, analyse }, info) => {
    const numeros = remplacement && surface === 'detail-etablissement' ? {
      numeroFacture: 'JOL-11111111111141118111111111111111-2026-100000',
      numeroRemplacement: 'JOL-11111111111141118111111111111111-2026-100001',
    } : {};
    const banc = await genererDocuments({ remplacement, unicode: remplacement, ...numeros }), simulation = creerSuiviSimule();
    const { state, installer } = simulation;
    Object.assign(state.soignant, banc.soignant, { id: idsMission.soignant, type_exercice: 'LIBERAL' });
    Object.assign(state.etablissement, banc.etablissement, { id: idsMission.etablissement, est_compte_test: true });
    Object.assign(state.mission, banc.mission, { id: idsMission.mission,
      soignant_assigne_id: idsMission.soignant, etablissement_id: idsMission.etablissement,
      statut: 'EN_COURS', nb_creneaux: 2, profession_requise: banc.soignant.profession,
      type_contrat_recherche: 'LIBERAL', etablissements: state.etablissement });
    if (remplacement) Object.assign(state.mission, { taux_horaire_base: 18, total_brut: 144, net_a_payer: 144, montant_commission_ht: 21.6 });
    // The mission spans two weeks, but contains two four-hour shifts, not
    // one continuous 316-hour shift. Only the first shift has been worked.
    state.creneaux.splice(0, state.creneaux.length,
      { id: '71000000-0000-4000-8000-000000000010', mission_id: idsMission.mission,
        debut: '2026-09-21T08:00:00Z', fin: '2026-09-21T12:00:00Z', est_pause: false, type_creneau: 'PREVISIONNEL' },
      { id: '71000000-0000-4000-8000-000000000011', mission_id: idsMission.mission,
        debut: '2026-10-04T08:00:00Z', fin: '2026-10-04T12:00:00Z', est_pause: false, type_creneau: 'PREVISIONNEL' },
      { id: '71000000-0000-4000-8000-000000000012', mission_id: idsMission.mission,
        debut: '2026-09-21T08:00:00Z', fin: '2026-09-21T12:00:00Z', est_pause: false, type_creneau: 'EFFECTIF' });
    const heures = (type: string) => state.creneaux.filter(c => c.type_creneau === type)
      .reduce((total, c) => total + (Date.parse(c.fin) - Date.parse(c.debut)) / 3_600_000, 0);
    expect(heures('PREVISIONNEL')).toBe(8); expect(heures('EFFECTIF')).toBe(4);
    if (remplacement) {
      // Le frontend n'a plus de génération libérale mission-only. Exercer la
      // reprise réelle du handler local, puis consulter les mêmes archives par
      // les gestes existants ; les RPC/Storage restent des doubles fermés.
      const avant = { appels: banc.appels.length, documents: banc.documents.size,
        versions: banc.versions.length, emissions: banc.emissions.length,
        factures: JSON.stringify(banc.factures) };
      const reprise = await banc.genererFacture(), payload = await reprise.json();
      expect(reprise.status).toBe(409); expect(payload.facture_id).toBe(ids.remplacement);
      const appels = banc.appels.slice(avant.appels);
      const commissions = appels.filter(a => a.path.includes('/fn_preparer_'));
      expect(commissions.map(a => ({ path: a.path, id: a.body.p_facture_honoraire_id }))).toEqual([
        { path: '/rest/v1/rpc/fn_preparer_commission_remplacement_honoraires', id: ids.remplacement },
      ]);
      expect(appels.filter(a => a.path.startsWith('/storage/') || a.path.endsWith('/send-email'))).toEqual([]);
      expect(banc.documents.size).toBe(avant.documents); expect(banc.versions.length).toBe(avant.versions);
      expect(banc.emissions.length).toBe(avant.emissions); expect(JSON.stringify(banc.factures)).toBe(avant.factures);
      expect(banc.inconnus).toEqual([]);
      await info.attach('reprise-remplacement-emis-handler', { body: JSON.stringify({ payload, commissions,
        aucunNouveauRendu: true, aucuneNouvelleEmission: true }, null, 2), contentType: 'application/json' });
    }
    const rows = banc.factures.map(f => ({ ...f, mission_id: idsMission.mission,
      soignant_id: idsMission.soignant, etablissement_id: idsMission.etablissement }));
    const [original, correction] = rows;
    expect(correction.type_document).toBe(remplacement ? 'FACTURE' : 'AVOIR');
    expect(correction.facture_precedente_id).toBe(original.id);
    const exigible = remplacement ? correction : original;
    const commissionTtc = remplacement ? 12.96 : 14.4;
    expect(original.est_facture_finale_mission).toBe(false);
    expect(rows.map(f => f.statut)).toEqual([remplacement ? 'REMPLACEE' : 'EMISE', 'EMISE']);
    state.facture = exigible;
    const avantMission = JSON.stringify(state.mission), avantDocuments = JSON.stringify(rows);
    const role = surface === 'detail-soignant' ? 'SOIGNANT' : 'ADMIN_ETABLISSEMENT';
    await installer(context, role);
    const refusHttpAttendus: Record<string, number> = {};
    const reseau = await encadrer(page, banc, refusHttpAttendus);
    const interdits: string[] = [], lectures: string[] = [], telechargements: string[] = [];
    const simulationsSansEffet: string[] = [], octetsVerifies: { numero: string; sha256: string }[] = [];
    const tactile = Boolean(info.project.use.hasTouch);
    page.on('download', download => telechargements.push(download.suggestedFilename()));
    // Explicit read-only RPC allowlist. Even a simulated payment/generation,
    // signature, completion or change of status is forbidden before dispatch.
    const rpcsPermises = new Set([
      'fn_get_my_role', 'fn_compte_auth_actif', 'fn_mon_profil_soignant_complet', 'fn_mon_etablissement_complet',
      'fn_etablissement_public', 'fn_etablissement_pour_mission', 'fn_etablissements_safe',
      'fn_soignant_pour_etablissement', 'fn_messages_non_lus', 'fn_mes_permissions_etab',
      'fn_obligations_financieres', 'fn_paiements_etablissement', 'fn_mes_factures',
      'fn_litige_pour_mission', 'fn_presences_detail_mission', 'fn_suivi_escrow_mission', 'fn_lister_copies_bulletins',
      'fn_note_moyenne', 'fn_mode_exercice', 'fn_param_bool', 'fn_onboarding_soignant_statut',
      'fn_alerte_cddu_repetitif', 'fn_etat_pointage_mission', 'fn_mode_paiement_mission',
      'fn_score_etab_public', 'fn_user_id_pour_etablissement', 'fn_est_bloque', 'fn_interlocuteurs_conversations',
    ]);
    await page.route('**/rest/v1/**', async route => {
      const req = route.request(), url = new URL(req.url()), nom = url.pathname.split('/').at(-1)!;
      const rpc = url.pathname.startsWith('/rest/v1/rpc/');
      // The mounted chat invokes these automatically. Answer inert fixtures
      // here, before the general helper: no presence/conversation is written.
      if (rpc && ['fn_update_presence', 'fn_obtenir_conversation', 'fn_marquer_messages_lus'].includes(nom)) {
        expect(['localhost', '127.0.0.1']).toContain(url.hostname);
        expect(req.method()).toBe('POST');
        expect(req.headers().authorization).toBe(`Bearer simulation-mission-${role}`);
        simulationsSansEffet.push(nom);
        return route.fulfill({ json: nom === 'fn_obtenir_conversation'
          ? '71000000-0000-4000-8000-000000000007' : null });
      }
      if (!['localhost', '127.0.0.1'].includes(url.hostname)
        || (rpc ? req.method() !== 'POST' || !rpcsPermises.has(nom) : !['GET', 'HEAD'].includes(req.method()))) {
        interdits.push(`${req.method()} ${url.origin}${url.pathname}`); return route.abort();
      }
      lectures.push(`${req.method()} ${nom}`);
      if (nom === 'fn_obligations_financieres') return route.fulfill({ json: {
        total_du: remplacement ? 84.96 : 94.4, total_soignants_du: exigible.montant_ttc, total_commissions_du: commissionTtc,
        nb_missions_non_payees: 1, factures_impayees: [],
        missions_non_payees: [{ mission_id: idsMission.mission, intitule: state.mission.intitule,
          soignant_id: idsMission.soignant, soignant_nom: `${state.soignant.prenom} ${state.soignant.nom}`,
          soignant_profession: 'IDE', soignant_stripe_connect: true, type_contrat_applique: 'LIBERAL',
          net_a_payer: exigible.montant_ttc, heures: 4, montant_commission_ttc: commissionTtc, jours_depuis_fin: 0,
          debut_le: state.mission.debut_le, fin_le: state.mission.fin_le, facture_honoraires_id: exigible.id,
          periode_debut: exigible.periode_debut, periode_fin: exigible.periode_fin,
          est_facture_finale_mission: false }],
      } });
      if (nom === 'factures_honoraires' && !url.searchParams.has('id')) {
        let result = rows;
        for (const key of ['mission_id', 'etablissement_id', 'soignant_id', 'type_document', 'statut']) {
          const filtre = url.searchParams.get(key);
          if (filtre?.startsWith('eq.')) result = result.filter(row => String(row[key]) === filtre.slice(3));
          if (filtre?.startsWith('in.(')) result = result.filter(row => filtre.slice(4, -1).split(',').includes(String(row[key])));
        }
        return route.fulfill({ json: result });
      }
      return route.fallback();
    });
    const chemin = surface === 'a-payer' ? '/etablissement/facturation?tab=payer'
      : `/${surface === 'detail-soignant' ? 'soignant' : 'etablissement'}/missions/${idsMission.mission}`;
    await page.goto(chemin);
    await expect(page.getByText(state.mission.intitule, { exact: true }).first()).toBeVisible();
    const documents = surface === 'a-payer' ? [exigible] : [original, correction];
    const bouton = (f: typeof original) => page.getByRole('button', { name: `Télécharger le PDF ${f.numero_facture}`, exact: true });
    await aria(page, info, `${surface}-avant-acces`);
    expect(state.mission.statut).toBe('EN_COURS');
    expect(state.mission.soignant_assigne_id).toBe(idsMission.soignant);
    await info.attach('fixture-avant-acces', { body: JSON.stringify({ mission: state.mission, creneaux: state.creneaux,
      factures: rows, role, interdits }, null, 2), contentType: 'application/json' });
    // This is the baseline failure: the original exists and the mission is
    // EN_COURS, yet the document button used to be absent on all three surfaces.
    await expect(bouton(exigible)).toBeVisible();
    if (surface === 'a-payer') await expect(page.getByRole('button', { name: 'Payer via Stripe', exact: true })).toBeVisible();
    else {
      await expect(page.getByRole('heading', { name: surface === 'detail-soignant'
        ? 'Vos documents d’honoraires pour cette mission' : 'Documents d’honoraires du soignant', exact: true })).toBeVisible();
      await expect(bouton(original)).toBeVisible();
      await expect(bouton(correction)).toBeVisible();
      if (!remplacement) await expect(page.getByText('1 avoir comptabilisé en négatif dans le total net.', { exact: true })).toBeVisible();
    }
    let pannes = 1;
    const stockage = `/storage/v1/object/sign/jolene-documents/${exigible.pdf_s3_key}`;
    await page.route('**/storage/v1/object/sign/jolene-documents/**', async route => {
      const req = route.request(), url = new URL(req.url());
      if (req.method() === 'GET' && decodeURIComponent(url.pathname) === stockage && pannes) {
        expect(['127.0.0.1', 'localhost']).toContain(url.hostname);
        expect(url.search).toBe('?token=recette-fictive');
        pannes--; refusHttpAttendus[url.href] = 503;
        return route.fulfill({ status: 503, contentType: 'text/plain', body: 'Indisponibilité fictive du document archivé' });
      }
      return route.fallback();
    });
    if (tactile) await bouton(exigible).tap(); else await bouton(exigible).click();
    const message = page.getByText('Téléchargement indisponible (503).', { exact: true });
    await expect(message).toBeVisible(); await expect(bouton(exigible)).toBeEnabled();
    await expect.poll(async () => {
      const box = await message.boundingBox(), viewport = page.viewportSize();
      return !!box && !!viewport && box.x >= 0 && box.y >= 0
        && box.x + box.width <= viewport.width && box.y + box.height <= viewport.height;
    }, { message: 'Erreur entière visible après animation, y compris sur téléphone' }).toBe(true);
    expect(pannes).toBe(0); expect(telechargements).toEqual([]);
    await page.screenshot({ path: info.outputPath(`${surface}-refus.png`), animations: 'disabled', scale: 'css' });
    const lecturesPointage = () => state.calls.filter(call => call.name === 'fn_etat_pointage_mission'
      && call.method === 'POST' && call.body?.p_mission_id === idsMission.mission).length;
    const reprisePointage: { avant: number; apresRecharge: number; apresPolling: number }[] = [];
    for (const recharge of [false, true]) {
      if (recharge) {
        // setFixedTime already installs Playwright's clock controller. Pause at
        // that same date: no time jump and no new polling during the API drain.
        const dateFigee = Date.parse('2026-09-30T10:00:00Z');
        expect(await page.evaluate(() => Date.now())).toBe(dateFigee);
        await page.clock.pauseAt(dateFigee);
        let avant = 0;
        try {
          await stabiliserActionsNationales(page);
          avant = lecturesPointage();
          await page.reload();
          // Replaying pauseAt in a new document clears fixed-time mode.
          await page.clock.setFixedTime(dateFigee);
        } finally {
          await page.clock.resume();
        }
        expect(await page.evaluate(() => Date.now())).toBe(dateFigee);
        if (surface === 'detail-etablissement') {
          await expect.poll(lecturesPointage, { message: 'Pointage relu après recharge' }).toBeGreaterThan(avant);
          const apresRecharge = lecturesPointage();
          // This screen mounts the 5 s polling even between the two shifts.
          // Keep every console/pageerror assertion below.
          await expect.poll(lecturesPointage, { timeout: 15_000,
            message: 'Le polling pointage reprend après clock.resume' }).toBeGreaterThan(apresRecharge);
          reprisePointage.push({ avant, apresRecharge, apresPolling: lecturesPointage() });
        }
      }
      for (const f of documents) {
        await expect(bouton(f)).toBeVisible();
        const bytes = await telecharger(page, bouton(f), f.numero_facture, tactile);
        expect(sha256(bytes)).toBe(sha256(banc.documents.get(f.pdf_s3_key).bytes));
        octetsVerifies.push({ numero: f.numero_facture, sha256: sha256(bytes) });
        if (remplacement && !recharge) {
          const texte = await analyserPdf(analyse, bytes, info, `${surface}-${f.numero_facture}`);
          expect(texte).toContain(f.numero_facture);
          expect(texte).toContain(`${banc.soignant.prenom} ${banc.soignant.nom}`);
          expect(texte).toContain(banc.etablissement.nom);
          const xml = verifierXml(banc.documents.get(f.facturx_xml_url).bytes, f,
            f.id === correction.id ? original : undefined, `${banc.soignant.prenom} ${banc.soignant.nom}`, banc.etablissement.nom);
          expect(xml.type).toBe('380');
          const total = f.id === correction.id ? '72.00' : '80.00';
          const taux = f.id === correction.id ? '18.00' : '20.00';
          expect(texte).toContain(`TOTAL ${total} EUR 0.00 EUR ${total} EUR`);
          expect(texte).toContain(`Quantite : 4.00 h · Prix unitaire HT : ${taux} EUR/h`);
          const reference = `Facture rectificative remplaçant la facture n° ${original.numero_facture} du ${original.date_emission}`;
          if (f.id === correction.id) expect(texte).toContain(reference);
          else expect(texte).not.toContain('Facture rectificative remplaçant');
        }
      }
      if (remplacement) {
        if (surface === 'a-payer') {
          await expect(bouton(original)).toHaveCount(0);
          await expect(page.getByText(original.numero_facture, { exact: true })).toHaveCount(0);
          await expect(page.getByRole('button', { name: 'Payer via Stripe', exact: true })).toBeVisible();
        } else {
          await expect(bouton(original).locator('..')).toContainText('Remplacée');
          await expect(bouton(correction).locator('..')).toContainText('Émise');
          const carte = page.locator('.card-base').filter({ has: page.getByRole('heading', { name: surface === 'detail-soignant'
            ? 'Vos documents d’honoraires pour cette mission' : 'Documents d’honoraires du soignant', exact: true }) });
          await expect(carte.getByText('Net facturé', { exact: true }).locator('..')).toContainText(/72,00\s*€/);
          await expect(carte.getByText('1 avoir comptabilisé en négatif dans le total net.', { exact: true })).toHaveCount(0);
        }
      }
      expect(JSON.stringify(state.mission)).toBe(avantMission);
      expect(JSON.stringify(rows)).toBe(avantDocuments);
      expect(state.mission.statut).toBe('EN_COURS');
      await expect(page.getByText(/Paiement confirmé|Facture honoraires générée automatiquement/)).toHaveCount(0);
    }
    expect(telechargements).toEqual([...documents, ...documents].map(f => `${f.numero_facture}.pdf`));
    expect(reseau.lectures.filter(x => x.startsWith('octets:'))).toHaveLength(documents.length * 2);
    await bouton(exigible).scrollIntoViewIfNeeded();
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
    await page.screenshot({ path: info.outputPath(`${surface}-apres-recharge.png`), animations: 'disabled', scale: 'css' });
    await aria(page, info, `${surface}-apres-recharge`);
    await info.attach('acces-documents-io-fictives', { body: JSON.stringify({ mission: state.mission, creneaux: state.creneaux,
      factures: rows, lectures, stockage: reseau.lectures, telechargements, octetsVerifies,
      simulationsSansEffet, interdits, reprisePointage }, null, 2), contentType: 'application/json' });
    expect(interdits).toEqual([]); expect(state.unknown).toEqual([]); expect(state.external).toEqual([]); expect(state.errors).toEqual([]);
    expect(state.signatures).toEqual([]); expect(state.emails).toEqual([]); expect(state.sms).toEqual([]); expect(state.notes).toEqual([]);
    reseau.verifier();
  });
}
