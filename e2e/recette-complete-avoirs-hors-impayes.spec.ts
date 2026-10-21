import { expect, test as base, chromium, type Locator, type Page, type TestInfo } from '@playwright/test';
import { readFile, writeFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { simulerEtablissement, ids, etablissement, stabiliserLectures, allerA } from './helpers/recette-complete-etablissement';

// Vrai frontend, réponses intégralement fictives : aucune base, aucun fournisseur,
// aucun paiement, remboursement ou mécanisme d'imputation n'est exercé ici.
// Le contrat SQL (exclusion des AVOIR des dettes) est vérifié séparément.
// Les cinq formats sont ceux de playwright.recette-complete.config.ts.
const require = createRequire(import.meta.url);
// Même lecteur local que recette-complete-facturation-documents : PDF.js 6
// requiert ReadableStream.asyncIterator, absent du WebKit installé. Le vrai
// téléchargement reste réalisé dans chacun des cinq navigateurs/formats.
const test = base.extend<{ analysePdf: Page }>({ analysePdf: async ({}, use) => {
  const browser = await chromium.launch({ executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH });
  const context = await browser.newContext({ viewport: { width: 800, height: 1000 }, serviceWorkers: 'block' });
  const inconnus: string[] = [], erreurs: string[] = [];
  try {
    await context.route('**/*', async route => {
      const url = new URL(route.request().url()), nom = url.pathname.split('/').pop();
      if (url.origin === 'http://127.0.0.1:8905' && url.pathname === '/analyse')
        return route.fulfill({ contentType: 'text/html', body: '<!doctype html><title>Analyse locale PDF avoir</title>' });
      if (url.origin === 'http://127.0.0.1:8905' && url.pathname.startsWith('/__recette_pdfjs/') && ['pdf.mjs', 'pdf.worker.mjs'].includes(nom!))
        return route.fulfill({ contentType: 'text/javascript', body: await readFile(require.resolve(`pdfjs-dist/legacy/build/${nom}`)) });
      inconnus.push(route.request().url()); return route.abort();
    });
    await context.routeWebSocket('**/*', socket => socket.close());
    const page = await context.newPage();
    page.on('pageerror', e => erreurs.push(e.message));
    page.on('console', m => { if (m.type() === 'error') erreurs.push(m.text()); });
    await page.goto('http://127.0.0.1:8905/analyse');
    await use(page);
    expect(inconnus).toEqual([]); expect(erreurs).toEqual([]);
  } finally { await browser.close(); }
} });

async function lirePdfTelecharge(page: Page, analyse: Page, bouton: Locator, numero: string, info: TestInfo, nom: string) {
  await expect(bouton).toBeVisible({ timeout: 12_000 });
  await bouton.scrollIntoViewIfNeeded({ timeout: 12_000 });
  const [fichier] = await Promise.all([
    page.waitForEvent('download', { timeout: 12_000 }),
    activer(page, bouton, info),
  ]);
  expect(fichier.suggestedFilename()).toBe(`${numero}.pdf`);
  expect(await fichier.failure()).toBeNull();
  const flux = await fichier.createReadStream(); expect(flux).toBeTruthy();
  const morceaux: Buffer[] = [];
  for await (const morceau of flux!) morceaux.push(Buffer.from(morceau));
  const bytes = Buffer.concat(morceaux); await fichier.delete();
  expect(bytes.subarray(0, 5).toString()).toBe('%PDF-');
  const resultat = await analyse.evaluate(async ({ octets, moduleUrl }) => {
    const pdfjs = await import(/* @vite-ignore */ moduleUrl);
    pdfjs.GlobalWorkerOptions.workerSrc = '/__recette_pdfjs/pdf.worker.mjs';
    const chargement = pdfjs.getDocument({ data: new Uint8Array(octets), useSystemFonts: true, isEvalSupported: false });
    const pdf = await chargement.promise;
    const pages: string[] = [], images: string[] = [], debordements: string[] = [];
    for (let i = 1; i <= pdf.numPages; i++) {
      const p = await pdf.getPage(i), contenu = await p.getTextContent(), viewport = p.getViewport({ scale: 1 });
      pages.push(contenu.items.map((item: { str?: string }) => item.str || '').join(' '));
      for (const item of contenu.items) if (item.str?.trim() && (item.transform[4] < 0
        || item.transform[4] + item.width > viewport.width + 0.5 || item.transform[5] < 0
        || item.transform[5] + item.height > viewport.height + 0.5)) debordements.push(`${i}: ${item.str}`);
      const canvas = document.createElement('canvas');
      canvas.width = viewport.width; canvas.height = viewport.height;
      await p.render({ canvasContext: canvas.getContext('2d'), viewport }).promise;
      images.push(canvas.toDataURL('image/png').split(',')[1]);
    }
    const nombrePages = pdf.numPages; await chargement.destroy();
    return { pages, images, debordements, nombrePages };
  }, { octets: [...bytes], moduleUrl: new URL('/__recette_pdfjs/pdf.mjs', analyse.url()).href });
  await info.attach(`${nom}-pdf`, { body: bytes, contentType: 'application/pdf' });
  await info.attach(`${nom}-texte`, { body: resultat.pages.join('\n\n'), contentType: 'text/plain' });
  if (info.project.name === 'ordinateur') for (const [i, image] of resultat.images.entries()) {
    const path = info.outputPath(`${nom}-page-${i + 1}.png`);
    await writeFile(path, Buffer.from(image, 'base64'));
    await info.attach(`${nom}-page-${i + 1}`, { path, contentType: 'image/png' });
  }
  expect(resultat.nombrePages).toBeGreaterThan(0);
  expect(resultat.debordements, 'Aucun texte ne doit sortir de la page PDF').toEqual([]);
  return resultat.pages.join(' ').replace(/\s+/g, ' ');
}

const avoir = {
  id: '79000000-0000-4000-8000-000000000981', numero_facture: 'COM-RECETTE-AVOIR-001',
  type_document: 'AVOIR', statut: 'EMISE', montant_ht: 12, montant_tva: 2.4,
  montant_ttc: 14.4, montant_signe: -12, nombre_missions: 0,
  montant_avoirs_imputes: 0, montant_a_payer: 14.4, rapprochement_paiement_requis: false,
  date_emission: '2026-10-16', date_echeance: '2026-10-16', date_paiement: null,
  etablissement_id: ids.etab, mission_id: null, facture_honoraire_id: null,
  mode_paiement: null, est_secteur_public: false, stripe_payment_intent_id: null,
};
const facture = {
  ...avoir, id: '79000000-0000-4000-8000-000000000982', numero_facture: 'COM-RECETTE-FACTURE-001',
  type_document: 'FACTURE', statut: 'EN_RETARD', montant_ht: 100, montant_tva: 20,
  montant_ttc: 120, montant_a_payer: 120, montant_signe: 100, date_echeance: '2026-10-15',
};
const complement = {
  ...avoir, id: '79000000-0000-4000-8000-000000000983', numero_facture: 'COM-RECETTE-COMPLEMENT-001',
  type_document: 'FACTURE_COMPLEMENTAIRE', statut: 'EMISE', montant_ht: 10, montant_tva: 2,
  montant_ttc: 12, montant_a_payer: 12, montant_signe: 10, date_echeance: '2026-11-16',
};

test('Imputation commission : TTC120, avoir40, net80 puis paiement, compensation et refus après recharge', async ({ page }, info) => {
  const banc = await preparer(page, 'ADMIN_ETABLISSEMENT');
  const baseDocument = { ...facture, statut: 'EMISE', mode_paiement: 'STRIPE',
    montant_avoirs_imputes: 40, montant_a_payer: 80, rapprochement_paiement_requis: false };
  const absent: Record<string, unknown> = { ...baseDocument };
  delete absent.montant_a_payer;
  const cas = [
    { nom: 'net80', document: baseDocument, payable: true, regle: false, zero: false, avertissement: null },
    { nom: 'payee80', document: { ...baseDocument, statut: 'PAYEE', date_paiement: '2026-10-18T10:00:00Z' },
      payable: false, regle: true, zero: false, avertissement: null },
    { nom: 'soldee-par-avoir', document: { ...baseDocument, statut: 'PAYEE', mode_paiement: 'AVOIR',
      montant_avoirs_imputes: 120, montant_a_payer: 0, stripe_payment_intent_id: null, date_paiement: '2026-10-18T10:00:00Z' },
      payable: false, regle: true, zero: true, avertissement: null },
    { nom: 'rapprochement', document: { ...baseDocument, rapprochement_paiement_requis: true },
      payable: false, regle: false, zero: false, avertissement: 'Règlement à rapprocher après remboursement.' },
    { nom: 'projection-absente', document: absent,
      payable: false, regle: false, zero: false, avertissement: 'Solde indisponible.' },
    { nom: 'projection-incoherente', document: { ...baseDocument, montant_a_payer: 120 },
      payable: false, regle: false, zero: false, avertissement: 'Solde indisponible.' },
  ];
  try {
    for (const scenario of cas) {
      const document = scenario.document;
      banc.etat.overrides.set('fn_detail_facture', { facture: document, missions: [] });
      banc.etat.overrides.set('factures', document);
      // Une ancienne admission positive ne doit pas outrepasser le solde affiché.
      banc.etat.overrides.set('fn_modalites_reglement_commission', {
        facture_id: facture.id, virement_autorise: !scenario.regle, motif: scenario.regle ? 'FACTURE_NON_PAYABLE' : null,
      });
      await allerA(page, `/etablissement/facturation/${facture.id}`);
      for (const recharge of [false, true]) {
        const avant = banc.lectures.filter(l => l.nom === 'fn_detail_facture').length;
        if (recharge) { await stabiliserLectures(page); await page.reload(); }
        await expect(page.getByRole('heading', { name: 'FACTURE', exact: true, level: 1 })).toBeVisible();
        if (recharge) await expect.poll(() => banc.lectures.filter(l => l.nom === 'fn_detail_facture').length).toBeGreaterThan(avant);
        const totalTtc = page.getByText('Total TTC', { exact: true });
        const totaux = totalTtc.locator('..').locator('..');
        await expect(totalTtc.locator('..').locator('span').last()).toHaveText(/^120,00\s*€$/);
        if (scenario.avertissement) {
          await expect(totaux.getByRole('status')).toContainText(scenario.avertissement);
          await expect(totaux.getByText('Montant à régler', { exact: true })).toHaveCount(0);
          await expect(totaux.locator('dl')).toHaveCount(0);
        } else {
          await expect(totaux.getByText('Avoirs déduits', { exact: true }).locator('..').locator('dd'))
            .toHaveText(scenario.zero ? /^−120,00\s*€$/ : /^−40,00\s*€$/);
          await expect(totaux.getByText(scenario.regle ? 'Montant réglé hors avoirs' : 'Montant à régler', { exact: true }).locator('..').locator('dd'))
            .toHaveText(scenario.zero ? /^0,00\s*€$/ : /^80,00\s*€$/);
          if (scenario.regle) {
            await expect(totaux.getByText('Restant à payer', { exact: true }).locator('..').locator('dd')).toHaveText(/^0,00\s*€$/);
            await expect(totaux.getByText('Montant à régler', { exact: true })).toHaveCount(0);
          }
          if (scenario.zero) await expect(totaux.getByText('Soldée par avoir. Aucun débit bancaire.', { exact: true })).toBeVisible();
        }
        if (scenario.payable) {
          await expect(page.getByRole('button', { name: 'Payer', exact: true })).toBeVisible();
          await activer(page, page.getByRole('button', { name: 'Virement', exact: true }), info);
          await expect(page.getByText('Montant à virer :', { exact: true }).locator('..')).toContainText(/80,00\s*€/);
          await expect(page.getByText('Montant à virer :', { exact: true }).locator('..')).not.toContainText(/120,00\s*€/);
          await activer(page, page.getByRole('button', { name: 'Annuler', exact: true }), info);
        } else {
          await expect(page.getByRole('button', { name: 'Payer', exact: true })).toHaveCount(0);
          await expect(page.getByRole('button', { name: 'Virement', exact: true })).toHaveCount(0);
        }
        await dump(page, info, `imputation-${scenario.nom}-${recharge ? 'recharge' : 'initial'}`);
        if (scenario.nom === 'net80' && !recharge) {
          await info.attach('imputation-net80-ecran', { body: await page.screenshot({ fullPage: true }), contentType: 'image/png' });
        }
      }
    }
    expect(baseDocument.montant_ttc).toBe(120);
    expect(baseDocument.montant_a_payer).toBe(80);
    await stabiliserLectures(page); banc.verifier();
  } finally {
    await info.attach('imputation-commission-reponses-simulees', { body: JSON.stringify({
      simulation: true, backendVerified: false, providerVerified: false, realPaymentOrRefundExecuted: false,
      cas, lectures: banc.lectures, interdits: banc.interdits, consoleErrors: banc.consoleErrors,
      inconnues: banc.etat.inconnues, erreurs: banc.etat.erreurs,
    }, null, 2), contentType: 'application/json' });
  }
});

function obligations(mixte: boolean) {
  const dues = mixte ? [facture, complement] : [];
  return {
    total_du: mixte ? 132 : 0, total_soignants_du: 0, total_commissions_du: mixte ? 132 : 0,
    nb_missions_non_payees: 0, nb_paiements_en_attente: 0, nb_factures_impayees: dues.length,
    nb_factures_commission_historique: 1, missions_non_payees: [], missions_non_facturees: [],
    paiements_soignants_en_attente: [], paiements_soignants_confirmes: [],
    factures_impayees: dues.map(f => ({ ...f, facture_id: f.id })),
    factures_commission_historique: [{ ...avoir, facture_id: avoir.id }],
  };
}

async function activer(page: Page, cible: Locator, info: TestInfo) {
  await expect(cible).toBeVisible({ timeout: 12_000 });
  await cible.scrollIntoViewIfNeeded({ timeout: 12_000 });
  if (info.project.use.hasTouch) await cible.tap({ timeout: 12_000 }); else await cible.click({ timeout: 12_000 });
}

async function dump(page: Page, info: TestInfo, nom: string) {
  await info.attach(nom, { body: await page.locator('main').first().ariaSnapshot(), contentType: 'text/plain' });
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1)).toBe(true);
  if (['historique-recharge', 'admin-recherche-avoir-recharge', 'admin-groupe-recharge', 'detail-avoir-protege-recharge'].includes(nom)) {
    const path = info.outputPath(`${nom}.png`);
    await page.screenshot({ path, animations: 'disabled', scale: 'css' });
    await info.attach(`${nom}-capture`, { path, contentType: 'image/png' });
  }
}

