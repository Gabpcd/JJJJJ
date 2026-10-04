import { phaseFailure } from './failure.mjs';
// Source-only, entirely synthetic. No transport is selected by this module.
import { randomBytes, randomUUID, createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const requireValue = (ok, code, diagnostic) => { if (!ok) throw phaseFailure(code, diagnostic); };
export function sqlJson(value) {
  const json = JSON.stringify(value), tag = '$restore_fixture_json$';
  requireValue(!json.includes(tag), 'RESTORE_JSON_DELIMITER');
  return `${tag}${json}${tag}::jsonb`;
}
function siret(id) {
  const stem = '99' + BigInt('0x' + id.replaceAll('-', '').slice(0, 10)).toString().padStart(11, '0').slice(-11);
  for (let digit = 0; digit < 10; digit++) {
    const value = stem + digit;
    if ([...value].reverse().reduce((total, char, index) => {
      const n = Number(char) * (index % 2 ? 2 : 1); return total + (n > 9 ? n - 9 : n);
    }, 0) % 10 === 0) return value;
  }
  throw phaseFailure('RESTORE_SIRET');
}
// A real small PDF file; deliberately not a claim of generate-invoice/Factur-X compliance.
export function syntheticPdf(marker) {
  requireValue(/^[a-f0-9-]{36}$/.test(marker), 'RESTORE_PDF_MARKER');
  const text = `RESTORE SYNTHETIC ONLY ${marker} - 4h x EUR20 = EUR80 - NO PAYMENT`;
  const stream = `BT /F1 10 Tf 40 760 Td (${text}) Tj ET\n`;
  const objects = ['<< /Type /Catalog /Pages 2 0 R >>', '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>', `<< /Length ${Buffer.byteLength(stream)} >>\nstream\n${stream}endstream`];
  let output = '%PDF-1.4\n'; const offsets = [0];
  for (let i = 0; i < objects.length; i++) { offsets.push(Buffer.byteLength(output)); output += `${i + 1} 0 obj\n${objects[i]}\nendobj\n`; }
  const xref = Buffer.byteLength(output);
  output += `xref\n0 6\n0000000000 65535 f \n${offsets.slice(1).map(n => String(n).padStart(10, '0') + ' 00000 n \n').join('')}trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`;
  return Buffer.from(output);
}
export function newSourceFixture(productSha, run) {
  requireValue(/^[a-f0-9]{40}$/.test(productSha) && /^jolene-restore-drill-[a-z0-9-]{1,26}$/.test(run), 'RESTORE_FIXTURE_CONTEXT');
  const roles = ['SOIGNANT', 'ADMIN_ETABLISSEMENT', 'ADMIN_PLATEFORME', 'SOIGNANT', 'ADMIN_ETABLISSEMENT'];
  const members = roles.map(role => { const id = randomUUID(); return {
    id, role, email: `restore-${id}@example.invalid`, password: 'Rs!' + randomBytes(36).toString('base64url'),
  }; });
  const runId = 'connect-test-restore-' + run.slice('jolene-restore-drill-'.length);
  const actor = index => ({ id: members[index].id, email: members[index].email });
  const invoiceId = randomUUID(), pdf = syntheticPdf(invoiceId);
  const xml = Buffer.from(`<?xml version="1.0" encoding="UTF-8"?><synthetic-restoration-fixture id="${invoiceId}"><hours>4</hours><amount currency="EUR">80.00</amount><legal-status>NOT_A_LEGAL_INVOICE</legal-status></synthetic-restoration-fixture>\n`);
  const files = [{ kind: 'pdf', key: `invoices/restore/${invoiceId}/invoice.pdf`, type: 'application/pdf', bytes: pdf },
    { kind: 'xml', key: `invoices/restore/${invoiceId}/invoice.xml`, type: 'application/xml', bytes: xml }];
  return { version: 1, run, members, sql: {
    schemaVersion: 1, projectRef: 'LOCAL_PG17_RESTORE_APP', sourceSha: productSha, runId, ownerMarker: runId + ':' + productSha,
    actors: { soignant: actor(0), etablissement: actor(1) }, sqlActors: { admin: actor(2) },
    ids: { mission: randomUUID(), equipeAdmin: randomUUID(), presence: randomUUID() },
    identifiants: { siretSoignant: siret(members[0].id), siretEtablissement: siret(members[1].id) },
    outsiders: { soignant: actor(3), etablissement: { ...actor(4), siret: siret(members[4].id) } },
    document: { id: invoiceId, files: files.map(({ bytes, ...file }) => ({ ...file, sha256: sha(bytes), size: bytes.length })) },
  }, files };
}
export async function seedSource(runtime, fixture) {
  requireValue(runtime.side === 'source' && runtime.run === fixture.run, 'RESTORE_SOURCE_ONLY');
  await runtime.guard('empty-imported');
  for (const member of fixture.members) {
    const result = await runtime.api('/auth/v1/admin/users', { method: 'POST', body: {
      id: member.id, email: member.email, password: member.password, email_confirm: true,
      app_metadata: { role: member.role, est_compte_test: true, is_test_playwright: true,
        jolene_connect_fixture_owner: fixture.sql.ownerMarker,
        ...(member.role === 'ADMIN_ETABLISSEMENT' ? { etablissement_id: member.id } : {}) },
    } });
    const user = result.json?.user ?? result.json;
    requireValue([200, 201].includes(result.status) && user?.id === member.id && user?.email === member.email
      && !!user.email_confirmed_at && user.app_metadata?.jolene_connect_fixture_owner === fixture.sql.ownerMarker
      && user.app_metadata?.role === member.role && user.app_metadata?.est_compte_test === true
      && (member.role !== 'ADMIN_ETABLISSEMENT' || user.app_metadata.etablissement_id === member.id),
    'RESTORE_AUTH_CREATE', { httpStatus: result.status });
  }
  const localMission = readFileSync(fileURLToPath(new URL('./sql/source-mission.sql', import.meta.url)), 'utf8');
  const documents = readFileSync(fileURLToPath(new URL('./sql/source-documents.sql', import.meta.url)), 'utf8');
  await runtime.sql(`BEGIN; SET LOCAL row_security=off; SET LOCAL statement_timeout='30s';
SELECT set_config('jolene.connect_test_fixture_manifest',(${sqlJson(fixture.sql)})::text,true);
${localMission}\n${documents}\nCOMMIT;`);
  for (const file of fixture.files) {
    const uploaded = await runtime.api('/storage/v1/object/jolene-documents/' + file.key,
      { method: 'POST', binary: file.bytes.toString('base64'), contentType: file.type });
    requireValue([200, 201].includes(uploaded.status), 'RESTORE_OBJECT_CREATE', { httpStatus: uploaded.status });
  }
  await runtime.guard('seeded', fixture.sql);
  return { users: 5, soignants: 2, etablissements: 2, invoices: 1, objects: 2, externalTransport: false };
}
