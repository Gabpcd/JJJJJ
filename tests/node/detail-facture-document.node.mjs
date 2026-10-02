import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { runInNewContext } from 'node:vm';
import assert from 'node:assert/strict';
import test from 'node:test';

const require = createRequire(resolve('package.json'));
const ts = require('typescript');
const React = require('react');
const { renderToStaticMarkup } = require('react-dom/server');
const source = readFileSync(process.env.DETAIL_FACTURE_TEST_SOURCE || 'src/pages/DetailFacture.tsx', 'utf8');
const compile = (text) => ts.transpileModule(text, {
  fileName: 'DetailFacture.tsx', reportDiagnostics: true,
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022, jsx: ts.JsxEmit.React, esModuleInterop: true },
});
const compiled = compile(`${source}\nexport { chargerContexteFactureCommission, lignesDocumentFactureCommission, presentationPaiementCommission, MissionDetail };`);
assert.equal(compiled.diagnostics?.length || 0, 0, 'Syntaxe TSX valide');
const normalizer = { exports: {} };
runInNewContext(compile(readFileSync('src/lib/factureCommissionUi.ts', 'utf8')).outputText, normalizer);
const noop = () => null;
let states = [];
let stateIndex = 0;
let permission = true;
const navigateTargets = [];
const jsxMock = ({ children }) => React.createElement('div', null, children);
const exports = {};
runInNewContext(compiled.outputText, {
  exports, Intl, Date, Number, Boolean, Object, Error, encodeURIComponent,
  require(name) {
    if (name === 'react') return { ...React, useState: () => [stateIndex < states.length ? states[stateIndex++] : true, noop], useEffect: noop, useCallback: (fn) => fn, useMemo: (fn) => fn(), useRef: () => ({ current: 0 }) };
    if (name === 'react-router-dom') return { useNavigate: () => (url) => navigateTargets.push(url), useParams: () => ({ id: 'commission' }) };
    if (name === 'lucide-react') return new Proxy({}, { get: () => noop });
    if (name === 'date-fns' || name === 'date-fns/locale') return require(name);
    if (name === '@/lib/factureCommissionUi') return normalizer.exports;
    if (name === '@/hooks/useEtablissementScope') return { useEtablissementScope: () => ({ user: { id: 'user' }, etablissementId: 'etab', loading: false, resolved: true, error: null, retry: noop }) };
    if (name === '@/hooks/useEtabPermissions') return { useEtabPermissions: () => ({ loading: false, permissions: { lecture_paiement: true, paiement: permission }, error: null, recharger: noop }) };
    if (name === '@/contexts/NotificationContext') return { useNotification: () => ({ afficherNotification: noop }) };
    if (name === '@/constantes/entreprise') return { ENTREPRISE: { nom: 'Jolene' } };
    if (name === '@/components/StripeEmbeddedCheckout') return { StripeEmbeddedCheckout: () => React.createElement('p', null, 'AUTONOMOUS_CHECKOUT') };
    if (name === '@/components/PaiementVirement') return { PaiementVirement: () => React.createElement('p', null, 'AUTONOMOUS_TRANSFER') };
    if (name === '@/integrations/supabase/client') return { supabase: {} };
    return new Proxy({}, { get: (_, key) => key === 'LayoutApp' ? jsxMock : noop });
  },
});

const facture = { id: 'commission', etablissement_id: 'etab', mission_id: 'mission', facture_honoraire_id: 'fh', type_document: 'FACTURE', statut: 'EMISE', mode_paiement: 'STRIPE', montant_ht: 12, montant_tva: 2.4, montant_ttc: 14.4, numero_facture: 'COM-TEST' };
const honoraires = { id: 'fh', etablissement_id: 'etab', mission_id: 'mission', numero_facture: 'FH-TEST', periode_debut: '2026-09-21', periode_fin: '2026-09-27', quantite_heures_snapshot: 4, taux_horaire_snapshot: 20, montant_ht: 80, description_prestation_snapshot: 'Prestations de soins facturées' };
const mission = { id: 'mission', intitule: 'Mission entière', debut_le: '2026-09-21', fin_le: '2026-10-05', duree_heures: 8, taux_horaire_base: 99, total_brut: 160, montant_commission_ht: 24, montant_commission_tva: 4.8, montant_commission_ttc: 28.8, presences: [{ id: 'presence-hors-periode' }], segments_effectifs: [{ id: 'segment-hors-periode' }] };
const plain = (x) => JSON.parse(JSON.stringify(x));