async function preparer(page: Page, role: 'ADMIN_ETABLISSEMENT' | 'ADMIN_PLATEFORME') {
  const interdits: string[] = [], consoleErrors: string[] = [];
  const lectures: { nom: string; methode: string; payload?: unknown }[] = [];
  // Les popups et toute autre page ne sont jamais autorisées à sortir du banc.
  await page.context().route('**/*', async route => {
    const req = route.request(), url = new URL(req.url());
    interdits.push(`CONTEXTE ${req.method()} ${url.origin}${url.pathname}`);
    await route.abort();
  });
  await page.context().routeWebSocket('**/*', socket => socket.close());
  const { etat } = await simulerEtablissement(page);
  await page.clock.setFixedTime(new Date('2026-10-17T12:00:00Z'));
  page.on('console', message => { if (message.type() === 'error') consoleErrors.push(message.text()); });
  await page.addInitScript(({ id, role }) => {
    // Le service worker et les notifications physiques sont hors de cette simulation.
    if (!Reflect.deleteProperty(Object.getPrototypeOf(navigator), 'serviceWorker') || 'serviceWorker' in navigator)
      throw new Error('Service worker non isolé dans la simulation');
    sessionStorage.setItem('sb-127-auth-token', JSON.stringify({
      user: { id, email: 'avoirs-recette@example.invalid', email_confirmed_at: '2026-10-01T12:00:00Z',
        app_metadata: { role }, user_metadata: {}, aud: 'authenticated', role: 'authenticated' },
      access_token: 'simulation-avoirs', refresh_token: 'simulation-avoirs-refresh', token_type: 'bearer',
      expires_in: 3600, expires_at: Math.floor(Date.now() / 1000) + 3600,
    }));
  }, { id: ids.user, role });
  etat.overrides.set('fn_get_my_role', { role, etablissement_id: role === 'ADMIN_ETABLISSEMENT' ? ids.etab : null });
  etat.overrides.set('fn_mon_etablissement_complet', { ...etablissement, mode_paiement_commission: 'CARTE' });
  etat.overrides.set('fn_admin_mes_acces', { acces_total: true, groupes: [] });
  etat.overrides.set('fn_admin_lister_revues_tva_missions', []);

  const rpcsLues = new Set([
    'fn_get_my_role', 'fn_compte_auth_actif', 'fn_mon_etablissement_complet', 'fn_mes_permissions_etab',
    'fn_messages_non_lus', 'fn_obtenir_mes_preferences_notifications', 'fn_param_bool',
    'fn_obligations_financieres', 'fn_paiements_etablissement', 'fn_mes_factures',
    'fn_detail_facture', 'fn_modalites_reglement_commission',
    'fn_admin_mes_acces', 'fn_admin_lister_revues_tva_missions',
  ]);
  const effetsCadreInertes = new Set(['fn_update_presence', 'fn_ecrire_audit_safe', 'fn_audit_connexion']);
  await page.route('**/rest/v1/**', async route => {
    const req = route.request(), url = new URL(req.url()), nom = url.pathname.split('/').at(-1)!;
    if (req.method() === 'OPTIONS') return route.fallback();
    const rpc = url.pathname.startsWith('/rest/v1/rpc/');
    if (!['127.0.0.1', 'localhost'].includes(url.hostname)
      || (rpc ? req.method() !== 'POST' || (!rpcsLues.has(nom) && !effetsCadreInertes.has(nom))
        : !['GET', 'HEAD'].includes(req.method()))) {
      interdits.push(`${req.method()} ${url.origin}${url.pathname}`);
      return route.abort();
    }
    lectures.push({ nom, methode: req.method(), payload: rpc ? req.postDataJSON() : undefined });
    return route.fallback();
  });
  await page.route(/\/(functions|storage)\/v1\//, async route => {
    const req = route.request(), url = new URL(req.url());
    interdits.push(`${req.method()} ${url.origin}${url.pathname}`);
    await route.abort();
  });
  const verifier = () => {
    expect(interdits).toEqual([]); expect(consoleErrors).toEqual([]);
    expect(etat.inconnues).toEqual([]); expect(etat.erreurs).toEqual([]);
    expect(etat.ecritures).toEqual([]); expect(etat.operations).toEqual([]);
  };
  return { etat, lectures, interdits, consoleErrors, verifier };
}

