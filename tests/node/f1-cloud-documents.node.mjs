import test from 'node:test';
import assert from 'node:assert/strict';
import { genererDocuments } from '../helpers/facturation-documents-harness.mjs';
import { validateDocumentSet, documentTransportF1, analyzeXmlF1 } from '../../scripts/ci/f1-cloud-documents.mjs';
import { documentContractF1 } from '../../scripts/ci/f1-cloud-document-contract.mjs';
import { ORIGIN, sha256 } from '../../scripts/ci/f1-cloud-core.mjs';

const canary = 'canary-password-jwt-email@example.invalid';
let prepared;
async function fixture() {
  if (!prepared) prepared = genererDocuments({ remplacement: true, unicode: true }).then(banc => {
    const documents = banc.factures.map((f, i) => ({ id: f.id, slot: i ? 'replacement' : 'original', kind: 'FACTURE',
      number: f.numero_facture, emittedOn: f.date_emission, dueOn: f.date_echeance,
      quantity: 4, rate: i ? 18 : 20, net: i ? 72 : 80, vat: 0, total: i ? 72 : 80,
      ...Object.fromEntries(['pdf', 'xml'].map(format => {
        const key = format === 'pdf' ? f.pdf_s3_key : f.facturx_xml_url, bytes = banc.documents.get(key).bytes;
        return [format, { key, size: bytes.length, sha256: sha256(bytes) }];
      })) }));
    return { banc, documents, soignantId: banc.soignant.id,
      parties: { seller: `${banc.soignant.prenom} ${banc.soignant.nom}`, buyer: banc.etablissement.nom,
        sellerSiren: '111111111', buyerSiren: '222222222', original: documents[0] } };
  });
  return prepared;
}

test('actual handler produces independently named keys, 80/72 XML380 with exact escaped predecessor and Unicode', async () => {
  const { banc, documents, soignantId, parties } = await fixture();
  validateDocumentSet(documents, soignantId);
  for (const d of documents) {
    const result = analyzeXmlF1(banc.documents.get(d.xml.key).bytes, d, parties);
    assert.equal(result.type, '380'); assert.equal(result.total, d.slot === 'original' ? 80 : 72);
    assert.equal(result.previous_number_and_date, d.slot === 'replacement');
    assert(!JSON.stringify(result).includes(parties.seller));
  }
});

test('XML wrong amount/type/party/date/reference, duplicate cardinality, namespace and entities all reject even with valid byte hash', async () => {
  const { banc, documents, parties } = await fixture(), d = documents[1];
  const xml = banc.documents.get(d.xml.key).bytes.toString('utf8');
  const mutations = [
    x => x.replace('<ram:TypeCode>380</ram:TypeCode>', '<ram:TypeCode>381</ram:TypeCode>'),
    x => x.replace('<ram:GrandTotalAmount>72.00</ram:GrandTotalAmount>', '<ram:GrandTotalAmount>80.00</ram:GrandTotalAmount>'),
    x => x.replace('<ram:BilledQuantity unitCode="HUR">4.00', '<ram:BilledQuantity unitCode="HUR">3.00'),
    x => x.replace('111111111</ram:ID>', '999999999</ram:ID>'),
    x => x.replace('<ram:IssuerAssignedID>F1-HONORAIRE-SEMAINE</ram:IssuerAssignedID>', `<ram:IssuerAssignedID>${canary}</ram:IssuerAssignedID>`),
    x => x.replace(/<ram:InvoiceReferencedDocument>[\s\S]*?<\/ram:InvoiceReferencedDocument>/, ''),
    x => x.replace('<ram:InvoiceCurrencyCode>EUR</ram:InvoiceCurrencyCode>', '<ram:InvoiceCurrencyCode>EUR</ram:InvoiceCurrencyCode>'.repeat(2)),
    x => x.replace('ReusableAggregateBusinessInformationEntity:100', 'ForeignEntity:100'),
    x => x.replace('?>', `?><!DOCTYPE x [<!ENTITY secret SYSTEM "https://${canary}/">]>`),
  ];
  for (const mutate of mutations) {
    const bytes = Buffer.from(mutate(xml)); assert.notDeepEqual(bytes, Buffer.from(xml));
    assert.throws(() => analyzeXmlF1(bytes, { ...d, xml: { ...d.xml, size: bytes.length, sha256: sha256(bytes) } }, parties),
      e => e.message === 'F1_XML_ANALYSIS_FAILED');
  }
});

