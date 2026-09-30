import { test as base, expect, chromium, type Page, type Locator, type TestInfo } from '@playwright/test';
import { readFile, writeFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { genererDocuments, verifierXml, sha256, ids } from '../tests/helpers/facturation-documents-harness.mjs';
import { simulerSoignant, entrer as entrerSoignant, aller, recharger } from './helpers/recette-complete-soignant';
import { simulerEtablissement, entrer as entrerEtablissement, allerA, stabiliserLectures, ids as idsEtab, etablissement } from './helpers/recette-complete-etablissement';

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
async function encadrer(page: Page, banc: Banc) {
  const interdits: string[] = [], erreurs: string[] = [], lectures: string[] = [];
  page.on('console', message => { if (message.type() === 'error') erreurs.push(message.text()); });
  await page.clock.setFixedTime(new Date('2026-09-30T10:00:00Z'));
  await page.addInitScript(() => Object.defineProperty(window, 'Stripe', { value: () => { throw Error('Paiement interdit dans cette recette'); } }));
  await page.context().routeWebSocket('**/*', socket => socket.close());
  // Also close popups/other pages: page-scoped mocks do not cover them.
  await page.context().route('**/*', async route => {
    const url = new URL(route.request().url());
    if (!['127.0.0.1', 'localhost'].includes(url.hostname) || /^\/(functions|storage)\//.test(url.pathname)) {
      interdits.push(`CONTEXTE ${route.request().method()} ${url.origin}${url.pathname}`); return route.abort();
    }
    return route.continue();
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
      const response = await route.fetch({ maxRedirects: 0 });
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
async function telecharger(page: Page, bouton: Locator, numero: string) {
  const pending = page.waitForEvent('download'); await bouton.click(); const download = await pending;
  expect(download.suggestedFilename()).toBe(`${numero}.pdf`); expect(await download.failure()).toBeNull();
  const stream = await download.createReadStream(); expect(stream).toBeTruthy();
  const chunks: Buffer[] = []; for await (const chunk of stream!) chunks.push(Buffer.from(chunk));
  await download.delete(); return Buffer.concat(chunks);
}
async function aria(page: Page, info: TestInfo, nom: string) {
  await info.attach(nom, { body: await page.locator('main').ariaSnapshot(), contentType: 'text/plain' });
}

for (const unicode of [false, true]) test(`Documents F1 soignant${unicode ? ' Unicode' : ''} : facture et avoir générés, téléchargés et cohérents après recharge`, async ({ page, analyse }, info) => {
  const banc = await genererDocuments({ unicode }), etat = await simulerSoignant(page), reseau = await encadrer(page, banc);
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
    const long = await genererDocuments({ pagination: true, unicode });
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
  etat.overrides.set('soignants', [banc.soignant]); etat.overrides.set('mission_creneaux', []);
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
  expect(etat.inconnues).toEqual([]); expect(etat.erreurs).toEqual([]); expect(etat.ecritures).toEqual([]); expect(etat.operations).toEqual([]);
  reseau.verifier();
});
