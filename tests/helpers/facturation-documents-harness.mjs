import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { createHash, webcrypto } from 'node:crypto';
import vm from 'node:vm';
import ts from 'typescript';
import * as pdfLib from 'pdf-lib';
import { createClient } from '@supabase/supabase-js';
import { DOMParser } from '@xmldom/xmldom';

export const ids = Object.freeze({
  mission: 'f1300003-3000-4000-8000-000000000003',
  facture: 'f1300004-4000-4000-8000-000000000004',
  avoir: 'f1300005-5000-4000-8000-000000000005',
  commission: 'f1300006-6000-4000-8000-000000000006',
  soignant: '11111111-1111-4111-8111-111111111111',
  etab: '22222222-2222-4222-8222-222222222222',
});
const root = new URL('../../', import.meta.url);
const origin = 'http://127.0.0.1:8904';
const secretFictif = 'service-role-recette-sans-acces';
const instant = '2026-09-30T10:00:00.000Z';
export const sha256 = value => createHash('sha256').update(value).digest('hex');

// Execute the whole current Edge module, never a copied/extracted renderer.
// Only Deno's host boundary and the Supabase client's HTTP transport change.
function chargerHandler(fetchFictif, logs) {
  let handler;
  const env = Object.freeze({ SUPABASE_URL: origin, SUPABASE_SERVICE_ROLE_KEY: secretFictif,
    SUPABASE_ANON_KEY: 'anon-recette-sans-acces', JOLENE_SIRET: '00000000000000' });
  const modules = new Map();
  class DateFixe extends Date {
    constructor(...args) { super(...(args.length ? args : [instant])); }
    static now() { return Date.parse(instant); }
  }
  const contexte = {
    Request, Response, Headers, Blob, FormData, URL, URLSearchParams, TextEncoder, TextDecoder,
    Uint8Array, ArrayBuffer, crypto: webcrypto, Date: DateFixe,
    console: Object.fromEntries(['log', 'warn', 'error'].map(level => [level, (...args) => logs.push({ level, message: args.join(' ') })])),
    Deno: { env: { get(name) { assert(Object.hasOwn(env, name), `Unknown env: ${name}`); return env[name]; } },
      serve(fn) { assert.equal(handler, undefined); handler = fn; } },
    fetch() { throw new Error('Direct network forbidden'); },
  };
  function charger(relative) {
    assert(['supabase/functions/generate-invoice/index.ts', 'supabase/functions/_shared/cors.ts',
      'supabase/functions/_shared/rate-limit.ts'].includes(relative), `Unknown module: ${relative}`);
    if (modules.has(relative)) return modules.get(relative);
    const module = { exports: {} }; modules.set(relative, module.exports);
    const source = readFileSync(new URL(relative, root), 'utf8');
    const compiled = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } }).outputText;
    const requireFerme = name => {
      if (name === 'npm:pdf-lib@1.17.1') return pdfLib;
      if (name === 'npm:@supabase/supabase-js@2.99.2') return { createClient(url, key, options) {
        assert.equal(url, origin); assert.equal(key, secretFictif);
        return createClient(url, key, { ...options, global: { ...options?.global, fetch: fetchFictif } });
      } };
      if (name === '../_shared/cors.ts') return charger('supabase/functions/_shared/cors.ts');
      if (name === '../_shared/rate-limit.ts') return charger('supabase/functions/_shared/rate-limit.ts');
      throw new Error(`Import forbidden: ${name}`);
    };
    // Keep one JS realm: pdf-lib checks Array with instanceof. Isolate IO via
    // lexical host arguments, without replacing Array or rewriting the source.
    new vm.Script(`(function(require,module,exports,${Object.keys(contexte).join(',')}){${compiled}\n})`, { filename: fileURLToPath(new URL(relative, root)) })
      .runInThisContext()(requireFerme, module, module.exports, ...Object.values(contexte));
    return module.exports;
  }
  charger('supabase/functions/generate-invoice/index.ts');
  assert.equal(typeof handler, 'function');
  return handler;
}