for (const mixte of [false, true]) {
  test(`Avoir commission ${mixte ? 'avec facture et complément' : 'seul'} : dettes exactes, historique et détail sans paiement après recharge`, async ({ page }, info) => {
    const banc = await preparer(page, 'ADMIN_ETABLISSEMENT');
    const reponse = obligations(mixte), documents = mixte ? [avoir, facture, complement] : [avoir];
    banc.etat.overrides.set('fn_obligations_financieres', reponse);
    banc.etat.overrides.set('fn_mes_factures', documents);
    banc.etat.overrides.set('fn_detail_facture', { facture: avoir, missions: [] });
    banc.etat.overrides.set('fn_modalites_reglement_commission', {
      facture_id: avoir.id, virement_autorise: false, motif: 'FACTURE_NON_PAYABLE',
    });
    banc.etat.overrides.set('factures', avoir);
    const total = mixte ? /^132,00\s*€$/ : /^0,00\s*€$/;
    try {
      await allerA(page, '/etablissement/facturation?tab=commissions');
      for (const recharge of [false, true]) {
        const lecturesAvant = banc.lectures.filter(l => l.nom === 'fn_obligations_financieres').length;
        if (recharge) { await stabiliserLectures(page); await page.reload(); }
        await expect(page.getByRole('heading', { name: 'Facturation', exact: true })).toBeVisible();
        if (recharge) await expect.poll(() => banc.lectures.filter(l => l.nom === 'fn_obligations_financieres').length).toBeGreaterThan(lecturesAvant);
        await expect(page.getByText('Total à régler', { exact: true }).locator('..').locator('p').first()).toHaveText(total);
        await expect(page.getByText(`Commissions Jolene · ${mixte ? '2 factures' : '0 facture'} à régler`, { exact: true }).locator('..').locator('p').first()).toHaveText(total);
        const section = page.locator('#section-commissions');
        await expect(section.getByRole('button', { name: `Commissions Jolene (${mixte ? 2 : 0})`, exact: true })).toHaveAttribute('aria-expanded', 'true');
        if (mixte) {
          await expect(page.getByText('Aucune obligation financière en cours', { exact: true })).toHaveCount(0);
          await expect(section.getByRole('heading', { name: 'Factures et règlements en cours (2)', exact: true })).toBeVisible();
          await expect(section.getByText(facture.numero_facture, { exact: true })).toBeVisible();
          await expect(section.getByText(complement.numero_facture, { exact: true })).toBeVisible();
          await expect(section.getByRole('button', { name: 'Consulter les modalités de règlement', exact: true })).toHaveCount(2);
          await expect(section.getByText('En retard depuis le 15 octobre 2026', { exact: true })).toBeVisible();
          await expect(section.getByText('À régler avant le 16 novembre 2026', { exact: true })).toBeVisible();
        } else {
          await expect(page.getByText('Aucune obligation financière en cours', { exact: true })).toBeVisible();
          await expect(section.getByText('Aucune facture de commission à régler ou en cours.', { exact: true })).toBeVisible();
          await expect(section.getByRole('button', { name: 'Consulter les modalités de règlement', exact: true })).toHaveCount(0);
          await expect(page.getByRole('button', { name: /^(Payer|Payer via Stripe|Virement|Déclarer un paiement)$/ })).toHaveCount(0);
        }
        // Avant l'ouverture de l'historique, l'avoir n'apparaît jamais comme dossier à régler.
        await expect(section.getByText(avoir.numero_facture, { exact: true })).toHaveCount(0);
        await dump(page, info, `obligations-${recharge ? 'recharge' : 'initial'}`);
        const historique = section.getByRole('button', { name: /^Historique factures et avoirs \(1 documents?\)$/ });
        await activer(page, historique, info);
        const lien = section.getByRole('link', { name: avoir.numero_facture, exact: true }).filter({ visible: true });
        await expect(lien).toBeVisible();
        const ligne = lien.locator('../..'); // tr sur tablette/ordinateur, carte sur téléphone.
        await expect(ligne).toContainText(/-14,40\s*€/);
        await expect(ligne.getByText('Avoir', { exact: true })).toBeVisible();
        await expect(ligne.getByText(/Payée|Remboursé|À régler|En retard/)).toHaveCount(0);
        await expect(section.getByText('Affiche les 10 dernières factures clôturées et avoirs émis.', { exact: true })).toBeVisible();
        await lien.scrollIntoViewIfNeeded();
        await dump(page, info, `historique-${recharge ? 'recharge' : 'initial'}`);
      }

      await activer(page, page.locator('#section-commissions').getByRole('link', { name: avoir.numero_facture, exact: true }).filter({ visible: true }), info);
      await expect(page).toHaveURL(new RegExp(`/etablissement/facturation/${avoir.id}$`));
      for (const recharge of [false, true]) {
        const lecturesAvant = banc.lectures.filter(l => l.nom === 'fn_detail_facture').length;
        if (recharge) { await stabiliserLectures(page); await page.reload(); }
        // L'URL change avant le rendu lazy de la route : l'ancien historique
        // contient encore ses deux liens responsive vers le même document.
        // Attendre le véritable détail chargé, puis exiger un numéro unique.
        await expect(page.getByRole('heading', { name: 'AVOIR', exact: true, level: 1 })).toBeVisible();
        await expect(page.locator('#section-commissions')).toHaveCount(0);
        await expect(page.getByText(avoir.numero_facture, { exact: true })).toHaveCount(1);
        await expect(page.getByText(avoir.numero_facture, { exact: true })).toBeVisible();
        await expect(page.getByText('Total TTC', { exact: true }).locator('..').locator('span').last()).toHaveText(/^-14,40\s*€$/);
        await expect(page.getByText('Avoir', { exact: true })).toBeVisible();
        if (recharge) await expect.poll(() => banc.lectures.filter(l => l.nom === 'fn_detail_facture').length).toBeGreaterThan(lecturesAvant);
        await expect(page.getByRole('button', { name: /^(Payer|Payer via Stripe|Virement|Déclarer un paiement)$/ })).toHaveCount(0);
        await expect(page.getByText(/Paiement confirmé|Remboursement effectué|Avoir remboursé/)).toHaveCount(0);
        await dump(page, info, `detail-avoir-${recharge ? 'recharge' : 'initial'}`);
      }
      for (const nom of ['fn_detail_facture', 'fn_modalites_reglement_commission']) {
        const appels = banc.lectures.filter(l => l.nom === nom);
        expect(appels.length).toBeGreaterThanOrEqual(2);
        for (const appel of appels) expect(appel.payload).toEqual({ p_facture_id: avoir.id });
      }
      await stabiliserLectures(page);
      banc.verifier();
    } finally {
      await info.attach('avoirs-obligations-reponses-simulees', { body: JSON.stringify({
        simulation: true, backendVerified: false, providerVerified: false, imputationTested: false,
        role: 'ADMIN_ETABLISSEMENT', obligations: reponse, documents,
        lectures: banc.lectures, interdits: banc.interdits, consoleErrors: banc.consoleErrors,
        inconnues: banc.etat.inconnues, erreurs: banc.etat.erreurs,
      }, null, 2), contentType: 'application/json' });
    }
  });
}