test('metadata excludes foreign owner, arbitrary path, unbounded size and duplicate document', async () => {
  const { documents, soignantId } = await fixture();
  for (const mutate of [d => { d[1].id = d[0].id; }, d => { d[1].rate = 20; },
    d => { d[0].pdf.key = `https://${canary}/file.pdf`; }, d => { d[0].xml.key = d[0].xml.key.replace(soignantId, '22222222-2222-4222-8222-222222222222'); },
    d => { d[0].pdf.size = 30 * 1024 * 1024; }, d => { d[1].emittedOn = '2026-02-30'; }]) {
    const changed = structuredClone(documents); mutate(changed);
    assert.throws(() => validateDocumentSet(changed, soignantId), /^Error: F1_DOCUMENT_/);
  }
});

test('real transport reads exactly 8 authenticated objects, no service key/redirect/retry; projection contains only hashes/timing', async () => {
  const { banc, documents, soignantId } = await fixture(); let calls = 0;
  const transport = documentTransportF1({ documents, soignantId, anonKey: 'public-key', fetcher: async (url, options) => {
    calls++; assert(url.startsWith(`${ORIGIN}/storage/v1/object/authenticated/jolene-documents/invoices/${soignantId}/`));
    assert.equal(options.method, 'GET'); assert.equal(options.redirect, 'error'); assert.equal(options.headers.apikey, 'public-key');
    assert.equal(options.headers.Authorization, `Bearer ${canary}`);
    const key = decodeURIComponent(url.slice(`${ORIGIN}/storage/v1/object/authenticated/jolene-documents/`.length));
    const file = banc.documents.get(key); assert(file);
    return new Response(file.bytes, { status: 200, headers: { 'Content-Type': file.contentType, 'Content-Length': String(file.bytes.length) } });
  } });
  for (const role of ['SOIGNANT', 'ETABLISSEMENT']) for (const slot of ['original', 'replacement']) for (const format of ['pdf', 'xml']) {
    await transport.download({ role, slot, format, token: canary });
  }
  assert.equal(calls, 8); assert(transport.complete());
  await assert.rejects(transport.download({ role: 'SOIGNANT', slot: 'original', format: 'pdf', token: canary }), /ALREADY_ATTEMPTED/);
  assert.equal(calls, 8);
  const output = JSON.stringify(transport.projection());
  for (const secret of [canary, soignantId, documents[0].number, ORIGIN]) assert(!output.includes(secret));
});

for (const failure of ['redirect', 'http', 'mime', 'truncated', 'corrupt', 'timeout']) test(`transport ${failure} is terminal without exposing a body`, async () => {
  const { banc, documents, soignantId } = await fixture(); let calls = 0;
  const transport = documentTransportF1({ documents, soignantId, anonKey: 'public-key', fetcher: async () => {
    calls++;
    if (failure === 'timeout') throw Error(canary);
    const bytes = banc.documents.get(documents[0].pdf.key).bytes;
    const response = new Response(failure === 'corrupt' ? Buffer.alloc(bytes.length) : failure === 'truncated' ? bytes.subarray(0, -1) : bytes,
      { status: failure === 'http' ? 503 : 200, headers: { 'content-type': failure === 'mime' ? 'text/html' : 'application/pdf' } });
    if (failure === 'redirect') Object.defineProperty(response, 'redirected', { value: true });
    return response;
  } });
  const request = { role: 'SOIGNANT', slot: 'original', format: 'pdf', token: canary };
  await assert.rejects(transport.download(request), e => e.message === 'F1_DOCUMENT_READ_FAILED');
  await assert.rejects(transport.download(request), /ALREADY_ATTEMPTED/); assert.equal(calls, 1); assert.deepEqual(transport.projection(), []);
});

test('UI signing contract only accepts the exact response-bound URL, refuses tokens/IDs from elsewhere and third download', async () => {
  const { documents, soignantId, banc } = await fixture();
  const contract = documentContractF1({ documents, soignantId, missionId: banc.mission.id });
  const key = documents[0].pdf.key, url = `${ORIGIN}/storage/v1/object/sign/jolene-documents/${key}`;
  assert.equal(contract.authorize({ url: `${url}?token=${canary}`, method: 'GET' }), false);
  for (const invalid of [`${url}?token=x&extra=y`, url.replace(ORIGIN, 'https://foreign.invalid'), `${url}?token=x#secret`, `${url}?token=x&token=y`]) {
    assert.throws(() => contract.registerSignedPdf(key, invalid), /SIGNED_URL_REFUSED/);
  }
  for (const i of [1, 2]) {
    assert(contract.authorize({ url, method: 'POST', body: { expiresIn: 300 } }));
    contract.registerSignedPdf(key, `${url}?token=${canary}${i}`);
    assert(contract.authorize({ url: `${url}?token=${canary}${i}`, method: 'GET' }));
  }
  assert.equal(contract.authorize({ url, method: 'POST', body: { expiresIn: 300 } }), false);
  assert.equal(contract.authorize({ url: `${url}?token=${canary}2`, method: 'GET' }), false);
  assert(!JSON.stringify(contract.projection()).includes(canary));
});
