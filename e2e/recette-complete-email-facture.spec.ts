import { test, expect, type Page, type TestInfo } from '@playwright/test';
import {
  simulerEtablissement, entrer as entrerEtablissement, allerA, stabiliserLectures,
  ids as idsEtablissement, etablissement,
} from './helpers/recette-complete-etablissement';
import {
  simulerSoignant, entrer as entrerSoignant, aller as allerSoignant,
  recharger as rechargerSoignant, attendreAPI,
} from './helpers/recette-complete-soignant';

// Simulation de navigation uniquement. Le message HTML ci-dessous est une
// fixture, pas un email reçu ni le rendu réel de send-email. Les IDs/numéro de
// document repris du plan ne rendent pas les réponses API fictives réelles.
const factureId = 'eb90af08-a796-4f6b-905f-6304a9e186d3';
const missionId = '2cd0ffcf-bbeb-4f8d-9054-0ba2033fa5dc';
const numeroFacture = 'JOL-202610-0001';
const lienFacture = `/etablissement/facturation/${factureId}`;
const typesEmail = [
  { type: 'FACTURE_EMISE', bouton: 'Consulter le document →' },
  { type: 'FACTURE_PAYEE', bouton: 'Voir la facture →' },
] as const;
const selectionContexte = 'id,etablissement_id,mission_id,facture_honoraire_id,type_document,mode_paiement,montant_ttc,montant_avoirs_imputes,montant_a_payer,rapprochement_paiement_requis';
const rpcFinancieresInterdites = /declarer_virement|confirmer_paiement|declarer_paiement|generer_facture|preparer_facture|emettre_facture|reserver_email|acquitter_email|reprendre_email|^fn_escrow_|refund|payout/;

function parametresExacts(url: URL, attendus: Record<string, string>) {
  expect([...url.searchParams.entries()].sort()).toEqual(Object.entries(attendus).sort());
}

async function encadrer(page: Page) {
  const diagnostic = {
    erreursConsole: [] as string[], erreursPage: [] as string[], requetesEchouees: [] as string[],
    interdites: [] as string[], messagesSimules: [] as string[],
  };
  page.on('console', message => { if (message.type() === 'error') diagnostic.erreursConsole.push(message.text()); });
  page.on('pageerror', error => diagnostic.erreursPage.push(error.message));
  page.on('requestfailed', request => {
    const url = new URL(request.url());
    diagnostic.requetesEchouees.push(`${request.method()} ${url.origin}${url.pathname}: ${request.failure()?.errorText}`);
  });
  await page.context().routeWebSocket('**/*', socket => socket.close());
  await page.route('**/*', async route => {
    const request = route.request(), url = new URL(request.url());
    // Ressources connues servies en mémoire, jamais depuis leurs fournisseurs.
    if (url.origin === 'https://fonts.googleapis.com' && request.method() === 'GET') {
      return route.fulfill({ contentType: 'text/css', body: '' });
    }
    if (url.origin === 'https://js.stripe.com' && url.pathname === '/clover/stripe.js' && request.method() === 'GET') {
      return route.fulfill({ contentType: 'application/javascript', body: `window.Stripe=function(){const refuse=()=>{throw Error('Fournisseur interdit dans la simulation email');};return {_registerWrapper(){},registerAppInfo(){},elements:refuse,initEmbeddedCheckout:refuse,confirmCardPayment:refuse,createPaymentMethod:refuse};};` });
    }
    if (!['127.0.0.1', 'localhost'].includes(url.hostname)) {
      diagnostic.interdites.push(`${request.method()} ${url.origin}${url.pathname}`);
      return route.abort('blockedbyclient');
    }
    if (url.pathname === '/__recette_email_facture') {
      expect(request.method()).toBe('GET');
      const email = typesEmail.find(item => item.type === url.searchParams.get('type'));
      expect(email).toBeDefined();
      parametresExacts(url, { type: email!.type });
      diagnostic.messagesSimules.push(email!.type);
      return route.fulfill({ contentType: 'text/html; charset=utf-8', body: `<!doctype html><html lang="fr"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Email simulé</title><main><h1>Email simulé — aucun envoi</h1><p>[TEST] ${email!.type}</p><a href="${lienFacture}">${email!.bouton}</a></main></html>` });
    }
    if (/^\/(functions|storage)\/v1\//.test(url.pathname)) {
      diagnostic.interdites.push(`${request.method()} ${url.pathname}`);
      return route.fulfill({ status: 501, json: { message: 'Effet ou document non prévu dans la simulation email' } });
    }
    if (url.pathname.startsWith('/rest/v1/')) {
      const nom = url.pathname.split('/').at(-1)!;
      if ((url.pathname.includes('/rpc/') && rpcFinancieresInterdites.test(nom))
        || (!url.pathname.includes('/rpc/') && !['GET', 'HEAD', 'OPTIONS'].includes(request.method()))) {
        diagnostic.interdites.push(`${request.method()} ${url.pathname}`);
        return route.fulfill({ status: 501, json: { message: 'Mutation financière interdite dans cette simulation' } });
      }
    }
    return route.fallback();
  });
  return { diagnostic, verifier() {
    expect(diagnostic.interdites).toEqual([]);
    expect(diagnostic.erreursConsole).toEqual([]);
    expect(diagnostic.erreursPage).toEqual([]);
    expect(diagnostic.requetesEchouees).toEqual([]);
  } };
}

