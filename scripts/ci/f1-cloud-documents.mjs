import { createRequire } from 'node:module';
import { readFile } from 'node:fs/promises';
import { performance } from 'node:perf_hooks';
import { ORIGIN, documentBytes, refuse, sha256 } from './f1-cloud-core.mjs';

const require = createRequire(import.meta.url);
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const HEX = /^[0-9a-f]{64}$/;
const NS = Object.freeze({ rsm: 'urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100',
  ram: 'urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100',
  udt: 'urn:un:unece:uncefact:data:standard:UnqualifiedDataType:100',
  qdt: 'urn:un:unece:uncefact:data:standard:QualifiedDataType:100' });
const check = (condition, code) => { if (!condition) refuse(code); };
const day = value => typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value)
  && Number.isFinite(Date.parse(`${value}T00:00:00Z`)) && new Date(`${value}T00:00:00Z`).toISOString().slice(0, 10) === value;

/** Only a reconciled immutable version may define a download destination. */
export function validateDocumentSet(documents, soignantId) {
  check(UUID.test(soignantId ?? '') && Array.isArray(documents) && documents.length === 2, 'F1_DOCUMENT_SET');
  const ids = new Set(), keys = new Set(), numbers = new Set();
  for (const [index, d] of documents.entries()) {
    check(d?.slot === (index ? 'replacement' : 'original') && d.kind === 'FACTURE'
      && UUID.test(d.id ?? '') && !ids.has(d.id) && typeof d.number === 'string'
      && /^[A-Za-z0-9_-]{1,120}$/.test(d.number) && !numbers.has(d.number)
      && day(d.emittedOn) && day(d.dueOn) && d.quantity === 4 && d.rate === (index ? 18 : 20)
      && d.net === (index ? 72 : 80) && d.vat === 0 && d.total === d.net, 'F1_DOCUMENT_SET');
    ids.add(d.id); numbers.add(d.number);
    for (const format of ['pdf', 'xml']) {
      const item = d[format], parts = item?.key?.split('/') ?? [];
      check(parts.length === 4 && parts[0] === 'invoices' && parts[1] === soignantId
        && parts[2] === d.number && parts[3].endsWith(`.${format}`)
        && UUID.test(parts[3].slice(0, -format.length - 1)) && !keys.has(item.key)
        && HEX.test(item.sha256 ?? '') && Number.isSafeInteger(item.size) && item.size > 0
        && item.size <= 25 * 1024 * 1024, 'F1_DOCUMENT_STORAGE_KEY');
      keys.add(item.key);
    }
    // The generator draws two independent UUIDs. Their common immutable version
    // row, checked by SQL reconciliation, binds these keys; basenames differ.
  }
  return documents;
}

/** Direct, authenticated Storage reads for XML and independent byte reconciliation.
 * No signed URL, provider redirect, retry, service-role fallback or arbitrary path.
 * UI downloads remain separate real button actions. Tokens stay in memory only. */
export function documentTransportF1({ documents, soignantId, anonKey, fetcher = fetch }) {
  validateDocumentSet(documents, soignantId);
  check(typeof anonKey === 'string' && anonKey.length > 0, 'F1_AUTH_REQUIRED');
  const attempted = new Set(), observations = [];
  return {
    async download({ role, token, slot, format }) {
      check(['SOIGNANT', 'ETABLISSEMENT'].includes(role) && typeof token === 'string' && token.length > 0
        && ['original', 'replacement'].includes(slot) && ['pdf', 'xml'].includes(format), 'F1_DOCUMENT_READ_REFUSED');
      const attempt = `${role}/${slot}/${format}`;
      check(!attempted.has(attempt), 'F1_DOCUMENT_READ_ALREADY_ATTEMPTED'); attempted.add(attempt);
      const d = documents.find(x => x.slot === slot), expected = d[format];
      const url = `${ORIGIN}/storage/v1/object/authenticated/jolene-documents/${expected.key.split('/').map(encodeURIComponent).join('/')}`;
      const start = performance.now();
      try {
        const response = await fetcher(url, { method: 'GET', redirect: 'error', signal: AbortSignal.timeout(30000),
          headers: { apikey: anonKey, Authorization: `Bearer ${token}`, Accept: format === 'pdf' ? 'application/pdf' : 'application/xml' } });
        check(response.status === 200 && !response.redirected, 'F1_DOCUMENT_HTTP');
        const mime = response.headers.get('content-type')?.split(';')[0].trim().toLowerCase();
        check(mime === (format === 'pdf' ? 'application/pdf' : 'application/xml'), 'F1_DOCUMENT_CONTENT_TYPE');
        const length = response.headers.get('content-length');
        check(length === null || (/^[0-9]+$/.test(length) && Number(length) === expected.size), 'F1_DOCUMENT_LENGTH');
        check(response.body !== null, 'F1_DOCUMENT_BODY');
        const chunks = []; let size = 0;
        for await (const chunk of response.body) {
          size += chunk.length; check(size <= expected.size, 'F1_DOCUMENT_LENGTH'); chunks.push(Buffer.from(chunk));
        }
        const bytes = Buffer.concat(chunks), verified = documentBytes(bytes, { ...expected, format });
        observations.push({ role, slot, ...verified, duration_ms: Math.max(0, Math.round(performance.now() - start)) });
        return bytes;
      } catch { refuse('F1_DOCUMENT_READ_FAILED'); }
    },
    projection() { return observations.map(x => ({ ...x })); },
    complete() { return observations.length === 8; },
  };
}

