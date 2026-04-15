#!/usr/bin/env npx tsx
/**
 * test-generate-invoice.ts — Invoque la VRAIE edge function generate-invoice
 *
 * Usage :
 *   SUPABASE_URL=https://flripxtsyegjshnhzjkz.supabase.co \
 *   SUPABASE_SERVICE_ROLE_KEY=xxx \
 *   npx tsx scripts/test-generate-invoice.ts [mission_id]
 *
 * Utilise le bypass service_role avec reason="ops_test_pr2_validation".
 * Sans mission_id : auto-sélectionne une mission TERMINEE éligible.
 *
 * Artefacts dans /tmp/jolene-invoice-test/ :
 *   facture.txt  — PDF text
 *   facture.xml  — XML CII Factur-X
 *   report.json  — Résumé des mentions
 */

import { createClient } from '@supabase/supabase-js';
import { writeFileSync, mkdirSync } from 'fs';
import { join } from 'path';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL || 'https://flripxtsyegjshnhzjkz.supabase.co';
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || '';

if (!SERVICE_ROLE_KEY) {
  console.error('❌ SUPABASE_SERVICE_ROLE_KEY required');
  process.exit(1);
}

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
const OUTPUT_DIR = '/tmp/jolene-invoice-test';

function log(step: string, status: 'OK' | 'FAIL' | 'INFO', message: string) {
  const icon = status === 'OK' ? '✅' : status === 'FAIL' ? '❌' : 'ℹ️';
  console.log(`${icon} [${step}] ${message}`);
}