export function creerBanc({ panneXml = false, pagination = false } = {}) {
  const documents = new Map(), factures = [], versions = [], appels = [], inconnus = [], logs = [];
  const soignant = { id: ids.soignant, prenom: 'Élodie', nom: pagination ? "L'Été de la Vallée de Saint-Martin" : "L'Été", profession: 'IDE',
    numero_rpps: '00000000001', siret_liberal: '11111111111111', email: 'camille@example.invalid',
    adresse_rue: '1 rue Fictive', adresse_code_postal: '75001', adresse_ville: 'Paris',
    mandat_facturation_signe: true, mandat_facturation_version: '1.4', statut_tva_honoraires: 'FRANCHISE_EN_BASE' };
  const etablissement = { id: ids.etab, nom: 'Clinique fictive F1 & Santé', siret: '22222222222222',
    adresse_rue: '2 rue Fictive', adresse_code_postal: '75002', adresse_ville: 'Paris', est_secteur_public: false };
  const mission = { id: ids.mission, intitule: 'Mission hebdomadaire fictive F1', service: 'Simulation',
    soignant_assigne_id: ids.soignant, etablissement_id: ids.etab, statut: 'EN_COURS', type_contrat_applique: 'LIBERAL',
    strategie_facturation: 'HEBDO_ET_FINALE', debut_le: '2026-09-21T08:00:00Z', fin_le: '2026-10-04T12:00:00Z',
    duree_heures: 8, taux_horaire_base: 20, total_brut: 160, net_a_payer: 160, montant_commission_ht: 24,
    nature_tva_prestation: 'SOIN_THERAPEUTIQUE_EXONERE', nature_tva_confirmee_soignant: 'SOIN_THERAPEUTIQUE_EXONERE',
    nature_tva_confirmee_par: ids.soignant, statut_validation_tva: 'CONFIRMEE' };
  if (pagination) mission.intitule += ` ${'Renfort de soins et suivi de la période fictive. '.repeat(46)}`;
  const json = (data, status = 200) => new Response(JSON.stringify(data), { status, headers: { 'Content-Type': 'application/json' } });
  const fetchFictif = async (input, init) => {
    const req = new Request(input, init), url = new URL(req.url), path = url.pathname;
    appels.push({ method: req.method, path, query: url.search });
    try {
      assert.equal(url.origin, origin, 'Cloud/provider origin forbidden');
      assert.equal(req.headers.get('authorization'), `Bearer ${secretFictif}`);
      if (path.startsWith('/storage/v1/object/jolene-documents/') && req.method === 'POST') {
        const key = decodeURIComponent(path.slice('/storage/v1/object/jolene-documents/'.length));
        assert.match(key, /^(invoices|avoirs)\/[^/]+\/[^/]+\/[0-9a-f-]+\.(pdf|xml)$/);
        assert.equal(req.headers.get('x-upsert'), 'false');
        assert(!documents.has(key));
        const form = await req.formData(), file = form.get(''); assert(file instanceof Blob);
        if (panneXml && key.endsWith('.xml')) return json({ message: 'XML storage failure' }, 500);
        documents.set(key, { bytes: Buffer.from(await file.arrayBuffer()), contentType: file.type });
        return json({ Key: `jolene-documents/${key}` });
      }
      const body = req.method === 'GET' ? null : await req.json();
      if (path.startsWith('/rest/v1/rpc/') && req.method === 'POST') {
        const name = path.split('/').at(-1);
        switch (name) {
          case 'fn_verifier_pre_facturation': assert.equal(body.p_mission_id, ids.mission); return json({ success: true });
          case 'next_invoice_number': assert.equal(body.p_soignant_id, ids.soignant); return json('F1-HONORAIRE-SEMAINE');
          case 'fn_calculer_montant_periode': assert.equal(body.p_mission_id, ids.mission); return json({ montant_ht_periode: 80, duree_periode_heures: 4, taux_horaire_base_fige: 20 });
          case 'fn_cumul_factures_mission': assert.equal(body.p_mission_id, ids.mission); return json({ cumul_ht: 0, nb_factures: 0 });
          case 'fn_param_num': assert.equal(body.p_cle, 'delai_paiement_prive_j'); return json(30);
          case 'fn_emettre_document_facturation_honoraires': {
            const f = factures.find(f => f.id === body.p_facture_id); assert(f);
            assert(documents.has(body.p_pdf_s3_key) && documents.has(body.p_facturx_xml_url));
            Object.assign(f, { statut: 'EMISE', pdf_s3_key: body.p_pdf_s3_key, facturx_xml_url: body.p_facturx_xml_url });
            return json({ success: true, delai_verification_heures: 48 });
          }
          case 'fn_preparer_facture_commission_periode': assert.equal(body.p_facture_honoraire_id, ids.facture); return json({ facture_id: ids.commission });
          case 'fn_preparer_avoir_commission_honoraires': assert.equal(body.p_avoir_honoraires_id, ids.avoir); return json({ facture_id: ids.commission });
          default: throw new Error(`Unknown RPC ${name}`);
        }
      }
      if (path === '/functions/v1/send-email' && req.method === 'POST') {
        assert.equal(body.type, 'FACTURE_EMISE'); assert([ids.soignant, ids.etab].includes(body.destinataire_id));
        return json({ success: true, skipped: true, reason: 'fictional IO: no delivery' });
      }
      if (path.startsWith('/rest/v1/')) {
        const table = path.split('/').at(-1), id = url.searchParams.get('id')?.replace(/^eq\./, '');
        if (req.method === 'GET') {
          const data = { missions: mission, soignants: soignant, etablissements: etablissement }[table];
          if (data) { assert.equal(id, data.id); return json(data); }
          if (table === 'factures_honoraires') {
            if (id) { const f = factures.find(f => f.id === id); assert(f); return json(f); }
            assert.equal(url.searchParams.get('mission_id'), `eq.${ids.mission}`);
            return json([]);
          }
        }
        if (req.method === 'POST' && table === 'factures_honoraires') {
          assert.equal(body.mission_id, ids.mission); assert.equal(body.statut, 'EN_GENERATION');
          const f = { ...body, id: ids.facture, type_document: 'FACTURE' }; factures.push(f); return json(f, 201);
        }
        if (req.method === 'POST' && table === 'factures_honoraires_documents') { versions.push(body); return json(null, 201); }
        if (req.method === 'POST' && ['invoice_audit_log', 'journaux_audit'].includes(table)) return json(null, 201);
        if (req.method === 'PATCH' && table === 'factures_honoraires') {
          const f = factures.find(f => f.id === id); assert(f); Object.assign(f, body); return json(null);
        }
      }
      throw new Error(`Unknown IO ${req.method} ${path}${url.search}`);
    } catch (error) { inconnus.push(String(error)); throw error; }
  };
  const handler = chargerHandler(fetchFictif, logs);
  const invoquer = body => handler(new Request(`${origin}/functions/v1/generate-invoice`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${secretFictif}` },
    body: JSON.stringify({ ...body, service_role_reason: 'ops_test_octets_locaux' }),
  }));
  return { documents, factures, versions, appels, inconnus, logs, mission, soignant, etablissement, invoquer,
    async genererFacture() { return invoquer({ mission_id: ids.mission, periode_debut: '2026-09-21', periode_fin: '2026-09-27', numero_semaine_iso: 39, annee_iso: 2026, est_facture_finale_mission: false }); },
    async genererAvoir() {
      assert.equal(factures.length, 1);
      factures.push({ ...factures[0], id: ids.avoir, numero_facture: 'F1-AVOIR-PARTIEL', type_document: 'AVOIR',
        facture_precedente_id: ids.facture, nature_correction: 'AVOIR', statut: 'EN_GENERATION',
        description_prestation_snapshot: pagination ? `Correction fictive de 1 heure. ${mission.intitule}` : 'Correction fictive de 1 heure', quantite_heures_snapshot: 1,
        montant_ht: 20, montant_tva: 0, montant_ttc: 20, pdf_s3_key: null, facturx_xml_url: null });
      return invoquer({ facture_id: ids.avoir });
    },
  };
}

export function verifierXml(bytes, facture, original, vendeur = "Élodie L'Été") {
  const erreurs = [];
  const doc = new DOMParser({ errorHandler: { warning: m => erreurs.push(m), error: m => erreurs.push(m), fatalError: m => erreurs.push(m) } }).parseFromString(bytes.toString('utf8'), 'application/xml');
  assert.deepEqual(erreurs, []);
  const namespaces = { rsm: 'urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100',
    ram: 'urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100',
    udt: 'urn:un:unece:uncefact:data:standard:UnqualifiedDataType:100',
    qdt: 'urn:un:unece:uncefact:data:standard:QualifiedDataType:100' };
  for (const element of Array.from(doc.getElementsByTagName('*'))) assert.equal(element.namespaceURI, namespaces[element.prefix], element.tagName);
  const all = name => Array.from(doc.getElementsByTagNameNS('*', name));
  const one = (parent, name) => { const list = parent.getElementsByTagNameNS('*', name); assert.equal(list.length, 1, name); return list[0].textContent; };
  const exchanged = all('ExchangedDocument')[0]; assert(exchanged);
  assert.equal(doc.documentElement.localName, 'CrossIndustryInvoice');
  assert.equal(doc.documentElement.namespaceURI, 'urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100');
  assert.equal(one(exchanged, 'ID'), facture.numero_facture);
  assert.equal(one(exchanged, 'TypeCode'), original ? '381' : '380');
  assert.equal(one(exchanged, 'DateTimeString'), '20260930');
  assert.equal(all('InvoiceCurrencyCode')[0].textContent, 'EUR');
  assert.equal(one(all('GuidelineSpecifiedDocumentContextParameter')[0], 'ID'), 'urn:cen.eu:en16931:2017#compliant#urn:factur-x.eu:1p0:basic');
  assert.equal(one(all('DueDateDateTime')[0], 'DateTimeString'), '20261030');
  assert.equal(one(all('SpecifiedTradeProduct')[0], 'Name'), facture.description_prestation_snapshot);
  if (!original) assert.match(facture.description_prestation_snapshot, /Periode du 2026-09-21 au 2026-09-27/);
  assert.equal(one(all('SellerTradeParty')[0], 'Name'), vendeur);
  assert.equal(one(all('BuyerTradeParty')[0], 'Name'), 'Clinique fictive F1 & Santé');
  assert.equal(one(all('SellerTradeParty')[0].getElementsByTagNameNS('*', 'SpecifiedLegalOrganization')[0], 'ID'), '111111111');
  assert.equal(one(all('BuyerTradeParty')[0].getElementsByTagNameNS('*', 'SpecifiedLegalOrganization')[0], 'ID'), '222222222');
  assert.equal(all('BilledQuantity')[0].getAttribute('unitCode'), 'HUR');
  const sums = all('SpecifiedTradeSettlementHeaderMonetarySummation')[0]; assert(sums);
  assert.equal(Number(one(sums, 'TaxBasisTotalAmount')), facture.montant_ht);
  assert.equal(Number(one(sums, 'TaxTotalAmount')), facture.montant_tva);
  assert.equal(Number(one(sums, 'GrandTotalAmount')), facture.montant_ttc);
  assert.equal(Number(one(sums, 'DuePayableAmount')), facture.montant_ttc);
  assert.equal(Number(one(all('SpecifiedTradeSettlementLineMonetarySummation')[0], 'LineTotalAmount')), facture.montant_ht);
  assert.equal(Number(all('BilledQuantity')[0].textContent), facture.quantite_heures_snapshot);
  assert.equal(Number(all('NetPriceProductTradePrice')[0].getElementsByTagNameNS('*', 'ChargeAmount')[0].textContent), 20);
  if (original) {
    assert.equal(one(all('InvoiceReferencedDocument')[0], 'IssuerAssignedID'), original.numero_facture);
    assert.equal(one(all('InvoiceReferencedDocument')[0], 'DateTimeString'), original.date_emission.replaceAll('-', ''));
  } else assert.equal(all('InvoiceReferencedDocument').length, 0);
  const mention = all('IncludedNote').map(note => one(note, 'Content')).find(value => value.startsWith('Facture emise par JOLENE SASU'));
  assert(mention);
  return { numero: facture.numero_facture, type: original ? '381' : '380', ht: facture.montant_ht, tva: facture.montant_tva, ttc: facture.montant_ttc, mention };
}

export async function genererDocuments(options = {}) {
  const banc = creerBanc(options);
  for (const generate of [() => banc.genererFacture(), () => banc.genererAvoir()]) {
    const response = await generate(), body = await response.json();
    assert.deepEqual(banc.inconnus, []); assert.equal(response.status, 200, JSON.stringify(body)); assert.equal(body.success, true);
  }
  assert.equal(banc.documents.size, 4); assert.equal(banc.versions.length, 2);
  for (const [index, facture] of banc.factures.entries()) {
    const pdf = banc.documents.get(facture.pdf_s3_key), xml = banc.documents.get(facture.facturx_xml_url);
    assert.equal(pdf.contentType, 'application/pdf'); assert.equal(xml.contentType, 'application/xml');
    assert.equal(pdf.bytes.subarray(0, 5).toString(), '%PDF-');
    assert.equal((await pdfLib.PDFDocument.load(pdf.bytes)).getPageCount(), options.pagination ? 2 : 1);
    assert.equal(banc.versions[index].facture_honoraire_id, facture.id);
    assert.equal(banc.versions[index].pdf_s3_key, facture.pdf_s3_key);
    assert.equal(banc.versions[index].facturx_xml_url, facture.facturx_xml_url);
    assert.equal(banc.versions[index].pdf_sha256, sha256(pdf.bytes));
    assert.equal(banc.versions[index].xml_sha256, sha256(xml.bytes));
    verifierXml(xml.bytes, facture, index ? banc.factures[0] : undefined, `${banc.soignant.prenom} ${banc.soignant.nom}`);
  }
  return banc;
}