test('Admin impayés imputés : net80, document120, rapprochement et net0 exclus après recharge', async ({ page }, info) => {
  const banc = await preparer(page, 'ADMIN_PLATEFORME');
  const partielle = { ...facture, montant_avoirs_imputes: 40, montant_a_payer: 80 };
  const gelee = { ...partielle, id: '79000000-0000-4000-8000-000000000987',
    numero_facture: 'COM-RECETTE-RAPPROCHEMENT-001', rapprochement_paiement_requis: true };
  const zero = { ...facture, id: '79000000-0000-4000-8000-000000000988',
    numero_facture: 'COM-RECETTE-NET-ZERO-001', montant_avoirs_imputes: 120, montant_a_payer: 0 };
  const documents = [partielle, gelee, zero];
  // Le marqueur « hors compte test » est une donnée simulée du lecteur admin,
  // sans lecture de production ni changement de la cohorte réelle.
  banc.etat.overrides.set('etablissements', [{ ...etablissement, est_compte_test: false }]);
  banc.etat.overrides.set('missions', []);
  banc.etat.overrides.set('notifications', []);
  let lecturesSoldes = 0;
  await page.route('**/rest/v1/factures?*', async route => {
    const req = route.request(), url = new URL(req.url());
    expect(['127.0.0.1', 'localhost']).toContain(url.hostname);
    expect(req.method()).toBe('GET');
    expect(url.searchParams.get('select')).toBe('id,numero_facture,montant_ht,montant_tva,montant_ttc,montant_avoirs_imputes,montant_a_payer,rapprochement_paiement_requis,statut,date_emission,date_echeance,nombre_missions,etablissement_id,periode_debut,periode_fin,type_document');
    expect(url.searchParams.get('type_document')).toBe('eq.FACTURE');
    expect(url.searchParams.get('statut')).toBe('in.(EMISE,EN_RETARD)');
    expect(url.searchParams.get('order')).toBe('date_echeance.asc');
    expect([...url.searchParams.keys()].sort()).toEqual(['order', 'select', 'statut', 'type_document']);
    lecturesSoldes++;
    banc.lectures.push({ nom: 'factures', methode: req.method() });
    return route.fulfill({ json: documents, headers: { 'access-control-allow-origin': '*' } });
  });
  try {
    await page.goto('/admin/impayees');
    for (const recharge of [false, true]) {
      const avant = lecturesSoldes;
      if (recharge) { await stabiliserLectures(page); await page.reload(); }
      await expect(page.getByRole('heading', { name: 'Factures impayées', exact: true })).toBeVisible();
      if (recharge) await expect.poll(() => lecturesSoldes).toBeGreaterThan(avant);
      await expect(page.getByText('1 facture en attente de paiement', { exact: true })).toBeVisible();
      await expect(page.getByText('Total impayé', { exact: true }).locator('..').locator('p').first()).toHaveText(/^80,00\s*€$/);
      const carte = page.getByRole('button', { name: new RegExp(`^${partielle.numero_facture}`) });
      await expect(carte).toContainText(/80,00\s*€ net dû/);
      await expect(carte).toContainText(/TTC du document : 120,00\s*€ · Avoirs imputés : 40,00\s*€/);
      await expect(page.getByText(gelee.numero_facture, { exact: true })).toHaveCount(0);
      await expect(page.getByText(zero.numero_facture, { exact: true })).toHaveCount(0);
      await activer(page, carte, info);
      await expect(page.getByRole('button', { name: 'Envoyer une relance', exact: true })).toHaveCount(1);
      await expect(page.getByRole('button', { name: 'Envoyer une relance', exact: true })).toBeVisible();
      await dump(page, info, `admin-impayes-net80-${recharge ? 'recharge' : 'initial'}`);
      if (!recharge) await info.attach('admin-impayes-net80-ecran', { body: await page.screenshot({ fullPage: true }), contentType: 'image/png' });
    }
    expect(partielle.montant_ttc).toBe(120); expect(partielle.montant_a_payer).toBe(80);
    expect(lecturesSoldes).toBeGreaterThanOrEqual(2);
    await stabiliserLectures(page); banc.verifier();
  } finally {
    await info.attach('admin-impayes-imputes-reponses-simulees', { body: JSON.stringify({
      simulation: true, backendVerified: false, providerVerified: false, emailSent: false,
      documents, lecturesSoldes, lectures: banc.lectures, interdits: banc.interdits,
      consoleErrors: banc.consoleErrors, inconnues: banc.etat.inconnues, erreurs: banc.etat.erreurs,
    }, null, 2), contentType: 'application/json' });
  }
});

