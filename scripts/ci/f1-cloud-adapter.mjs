import { randomUUID, randomBytes } from 'node:crypto';
import { readFile, open, rename, lstat } from 'node:fs/promises';
import { join } from 'node:path';
import { STAGING, ORIGIN, sha256, refuse, requireReady, requireTimeReserveF1, originalBody } from './f1-cloud-core.mjs';
import { catalogueSqlF1, reconcileSqlF1, transactionF1, sqlManifestF1, supportResponseSqlF1 } from './f1-cloud-sql.mjs';
import { validateDocumentSet, documentTransportF1, analyzeXmlF1 } from './f1-cloud-documents.mjs';

const API = `https://api.supabase.com/v1/projects/${STAGING}`;
const MAIN = 'https://api.github.com/repos/Gabpcd/JJJJJ/git/ref/heads/main';
const TEMPLATE_HASHES = Object.freeze({ prepare: 'a406cf8b69ec0a31babb0071c0e081714423dea3898ee620e838b991ef5383d9',
  correction: 'b666939c79638ec832d5eb3fc690335ca756a232f46e318edf63ac85d42cb39a' });
const ROLES = Object.freeze(['SOIGNANT', 'ADMIN_ETABLISSEMENT', 'ADMIN_PLATEFORME']);
const check = (condition, code) => { if (!condition) refuse(code); };
const uuid = x => typeof x === 'string' && /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/.test(x);
const one = rows => { check(Array.isArray(rows) && rows.length === 1 && rows[0] && Object.keys(rows[0]).length === 1, 'F1_SQL_RESPONSE'); return Object.values(rows[0])[0]; };
const canonical = x => Array.isArray(x) ? x.map(canonical) : x && typeof x === 'object' ? Object.fromEntries(Object.keys(x).sort().map(k => [k, canonical(x[k])])) : x;
const equal = (a, b) => JSON.stringify(canonical(a)) === JSON.stringify(canonical(b));