function clientWith(rows) {
  const queries = [];
  return { queries, from(table) {
    const query = { table, filters: [], fields: null }; queries.push(query);
    const chain = { select(fields) { query.fields = fields; return chain; }, eq(key, value) { query.filters.push([key, value]); return chain; }, async single() { return rows[table] || { data: null, error: null }; } };
    return chain;
  } };
}

function renderPage({ invoice = facture, fees = honoraires, etab = { mode_paiement_commission: 'SEPA_DEBIT' }, allowed = true, error = null } = {}) {
  stateIndex = 0; permission = allowed;
  states = [false, invoice, [mission], fees, etab, true, false, error];
  return renderToStaticMarkup(React.createElement(exports.default));
}

test('la semaine et les valeurs émises restent figées malgré la mission de 8 h', () => {
  const [line] = exports.lignesDocumentFactureCommission([mission], facture, honoraires);
  assert.equal(line.debut_le, '2026-09-21'); assert.equal(line.fin_le, '2026-09-27');
  assert.equal(line.duree_heures, 4); assert.equal(line.taux_horaire_snapshot, 20); assert.equal(line.montant_honoraires_ht, 80);
  assert.equal(line.montant_commission_ht, 12); assert.equal(line.montant_commission_tva, 2.4); assert.equal(line.montant_commission_ttc, 14.4);
  assert.equal(line.presences, undefined); assert.equal(line.segments_effectifs, undefined);
  assert.equal(mission.duree_heures, 8); assert.equal(facture.montant_ttc, 14.4);
});

test('un snapshot absent ne reprend jamais une valeur courante ou recalculée', () => {
  const [line] = exports.lignesDocumentFactureCommission([mission], facture, { ...honoraires, quantite_heures_snapshot: null, taux_horaire_snapshot: null });
  assert.equal(line.duree_heures, null); assert.equal(line.taux_horaire_snapshot, null);
  const [zero] = exports.lignesDocumentFactureCommission([mission], facture, { ...honoraires, quantite_heures_snapshot: 0 });
  assert.equal(zero.duree_heures, 0);
  const [frozen] = exports.lignesDocumentFactureCommission([mission], { ...facture, montant_ttc: 14.41 }, honoraires);
  assert.equal(frozen.montant_commission_ttc, 14.41, 'Le document émis ne doit pas être recalculé');
});

test('le rendu lié affiche 4 h et la semaine, sans SEPA annoncé ni paiement isolé dormant', () => {
  const html = renderPage();
  assert.match(html, /21\/09\/2026/); assert.match(html, /27\/09\/2026/); assert.match(html, /4 h facturées/);
  assert.match(html, /20,00/); assert.match(html, /80,00/); assert.match(html, /14,40/);
  assert.match(html, /Consulter le règlement des honoraires/); assert.match(html, /Paiement avec les honoraires/);
  for (const forbidden of ['05/10/2026', '8 h retenues', 'Prélèvement SEPA', 'Carte bancaire', 'AUTONOMOUS_CHECKOUT', 'AUTONOMOUS_TRANSFER', 'Pointages détaillés']) assert.ok(!html.includes(forbidden), forbidden);
});

test('une commission liée ne peut jamais ouvrir un paiement séparé', () => {
  for (const statut of ['EMISE', 'EN_RETARD', 'PAYEE', 'ANNULEE']) for (const mode of ['SEPA_DEBIT', 'STRIPE', null]) {
    const result = exports.presentationPaiementCommission({ ...facture, statut }, { mode_paiement_commission: mode }, true);
    assert.equal(result.canPay, false); assert.equal(result.estSepaAutomatique, false);
  }
});