test('Admin : avoir conservé en négatif dans l’historique, seule la vraie facture en retard reste à traiter après recharge', async ({ page }, info) => {
  const banc = await preparer(page, 'ADMIN_PLATEFORME');
  // Le marqueur de périmètre est lui aussi fictif : aucun compte de production n'est lu.
  const documents = [avoir, facture, complement].map(f => ({ ...f,
    etablissements: { nom: 'Établissement de simulation des avoirs', est_compte_test: false },
  }));
  banc.etat.overrides.set('factures', documents);
  try {
    await page.goto('/admin/facturation?q=COM-RECETTE');
    for (const recharge of [false, true]) {
      if (recharge) { await stabiliserLectures(page); await page.reload(); }
      const aTraiter = page.getByRole('region', { name: 'À traiter', exact: true });
      await expect(aTraiter.getByText(facture.numero_facture, { exact: true })).toBeVisible();
      await expect(aTraiter.getByText(avoir.numero_facture, { exact: true })).toHaveCount(0);
      await expect(aTraiter.getByText(complement.numero_facture, { exact: true })).toHaveCount(0);
      await expect(aTraiter.getByRole('checkbox')).toHaveCount(1);
      const historique = page.getByRole('region', { name: 'Historique des factures', exact: true });
      await expect(historique.getByRole('button', { name: /^Historique des factures/ })).toHaveAttribute('aria-expanded', 'true');
      await expect(historique.getByText(avoir.numero_facture, { exact: true }).filter({ visible: true })).toBeVisible();
      await expect(historique.getByText(complement.numero_facture, { exact: true }).filter({ visible: true })).toBeVisible();
      await expect(historique.getByText(facture.numero_facture, { exact: true })).toHaveCount(0);
      await expect(historique.getByText(/^-14,40\s*€$/).filter({ visible: true })).toBeVisible();
      await expect(page.getByRole('button', { name: /^(Payer|Rembourser|Confirmer|Rejeter)$/ })).toHaveCount(0);
      await dump(page, info, `admin-historique-${recharge ? 'recharge' : 'initial'}`);
      // La recherche visible ne supprime pas l'avoir : elle le retrouve seul.
      await historique.getByRole('textbox', { name: 'Rechercher dans l’historique des factures', exact: true }).fill(avoir.numero_facture);
      await expect(historique.getByText(avoir.numero_facture, { exact: true }).filter({ visible: true })).toBeVisible();
      await expect(historique.getByText(complement.numero_facture, { exact: true })).toHaveCount(0);
      await expect(aTraiter.getByText(facture.numero_facture, { exact: true })).toBeVisible();
      await historique.getByText(avoir.numero_facture, { exact: true }).filter({ visible: true }).scrollIntoViewIfNeeded();
      await dump(page, info, `admin-recherche-avoir-${recharge ? 'recharge' : 'initial'}`);
    }
    await stabiliserLectures(page);
    banc.verifier();
  } finally {
    await info.attach('avoirs-admin-reponses-simulees', { body: JSON.stringify({
      simulation: true, backendVerified: false, providerVerified: false, role: 'ADMIN_PLATEFORME', documents,
      lectures: banc.lectures, interdits: banc.interdits, consoleErrors: banc.consoleErrors,
      inconnues: banc.etat.inconnues, erreurs: banc.etat.erreurs,
    }, null, 2), contentType: 'application/json' });
  }
});