async function main() {
  mkdirSync(OUTPUT_DIR, { recursive: true });

  console.log('═══════════════════════════════════════');
  console.log('  P1bis — Test generate-invoice (REAL)');
  console.log('═══════════════════════════════════════\n');

  // 1. Find eligible mission
  const inputMissionId = process.argv[2];
  let missionId: string;

  if (inputMissionId) {
    missionId = inputMissionId;
    log('MISSION', 'INFO', `Using provided: ${missionId}`);
  } else {
    const { data: missions } = await supabase
      .from('missions')
      .select('id, intitule, soignant_assigne_id')
      .eq('statut', 'TERMINEE')
      .limit(20);

    let found = false;
    for (const m of (missions || [])) {
      const { data: sg } = await supabase
        .from('soignants')
        .select('mandat_facturation_signe')
        .eq('id', m.soignant_assigne_id)
        .single();
      if (!sg?.mandat_facturation_signe) continue;

      const { data: existing } = await supabase
        .from('factures_honoraires')
        .select('id')
        .eq('mission_id', m.id)
        .not('statut', 'eq', 'ANNULEE')
        .maybeSingle();
      if (existing) continue;

      missionId = m.id;
      log('MISSION', 'OK', `Auto-selected: ${m.intitule} (${m.id})`);
      found = true;
      break;
    }
    if (!found) {
      log('MISSION', 'FAIL', 'No eligible mission (TERMINEE + mandate + no invoice)');
      process.exit(1);
    }
  }

  // 2. Call REAL edge function via supabase.functions.invoke
  log('INVOKE', 'INFO', `POST /functions/v1/generate-invoice`);

  const { data: result, error: invokeError } = await supabase.functions.invoke('generate-invoice', {
    body: {
      mission_id: missionId!,
      service_role_reason: 'ops_test_pr2_validation',
    },
  });

  if (invokeError) {
    log('INVOKE', 'FAIL', `Edge function error: ${JSON.stringify(invokeError)}`);
    process.exit(1);
  }

  if (!result?.success) {
    log('INVOKE', 'FAIL', `Generation failed: ${JSON.stringify(result)}`);
    process.exit(1);
  }

  log('INVOKE', 'OK', `Facture: ${result.numero_facture} (${result.facture_id})`);
  log('INVOKE', 'INFO', `Public sector: ${result.is_public_sector}`);
  log('INVOKE', 'INFO', `PDF: ${result.pdf_path}`);
  log('INVOKE', 'INFO', `XML: ${result.xml_path}`);

  // 3. Verify DB entry
  const { data: dbFact } = await supabase
    .from('factures_honoraires')
    .select('id, numero_facture, template_version, statut, soignant_id, montant_ttc')
    .eq('id', result.facture_id)
    .single();

  if (dbFact) {
    log('DB', dbFact.template_version === 'v2_facturx' ? 'OK' : 'FAIL',
      `template_version = ${dbFact.template_version}`);
    log('DB', dbFact.statut === 'EMISE' ? 'OK' : 'FAIL',
      `statut = ${dbFact.statut}`);
    log('DB', 'INFO', `montant_ttc = ${dbFact.montant_ttc}`);
  } else {
    log('DB', 'FAIL', 'Facture not found in DB');
  }

  // 4. Check audit log for GENERATED_VIA_SERVICE_ROLE
  const { data: auditLog } = await supabase
    .from('invoice_audit_log')
    .select('id, action, payload_before')
    .eq('invoice_id', result.facture_id)
    .eq('action', 'GENERATED_VIA_SERVICE_ROLE')
    .maybeSingle();

  log('AUDIT', auditLog ? 'OK' : 'FAIL',
    auditLog
      ? `Audit log found: reason="${(auditLog.payload_before as any)?.reason}"`
      : 'No GENERATED_VIA_SERVICE_ROLE audit entry');

  // 5. Check numbering continuity
  const { data: lastTwo } = await supabase
    .from('factures_honoraires')
    .select('numero_facture')
    .eq('soignant_id', dbFact?.soignant_id)
    .like('numero_facture', 'JOL-%')
    .order('numero_facture', { ascending: false })
    .limit(2);

  if (lastTwo && lastTwo.length >= 1) {
    log('NUMBERING', 'OK', `Latest: ${lastTwo.map(f => f.numero_facture).join(', ')}`);
  }

  // 6. Download artifacts from Storage
  log('STORAGE', 'INFO', 'Downloading PDF...');
  const { data: pdfBlob } = await supabase.storage
    .from('jolene-documents')
    .download(result.pdf_path);

  if (pdfBlob) {
    const pdfText = await pdfBlob.text();
    writeFileSync(join(OUTPUT_DIR, 'facture.txt'), pdfText);
    log('STORAGE', 'OK', `PDF saved: ${join(OUTPUT_DIR, 'facture.txt')} (${pdfText.length} chars)`);

    // Check mentions
    const checks: Record<string, boolean> = {
      'numero_facture': pdfText.includes(result.numero_facture),
      'mandataire_289': pdfText.includes('289 I-2') || pdfText.includes('mandataire'),
      'TVA_261': pdfText.includes('261') || pdfText.includes('TVA non applicable'),
      'SIRET_pro': /SIRET\s*:\s*\S+/.test(pdfText),
      'RPPS_ou_ADELI': /RPPS|ADELI/.test(pdfText),
      'montant_HT': /Montant HT/.test(pdfText),
      'montant_TTC': /Montant TTC/.test(pdfText),
    };
    console.log('\nMentions PDF:');
    for (const [k, v] of Object.entries(checks)) {
      log('PDF', v ? 'OK' : 'FAIL', k);
    }
  } else {
    log('STORAGE', 'FAIL', 'PDF download failed');
  }

  log('STORAGE', 'INFO', 'Downloading XML...');
  const { data: xmlBlob } = await supabase.storage
    .from('jolene-documents')
    .download(result.xml_path);

  if (xmlBlob) {
    const xmlText = await xmlBlob.text();
    writeFileSync(join(OUTPUT_DIR, 'facture.xml'), xmlText);
    log('STORAGE', 'OK', `XML saved: ${join(OUTPUT_DIR, 'facture.xml')} (${xmlText.length} chars)`);

    const xmlChecks: Record<string, boolean> = {
      'namespace_CII': xmlText.includes('CrossIndustryInvoice'),
      'EN16931': xmlText.includes('urn:cen.eu:en16931'),
      'TypeCode_380': xmlText.includes('<ram:TypeCode>380</ram:TypeCode>'),
      'EUR': xmlText.includes('EUR'),
      'TVA_CategoryCode': xmlText.includes('CategoryCode'),
    };
    console.log('\nXML CII:');
    for (const [k, v] of Object.entries(xmlChecks)) {
      log('XML', v ? 'OK' : 'FAIL', k);
    }
  } else {
    log('STORAGE', 'FAIL', 'XML download failed');
  }

  // 7. Generate signed URLs (24h)
  const { data: pdfSigned } = await supabase.storage
    .from('jolene-documents')
    .createSignedUrl(result.pdf_path, 86400);
  const { data: xmlSigned } = await supabase.storage
    .from('jolene-documents')
    .createSignedUrl(result.xml_path, 86400);

  console.log('\n═══════════════════════════════════════');
  console.log('  SIGNED URLs (24h):');
  if (pdfSigned?.signedUrl) console.log(`  PDF: ${pdfSigned.signedUrl}`);
  if (xmlSigned?.signedUrl) console.log(`  XML: ${xmlSigned.signedUrl}`);
  console.log('═══════════════════════════════════════');

  // Write report
  writeFileSync(join(OUTPUT_DIR, 'report.json'), JSON.stringify({
    facture_id: result.facture_id,
    numero_facture: result.numero_facture,
    template_version: dbFact?.template_version,
    statut: dbFact?.statut,
    audit_logged: !!auditLog,
    pdf_signed_url: pdfSigned?.signedUrl,
    xml_signed_url: xmlSigned?.signedUrl,
  }, null, 2));

  console.log(`\nAll artifacts in: ${OUTPUT_DIR}`);
  console.log('Done.');
}

main().catch(err => {
  console.error('Fatal:', err);
  process.exit(1);
});