test('le règlement cible la pièce ouverte et une facture payée mène explicitement à l’historique général', () => {
  const visit = (node) => {
    if (!node || typeof node !== 'object') return null;
    if (node.type === 'button' && ['Consulter le règlement des honoraires', 'Consulter l’historique des paiements'].includes(node.props.children)) return node;
    for (const child of React.Children.toArray(node.props?.children)) { const found = visit(child); if (found) return found; }
    return null;
  };
  for (const [statut, label, target] of [
    ['EMISE', 'Consulter le règlement des honoraires', '/etablissement/facturation?tab=missions-a-payer&mission=mission&facture_honoraire=fh'],
    ['EN_RETARD', 'Consulter le règlement des honoraires', '/etablissement/facturation?tab=missions-a-payer&mission=mission&facture_honoraire=fh'],
    ['PAYEE', 'Consulter l’historique des paiements', '/etablissement/facturation?tab=historique'],
  ]) {
    stateIndex = 0; permission = false;
    states = [false, { ...facture, statut }, [mission], honoraires, {}, true, false, null];
    const button = visit(exports.default()); assert.ok(button);
    assert.equal(button.props.children, label);
    button.props.onClick();
    assert.equal(navigateTargets.at(-1), target);
    assert.ok(!navigateTargets.at(-1).includes('paiement='));
  }
});

test('une facture complémentaire salariée non liée reste payable, jamais un avoir ou une commission liée', async () => {
  const salaryInvoice = { ...facture, facture_honoraire_id: null, type_document: 'FACTURE_COMPLEMENTAIRE' };
  const client = clientWith({ factures: { data: salaryInvoice }, missions: { data: { id: 'mission', type_contrat_applique: 'SALARIE' } } });
  const context = await exports.chargerContexteFactureCommission(client, 'commission', 'etab');
  assert.equal(context.honoraires, null);
  for (const statut of ['EMISE', 'EN_RETARD']) {
    assert.equal(exports.presentationPaiementCommission({ ...salaryInvoice, statut }, {}, true).canPay, true);
    assert.equal(exports.presentationPaiementCommission({ ...salaryInvoice, statut }, {}, true).canPayCard, false);
    assert.equal(exports.presentationPaiementCommission({ ...salaryInvoice, statut }, {}, false).canPay, false);
    assert.equal(exports.presentationPaiementCommission({ ...salaryInvoice, statut, type_document: 'AVOIR' }, {}, true).canPay, false);
    assert.equal(exports.presentationPaiementCommission({ ...salaryInvoice, statut, facture_honoraire_id: 'fh' }, {}, true).canPay, false);
  }
  const html = renderPage({ invoice: salaryInvoice, fees: null, etab: {} });
  assert.ok(!html.includes('AUTONOMOUS_CHECKOUT')); assert.match(html, /AUTONOMOUS_TRANSFER/);
});

test('les commissions mensuelles distinctes conservent leurs modes et permissions', () => {
  const monthly = { ...facture, facture_honoraire_id: null, mission_id: null };
  assert.equal(exports.presentationPaiementCommission(monthly, {}, true).canPay, true);
  assert.equal(exports.presentationPaiementCommission(monthly, {}, false).canPay, false);
  assert.equal(exports.presentationPaiementCommission({ ...monthly, est_secteur_public: true }, {}, true).canPay, false);
  assert.equal(exports.presentationPaiementCommission({ ...monthly, type_document: 'AVOIR' }, {}, true).canPay, false);
  assert.equal(exports.presentationPaiementCommission(monthly, { mode_paiement_commission: 'SEPA_DEBIT' }, true).canPay, false);
  for (const [mode, label] of [['STRIPE', 'Paiement en ligne'], ['VIREMENT', 'Virement bancaire'], ['SEPA', 'Prélèvement SEPA'], ['CHORUS_PRO', 'Chorus Pro']]) assert.equal(exports.presentationPaiementCommission({ ...monthly, mode_paiement: mode }, {}, true).modeLibelle, label);
  const html = renderPage({ invoice: monthly, fees: null });
  assert.match(html, /utilise le prélèvement SEPA/); assert.ok(!html.includes('programmé'));
});