for (const cas of [
  { nom: 'en retard lié aux honoraires, établissement SEPA', statut: 'EN_RETARD', lie: true },
  { nom: 'en retard sans honoraires, établissement SEPA', statut: 'EN_RETARD', lie: false },
  { nom: 'annulé, établissement SEPA', statut: 'ANNULEE', lie: false },
]) {
  test(`Détail avoir ${cas.nom} : montants signés et aucune invitation au règlement après recharge`, async ({ page }, info) => {
    const banc = await preparer(page, 'ADMIN_ETABLISSEMENT');
    const honoraire = {
      id: '79000000-0000-4000-8000-000000000984', etablissement_id: ids.etab, mission_id: ids.mission,
      numero_facture: 'HON-RECETTE-REFERENCE-001', periode_debut: '2026-10-01', periode_fin: '2026-10-07',
      quantite_heures_snapshot: 4, taux_horaire_snapshot: 20, montant_ht: 80,
      description_prestation_snapshot: 'Prestation de référence fictive',
    };
    const document = { ...avoir, statut: cas.statut, mode_paiement: cas.lie ? 'STRIPE' : 'SEPA_DEBIT',
      mission_id: cas.lie ? ids.mission : null, facture_honoraire_id: cas.lie ? honoraire.id : null };
    banc.etat.overrides.set('fn_mon_etablissement_complet', { ...etablissement, mode_paiement_commission: 'SEPA_DEBIT' });
    banc.etat.overrides.set('fn_detail_facture', { facture: document, missions: [] });
    banc.etat.overrides.set('fn_modalites_reglement_commission', {
      facture_id: document.id, virement_autorise: false, motif: 'FACTURE_NON_PAYABLE',
    });
    banc.etat.overrides.set('factures', document);
    banc.etat.overrides.set('factures_honoraires', honoraire);
    try {
      await page.goto(`/etablissement/facturation/${document.id}`);
      for (const recharge of [false, true]) {
        if (recharge) { await stabiliserLectures(page); await page.reload(); }
        await expect(page.getByRole('heading', { name: 'AVOIR', exact: true, level: 1 })).toBeVisible();
        await expect(page.getByText(document.numero_facture, { exact: true })).toHaveCount(1);
        await expect(page.getByText(document.numero_facture, { exact: true })).toBeVisible();
        await expect(page.getByText(cas.statut === 'ANNULEE' ? 'Avoir annulé' : 'Avoir', { exact: true })).toBeVisible();
        for (const [libelle, montant] of [
          ['Total commissions HT', /^-12,00\s*€$/], ['TVA (20%)', /^-2,40\s*€$/], ['Total TTC', /^-14,40\s*€$/],
        ] as const) {
          await expect(page.getByText(libelle, { exact: true }).locator('..').locator('span').last()).toHaveText(montant);
        }
        await expect(page.getByRole('heading', { name: 'FACTURE', exact: true })).toHaveCount(0);
        await expect(page.getByText(/^(En retard|Échéance :|Mode :|Mode de paiement)/)).toHaveCount(0);
        await expect(page.getByRole('button', { name: /^(Payer|Virement|Consulter le règlement des honoraires|Consulter l’historique des paiements)$/ })).toHaveCount(0);
        await expect(page.getByText(/commission Jolene reste à régler|paiement groupé des honoraires|suivi des prélèvements|paiement en ligne est déjà engagé/)).toHaveCount(0);
        if (cas.lie) {
          await expect(page.getByText(`Cet avoir est lié à la facture d’honoraires ${honoraire.numero_facture}.`, { exact: true })).toBeVisible();
          const prestation = page.getByRole('button', { name: /^Prestation de référence fictive/ });
          await expect(prestation).toContainText(/-12,00\s*€/);
          await activer(page, prestation, info);
          await expect(page.getByText('Com. TTC', { exact: true }).locator('..')).toContainText(/-14,40\s*€/);
          await expect(page.getByText('Honoraires HT', { exact: true }).locator('..')).toContainText(/80,00\s*€/);
        }
        await page.getByRole('heading', { name: 'AVOIR', exact: true }).scrollIntoViewIfNeeded();
        await dump(page, info, `detail-avoir-protege-${recharge ? 'recharge' : 'initial'}`);
      }
      await stabiliserLectures(page);
      banc.verifier();
    } finally {
      await info.attach('detail-avoir-reponses-simulees', { body: JSON.stringify({
        simulation: true, backendVerified: false, providerVerified: false, document,
        honoraire: cas.lie ? honoraire : null, lectures: banc.lectures,
        interdits: banc.interdits, consoleErrors: banc.consoleErrors,
        inconnues: banc.etat.inconnues, erreurs: banc.etat.erreurs,
      }, null, 2), contentType: 'application/json' });
    }
  });
}

test('Détail vraies factures : montants positifs et possibilités de règlement conservées après recharge', async ({ page }, info) => {
  const banc = await preparer(page, 'ADMIN_ETABLISSEMENT');
  try {
    for (const document of [facture, complement]) {
      banc.etat.overrides.set('fn_detail_facture', { facture: document, missions: [] });
      banc.etat.overrides.set('fn_modalites_reglement_commission', { facture_id: document.id, virement_autorise: true, motif: null });
      banc.etat.overrides.set('factures', document);
      await allerA(page, `/etablissement/facturation/${document.id}`);
      for (const recharge of [false, true]) {
        if (recharge) { await stabiliserLectures(page); await page.reload(); }
        await expect(page.getByRole('heading', { name: 'FACTURE', exact: true, level: 1 })).toBeVisible();
        await expect(page.getByText(document.numero_facture, { exact: true })).toBeVisible();
        await expect(page.getByText('Total TTC', { exact: true }).locator('..').locator('span').last())
          .toHaveText(document.type_document === 'FACTURE' ? /^120,00\s*€$/ : /^12,00\s*€$/);
        await expect(page.getByRole('button', { name: 'Virement', exact: true })).toBeVisible();
        if (document.type_document === 'FACTURE') await expect(page.getByRole('button', { name: 'Payer', exact: true })).toBeVisible();
        else await expect(page.getByRole('button', { name: 'Payer', exact: true })).toHaveCount(0);
        await dump(page, info, `detail-${document.type_document}-${recharge ? 'recharge' : 'initial'}`);
      }
    }
    await stabiliserLectures(page);
    banc.verifier();
  } finally {
    await info.attach('detail-factures-reponses-simulees', { body: JSON.stringify({
      simulation: true, backendVerified: false, providerVerified: false, documents: [facture, complement],
      lectures: banc.lectures, interdits: banc.interdits, consoleErrors: banc.consoleErrors,
      inconnues: banc.etat.inconnues, erreurs: banc.etat.erreurs,
    }, null, 2), contentType: 'application/json' });
  }
});