/** CII structure/content checks, not an XSD or Schematron compliance assertion. */
export function analyzeXmlF1(bytes, d, { seller, buyer, sellerSiren, buyerSiren, original } = {}) {
  try {
    documentBytes(bytes, { ...d.xml, format: 'xml' });
    const xml = new TextDecoder('utf-8', { fatal: true }).decode(bytes);
    check(!/<!\s*(?:DOCTYPE|ENTITY)/i.test(xml), 'F1_XML_ENTITY');
    const { DOMParser } = require('@xmldom/xmldom'); let parseErrors = 0;
    const document = new DOMParser({ errorHandler: { warning() { parseErrors++; }, error() { parseErrors++; }, fatalError() { parseErrors++; } } }).parseFromString(xml, 'application/xml');
    check(parseErrors === 0 && document.documentElement?.localName === 'CrossIndustryInvoice'
      && document.documentElement.namespaceURI === NS.rsm, 'F1_XML_STRUCTURE');
    for (const e of Array.from(document.getElementsByTagName('*'))) check(e.namespaceURI === NS[e.prefix], 'F1_XML_NAMESPACE');
    const all = (name, parent = document) => Array.from(parent.getElementsByTagNameNS('*', name));
    const element = (name, parent = document) => { const found = all(name, parent); check(found.length === 1, 'F1_XML_CARDINALITY'); return found[0]; };
    const text = (name, parent = document) => element(name, parent).textContent;
    const eq = (actual, expected) => check(typeof expected === 'string' && actual === expected, 'F1_XML_VALUE');
    const money = (name, parent, expected) => { const value = text(name, parent); check(/^\d+\.\d{2}$/.test(value) && Number(value) === expected, 'F1_XML_AMOUNT'); };
    const exchanged = element('ExchangedDocument');
    eq(text('ID', exchanged), d.number); eq(text('TypeCode', exchanged), '380');
    eq(text('DateTimeString', exchanged), d.emittedOn.replaceAll('-', ''));
    eq(text('DateTimeString', element('DueDateDateTime')), d.dueOn.replaceAll('-', ''));
    eq(text('InvoiceCurrencyCode'), 'EUR');
    eq(text('ID', element('GuidelineSpecifiedDocumentContextParameter')), 'urn:cen.eu:en16931:2017#compliant#urn:factur-x.eu:1p0:basic');
    for (const [name, expectedName, siren] of [['SellerTradeParty', seller, sellerSiren], ['BuyerTradeParty', buyer, buyerSiren]]) {
      check(/^\d{9}$/.test(siren ?? ''), 'F1_XML_PARTY');
      const party = element(name); eq(text('Name', party), expectedName);
      eq(text('ID', element('SpecifiedLegalOrganization', party)), siren);
    }
    const quantity = element('BilledQuantity'); eq(quantity.getAttribute('unitCode'), 'HUR');
    check(/^\d+(?:\.\d+)?$/.test(quantity.textContent) && Number(quantity.textContent) === d.quantity, 'F1_XML_QUANTITY');
    money('ChargeAmount', element('NetPriceProductTradePrice'), d.rate);
    const sums = element('SpecifiedTradeSettlementHeaderMonetarySummation');
    for (const [name, value] of [['TaxBasisTotalAmount', d.net], ['TaxTotalAmount', d.vat], ['GrandTotalAmount', d.total], ['DuePayableAmount', d.total]]) money(name, sums, value);
    money('LineTotalAmount', element('SpecifiedTradeSettlementLineMonetarySummation'), d.net);
    const references = all('InvoiceReferencedDocument');
    if (d.slot === 'replacement') {
      check(original && references.length === 1, 'F1_XML_PREDECESSOR');
      eq(text('IssuerAssignedID', references[0]), original.number);
      eq(text('DateTimeString', references[0]), original.emittedOn.replaceAll('-', ''));
    } else check(references.length === 0, 'F1_XML_PREDECESSOR');
    return { slot: d.slot, type: '380', quantity: d.quantity, rate: d.rate, net: d.net, vat: d.vat,
      total: d.total, previous_number_and_date: d.slot === 'replacement', xml_sha256: sha256(bytes) };
  } catch { refuse('F1_XML_ANALYSIS_FAILED'); }
}