test('les deux lectures sont bornées à la facture et à son établissement', async () => {
  const client = clientWith({ factures: { data: facture }, factures_honoraires: { data: honoraires } });
  const result = await exports.chargerContexteFactureCommission(client, 'commission', 'etab');
  assert.equal(result.honoraires.id, 'fh');
  assert.deepEqual(plain(client.queries.map((query) => query.filters)), [[['id', 'commission'], ['etablissement_id', 'etab']], [['id', 'fh'], ['etablissement_id', 'etab']]]);
});

test('RLS refusée ou facture absente ferme le chargement sans repli de paiement', async () => {
  for (const row of [{ data: null }, { data: null, error: new Error('RLS') }, { data: { ...facture, etablissement_id: 'autre' } }]) {
    const client = clientWith({ factures: row });
    await assert.rejects(exports.chargerContexteFactureCommission(client, 'commission', 'etab'));
    assert.equal(client.queries.length, 1);
  }
  const html = renderPage({ invoice: null, fees: null, error: 'Impossible de charger cette facture en toute sécurité.' });
  assert.match(html, /Facture indisponible/);
  for (const forbidden of ['AUTONOMOUS_CHECKOUT', 'AUTONOMOUS_TRANSFER', 'SEPA', 'Consulter le règlement']) assert.ok(!html.includes(forbidden));
});

test('la pièce liée absente, refusée ou incohérente ferme aussi le chargement', async () => {
  for (const row of [{ data: null }, { data: null, error: new Error('RLS') }, { data: { ...honoraires, mission_id: 'autre' } }, { data: { ...honoraires, etablissement_id: 'autre' } }, { data: { ...honoraires, periode_fin: null } }]) {
    const client = clientWith({ factures: { data: facture }, factures_honoraires: row });
    await assert.rejects(exports.chargerContexteFactureCommission(client, 'commission', 'etab'));
  }
});

test('une ancienne commission libérale non liée ne devient pas une commission mensuelle', async () => {
  const oldInvoice = { ...facture, facture_honoraire_id: null };
  const liberal = clientWith({ factures: { data: oldInvoice }, missions: { data: { id: 'mission', type_contrat_applique: 'LIBERAL' } } });
  await assert.rejects(exports.chargerContexteFactureCommission(liberal, 'commission', 'etab'));
  const salary = clientWith({ factures: { data: oldInvoice }, missions: { data: { id: 'mission', type_contrat_applique: 'SALARIE' } } });
  assert.equal((await exports.chargerContexteFactureCommission(salary, 'commission', 'etab')).honoraires, null);
  const monthly = clientWith({ factures: { data: { ...oldInvoice, mission_id: null } } });
  assert.equal((await exports.chargerContexteFactureCommission(monthly, 'commission', 'etab')).honoraires, null);
  assert.equal(monthly.queries.length, 1);
});