test('Admin groupes : seules facture et complément alimentent les 132 euros impayés du groupe et de sa clinique après recharge', async ({ page }, info) => {
  const banc = await preparer(page, 'ADMIN_PLATEFORME');
  const groupe = { id: '79000000-0000-4000-8000-000000000985', nom: 'Groupe Avoirs — simulation',
    siren: null, nom_marque: null, remise_groupe_pourcent: 0, formule_abonnement: null,
    bfa_eligible: false, email_admin: null, telephone_admin: null };
  const clinique = { ...etablissement, nom: 'Clinique Avoirs — simulation', type: 'CLINIQUE',
    groupe_sante_id: groupe.id, taux_commission_negocie: null };
  const documents = [{ ...avoir, statut: 'EN_RETARD' }, facture, complement];
  banc.etat.overrides.set('groupes_sante', [groupe]);
  banc.etat.overrides.set('etablissements', [clinique]);
  banc.etat.overrides.set('factures', documents);
  try {
    await page.goto('/admin/groupes');
    for (const recharge of [false, true]) {
      const avant = banc.lectures.filter(l => l.nom === 'factures').length;
      if (recharge) { await stabiliserLectures(page); await page.reload(); }
      await expect(page.getByRole('heading', { name: groupe.nom, exact: true })).toBeVisible();
      if (recharge) await expect.poll(() => banc.lectures.filter(l => l.nom === 'factures').length).toBeGreaterThan(avant);
      await expect(page.getByText('Impayées', { exact: true }).locator('..').locator('p').first()).toHaveText(/^132,00\s*€$/);
      if ((page.viewportSize()?.width ?? 0) >= 768) {
        const ligne = page.getByRole('row').filter({ has: page.getByRole('button', { name: clinique.nom, exact: true }) });
        await expect(ligne.getByRole('cell').nth(6)).toHaveText(/^132,00\s*€$/);
      } else {
        const carte = page.locator('div.rounded-xl.border.p-3.space-y-3').filter({ hasText: clinique.nom });
        await expect(carte.getByText(/^Impayé : 132,00\s*€$/)).toBeVisible();
      }
      await expect(page.getByText(/146,40\s*€|117,60\s*€/)).toHaveCount(0);
      await page.getByText('Impayées', { exact: true }).scrollIntoViewIfNeeded();
      await dump(page, info, `admin-groupe-${recharge ? 'recharge' : 'initial'}`);
    }
    await stabiliserLectures(page);
    banc.verifier();
  } finally {
    await info.attach('groupe-avoirs-reponses-simulees', { body: JSON.stringify({
      simulation: true, backendVerified: false, providerVerified: false, groupe, clinique, documents,
      lectures: banc.lectures, interdits: banc.interdits, consoleErrors: banc.consoleErrors,
      inconnues: banc.etat.inconnues, erreurs: banc.etat.erreurs,
    }, null, 2), contentType: 'application/json' });
  }
});