async function privateWrite(path, value, replace = false) {
  const target = replace ? `${path}.next` : path;
  const fd = await open(target, 'wx', 0o600);
  try { await fd.writeFile(JSON.stringify(value)); await fd.sync(); } finally { await fd.close(); }
  if (replace) await rename(target, path);
}
async function privateRead(path) {
  const stat = await lstat(path);
  check(stat.isFile() && !stat.isSymbolicLink() && (stat.mode & 0o077) === 0, 'F1_PRIVATE_PERMISSIONS');
  return JSON.parse(await readFile(path, 'utf8'));
}
export async function loadSqlTemplatesF1() {
  const templates = {};
  for (const [kind, filename] of [['prepare', 'prepare.sql'], ['correction', 'prepare-remplacement.sql']]) {
    const bytes = await readFile(new URL(`./f1-cloud-sql/${filename}`, import.meta.url));
    check(sha256(bytes) === TEMPLATE_HASHES[kind], 'F1_SQL_TEMPLATE_DRIFT'); templates[kind] = bytes.toString('utf8');
  }
  return templates;
}
function siret(seed) {
  const base = `99${BigInt(`0x${seed.replaceAll('-', '').slice(0, 10)}`).toString().padStart(11, '0').slice(-11)}`;
  for (let n = 0; n <= 9; n++) {
    const value = base + n;
    const sum = [...value].reverse().reduce((acc, digit, i) => { let x = Number(digit) * (i % 2 ? 2 : 1); return acc + (x > 9 ? x - 9 : x); }, 0);
    if (sum % 10 === 0) return value;
  }
  refuse('F1_SIRET_GENERATION');
}
export function manifestF1(ctx) {
  const ids = Array.from({ length: 7 }, () => randomUUID());
  const members = ids.slice(0, 3).map((id, slot) => ({ id, email: `f1-${id}@example.invalid`,
    role: slot === 0 ? 'SOIGNANT' : slot === 1 ? 'ETABLISSEMENT' : 'ADMIN_PLATEFORME',
    authRole: ROLES[slot], password: `F1!${randomBytes(36).toString('base64url')}` }));
  const actor = slot => ({ id: members[slot].id, email: members[slot].email });
  const sql = { schemaVersion: 1, projectRef: STAGING, runId: ctx.run, sourceSha: ctx.sha, ownerMarker: `${ctx.run}:${ctx.sha}`,
    actors: { soignant: actor(0), etablissement: actor(1) }, sqlActors: { admin: actor(2) },
    ids: { mission: ids[3], equipeAdmin: ids[4], litige: ids[5], presence: ids[6] },
    identifiants: { siretSoignant: siret(ids[0]), siretEtablissement: siret(ids[1]) }, documents: {} };
  const manifest = { sql, members: members.slice(0, 2), admin: members[2], missionId: ids[3], period: null, tokens: {}, snapshots: {} };
  sqlManifestF1(manifest); return manifest;
}
export function validateActorF1(user, member, manifest) {
  check(user?.id === member.id && user.email === member.email && user.email_confirmed_at
    && !user.deleted_at && (!user.banned_until || Date.parse(user.banned_until) <= Date.now())
    && user.app_metadata?.role === member.authRole && user.app_metadata?.est_compte_test === true
    && user.app_metadata?.jolene_f1_owner === manifest.sql.ownerMarker, 'F1_AUTH_OWNERSHIP');
}
export function periodFromReceiptF1(receipt, manifest) {
  check(receipt?.runId === manifest.sql.runId && receipt.missionId === manifest.missionId
    && receipt.presenceIdReserve === manifest.sql.ids.presence && receipt.montantOriginal === 80 && receipt.montantRemplacement === 72 && receipt.qualificationVerifiee === false
    && receipt.signatureSynthetique === true && receipt.mfaProuve === false, 'F1_SEED_RECEIPT');
  const start = new Date(`${receipt.periodeDebut}T00:00:00Z`), end = new Date(`${receipt.periodeFin}T00:00:00Z`);
  check(Number.isFinite(+start) && Number.isFinite(+end) && start.getUTCDay() === 1 && end.getUTCDay() === 0
    && +end - +start === 6 * 86400000, 'F1_SEED_PERIOD');
  const thursday = new Date(+start + 3 * 86400000), year = thursday.getUTCFullYear();
  const jan4 = new Date(Date.UTC(year, 0, 4)), monday = new Date(+jan4 - ((jan4.getUTCDay() + 6) % 7) * 86400000);
  const period = { start: receipt.periodeDebut, end: receipt.periodeFin, week: 1 + Math.round((+start - +monday) / (7 * 86400000)), year };
  originalBody({ missionId: manifest.missionId, period }); return period;
}
export function validateReconciliationF1(row, manifest, phase) {
  const allIds = [...manifest.members, manifest.admin].map(x => x.id).sort();
  check(row && equal(row.actors?.map(x => x.id).sort(), allIds) && row.actors.every(x => x.owned === true && x.confirmed === true)
    && row.adminActive === 0 && row.payments === 0 && row.paymentsSoignant === 0 && row.paymentsMission === 0 && row.transfers === 0 && row.emailsQueued === 0 && row.emailRetries === 0
    && row.messages === 0, 'F1_EFFECTS_UNEXPECTED');
  const m = row.mission;
  check(m?.id === manifest.missionId && m.soignant === manifest.members[0].id && m.etablissement === manifest.members[1].id
    && m.status === 'EN_COURS' && m.hours === 8 && m.effectiveHours === 4, 'F1_MISSION_MISMATCH');
  const originalOnly = phase === 'original', docs = row.documents;
  check(Array.isArray(row.syntheticPresence) && row.syntheticPresence.length === (originalOnly ? 0 : 1)
    && (originalOnly || equal(row.syntheticPresence[0], {id:manifest.sql.ids.presence,mission:manifest.missionId,
      soignant:manifest.members[0].id,hours:4,adjusted:4,litige:manifest.sql.ids.litige,arrival:false,departure:false,validated:false})), 'F1_SYNTHETIC_PRESENCE');
  check(Array.isArray(docs) && docs.length === (originalOnly ? 1 : 2), 'F1_DOCUMENT_COUNT');
  for (const [index, d] of docs.entries()) {
    check(uuid(d.id) && d.kind === 'FACTURE' && d.nature === (index ? 'REMPLACEMENT' : 'ORIGINALE')
      && d.status === (originalOnly || index ? 'EMISE' : 'REMPLACEE') && d.predecessor === (index ? docs[0].id : null)
      && d.soignant === manifest.members[0].id && d.etablissement === manifest.members[1].id
      && d.quantity === 4 && d.rate === (index ? 18 : 20) && d.net === (index ? 72 : 80) && d.vat === 0 && d.total === d.net
      && d.paid === false && d.final === false && d.periodStart === manifest.period.start && d.periodEnd === manifest.period.end
      && d.versionCount === 1 && d.versions?.length === 1 && d.versions[0].pdf_s3_key === d.pdf.key
      && d.versions[0].facturx_xml_url === d.xml.key, 'F1_DOCUMENT_RECONCILIATION');
  }
  check(Array.isArray(row.commissions)&&row.commissions.length===docs.length,'F1_COMMISSION_COUNT');
  for(const [i,c] of row.commissions.entries())check(uuid(c.id)&&c.honoraire===docs[i].id&&c.mission===manifest.missionId
    &&c.etablissement===manifest.members[1].id&&c.kind==='FACTURE'&&c.status===(originalOnly||i?'EMISE':'REMPLACEE')
    &&c.predecessor===(i?row.commissions[0].id:null)&&c.net===(i?10.8:12)&&c.vat===(i?2.16:2.4)&&c.total===(i?12.96:14.4)
    &&c.periodStart===manifest.period.start&&c.periodEnd===manifest.period.end&&c.providerLinked===false,'F1_COMMISSION_RECONCILIATION');
  if(manifest.snapshots.originalCommission)check(equal(row.commissions[0].immutable,manifest.snapshots.originalCommission),'F1_ORIGINAL_COMMISSION_CHANGED');
  check(m.rate === (originalOnly ? 20 : 18) && m.net === (originalOnly ? 160 : 144)
    && m.commission === (originalOnly ? 24 : 21.6), 'F1_MISSION_FINANCE');
  if (manifest.snapshots.original) {
    const d = docs[0], old = manifest.snapshots.original;
    check(equal(d.versions, old.versions) && equal(d.pdf, old.pdf) && equal(d.xml, old.xml)
      && d.number === old.number && d.emittedOn === old.emittedOn, 'F1_ORIGINAL_CHANGED');
  }
  return docs.map((d, i) => ({ ...d, slot: i ? 'replacement' : 'original' }));
}