/** PDF.js runs in an isolated analysis page. Only these two pinned local library
 * files and inert HTML are fulfilled; no Auth/REST/Storage/Edge is mocked here. */
export async function createPdfAnalyzerF1(browser) {
  const context = await browser.newContext({ viewport: { width: 800, height: 1000 }, serviceWorkers: 'block' });
  const origin = 'http://127.0.0.1:8905'; let errors = 0;
  try {
    const modules = new Map(await Promise.all(['pdf.mjs', 'pdf.worker.mjs'].map(async name =>
      [name, await readFile(require.resolve(`pdfjs-dist/legacy/build/${name}`))])));
    await context.routeWebSocket('**/*', socket => { errors++; return socket.close(); });
    await context.route('**/*', route => {
      const req = route.request(), u = new URL(req.url());
      if (req.method() === 'GET' && u.origin === origin && !u.search && !u.hash) {
        if (u.pathname === '/analyse') return route.fulfill({ contentType: 'text/html', body: '<!doctype html><title>Analyse synthétique F1</title>' });
        const body = modules.get(u.pathname.slice(1));
        if (body) return route.fulfill({ contentType: 'text/javascript', body });
      }
      errors++; return route.abort();
    });
    const page = await context.newPage();
    page.on('pageerror', () => errors++); page.on('console', m => { if (m.type() === 'error') errors++; });
    await page.goto(`${origin}/analyse`);
    return {
      async analyze(bytes, d, { seller, buyer, original }) {
        try {
          documentBytes(bytes, { ...d.pdf, format: 'pdf' });
          const result = await page.evaluate(async input => {
            const pdfjs = await import('/pdf.mjs'); pdfjs.GlobalWorkerOptions.workerSrc = '/pdf.worker.mjs';
            const task = pdfjs.getDocument({ data: new Uint8Array(input), isEvalSupported: false, useSystemFonts: true });
            try {
              const doc = await task.promise, pages = []; let overflows = 0;
              if (doc.numPages < 1 || doc.numPages > 8) throw Error('PDF_PAGE_COUNT');
              for (let i = 1; i <= doc.numPages; i++) {
                const p = await doc.getPage(i), content = await p.getTextContent(), viewport = p.getViewport({ scale: 1 });
                pages.push(content.items.map(x => x.str || '').join(' '));
                for (const x of content.items) if (x.str?.trim() && (x.transform[4] < 0 || x.transform[5] < 0
                  || x.transform[4] + x.width > viewport.width + .5 || x.transform[5] + x.height > viewport.height + .5)) overflows++;
                const canvas = document.createElement('canvas'); canvas.width = viewport.width; canvas.height = viewport.height;
                await p.render({ canvasContext: canvas.getContext('2d'), viewport }).promise;
              }
              return { pages, count: doc.numPages, overflows };
            } finally { await task.destroy(); }
          }, [...bytes]);
          const text = result.pages.join(' ').replace(/\s+/g, ' ');
          check(errors === 0 && result.overflows === 0 && [seller, buyer, d.number].every(x => typeof x === 'string' && x.length && text.includes(x)), 'F1_PDF_CONTENT');
          check(text.includes(`TOTAL ${d.net.toFixed(2)} EUR ${d.vat.toFixed(2)} EUR ${d.total.toFixed(2)} EUR`)
            && text.includes(`Quantite : ${d.quantity.toFixed(2)} h · Prix unitaire HT : ${d.rate.toFixed(2)} EUR/h`), 'F1_PDF_AMOUNT');
          if (d.slot === 'replacement') check(original && text.includes(`Facture rectificative remplaçant la facture n° ${original.number} du ${original.emittedOn}`), 'F1_PDF_PREDECESSOR');
          return { slot: d.slot, pages: result.count, overflow_count: 0, previous_number_and_date: d.slot === 'replacement', pdf_sha256: sha256(bytes) };
        } catch { refuse('F1_PDF_ANALYSIS_FAILED'); }
      },
      async close() { await context.close(); check(errors === 0, 'F1_PDF_BROWSER_ERROR'); },
    };
  } catch { await context.close(); refuse('F1_PDF_ANALYZER_SETUP'); }
}