test('PDF commission : vrai téléchargement de l’avoir depuis historique et détail rechargé, signes et facture témoin conservés', async ({ page, analysePdf }, info) => {
  const banc = await preparer(page, 'ADMIN_ETABLISSEMENT');
  const mission = {
    id: ids.mission, etablissement_id: ids.etab, intitule: 'Mission de référence PDF fictive',
    service: 'Recette', profession_requise: 'IDE', debut_le: '2026-10-15T06:00:00Z', fin_le: '2026-10-15T10:00:00Z',
    duree_heures: 4, taux_horaire_base: 20, taux_horaire_base_fige: 20, total_brut: 80,
    type_contrat_applique: 'LIBERAL', taux_commission_fige: 15, soignant_assigne_id: null,
    montant_commission_ht: 12, montant_commission_tva: 2.4, montant_commission_ttc: 14.4,
  };
  const honoraires = {
    id: '79000000-0000-4000-8000-000000000986', etablissement_id: ids.etab, mission_id: mission.id,
    type_document: 'FACTURE', statut: 'PAYEE',
    numero_facture: 'HON-RECETTE-PDF-REFERENCE-001', periode_debut: '2026-10-15', periode_fin: '2026-10-15',
    quantite_heures_snapshot: 4, taux_horaire_snapshot: 20, montant_ht: 80,
    description_prestation_snapshot: mission.intitule,
  };
  const avoirHonoraires = { ...honoraires, id: '79000000-0000-4000-8000-000000000987',
    type_document: 'AVOIR', statut: 'EMISE', numero_facture: 'HON-RECETTE-PDF-AVOIR-001',
    facture_precedente_id: honoraires.id };
  const document = { ...avoir, statut: 'EN_RETARD', mission_id: mission.id, nombre_missions: 1,
    facture_honoraire_id: avoirHonoraires.id, periode_debut: honoraires.periode_debut, periode_fin: honoraires.periode_fin,
    mode_paiement: 'STRIPE', stripe_payment_intent_id: 'pi_simulation_pdf_sans_paiement',
    date_paiement: '2026-10-16T10:00:00Z', taux_tva: 20 };
  const annule = { ...document, statut: 'ANNULEE' };
  const temoin = { ...document, id: facture.id, type_document: 'FACTURE', statut: 'PAYEE',
    facture_honoraire_id: honoraires.id, numero_facture: 'COM-RECETTE-FACTURE-PDF-001' };
  let pieceSelectionnee = document;
  const choisir = (piece: typeof document) => {
    pieceSelectionnee = piece;
    banc.etat.overrides.set('factures', piece);
    banc.etat.overrides.set('fn_detail_facture', { facture: piece, missions: [] });
    banc.etat.overrides.set('fn_modalites_reglement_commission', {
      facture_id: piece.id, virement_autorise: false, motif: 'FACTURE_NON_PAYABLE',
    });
  };
  choisir(document);
  banc.etat.overrides.set('fn_obligations_financieres', { ...obligations(false),
    factures_commission_historique: [{ ...document, facture_id: document.id }] });
  banc.etat.overrides.set('fn_mes_factures', [document]);
  banc.etat.overrides.set('missions', [mission]);
  const lecturesAssiettes: string[] = [];
  await page.route('**/rest/v1/factures_honoraires?*', async route => {
    const req = route.request(), url = new URL(req.url());
    expect(['127.0.0.1', 'localhost']).toContain(url.hostname);
    expect(req.method()).toBe('GET');
    expect(url.searchParams.get('etablissement_id')).toBe(`eq.${ids.etab}`);
    banc.lectures.push({ nom: 'factures_honoraires', methode: req.method() });
    const unique = req.headers().accept?.includes('object');
    if (url.searchParams.has('id')) {
      const liee = pieceSelectionnee.type_document === 'AVOIR' ? avoirHonoraires : honoraires;
      expect(url.searchParams.get('id')).toBe(`eq.${liee.id}`);
      expect(pieceSelectionnee.facture_honoraire_id).toBe(liee.id);
      expect(url.searchParams.has('statut')).toBe(false);
      expect(url.searchParams.has('type_document')).toBe(false);
      if (!unique) {
        // maybeSingle(GET) demande du JSON ordinaire ; le SDK réduit le tableau.
        expect(url.searchParams.get('select')).toBe('id,mission_id,etablissement_id,type_document,montant_ht');
        lecturesAssiettes.push(liee.id);
      }
      return route.fulfill({ json: unique ? liee : [liee], headers: { 'access-control-allow-origin': '*' } });
    } else {
      expect(unique).toBeFalsy();
      expect(url.searchParams.has('id')).toBe(false);
      expect(url.searchParams.get('type_document')).toBe('eq.FACTURE');
      expect(url.searchParams.get('statut')).toBe('in.(EMISE,EN_RETARD,VIREMENT_DECLARE)');
    }
    // La facture est PAYEE et l'autre pièce est un AVOIR : aucune n'est une
    // facture d'honoraires ouverte, mais chacune reste lisible par son ID exact.
    return route.fulfill({ json: [], headers: { 'access-control-allow-origin': '*' } });
  });
  let lecturesPlanning = 0;
  await page.route('**/rest/v1/mission_creneaux?*', async route => {
    const req = route.request(), url = new URL(req.url());
    expect(['127.0.0.1', 'localhost']).toContain(url.hostname);
    expect(req.method()).toBe('GET');
    expect(url.searchParams.get('mission_id')).toBe(`in.(${mission.id})`);
    expect(url.searchParams.get('est_pause')).toBe('eq.false');
    expect(req.headers().prefer).toContain('count=exact');
    expect(url.searchParams.get('offset')).toBe('0');
    expect(url.searchParams.get('limit')).toBe('500');
    lecturesPlanning += 1;
    return route.fulfill({ json: [], headers: { 'access-control-allow-origin': '*',
      'access-control-expose-headers': 'content-range', 'content-range': '*/0' } });
  });
  const verifierAvoir = (texte: string, estAnnule = false) => {
    expect(texte).toContain(`AVOIR COMMISSION ${document.numero_facture} AVOIR${estAnnule ? ' ANNULÉ' : ''}`);
    expect(texte).toContain('Mission de référence PDF fictive');
    // La base documentaire reste positive ; seuls les montants de commission
    // et les totaux de l'avoir sont signés. Aucun PDF artificiel n'est injecté.
    expect(texte).toMatch(/Assiette facturée pour la période Base de calcul de cette facture uniquement 80,00\s*€/);
    expect(texte).toMatch(/Commission Jolene 15% x 80,00\s*€ assiette facturée pour la période -12,00\s*€/);
    expect(texte).toMatch(/TVA 20% -2,40\s*€/);
    expect(texte).toMatch(/Commission TTC de l'avoir -14,40\s*€/);
    expect(texte).toMatch(/Total HT -12,00\s*€ TVA \(20%\) -2,40\s*€ TOTAL TTC -14,40\s*€/);
    expect(texte).toContain('Avoir généré le');
    expect(texte).not.toMatch(/FACTURE COMMISSION|EN_RETARD|FACTURE PAYÉE|Payée le|Échéance|Mode paiement|capturée à la source/);
    expect(texte).not.toMatch(/remboursé|remboursement effectué|à régler|à payer/i);
  };
  try {
    await allerA(page, '/etablissement/facturation?tab=commissions');
    await expect(page.getByRole('heading', { name: 'Facturation', exact: true })).toBeVisible({ timeout: 12_000 });
    const section = page.locator('#section-commissions');
    await expect(section).toBeVisible({ timeout: 12_000 });
    await activer(page, section.getByRole('button', { name: /^Historique factures et avoirs \(1 documents?\)$/ }), info);
    const lien = section.getByRole('link', { name: document.numero_facture, exact: true }).filter({ visible: true });
    await expect(lien).toBeVisible();
    const boutonHistorique = section.getByTitle('Télécharger l’avoir PDF', { exact: true }).filter({ visible: true });
    verifierAvoir(await lirePdfTelecharge(page, analysePdf, boutonHistorique, document.numero_facture, info, 'avoir-historique'));
    await activer(page, lien, info);
    await expect(page.getByRole('heading', { name: 'AVOIR', exact: true, level: 1 })).toBeVisible();
    await stabiliserLectures(page); await page.reload();
    await expect(page.getByRole('heading', { name: 'AVOIR', exact: true, level: 1 })).toBeVisible();
    await expect(page.getByText(document.numero_facture, { exact: true })).toHaveCount(1);
    verifierAvoir(await lirePdfTelecharge(page, analysePdf, page.getByRole('button', { name: 'PDF', exact: true }), document.numero_facture, info, 'avoir-detail-recharge'));
    await stabiliserLectures(page); choisir(annule); await page.reload();
    await expect(page.getByText('Avoir annulé', { exact: true })).toBeVisible();
    verifierAvoir(await lirePdfTelecharge(page, analysePdf, page.getByRole('button', { name: 'PDF', exact: true }), annule.numero_facture, info, 'avoir-annule'), true);
    await stabiliserLectures(page); choisir(temoin); await page.goto(`/etablissement/facturation/${temoin.id}`);
    await expect(page.getByRole('heading', { name: 'FACTURE', exact: true, level: 1 })).toBeVisible();
    const positif = await lirePdfTelecharge(page, analysePdf, page.getByRole('button', { name: 'PDF', exact: true }), temoin.numero_facture, info, 'facture-positive-temoin');
    expect(positif).toContain(`FACTURE COMMISSION ${temoin.numero_facture} PAYÉE`);
    expect(positif).toMatch(/Assiette facturée pour la période Base de calcul de cette facture uniquement 80,00\s*€/);
    expect(positif).toMatch(/Commission Jolene 15% x 80,00\s*€ assiette facturée pour la période 12,00\s*€/);
    expect(positif).toMatch(/Commission TTC facturée 14,40\s*€/);
    expect(positif).toMatch(/Total HT 12,00\s*€ TVA \(20%\) 2,40\s*€ TOTAL TTC 14,40\s*€/);
    expect(positif).toContain('FACTURE PAYÉE le');
    expect(positif).toContain('Mode paiement :'); expect(positif).toContain('Échéance :');
    expect(positif).toContain('Facture générée le');
    expect(positif).not.toMatch(/AVOIR|-14,40|-12,00|-2,40/);
    expect(lecturesPlanning).toBe(4);
    expect(lecturesAssiettes).toEqual([avoirHonoraires.id, avoirHonoraires.id, avoirHonoraires.id, honoraires.id]);
    expect(banc.lectures.filter(l => l.nom === 'factures_honoraires').length).toBeGreaterThanOrEqual(4);
    await stabiliserLectures(page); banc.verifier();
  } finally {
    await info.attach('pdf-avoirs-reponses-simulees', { body: JSON.stringify({
      simulation: true, realFrontendPdfGeneration: true, backendVerified: false, providerVerified: false,
      role: 'ADMIN_ETABLISSEMENT', documents: [document, annule, temoin], mission, honoraires, avoirHonoraires,
      lecturesPlanning, lecturesAssiettes,
      lectures: banc.lectures, interdits: banc.interdits, consoleErrors: banc.consoleErrors,
      inconnues: banc.etat.inconnues, erreurs: banc.etat.erreurs,
    }, null, 2), contentType: 'application/json' });
  }
});
