#!/usr/bin/env npx tsx
/**
 * test-generate-invoice.ts — E2E test via admin-invoke
 *
 * Usage:
 *   OPS_TEST_ADMIN_PASSWORD=xxx \
 *   ADMIN_INVOKE_SALT=yyy \
 *   npx tsx scripts/test-generate-invoice.ts [mission_id]
 *
 * Signs in as ops-test@jolene.app, computes X-Admin-Confirm,
 * calls admin-invoke → generate-invoice, downloads PDF + XML.
 */

import { createClient } from '@supabase/supabase-js';
import { writeFileSync, mkdirSync } from 'fs';
import { join } from 'path';
import { createHash } from 'crypto';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL || 'https://flripxtsyegjshnhzjkz.supabase.co';
const ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZscmlweHRzeWVnanNobmh6amt6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMyMTk2OTYsImV4cCI6MjA4ODc5NTY5Nn0.ywor0oGht7aYi8J1YwNRo_rfmJtQ6GBodmCp1kAB3UY';
const OPS_EMAIL = 'ops-test@jolene.app';
const OPS_PASSWORD = process.env.OPS_TEST_ADMIN_PASSWORD || '';
const SALT = process.env.ADMIN_INVOKE_SALT || 'jolene-ops-default-salt-change-me';

const OUTPUT_DIR = '/tmp/jolene-invoice-test';
const FIXTURES_DIR = join(process.cwd(), 'tests', 'fixtures', 'sample-invoice');

function log(step: string, status: 'OK' | 'FAIL' | 'INFO', msg: string) {
  const icon = status === 'OK' ? '✅' : status === 'FAIL' ? '❌' : 'ℹ️';
  console.log(`${icon} [${step}] ${msg}`);
}

function computeAdminConfirm(userId: string, salt: string): string {
  const minute = Math.floor(Date.now() / 60000);
  return createHash('sha256').update(`${userId}:${minute}:${salt}`).digest('hex');
}