async function cliquer(page: Page, cible: ReturnType<Page['getByRole']>) {
  await cible.scrollIntoViewIfNeeded();
  if (test.info().project.use.hasTouch) await cible.tap(); else await cible.click();
}

async function preuve(info: TestInfo, role: string, diagnostic: unknown, observations: Record<string, unknown>) {
  await info.attach('email-facture-simulation', { contentType: 'application/json', body: JSON.stringify({
    schema: 'jolene-invoice-email-frontend-simulation/v1', role, format: info.project.name,
    viewport: info.project.use.viewport, simulationApiFermee: true, factureId, numeroFacture,
    backendVerified: false, providerVerified: false, realEmailReceived: false,
    paymentCreated: false, invoiceIssued: false, ...observations, diagnostic,
  }, null, 2) });
}

test('Email facture établissement : deux liens publics, même facture payée après recharge, aucun règlement créé', async ({ page }, info) => {
  const { etat } = await simulerEtablissement(page);
  const cadre = await encadrer(page);
  const lectures: string[] = [];
  const ecrans: Record<string, string> = {};
  const facture = {
    id: factureId, facture_id: factureId, etablissement_id: idsEtablissement.etab,
    numero_facture: numeroFacture, statut: 'PAYEE', type_document: 'FACTURE',
    mission_id: null, facture_honoraire_id: null, mode_paiement: 'STRIPE', est_secteur_public: false,
    montant_ht: 14.52, montant_tva: 2.90, taux_tva: 20, montant_ttc: 17.42,
    montant_avoirs_imputes: 0, montant_a_payer: 17.42, rapprochement_paiement_requis: false,
    date_emission: '2026-10-17', date_echeance: '2026-11-16', date_paiement: '2026-10-17',
    periode_debut: '2026-10-12', periode_fin: '2026-10-18', nombre_missions: 1,
  };
  await page.route('**/rest/v1/**', async route => {
    const request = route.request(), url = new URL(request.url()), nom = url.pathname.split('/').at(-1)!;
    if (!['fn_detail_facture', 'fn_modalites_reglement_commission', 'factures', 'mission_creneaux'].includes(nom)) return route.fallback();
    expect(['127.0.0.1', 'localhost']).toContain(url.hostname);
    if (request.method() === 'OPTIONS') return route.fallback();
    expect(request.headers().authorization).toBe('Bearer fixture-auth');
    const json = (data: unknown) => route.fulfill({ json: data, headers: { 'access-control-allow-origin': '*', 'access-control-expose-headers': 'content-range' } });
    if (url.pathname.startsWith('/rest/v1/rpc/')) {
      expect(request.method()).toBe('POST'); expect(request.postDataJSON()).toEqual({ p_facture_id: factureId });
      lectures.push(nom);
      if (nom === 'fn_modalites_reglement_commission') return json({ facture_id: factureId, virement_autorise: false, motif: 'FACTURE_NON_PAYABLE' });
      return json({ facture: { ...facture, avoirs: { imputations: [], avoir_eligible: false, avoir_reliquat: null } },
        missions: [{ id: missionId, intitule: 'Mission salariée — email simulé', type_contrat_applique: 'SALARIE',
          debut_le: '2026-10-17T14:15:00Z', fin_le: '2026-10-17T17:27:00Z', duree_heures: 3.2,
          taux_horaire_base: 25, total_brut: 80, net_estime: 75.50, soignant_nom: 'Camille Recette',
          montant_commission_ht: 14.52, montant_commission_tva: 2.90, montant_commission_ttc: 17.42, presences: [] }] });
    }
    expect(request.method()).toBe('GET');
    if (nom === 'factures') {
      parametresExacts(url, { select: selectionContexte, id: `eq.${factureId}`, etablissement_id: `eq.${idsEtablissement.etab}` });
      lectures.push('contexte-facture-scope-exact'); return json(facture);
    }
    parametresExacts(url, { select: 'id,mission_id,debut,fin,type_creneau,est_pause', mission_id: `in.(${missionId})`,
      type_creneau: 'eq.EFFECTIF', est_pause: 'eq.false', fin: 'not.is.null', order: 'debut.asc' });
    return json([{ id: '71000000-0000-4000-8000-000000000078', mission_id: missionId,
      debut: '2026-10-17T14:15:00Z', fin: '2026-10-17T17:27:00Z', type_creneau: 'EFFECTIF', est_pause: false }]);
  });
  await entrerEtablissement(page, 'connexion');
  for (const email of typesEmail) {
    await allerA(page, `/__recette_email_facture?type=${email.type}`);
    ecrans[`${email.type}-email-simule`] = await page.locator('body').ariaSnapshot();
    await cliquer(page, page.getByRole('link', { name: email.bouton, exact: true }));
    for (const recharge of [false, true]) {
      if (recharge) { await stabiliserLectures(page); await page.reload(); }
      await expect(page).toHaveURL(new RegExp(`${lienFacture}$`));
      const document = page.locator('.print-invoice');
      await expect(document.getByRole('heading', { name: 'FACTURE', exact: true })).toBeVisible();
      await expect(document.getByText(numeroFacture, { exact: true })).toBeVisible();
      await expect(document.getByText('Payée', { exact: true })).toBeVisible();
      await expect(document.getByText('Total TTC', { exact: true }).locator('..')).toContainText(/17,42\s*€/);
      await expect(document.getByText(etablissement.nom, { exact: true })).toBeVisible();
      await expect(page.getByRole('button', { name: /^(Payer|Déclarer un virement)$/ })).toHaveCount(0);
      await expect(page.getByText('Impossible de charger cette facture en toute sécurité.', { exact: true })).toHaveCount(0);
      ecrans[`${email.type}-${recharge ? 'apres' : 'avant'}-rechargement`] = await page.locator('body').ariaSnapshot();
    }
  }
  await stabiliserLectures(page);
  expect(lectures.filter(nom => nom === 'fn_detail_facture').length).toBeGreaterThanOrEqual(4);
  expect(lectures.filter(nom => nom === 'contexte-facture-scope-exact').length).toBeGreaterThanOrEqual(4);
  expect(etat.inconnues).toEqual([]); expect(etat.erreurs).toEqual([]);
  expect(etat.ecritures).toEqual([]); expect(etat.operations).toEqual([]);
  cadre.verifier();
  await preuve(info, 'ADMIN_ETABLISSEMENT', cadre.diagnostic, { linksChecked: typesEmail.map(item => item.type),
    invoiceStatus: 'PAYEE', amountCents: 1742, reloadsChecked: 2, lectures, ecrans });
  if (['iphone', 'ordinateur'].includes(info.project.name)) {
    await info.attach('facture-payee-apres-rechargement', { contentType: 'image/png', body: await page.screenshot({ fullPage: true }) });
  }
});

