#!/usr/bin/env npx tsx
/**
 * test-generate-invoice.ts — Teste la génération d'une facture via l'edge function
 *
 * Usage :
 *   SUPABASE_URL=https://flripxtsyegjshnhzjkz.supabase.co \
 *   SUPABASE_SERVICE_ROLE_KEY=xxx \
 *   npx tsx scripts/test-generate-invoice.ts [mission_id]
 *
 * Sans mission_id : utilise la première mission TERMINEE avec mandat signé et sans facture.
 *
 * Artefacts générés :
 *   /tmp/jolene-invoice-test/facture.txt  — PDF text content
 *   /tmp/jolene-invoice-test/facture.xml  — XML CII Factur-X
 *   /tmp/jolene-invoice-test/report.json  — Résumé des mentions présentes
 */

import { createClient } from '@supabase/supabase-js';
import { writeFileSync, mkdirSync } from 'fs';
import { join } from 'path';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL || 'https://flripxtsyegjshnhzjkz.supabase.co';
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || '';

if (!SERVICE_ROLE_KEY) {
  console.error('SUPABASE_SERVICE_ROLE_KEY required');
  process.exit(1);
}

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
const OUTPUT_DIR = '/tmp/jolene-invoice-test';

async function main() {
  mkdirSync(OUTPUT_DIR, { recursive: true });

  const missionId = process.argv[2];
  let testMissionId: string;

  if (missionId) {
    testMissionId = missionId;
    console.log(`Using provided mission_id: ${testMissionId}`);
  } else {
    // Find a suitable test mission
    const { data: missions } = await supabase
      .from('missions')
      .select('id, intitule, soignant_assigne_id, etablissement_id, total_brut, net_a_payer, statut')
      .eq('statut', 'TERMINEE')
      .limit(10);

    if (!missions || missions.length === 0) {
      console.error('No TERMINEE missions found');
      process.exit(1);
    }

    // Find one with a signed mandate and no existing invoice
    for (const m of missions) {
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

      testMissionId = m.id;
      console.log(`Auto-selected mission: ${m.intitule} (${m.id})`);
      break;
    }

    if (!testMissionId!) {
      console.error('No eligible mission found (TERMINEE + mandate signed + no existing invoice)');
      process.exit(1);
    }
  }

  // Call generate-invoice edge function
  console.log(`\nCalling generate-invoice for mission ${testMissionId!}...`);

  const { data: result, error } = await supabase.functions.invoke('generate-invoice', {
    body: { mission_id: testMissionId! },
  });

  if (error) {
    console.error('Edge function error:', error);
    process.exit(1);
  }

  if (!result?.success) {
    console.error('Generation failed:', result);
    process.exit(1);
  }

  console.log(`\nFacture generated: ${result.numero_facture}`);
  console.log(`  ID: ${result.facture_id}`);
  console.log(`  Public sector: ${result.is_public_sector}`);
  console.log(`  PDF path: ${result.pdf_path}`);
  console.log(`  XML path: ${result.xml_path}`);

  // Download artifacts from storage
  console.log('\nDownloading artifacts...');

  const { data: pdfData } = await supabase.storage
    .from('jolene-documents')
    .download(result.pdf_path);

  const { data: xmlData } = await supabase.storage
    .from('jolene-documents')
    .download(result.xml_path);

  if (pdfData) {
    const pdfText = await pdfData.text();
    writeFileSync(join(OUTPUT_DIR, 'facture.txt'), pdfText);
    console.log(`  PDF saved: ${join(OUTPUT_DIR, 'facture.txt')}`);

    // Check mentions
    const report: Record<string, boolean> = {
      'numero_facture': pdfText.includes(result.numero_facture),
      'mention_mandataire': pdfText.includes('mandataire') || pdfText.includes('289 I-2'),
      'exoneration_tva_261': pdfText.includes('261') || pdfText.includes('TVA non applicable'),
      'SIRET_pro': /SIRET\s*:\s*\S+/.test(pdfText),
      'RPPS_ou_ADELI': /RPPS|ADELI/.test(pdfText),
      'montant_HT': /Montant HT/.test(pdfText),
      'montant_TTC': /Montant TTC/.test(pdfText),
      'subrogation_mention': pdfText.includes('subrogation'),
      'mandat_version': /mandat v\d/.test(pdfText),
    };

    console.log('\nMentions check (PDF):');
    for (const [key, present] of Object.entries(report)) {
      console.log(`  ${present ? '✅' : '❌'} ${key}`);
    }

    writeFileSync(join(OUTPUT_DIR, 'report.json'), JSON.stringify(report, null, 2));
  } else {
    console.warn('  PDF download failed');
  }

  if (xmlData) {
    const xmlText = await xmlData.text();
    writeFileSync(join(OUTPUT_DIR, 'facture.xml'), xmlText);
    console.log(`  XML saved: ${join(OUTPUT_DIR, 'facture.xml')}`);

    // Check XML CII compliance
    const xmlReport: Record<string, boolean> = {
      'namespace_CII': xmlText.includes('CrossIndustryInvoice'),
      'namespace_EN16931': xmlText.includes('urn:cen.eu:en16931'),
      'TypeCode_380': xmlText.includes('<ram:TypeCode>380</ram:TypeCode>'),
      'SellerTradeParty': xmlText.includes('SellerTradeParty'),
      'BuyerTradeParty': xmlText.includes('BuyerTradeParty'),
      'InvoiceCurrencyCode_EUR': xmlText.includes('EUR'),
      'TVA_category': xmlText.includes('CategoryCode'),
      'GrandTotalAmount': xmlText.includes('GrandTotalAmount'),
      'PaymentMeans': xmlText.includes('SpecifiedTradeSettlementPaymentMeans'),
    };

    console.log('\nXML CII compliance check:');
    for (const [key, present] of Object.entries(xmlReport)) {
      console.log(`  ${present ? '✅' : '❌'} ${key}`);
    }

    writeFileSync(join(OUTPUT_DIR, 'report.json'),
      JSON.stringify({ pdf: JSON.parse(require('fs').readFileSync(join(OUTPUT_DIR, 'report.json'), 'utf8')), xml: xmlReport }, null, 2));
  } else {
    console.warn('  XML download failed');
  }

  console.log(`\nAll artifacts in: ${OUTPUT_DIR}`);
  console.log('Done.');
}

main().catch(err => {
  console.error('Fatal:', err);
  process.exit(1);
});
