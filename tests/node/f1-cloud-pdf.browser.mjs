import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { genererDocuments } from '../helpers/facturation-documents-harness.mjs';
import { createPdfAnalyzerF1 } from '../../scripts/ci/f1-cloud-documents.mjs';
import { sha256 } from '../../scripts/ci/f1-cloud-core.mjs';
const require = createRequire(import.meta.url);

test('real PDF.js browser render and Unicode/predecessor checks on actual handler bytes; corrupt and wrong-reference documents reject', async () => {
  const { chromium } = require('@playwright/test');
  const browser = await chromium.launch({
    ...(process.env.F1_CHROMIUM_EXECUTABLE_PATH ? { executablePath: process.env.F1_CHROMIUM_EXECUTABLE_PATH } : {}),
    env: Object.fromEntries(['PATH', 'HOME', 'TMPDIR'].filter(k => process.env[k]).map(k => [k, process.env[k]])),
  });
  let analyzer;
  try {
    analyzer = await createPdfAnalyzerF1(browser);
    const banc = await genererDocuments({ remplacement: true, unicode: true });
    const documents = banc.factures.map((f, index) => {
      const bytes = banc.documents.get(f.pdf_s3_key).bytes;
      return { slot: index ? 'replacement' : 'original', number: f.numero_facture, emittedOn: f.date_emission,
        net: index ? 72 : 80, total: index ? 72 : 80, vat: 0, quantity: 4, rate: index ? 18 : 20,
        pdf: { size: bytes.length, sha256: sha256(bytes) } };
    });
    const parties = { seller: `${banc.soignant.prenom} ${banc.soignant.nom}`, buyer: banc.etablissement.nom, original: documents[0] };
    for (const [index, d] of documents.entries()) {
      const bytes = banc.documents.get(banc.factures[index].pdf_s3_key).bytes;
      const result = await analyzer.analyze(bytes, d, parties);
      assert.equal(result.pages, 1); assert.equal(result.overflow_count, 0);
      assert.equal(result.previous_number_and_date, !!index);
      await assert.rejects(analyzer.analyze(bytes, { ...d, total: 999 }, parties), /^Error: F1_PDF_ANALYSIS_FAILED$/);
    }
    const bytes = banc.documents.get(banc.factures[1].pdf_s3_key).bytes;
    await assert.rejects(analyzer.analyze(bytes, documents[1], { ...parties, original: { ...documents[0], number: 'wrong-predecessor' } }), /F1_PDF_ANALYSIS_FAILED/);
    // Hash/size still match the intentionally corrupt input: actual parser must fail.
    const corrupt = Buffer.from('%PDF-not-a-document');
    await assert.rejects(analyzer.analyze(corrupt, { ...documents[1], pdf: { size: corrupt.length, sha256: sha256(corrupt) } }, parties), /F1_PDF_ANALYSIS_FAILED/);
  } finally { if (analyzer) await analyzer.close(); await browser.close(); }
});