test('Email facture soignant : lien établissement inaccessible et parcours Paie salarié conservé après recharge', async ({ page }, info) => {
  const etat = await simulerSoignant(page);
  const cadre = await encadrer(page);
  const lecturesEtablissement: string[] = [];
  const ecrans: Record<string, string> = {};
  await page.route('**/rest/v1/**', async route => {
    const url = new URL(route.request().url()), nom = url.pathname.split('/').at(-1)!;
    if (url.pathname === '/rest/v1/factures' || ['fn_detail_facture', 'fn_modalites_reglement_commission'].includes(nom)) {
      lecturesEtablissement.push(`${route.request().method()} ${url.pathname}`);
      return route.fulfill({ status: 501, json: { message: 'Le garde de route doit empêcher toute lecture de facture établissement' } });
    }
    return route.fallback();
  });
  await entrerSoignant(page, 'connexion');
  for (const email of typesEmail) {
    await allerSoignant(page, `/__recette_email_facture?type=${email.type}`);
    await cliquer(page, page.getByRole('link', { name: email.bouton, exact: true }));
    await expect(page).toHaveURL(/\/soignant\/tableau-de-bord$/);
    await expect(page.getByRole('heading', { name: 'FACTURE', exact: true })).toHaveCount(0);
    await expect(page.getByText(numeroFacture, { exact: true })).toHaveCount(0);
    await attendreAPI(page);
    ecrans[`${email.type}-acces-refuse`] = await page.locator('body').ariaSnapshot();
  }
  await allerSoignant(page, '/soignant/mes-gains?tab=bulletins');
  for (const recharge of [false, true]) {
    if (recharge) await rechargerSoignant(page);
    await expect(page).toHaveURL(/\/soignant\/mes-gains\?tab=bulletins$/);
    await expect(page.getByRole('heading', { level: 1 })).toHaveText('💰 Revenus');
    await expect(page.getByRole('tab', { name: 'Paie', exact: true })).toHaveAttribute('aria-selected', 'true');
    await expect(page.getByRole('heading', { name: 'Simulations de paie', exact: true })).toBeVisible();
    await expect(page.getByText('Aucune simulation de paie pour le moment', { exact: true })).toBeVisible();
    await expect(page.getByRole('tab', { name: 'Factures', exact: true })).toHaveCount(0);
    await expect(page.getByText(numeroFacture, { exact: true })).toHaveCount(0);
    await expect(page.getByText('Historique financier partiellement indisponible', { exact: true })).toHaveCount(0);
    await expect(page.getByText('Impossible de charger les simulations de paie', { exact: true })).toHaveCount(0);
    ecrans[`paie-${recharge ? 'apres' : 'avant'}-rechargement`] = await page.locator('body').ariaSnapshot();
  }
  await attendreAPI(page);
  expect(lecturesEtablissement).toEqual([]);
  expect(etat.unknown).toEqual([]); expect(etat.errors).toEqual([]);
  expect(etat.calls.filter(appel => rpcFinancieresInterdites.test(appel.name))).toEqual([]);
  cadre.verifier();
  await preuve(info, 'SOIGNANT', cadre.diagnostic, { linksChecked: typesEmail.map(item => item.type),
    invoiceDetailsRequested: 0, invoiceContentVisible: false, salariedPayrollTabRestored: true,
    reloadsChecked: 1, salaryReceiptProven: false, ecrans });
  if (['iphone', 'ordinateur'].includes(info.project.name)) {
    await info.attach('paie-apres-rechargement', { contentType: 'image/png', body: await page.screenshot({ fullPage: true }) });
  }
});