test('les vrais hooks affichent l’erreur initiale puis permettent une reprise sans ancienne facture', async () => {
  const { JSDOM } = require('jsdom');
  const dom = new JSDOM('<!doctype html><div id="root"></div>', { url: 'http://localhost/etablissement/facturation/commission' });
  const previousGlobals = new Map();
  for (const [key, value] of Object.entries({ window: dom.window, document: dom.window.document, navigator: dom.window.navigator, IS_REACT_ACT_ENVIRONMENT: true })) {
    previousGlobals.set(key, Object.getOwnPropertyDescriptor(globalThis, key));
    Object.defineProperty(globalThis, key, { configurable: true, writable: true, value });
  }
  const { createRoot } = require('react-dom/client');
  const mount = dom.window.document.getElementById('root');
  const root = createRoot(mount);
  const user = { id: 'user' };
  const permissions = { lecture_paiement: true, paiement: true };
  let scope = { user, etablissementId: 'etab', loading: false, resolved: false, error: new Error('scope refusé') };
  let releaseDetail;
  let invoiceNumber = 'COM-INITIAL';
  const contextFacture = Object.fromEntries(['id', 'etablissement_id', 'mission_id', 'facture_honoraire_id', 'type_document', 'mode_paiement'].map((key) => [key, facture[key]]));
  const client = clientWith({ factures: { data: contextFacture }, factures_honoraires: { data: honoraires } });
  client.rpc = async (name) => name === 'fn_detail_facture'
    ? new Promise((resolve) => { releaseDetail = () => resolve({ data: { facture: { ...facture, numero_facture: invoiceNumber }, missions: [mission] } }); })
    : { data: { nom: 'Établissement TEST', mode_paiement_commission: 'SEPA_DEBIT' } };
  const live = {};
  const rerender = () => root.render(React.createElement(live.default));
  const retryScope = () => { scope = { ...scope, loading: true, resolved: false, error: null }; rerender(); };
  runInNewContext(compiled.outputText, { exports: live, Intl, Date, Number, Boolean, Object, Error, encodeURIComponent,
    require(name) {
      if (name === 'react') return React;
      if (name === 'react-router-dom') return { useNavigate: () => noop, useParams: () => ({ id: 'commission' }) };
      if (name === 'lucide-react') return new Proxy({}, { get: () => noop });
      if (name === 'date-fns' || name === 'date-fns/locale') return require(name);
      if (name === '@/lib/factureCommissionUi') return normalizer.exports;
      if (name === '@/hooks/useEtablissementScope') return { useEtablissementScope: () => ({ ...scope, retry: retryScope }) };
      if (name === '@/hooks/useEtabPermissions') return { useEtabPermissions: () => ({ loading: false, permissions, error: null, recharger: noop }) };
      if (name === '@/contexts/NotificationContext') return { useNotification: () => ({ afficherNotification: noop }) };
      if (name === '@/constantes/entreprise') return { ENTREPRISE: { nom: 'Jolene' } };
      if (name === '@/components/ChargementPage') return { ChargementPage: () => React.createElement('p', null, 'CHARGEMENT') };
      if (name === '@/components/StripeEmbeddedCheckout') return { StripeEmbeddedCheckout: () => React.createElement('p', null, 'AUTONOMOUS_CHECKOUT') };
      if (name === '@/components/PaiementVirement') return { PaiementVirement: () => React.createElement('p', null, 'AUTONOMOUS_TRANSFER') };
      if (name === '@/integrations/supabase/client') return { supabase: client };
      return new Proxy({}, { get: (_, key) => key === 'LayoutApp' ? jsxMock : noop });
    },
  });
  try {
    await React.act(async () => { rerender(); });
    assert.match(mount.textContent, /Impossible de vérifier votre établissement/);
    assert.ok(!mount.textContent.includes('CHARGEMENT'));
    for (const nextNumber of ['COM-INITIAL', 'COM-REPRISE']) {
      if (nextNumber === 'COM-REPRISE') {
        await React.act(async () => { scope = { ...scope, resolved: false, error: new Error('scope refusé après facture') }; rerender(); });
        assert.match(mount.textContent, /Impossible de vérifier votre établissement/);
        assert.ok(!mount.textContent.includes('COM-INITIAL'));
      }
      const retry = [...mount.querySelectorAll('button')].find((button) => button.textContent.includes('Réessayer'));
      assert.ok(retry);
      await React.act(async () => { retry.dispatchEvent(new dom.window.MouseEvent('click', { bubbles: true })); });
      assert.equal(mount.textContent, 'CHARGEMENT');
      await React.act(async () => { scope = { ...scope, loading: false, resolved: true }; rerender(); });
      assert.equal(mount.textContent, 'CHARGEMENT');
      invoiceNumber = nextNumber;
      await React.act(async () => { releaseDetail(); });
      assert.match(mount.textContent, new RegExp(nextNumber));
      assert.ok(!mount.textContent.includes('CHARGEMENT'));
      assert.ok(!mount.textContent.includes('AUTONOMOUS_CHECKOUT'));
      if (nextNumber === 'COM-REPRISE') assert.ok(!mount.textContent.includes('COM-INITIAL'));
    }
  } finally {
    await React.act(async () => { root.unmount(); });
    dom.window.close();
    for (const [key, descriptor] of previousGlobals) {
      if (descriptor) Object.defineProperty(globalThis, key, descriptor); else delete globalThis[key];
    }
  }
});