export function verifyUiEffectsF1(row, manifest) {
  const [s,e]=manifest.members.map(x=>x.id), before=manifest.snapshots.uiAudit;
  check(Array.isArray(before)&&Array.isArray(row.uiAudit)&&before.length===2&&row.uiAudit.length===2,
    'F1_UI_AUDIT_MISSING');
  for(const id of [s,e]) {
    const b=before.find(x=>x.id===id),a=row.uiAudit.find(x=>x.id===id);
    check(b&&a&&a.connexions-b.connexions===5&&a.consultations-b.consultations===(id===e?5:0)
      &&a.other===b.other,'F1_UI_AUDIT_DELTA');
  }
  const c=row.conversations?.[0];
  check(row.conversations?.length===1&&uuid(c.id)&&c.mission===manifest.missionId&&c.soignant===s&&c.etablissement===e
    &&equal([c.first,c.second].sort(),[s,e].sort())&&row.messages===0&&row.presences===2&&row.typing===0,
    'F1_UI_CHAT_EFFECTS');
}

/** Real Auth/Management/Storage adapter. Unit tests inject HTTP, never production
 * execution. The distributed review contract remains false until independently
 * acquired hashes/effects are approved; no hashes are auto-refreshed. */
export function createAdapterF1({ env, contract, fetcher = fetch, analyzePdf, verifyUiEffects = verifyUiEffectsF1 }) {
  let directory, current, baseline, preflight, templates, finalizing = false;
  const save = async () => privateWrite(join(directory, 'manifest.private.json'), current, true);
  async function json(url, { method = 'GET', body, token, scope = 'management', nullable = false } = {}) {
    const headers = scope === 'public' ? { Accept: 'application/json', 'User-Agent': 'Jolene-F1-staging' }
      : scope === 'management' ? { Authorization: `Bearer ${env.STAGING_SUPABASE_ACCESS_TOKEN}` }
        : { apikey: scope === 'admin' ? env.STAGING_SUPABASE_SERVICE_ROLE_KEY : env.STAGING_SUPABASE_ANON_KEY,
          Authorization: `Bearer ${token ?? (scope === 'admin' ? env.STAGING_SUPABASE_SERVICE_ROLE_KEY : env.STAGING_SUPABASE_ANON_KEY)}` };
    try {
      const r = await fetcher(url, { method, headers: { ...headers, 'Content-Type': 'application/json' }, redirect: 'error',
        signal: AbortSignal.timeout(finalizing ? 20000 : 55000), ...(body !== undefined ? { body: JSON.stringify(body) } : {}) });
      check(r.ok && !r.redirected, 'F1_HTTP_REFUSED'); if (nullable && r.status === 204) return null;
      return await r.json();
    } catch { refuse('F1_HTTP_FAILED'); }
  }
  const query = async (sql, readOnly) => one(await json(`${API}/database/query`, { method: 'POST', body: { query: sql, read_only: readOnly } }));
  const once = async (name, action) => {
    check(/^(?:auth_create_[012]|generator_login|auth_logout_[01]|auth_ban_[012]|sql_prepare|sql_correction)$/.test(name), 'F1_ADAPTER_EFFECT');
    try { await privateWrite(join(directory, `${name}.intent.private.json`), { run: current.sql.runId, effect: name }); }
    catch { refuse('F1_ADAPTER_EFFECT_ALREADY_ATTEMPTED'); }
    try { return await action(); } catch { refuse('F1_ADAPTER_EFFECT_AMBIGUOUS'); }
  };
  const catalogue = async () => {
    const c = await query(catalogueSqlF1(), true);
    check(c && ['routines', 'triggers', 'columns'].every(k => c[k] === contract.catalogue[k])
      && c.commissionHelper === 'c793ac81eaef0fe18fb5920c9264c675' && c.queuedRequests === 0 && c.activeCrons === 0 && c.runningCrons === 0 && c.generationUrlAbsent === true && c.supportStagingExact === true, 'F1_CATALOGUE_DRIFT');
    return c;
  };
  const adapter = {
    async preflight(ctx) {
      requireReady(contract, ctx);
      check(['STAGING_SUPABASE_ACCESS_TOKEN','STAGING_SUPABASE_SERVICE_ROLE_KEY','STAGING_SUPABASE_ANON_KEY'].every(k => typeof env[k] === 'string' && env[k].length), 'F1_CREDENTIALS_REQUIRED');
      check(typeof analyzePdf === 'function' && typeof verifyUiEffects === 'function', 'F1_ADAPTER_CONTRACT_PENDING');
      templates = await loadSqlTemplatesF1();
      const main = await json(MAIN, { scope: 'public' });
      check(main?.ref === 'refs/heads/main' && main.object?.sha === ctx.sha && main.object?.type === 'commit', 'F1_MAIN_MOVED');
      const functions = await json(`${API}/functions`);
      check(Array.isArray(functions), 'F1_EDGE_CATALOGUE');
      for (const slug of ['generate-invoice','send-email','notify-support']) {
        const actual = functions.filter(x => x.slug === slug), expected = contract.edge?.[slug];
        check(expected && actual.length === 1 && actual[0].status === 'ACTIVE' && actual[0].version === expected.version
          && actual[0].verify_jwt === expected.verify_jwt && actual[0].ezbr_sha256 === expected.ezbr_sha256, 'F1_EDGE_DRIFT');
      }
      baseline = await catalogue(); preflight = { ...contract }; return preflight;
    },
    async prepare(ctx, privateDirectory) {
      requireTimeReserveF1(ctx);
      directory = privateDirectory; current = manifestF1(ctx);
      await privateWrite(join(directory, 'manifest.private.json'), current);
      const actors = [...current.members, current.admin];
      for (const [slot, actor] of actors.entries()) await once(`auth_create_${slot}`, async () => {
        const user = await json(`${ORIGIN}/auth/v1/admin/users`, { method: 'POST', scope: 'admin', body: {
          id: actor.id, email: actor.email, password: actor.password, email_confirm: true,
          app_metadata: { role: actor.authRole, est_compte_test: true, is_test_playwright: true,
            jolene_f1_owner: current.sql.ownerMarker, ...(slot === 1 ? { etablissement_id: actor.id } : {}) },
        } });
        validateActorF1(user, actor, current);
      });
      const receipt = await once('sql_prepare', () => query(transactionF1('prepare', current, templates.prepare, baseline), false));
      current.period = periodFromReceiptF1(receipt, current); await save(); return current;
    },
    async authenticateGenerator() {
      const actor = current.members[0];
      return once('generator_login', async () => {
        const auth = await json(`${ORIGIN}/auth/v1/token?grant_type=password`, { method: 'POST', scope: 'publicAuth',
          body: { email: actor.email, password: actor.password } });
        validateActorF1(auth.user, actor, current); check(typeof auth.access_token === 'string' && auth.access_token.length > 0, 'F1_AUTH_TOKEN');
        current.tokens[actor.id] = auth.access_token; await save(); return auth.access_token;
      });
    },
    async recordUiAuth(actor, auth) {
      const member = current.members.find(x => x.id === actor.id); check(member, 'F1_AUTH_OWNERSHIP');
      validateActorF1(auth.user, member, current); check(typeof auth.access_token === 'string' && auth.access_token.length > 0, 'F1_AUTH_TOKEN');
      current.tokens[member.id] = auth.access_token; await save();
    },
    async reconcileOriginal(ctx, manifest, response) {
      const row = await query(reconcileSqlF1(current), true), docs = validateReconciliationF1(row, current, 'original');
      check(docs[0].id === response.facture_id && docs[0].pdf.key === response.pdf_path && docs[0].xml.key === response.xml_path, 'F1_EDGE_DOCUMENT_BINDING');
      current.sql.documents.original = { id: docs[0].id }; current.snapshots.original = docs[0]; current.snapshots.originalCommission=row.commissions[0].immutable; await save();
    },
    async prepareCorrection() {
      const receipt = await once('sql_correction', () => query(transactionF1('correction', current, templates.correction, baseline), false));
      check(receipt?.runId === current.sql.runId && uuid(receipt.id) && receipt.id !== current.sql.documents.original.id
        && receipt.originalId === current.sql.documents.original.id && receipt.litigeId === current.sql.ids.litige
        && receipt.presenceId === current.sql.ids.presence && receipt.typeDocument === 'FACTURE' && receipt.natureCorrection === 'REMPLACEMENT'
        && equal(receipt.initiation, { type: 'runner' }) && equal(receipt.regenPdfRequestIds, [])
        && Number.isSafeInteger(receipt.supportRequestId) && receipt.supportRequestId > 0, 'F1_CORRECTION_RECEIPT');
      current.correction = receipt; await save(); return receipt;
    },
    async reconcileDocuments(ctx, manifest, { replacement }) {
      const row = await query(reconcileSqlF1(current), true), documents = validateReconciliationF1(row, current, 'replacement');
      check(documents[1].id === replacement.facture_id && documents[1].pdf.key === replacement.pdf_path && documents[1].xml.key === replacement.xml_path, 'F1_EDGE_DOCUMENT_BINDING');
      validateDocumentSet(documents, current.members[0].id);
      current.snapshots.financeDigest = row.financeDigest; current.snapshots.versionsDigest = row.versionsDigest; current.snapshots.commissionsDigest=row.commissionsDigest; current.snapshots.invoiceAuditDigest=row.invoiceAuditDigest;
      current.snapshots.uiAudit = row.uiAudit;
      current.documents = documents; await save(); return documents;
    },
    async verifyDownloads() {
      const transport = documentTransportF1({ documents: current.documents, soignantId: current.members[0].id,
        anonKey: env.STAGING_SUPABASE_ANON_KEY, fetcher });
      const parties = { seller: 'Łukasz İpek TEST García & d’Élodie', buyer: 'TEST Clinique Łódź & d’Élodie',
        sellerSiren: current.sql.identifiants.siretSoignant.slice(0, 9), buyerSiren: current.sql.identifiants.siretEtablissement.slice(0, 9), original: current.documents[0] };
      const semantic = [];
      for (const actor of current.members) for (const doc of current.documents) {
        const token = current.tokens[actor.id]; check(token, 'F1_UI_AUTH_REQUIRED');
        const xml = await transport.download({ role: actor.role, token, slot: doc.slot, format: 'xml' });
        semantic.push({ role: actor.role, ...analyzeXmlF1(xml, doc, parties) });
        const pdf = await transport.download({ role: actor.role, token, slot: doc.slot, format: 'pdf' });
        semantic.push({ role: actor.role, ...await analyzePdf(pdf, doc, parties) });
      }
      check(transport.complete(), 'F1_DOCUMENT_READ_INCOMPLETE'); return { downloads: transport.projection(), semantic };
    },
    async reconcileEffects() {
      const row = await query(reconcileSqlF1(current), true); validateReconciliationF1(row, current, 'replacement');
      check(row.financeDigest === current.snapshots.financeDigest && row.versionsDigest === current.snapshots.versionsDigest && row.commissionsDigest===current.snapshots.commissionsDigest && row.invoiceAuditDigest===current.snapshots.invoiceAuditDigest,
        'F1_FINANCE_CHANGED_DURING_READS');
      check(row.emailTestSkips === 4 && row.supportTestSkips === 1, 'F1_PROVIDER_SKIP_NOT_PROVEN');
      const support = await query(supportResponseSqlF1(current.correction.supportRequestId), true);
      check(support.count === 1 && support.finished === true && support.testSkip === true, 'F1_SUPPORT_RESPONSE_NOT_PROVEN');
      await verifyUiEffects(row, current); await catalogue();
    },
    async finalize(ctx, privateDirectory) {
      finalizing = true;
      directory = privateDirectory; current = await privateRead(join(directory, 'manifest.private.json'));
      sqlManifestF1(current); check(current.sql.runId === ctx.run && current.sql.sourceSha === ctx.sha, 'F1_FINALIZE_OWNERSHIP');
      // All contexts have already closed in the UI's finally. Global logout uses
      // the last real session retained privately; banning alone is not revocation.
      const failures = [];
      for (const [slot, actor] of [...current.members, current.admin].entries()) {
        try {
          const result = await json(`${ORIGIN}/auth/v1/admin/users/${actor.id}`, { scope: 'admin' });
          const user = result.user ?? result; validateActorF1(user, actor, current);
          if (slot < 2 && current.tokens[actor.id]) {
            try { await once(`auth_logout_${slot}`, () => json(`${ORIGIN}/auth/v1/logout?scope=global`, {
              method: 'POST', scope: 'admin', token: current.tokens[actor.id], nullable: true })); } catch { failures.push('logout'); }
          }
          await once(`auth_ban_${slot}`, () => json(`${ORIGIN}/auth/v1/admin/users/${actor.id}`, {
            method: 'PUT', scope: 'admin', body: { ban_duration: '876000h' } }));
        } catch { failures.push('ban'); }
      }
      check(failures.length === 0, 'F1_AUTH_FINALIZATION_UNCERTAIN');
    },
    async verifyFinalization(ctx, privateDirectory) {
      finalizing = true;
      current = await privateRead(join(privateDirectory, 'manifest.private.json'));
      sqlManifestF1(current); check(current.sql.runId === ctx.run && current.sql.sourceSha === ctx.sha, 'F1_FINALIZE_OWNERSHIP');
      const row = await query(reconcileSqlF1(current), true);
      // Partial preparation can legitimately have fewer than three users; any
      // remaining one must still be exactly owned and banned, with zero sessions.
      const planned = new Set([...current.members, current.admin].map(x => x.id));
      check(Array.isArray(row.actors) && row.actors.every(x => planned.has(x.id) && x.owned === true && x.banned === true)
        && row.sessions === 0 && row.adminActive === 0, 'F1_AUTH_FINALIZATION_NOT_PROVEN');
      if (current.snapshots.financeDigest) {
        check(row.financeDigest === current.snapshots.financeDigest && row.versionsDigest === current.snapshots.versionsDigest && row.commissionsDigest===current.snapshots.commissionsDigest && row.invoiceAuditDigest===current.snapshots.invoiceAuditDigest, 'F1_RETAINED_ARCHIVES_CHANGED');
        validateReconciliationF1(row,current,'replacement');
      }
      await catalogue();
      return { owned_auth_banned: row.actors.length, sessions: 0, active_admin: 0, financial_retention: !!current.snapshots.financeDigest };
    },
  };
  return adapter;
}
