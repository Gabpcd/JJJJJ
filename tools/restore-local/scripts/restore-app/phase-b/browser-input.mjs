// Runtime-generated synthetic credentials only. No admin or service key is projected.
import { createHash } from 'node:crypto';
import { lstatSync, readFileSync, realpathSync } from 'node:fs';

export const INPUT_PATH = '/restore-private/input.json';
const UUID = /^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/;
const requireValue = ok => { if (!ok) throw new Error('RESTORE_BROWSER_INPUT_REFUSED'); };
const exactKeys = (value, keys) => value && typeof value === 'object' && !Array.isArray(value)
  && JSON.stringify(Object.keys(value).sort()) === JSON.stringify([...keys].sort());

export function validateBrowserInput(value) {
  try {
    requireValue(exactKeys(value, ['version', 'run', 'side', 'appUrl', 'apiUrl', 'anonKey', 'members',
      'missionId', 'invoiceId', 'invoiceNumber', 'pdfKey', 'pdfBytes', 'pdfSha256']));
    requireValue(value.version === 1 && /^jolene-restore-drill-[a-z0-9-]{1,26}$/.test(value.run)
      && ['source', 'target'].includes(value.side) && value.appUrl === 'http://127.0.0.1:4173'
      && value.apiUrl === `http://${value.run}-${value.side}-api:8000`);
    requireValue(typeof value.anonKey === 'string' && value.anonKey.length <= 4096
      && /^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(value.anonKey));
    requireValue(JSON.parse(Buffer.from(value.anonKey.split('.')[1], 'base64url')).role === 'anon');
    requireValue(Array.isArray(value.members) && value.members.length === 4);
    const roles = ['SOIGNANT', 'ADMIN_ETABLISSEMENT', 'SOIGNANT', 'ADMIN_ETABLISSEMENT'];
    for (const [index, member] of value.members.entries()) requireValue(
      exactKeys(member, ['id', 'role', 'email', 'password']) && UUID.test(member.id)
      && member.role === roles[index] && member.email === `restore-${member.id}@example.invalid`
      && typeof member.password === 'string' && /^Rs![A-Za-z0-9_-]{48}$/.test(member.password));
    requireValue(new Set(value.members.map(member => member.id)).size === 4
      && UUID.test(value.missionId) && UUID.test(value.invoiceId)
      && new Set([...value.members.map(member => member.id), value.missionId, value.invoiceId]).size === 6);
    requireValue(typeof value.invoiceNumber === 'string' && /^[A-Za-z0-9][A-Za-z0-9_-]{0,119}$/.test(value.invoiceNumber)
      && value.pdfKey === `invoices/restore/${value.invoiceId}/invoice.pdf`
      && Number.isSafeInteger(value.pdfBytes) && value.pdfBytes > 0 && value.pdfBytes <= 64 * 1024
      && /^[a-f0-9]{64}$/.test(value.pdfSha256));
    return value;
  } catch { throw new Error('RESTORE_BROWSER_INPUT_REFUSED'); }
}

export function readBrowserInput(path = process.env.JOLENE_RESTORE_BROWSER_INPUT) {
  try {
    requireValue(path === INPUT_PATH);
    const info = lstatSync(path), directory = lstatSync('/restore-private');
    requireValue(directory.isDirectory() && !directory.isSymbolicLink() && (directory.mode & 0o077) === 0
      && info.isFile() && !info.isSymbolicLink() && info.nlink === 1 && (info.mode & 0o077) === 0
      && realpathSync(path) === path && info.size > 0 && info.size <= 32 * 1024);
    return validateBrowserInput(JSON.parse(readFileSync(path, 'utf8')));
  } catch { throw new Error('RESTORE_BROWSER_INPUT_REFUSED'); }
}

export async function writeBrowserInput(runtime, sourceFixture, side, outputFile) {
  try {
    requireValue(['source', 'target'].includes(side) && runtime.run === sourceFixture.run
      && UUID.test(sourceFixture.sql.document.id) && UUID.test(sourceFixture.sql.ids.mission));
    const invoice = await runtime.sqlJson(side, `BEGIN READ ONLY; SET LOCAL statement_timeout='15s';
SELECT jsonb_build_object('id',id,'number',numero_facture,'mission',mission_id,'pdf',pdf_s3_key)
FROM public.factures_honoraires WHERE id='${sourceFixture.sql.document.id}'::uuid;
ROLLBACK;`);
    const pdf = sourceFixture.files[0];
    requireValue(invoice?.id === sourceFixture.sql.document.id && invoice.mission === sourceFixture.sql.ids.mission
      && pdf.kind === 'pdf' && Buffer.isBuffer(pdf.bytes) && invoice.pdf === pdf.key);
    const environment = runtime.plan.services[side + '-storage'].environment;
    requireValue(environment.ANON_KEY !== environment.SERVICE_KEY);
    const input = validateBrowserInput({ version: 1, run: runtime.run, side, appUrl: 'http://127.0.0.1:4173',
      apiUrl: `http://${runtime.run}-${side}-api:8000`, anonKey: environment.ANON_KEY,
      members: [0, 1, 3, 4].map(index => {
        const { id, role, email, password } = sourceFixture.members[index]; return { id, role, email, password };
      }), missionId: invoice.mission, invoiceId: invoice.id, invoiceNumber: invoice.number, pdfKey: invoice.pdf,
      pdfBytes: pdf.bytes.length, pdfSha256: createHash('sha256').update(pdf.bytes).digest('hex') });
    await runtime.privateWrite(outputFile, Buffer.from(JSON.stringify(input)));
    return { written: true, members: 4, adminIncluded: false, serverKeyIncluded: false };
  } catch { throw new Error('RESTORE_BROWSER_INPUT_REFUSED'); }
}