async function main() {
  mkdirSync(OUTPUT_DIR, { recursive: true });
  mkdirSync(FIXTURES_DIR, { recursive: true });

  console.log('═══════════════════════════════════════');
  console.log('  E2E Test: generate-invoice via admin-invoke');
  console.log('═══════════════════════════════════════\n');

  if (!OPS_PASSWORD) {
    log('PREREQ', 'FAIL', 'OPS_TEST_ADMIN_PASSWORD env var required');
    process.exit(1);
  }

  const missionId = process.argv[2];
  if (!missionId) {
    log('PREREQ', 'FAIL', 'Usage: npx tsx scripts/test-generate-invoice.ts <mission_id>');
    process.exit(1);
  }

  // ── Step 1: Sign in as ops-test admin ──
  log('AUTH', 'INFO', `Signing in as ${OPS_EMAIL}...`);
  const supabase = createClient(SUPABASE_URL, ANON_KEY);
  const { data: authData, error: authErr } = await supabase.auth.signInWithPassword({
    email: OPS_EMAIL,
    password: OPS_PASSWORD,
  });

  if (authErr || !authData.session) {
    log('AUTH', 'FAIL', `Sign-in failed: ${authErr?.message || 'no session'}`);
    process.exit(1);
  }

  const accessToken = authData.session.access_token;
  const userId = authData.user.id;
  log('AUTH', 'OK', `JWT obtained for ${userId}`);

  // ── Step 2: Compute X-Admin-Confirm ──
  const adminConfirm = computeAdminConfirm(userId, SALT);
  log('AUTH', 'OK', `X-Admin-Confirm computed (minute ${Math.floor(Date.now() / 60000)})`);

  // ── Step 3: Call admin-invoke ──
  log('INVOKE', 'INFO', `POST /functions/v1/admin-invoke → generate-invoice`);
  const startMs = Date.now();

  const invokeRes = await fetch(`${SUPABASE_URL}/functions/v1/admin-invoke`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
      'X-Admin-Confirm': adminConfirm,
    },
    body: JSON.stringify({
      target_function: 'generate-invoice',
      target_payload: { mission_id: missionId },
      reason: 'ops_test_pr2_validation_v5_pdf',
    }),
  });

  const elapsed = Date.now() - startMs;
  const invokeBody = await invokeRes.text();
  let invokeResult: any;
  try { invokeResult = JSON.parse(invokeBody); } catch { invokeResult = { raw: invokeBody }; }

  log('INVOKE', invokeRes.ok ? 'OK' : 'FAIL', `Status ${invokeRes.status} (${elapsed}ms)`);

  if (!invokeRes.ok) {
    log('INVOKE', 'FAIL', `Response: ${invokeBody.substring(0, 500)}`);
    process.exit(1);
  }

  const invocationId = invokeResult.invocation_id;
  const requestId = invokeResult.request_id;
  log('INVOKE', 'INFO', `Invocation ID: ${invocationId}`);
  log('INVOKE', 'INFO', `Request ID: ${requestId}`);

  // The response from admin-invoke contains the generate-invoice result
  const genResult = invokeResult.response;
  if (!genResult?.success) {
    log('INVOKE', 'FAIL', `generate-invoice failed: ${JSON.stringify(genResult)}`);
    process.exit(1);
  }

  log('INVOICE', 'OK', `Facture: ${genResult.numero_facture} (${genResult.facture_id})`);

  // ── Step 4: Verify DB records ──
  const serviceClient = createClient(SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY || ANON_KEY);

  // admin_invocations
  if (process.env.SUPABASE_SERVICE_ROLE_KEY) {
    const { data: invRow } = await serviceClient
      .from('admin_invocations')
      .select('*')
      .eq('id', invocationId)
      .single();

    if (invRow) {
      log('AUDIT', invRow.internal_status === 'COMPLETED' ? 'OK' : 'FAIL',
        `internal_status = ${invRow.internal_status}`);
      log('AUDIT', 'INFO', `request_id = ${invRow.request_id}`);
      log('AUDIT', 'INFO', `reason = ${invRow.reason}`);
    }

    // factures_honoraires
    const { data: fh } = await serviceClient
      .from('factures_honoraires')
      .select('id, numero_facture, template_version, statut, montant_ht, montant_ttc, mandat_version, pdf_s3_key, facturx_xml_url')
      .eq('id', genResult.facture_id)
      .single();

    if (fh) {
      log('DB', fh.template_version === 'v2_facturx' ? 'OK' : 'FAIL', `template_version = ${fh.template_version}`);
      log('DB', 'OK', `statut = ${fh.statut}`);
      log('DB', 'OK', `montant_ht = ${fh.montant_ht}, montant_ttc = ${fh.montant_ttc}`);
      log('DB', 'OK', `mandat_version = ${fh.mandat_version}`);
      log('DB', 'OK', `pdf_s3_key = ${fh.pdf_s3_key}`);
      log('DB', 'OK', `facturx_xml_url = ${fh.facturx_xml_url}`);

      // invoice_audit_log with chain reason
      const { data: auditLogs } = await serviceClient
        .from('invoice_audit_log')
        .select('action, payload_before')
        .eq('invoice_id', genResult.facture_id)
        .eq('action', 'GENERATED_VIA_SERVICE_ROLE');

      if (auditLogs && auditLogs.length > 0) {
        const reason = (auditLogs[0].payload_before as any)?.reason || '';
        log('AUDIT', reason.startsWith('admin_invoke_') ? 'OK' : 'FAIL',
          `invoice_audit reason = ${reason}`);
      }

      // Download PDF
      if (fh.pdf_s3_key) {
        log('STORAGE', 'INFO', 'Downloading PDF...');
        const { data: pdfBlob } = await serviceClient.storage.from('jolene-documents').download(fh.pdf_s3_key);
        if (pdfBlob) {
          const pdfBytes = new Uint8Array(await pdfBlob.arrayBuffer());
          const isPdf = pdfBytes[0] === 0x25 && pdfBytes[1] === 0x50 && pdfBytes[2] === 0x44 && pdfBytes[3] === 0x46; // %PDF
          log('STORAGE', isPdf ? 'OK' : 'FAIL', `PDF binary: ${pdfBytes.length} bytes, starts with %PDF: ${isPdf}`);

          writeFileSync(join(OUTPUT_DIR, `${genResult.numero_facture}.pdf`), pdfBytes);
          writeFileSync(join(FIXTURES_DIR, `${genResult.numero_facture}.pdf`), pdfBytes);
          log('STORAGE', 'OK', `Saved to ${OUTPUT_DIR} and fixtures/`);
        }

        const { data: pdfUrl } = await serviceClient.storage.from('jolene-documents').createSignedUrl(fh.pdf_s3_key, 86400);
        if (pdfUrl?.signedUrl) log('STORAGE', 'OK', `PDF signed URL: ${pdfUrl.signedUrl}`);
      }

      // Download XML
      if (fh.facturx_xml_url) {
        log('STORAGE', 'INFO', 'Downloading XML...');
        const { data: xmlBlob } = await serviceClient.storage.from('jolene-documents').download(fh.facturx_xml_url);
        if (xmlBlob) {
          const xmlText = await xmlBlob.text();
          log('STORAGE', 'OK', `XML CII: ${xmlText.length} chars`);
          log('XML', xmlText.includes('CrossIndustryInvoice') ? 'OK' : 'FAIL', 'namespace CII');
          log('XML', xmlText.includes('urn:cen.eu:en16931') ? 'OK' : 'FAIL', 'EN16931 profile');
          log('XML', xmlText.includes('<ram:TypeCode>380</ram:TypeCode>') ? 'OK' : 'FAIL', 'TypeCode 380');

          writeFileSync(join(OUTPUT_DIR, `${genResult.numero_facture}.xml`), xmlText);
          writeFileSync(join(FIXTURES_DIR, `${genResult.numero_facture}.xml`), xmlText);
        }

        const { data: xmlUrl } = await serviceClient.storage.from('jolene-documents').createSignedUrl(fh.facturx_xml_url, 86400);
        if (xmlUrl?.signedUrl) log('STORAGE', 'OK', `XML signed URL: ${xmlUrl.signedUrl}`);
      }
    }
  } else {
    log('DB', 'INFO', 'SUPABASE_SERVICE_ROLE_KEY not set — skipping DB verification (PDF/XML not downloadable)');
  }

  // Write fixtures README
  writeFileSync(join(FIXTURES_DIR, 'README.md'), `# Sample Invoice Fixture

Generated by \`scripts/test-generate-invoice.ts\` via admin-invoke.

- **Date**: ${new Date().toISOString()}
- **Mission**: ${missionId}
- **Facture**: ${genResult.numero_facture}
- **Template**: v2_facturx (pdf-lib + XML CII EN16931)
- **Admin**: ops-test@jolene.app
- **Invocation ID**: ${invocationId}
- **Request ID**: ${requestId}

## How to regenerate

\`\`\`bash
OPS_TEST_ADMIN_PASSWORD=<from Supabase Secrets> \\
ADMIN_INVOKE_SALT=<from Supabase Secrets> \\
SUPABASE_SERVICE_ROLE_KEY=<from Supabase dashboard> \\
npx tsx scripts/test-generate-invoice.ts <mission_id>
\`\`\`

Note: The mission must be TERMINEE with no existing non-ANNULEE invoice.
`);

  console.log(`\n═══════════════════════════════════════`);
  console.log(`  DONE — artifacts in ${OUTPUT_DIR} and tests/fixtures/sample-invoice/`);
  console.log(`═══════════════════════════════════════`);
}

main().catch(err => {
  console.error('Fatal:', err);
  process.exit(1);
});
