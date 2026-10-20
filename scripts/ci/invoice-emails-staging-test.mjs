// SOURCE ONLY until --execute and a separately reviewed, fresh public contract.
import { readFileSync, writeFileSync, openSync, closeSync, fsyncSync, realpathSync } from 'node:fs';
import { createHash, webcrypto } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { resolve, dirname, isAbsolute } from 'node:path';

const PROJECT = 'mejpriaetwgtcstbgfid';
const STAGE = `https://${PROJECT}.supabase.co`, API = `https://api.supabase.com/v1/projects/${PROJECT}`;
const APP = 'http://127.0.0.1:8085';
const E = 'fcaa6c97-46c1-4da9-8f74-1395aed616c5', S = 'abba3c93-5408-47bf-96e3-0864c7de3cb7';
const UUID = /^[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/;
const QUEUE_HELPER = 'supabase/functions/_shared/facturation-email-queue.ts';
const ADMISSION_HELPER = 'supabase/functions/_shared/invoice-email-staging-test.ts';
const ENTRY = 'supabase/functions/send-email/index.ts';
const ANCHOR_SUBJECT = '[TEST] Ancre de tentative de transport';
const sha = value => createHash('sha256').update(value).digest('hex');
const canonical = value => Array.isArray(value) ? value.map(canonical) : value && typeof value === 'object'
  ? Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])])) : value;
const same = (a, b) => JSON.stringify(canonical(a)) === JSON.stringify(canonical(b));
const digest = value => typeof value === 'string' && /^[a-f0-9]{64}$/.test(value) && !/^0+$/.test(value);
class Refusal extends Error { constructor(code) { super(code); this.code = code; } }
const must = (condition, code) => { if (!condition) throw new Refusal(code); };
const file = path => { must(isAbsolute(path), 'ABSOLUTE_PATH_REQUIRED'); return readFileSync(path, 'utf8'); };
const publicJson = path => JSON.parse(file(path));
const git = (cwd, args) => execFileSync('git', args, { cwd, stdio: ['ignore', 'pipe', 'pipe'], encoding: 'utf8', timeout: 10_000, maxBuffer: 4 * 1024 * 1024 });

const readbackSql = (F, H, M, EVENTS) => `BEGIN READ ONLY;
SELECT jsonb_build_object(
 'read_only',current_setting('transaction_read_only')='on',
 'recorded_at',clock_timestamp(),
 'active_crons',(SELECT count(*) FROM cron.job WHERE active),
 'running_crons',(SELECT count(*) FROM cron.job_run_details WHERE end_time IS NULL AND status IN ('starting','running','connecting','sending')),
 'network_queue',(SELECT count(*) FROM net.http_request_queue),
 'receipt_count',(SELECT count(*) FROM private.facturation_email_livraisons WHERE (famille='COMMISSION' AND document_id='${F}'::uuid) OR (famille='HONORAIRES' AND document_id='${H}'::uuid)),
 'honoraires',(SELECT jsonb_build_object('id',id,'statut',statut,'type_document',type_document,'nature_correction',nature_correction,'est_facture_finale_mission',est_facture_finale_mission,'etablissement_id',etablissement_id,'soignant_id',soignant_id,'mission_id',mission_id,'pdf_s3_key',pdf_s3_key,'facturx_xml_url',facturx_xml_url,'emise_le',emise_le,'stripe_payment_intent_id',stripe_payment_intent_id,'date_paiement',date_paiement) FROM public.factures_honoraires WHERE id='${H}'::uuid),
 'invoice',(SELECT jsonb_build_object('id',id,'statut',statut,'type_document',type_document,'montant_ttc',montant_ttc,'montant_a_payer',montant_a_payer,'montant_avoirs_imputes',montant_avoirs_imputes,'rapprochement',rapprochement_paiement_requis,'etablissement_id',etablissement_id,'stripe_payment_intent_id',stripe_payment_intent_id,'date_paiement',date_paiement,'mission_id',mission_id,'facture_honoraire_id',facture_honoraire_id) FROM public.factures WHERE id='${F}'::uuid),
 'mission',(SELECT jsonb_build_object('id',id,'statut',statut,'type_contrat',type_contrat_applique,'facture_id',facture_id,'etablissement_id',etablissement_id,'soignant_id',soignant_assigne_id) FROM public.missions WHERE id='${M}'::uuid),
 'receipts',(SELECT jsonb_agg(jsonb_build_object(
   'id',l.email_id,'family',l.famille,'document_id',l.document_id,'recipient_id',l.destinataire_id,'event',l.evenement,
   'key',l.idempotency_key,'body',l.corps,'attempts',l.tentatives,'first_attempt',l.premiere_tentative_le,'reservation',l.reservation,
   'queue_type',q.type,'queue_recipient',q.destinataire_id,'queue_body',q.data,'status',q.statut,'sent',q.envoye,'sent_at',q.envoye_le,
   'dispatch',(SELECT to_jsonb(d) FROM private.email_dispatch_idempotency d WHERE d.idempotency_key=l.idempotency_key),
   'traces',(SELECT coalesce(jsonb_agg(jsonb_build_object('provider_id',x.provider_id,'status',x.statut,'recipient_id',x.destinataire_id,'recipient_email',x.destinataire_email,'type',x.type,'key',x.idempotency_key,'created_at',x.cree_le,'subject',x.sujet)),'[]'::jsonb) FROM public.emails_envoyes x WHERE x.idempotency_key=l.idempotency_key)
 ) ORDER BY l.evenement) FROM private.facturation_email_livraisons l JOIN public.email_queue q ON q.id=l.email_id
 WHERE l.email_id IN (${EVENTS.map(event => `'${event.id}'::uuid`).join(',')}))
) AS evidence;
ROLLBACK;`;

function sourceClosure(checkout, name, pins = {}) {
  if (pins[name]) return pins;
  const absolute = realpathSync(resolve(checkout, name));
  must(absolute.startsWith(`${realpathSync(checkout)}/supabase/functions/`), 'SOURCE_PATH_REFUSED');
  const source = readFileSync(absolute, 'utf8'); pins[name] = sha(source);
  for (const match of source.matchAll(/(?:from\s*|import\s*)['"]([^'"]+)['"]/g)) {
    if (!match[1].startsWith('.')) continue;
    const child = resolve(dirname(absolute), match[1]);
    must(child.endsWith('.ts'), 'LOCAL_IMPORT_REFUSED');
    sourceClosure(checkout, child.slice(realpathSync(checkout).length + 1), pins);
  }
  return pins;
}

async function stdinCredential() {
  must(!process.stdin.isTTY, 'CREDENTIAL_STDIN_REQUIRED');
  let text = ''; for await (const chunk of process.stdin) { text += chunk; must(Buffer.byteLength(text) <= 16384, 'CREDENTIAL_INPUT_REFUSED'); }
  let input; try { input = JSON.parse(text); } catch { throw new Refusal('CREDENTIAL_INPUT_REFUSED'); }
  must(input && Object.keys(input).length === 1 && typeof input.managementToken === 'string'
    && input.managementToken.length > 20 && !/\s/.test(input.managementToken), 'CREDENTIAL_INPUT_REFUSED');
  const token = input.managementToken; text = ''; input.managementToken = ''; return token;
}

async function main(contractPath) {
  const contract = publicJson(contractPath);
  must(contract.schemaVersion === 1 && contract.ready === true && contract.project === PROJECT
    && typeof contract.checkout === 'string' && isAbsolute(contract.checkout)
    && typeof contract.intentPath === 'string' && isAbsolute(contract.intentPath)
    && /^[a-f0-9]{40}$/.test(contract.targetSha || '')
    && digest(contract.runtimeSha256) && digest(contract.sourceAttestationSha256), 'REVIEWED_CONTRACT_REQUIRED');
  const checkout = contract.checkout;
  must(git(checkout, ['rev-parse', 'HEAD']).trim() === contract.targetSha
    && !git(checkout, ['status', '--porcelain', '--untracked-files=no']).trim(), 'EXACT_CLEAN_TARGET_REQUIRED');
  const runtimeRaw = file(contract.runtimePath).trim(), runtime = JSON.parse(runtimeRaw);
  must(sha(runtimeRaw) === contract.runtimeSha256 && runtime.serverSha === contract.targetSha
    && runtime.manifestSha256 === sha(file(contract.activationManifestPath))
    && [runtime.missionId, runtime.honorairesId, runtime.commissionId].every(id => typeof id === 'string' && UUID.test(id))
    && new Set([runtime.missionId, runtime.honorairesId, runtime.commissionId]).size === 3
    && Date.now() - Date.parse(runtime.createdAt) >= 0 && Date.now() - Date.parse(runtime.createdAt) <= 5 * 60_000
    && Date.parse(runtime.expiresAt) - Date.now() >= 5 * 60_000, 'FRESH_RUNTIME_REQUIRED');
  const F = runtime.commissionId, H = runtime.honorairesId, M = runtime.missionId;
  must(Array.isArray(runtime.events) && runtime.events.length === 3, 'EXACT_EVENTS_REQUIRED');
  const scopes = [['HONORAIRES', 'SOIGNANT', S, H], ['HONORAIRES', 'ETABLISSEMENT', E, H], ['COMMISSION', 'ETABLISSEMENT', E, F]];
  const EVENTS = scopes.map(([family, role, recipientId, documentId], i) => {
    const event = runtime.events[i];
    must(event?.family === family && event.recipientRole === role && UUID.test(event.emailId || ''), 'EXACT_EVENTS_REQUIRED');
    return { id: event.emailId, type: 'FACTURE_EMISE', event: 'EMISSION', family, role, recipientId, documentId,
      key: family === 'HONORAIRES' ? `facture-emise-${role.toLowerCase()}:${documentId}` : `facture-emise-commission:${F}:${E}` };
  });
  must(new Set(EVENTS.map(event => event.id)).size === 3, 'EXACT_EVENTS_REQUIRED');
  const attestationRaw = file(contract.sourceAttestationPath), attestation = JSON.parse(attestationRaw);
  const pins = sourceClosure(checkout, ENTRY);
  must(sha(attestationRaw) === contract.sourceAttestationSha256 && attestation.project === PROJECT
    && attestation.targetSha === contract.targetSha && attestation.allExact === true
    && attestation.method === 'Supabase Management API GET /v1/projects/{project}/functions/send-email/body'
    && same(attestation.sourcePins, pins), 'OFFICIAL_SOURCE_ATTESTATION_REQUIRED');
  must(digest(contract.queueHelperSha256) && sha(readFileSync(resolve(checkout, QUEUE_HELPER))) === contract.queueHelperSha256,
    'QUEUE_HELPER_PIN_REQUIRED');
  for (const [name, hash] of Object.entries({ ...pins, [QUEUE_HELPER]: contract.queueHelperSha256 })) {
    must(sha(git(checkout, ['show', `${contract.targetSha}:${name}`])) === hash, 'COMMITTED_SOURCE_PIN_REQUIRED');
  }
  const require = createRequire(resolve(checkout, 'package.json'));
  const ts = require('typescript');
  const moduleUrls = new Map();
  const moduleUrl = name => {
    if (moduleUrls.has(name)) return moduleUrls.get(name);
    let source = readFileSync(resolve(checkout, name), 'utf8');
    for (const match of [...source.matchAll(/from\s*['"]([^'"]+)['"]/g)]) {
      if (!match[1].startsWith('.')) continue;
      const child = resolve(checkout, dirname(name), match[1]).slice(realpathSync(checkout).length + 1);
      source = source.replaceAll(`'${match[1]}'`, `'${moduleUrl(child)}'`).replaceAll(`"${match[1]}"`, `"${moduleUrl(child)}"`);
    }
    const compiled = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 }, reportDiagnostics: true });
    must(!compiled.diagnostics?.length, 'HELPER_SYNTAX_REFUSED');
    const url = `data:text/javascript;base64,${Buffer.from(compiled.outputText).toString('base64')}`;
    moduleUrls.set(name, url); return url;
  };
  globalThis.crypto ??= webcrypto;
  const { traiterEmailFacturation } = await import(moduleUrl(QUEUE_HELPER));
  const { invoiceEmailStagingConfig, invoiceEmailBodySha256, stagingInvoiceEmailScope, admitStagingInvoiceEmail } = await import(moduleUrl(ADMISSION_HELPER));
  const localEnv = { SUPABASE_URL: STAGE, SUPABASE_ENV: 'staging', APP_URL: APP, INVOICE_EMAIL_STAGING_TEST_RUN: runtimeRaw };
  const get = key => localEnv[key];
  must(invoiceEmailStagingConfig(get)?.events.every((event, i) => event.emailId === EVENTS[i].id && event.family === EVENTS[i].family && event.recipientRole === EVENTS[i].role), 'EXACT_EVENTS_REQUIRED');

  let managementToken = await stdinCredential(), serviceKey;
  const request = async (url, options = {}) => {
    let response; try { response = await fetch(url, { ...options, redirect: 'error', signal: AbortSignal.timeout(20_000) }); }
    catch { throw new Refusal('HTTP_RESULT_UNCERTAIN'); }
    must(response.ok && !response.redirected, 'HTTP_REFUSED');
    const text = await response.text(); must(Buffer.byteLength(text) <= 2 * 1024 * 1024, 'HTTP_SIZE_REFUSED');
    try { return JSON.parse(text); } catch { throw new Refusal('HTTP_JSON_REFUSED'); }
  };
  const mgmt = (suffix, body) => request(API + suffix, { method: body ? 'POST' : 'GET',
    headers: { Authorization: `Bearer ${managementToken}`, 'Content-Type': 'application/json' }, ...(body ? { body: JSON.stringify(body) } : {}) });
  const project = await mgmt('');
  must(project.id === PROJECT && project.status === 'ACTIVE_HEALTHY' && project.database?.host === `db.${PROJECT}.supabase.co`, 'STAGING_PROJECT_REQUIRED');
  const verifyDeployment = async () => {
    const functions = await mgmt('/functions');
    const matches = functions.filter(row => row.slug === 'send-email');
    const current = matches[0], expected = attestation.function;
    must(matches.length === 1 && expected?.slug === 'send-email' && expected.status === 'ACTIVE'
      && expected.verifyJwt === false && current.id === expected.id
      && current.version === expected.version && current.status === 'ACTIVE' && current.verify_jwt === false
      && digest(current.ezbr_sha256) && current.ezbr_sha256 === expected.ezbrSha256, 'DEPLOYMENT_DRIFT');
    const secrets = await mgmt('/secrets'); must(Array.isArray(secrets), 'SECRETS_METADATA_REFUSED');
    must(!secrets.some(row => ['HONORAIRES_STAGING_TEST_RUN', 'INVOICE_STAGING_TEST_RUN', 'CONNECT_STAGING_TEST_RUN', 'SIGNATURE_SMS_STAGING_TEST_RUN'].includes(row.name)), 'OTHER_CAPACITY_STILL_OPEN');
    const publicValueMatches = (name, value) => {
      const rows = secrets.filter(row => row.name === name); if (rows.length !== 1) return false;
      // Only these two PUBLIC values are compared/hashed; no key digest is emitted.
      return rows[0].digest === sha(value) || rows[0].value === sha(value) || rows[0].value === value;
    };
    must(publicValueMatches('APP_URL', APP) && publicValueMatches('INVOICE_EMAIL_STAGING_TEST_RUN', runtimeRaw)
      && secrets.filter(row => row.name === 'RESEND_API_KEY').length === 1, 'STAGING_RUNTIME_NOT_CONFIRMED');
    must(invoiceEmailStagingConfig(get), 'CAPACITY_NOT_ACTIVE');
  };
  await verifyDeployment();
  const keys = await mgmt('/api-keys');
  const matches = keys.filter(row => row.name === 'service_role');
  must(matches.length === 1 && typeof matches[0].api_key === 'string' && matches[0].api_key.length > 20, 'STAGING_SERVICE_KEY_REQUIRED');
  serviceKey = matches[0].api_key; for (const row of keys) if ('api_key' in row) row.api_key = '';
  const snapshot = async () => {
    const result = await mgmt('/database/query', { query: readbackSql(F, H, M, EVENTS), read_only: true });
    must(Array.isArray(result) && result.length === 1 && result[0]?.evidence, 'READBACK_SHAPE_REFUSED');
    const state = result[0].evidence;
    must(state.read_only === true && state.active_crons === 0 && state.running_crons === 0 && state.network_queue === 0
      && Math.abs(Date.now() - Date.parse(state.recorded_at)) < 60_000 && state.receipt_count === 3, 'STAGE_NOT_QUIET');
    must(state.invoice?.id === F && state.invoice.etablissement_id === E && state.invoice.statut === 'EMISE'
      && state.invoice.type_document === 'FACTURE' && state.invoice.mission_id === M && state.invoice.facture_honoraire_id === H
      && state.invoice.stripe_payment_intent_id === null && state.invoice.date_paiement === null
      && state.honoraires?.id === H && state.honoraires.etablissement_id === E && state.honoraires.soignant_id === S
      && state.honoraires.mission_id === M && state.honoraires.statut === 'EMISE' && state.honoraires.type_document === 'FACTURE'
      && state.honoraires.nature_correction === 'ORIGINALE' && state.honoraires.est_facture_finale_mission === true
      && !!state.honoraires.pdf_s3_key && !!state.honoraires.facturx_xml_url && !!state.honoraires.emise_le
      && state.honoraires.stripe_payment_intent_id === null && state.honoraires.date_paiement === null
      && state.mission?.id === M && state.mission.etablissement_id === E
      && state.mission.soignant_id === S && state.mission.statut === 'TERMINEE' && state.mission.type_contrat === 'LIBERAL'
      && Array.isArray(state.receipts) && state.receipts.length === 3, 'DOCUMENT_SCOPE_DRIFT');
    for (const [i, event] of EVENTS.entries()) {
      const rows = state.receipts.filter(row => row.id === event.id), row = rows[0];
      must(rows.length === 1 && row.family === event.family && row.document_id === event.documentId && row.recipient_id === event.recipientId
        && row.event === event.event && row.key === event.key && row.body.type === event.type
        && row.queue_type === 'FACTURATION_DOCUMENT' && row.queue_recipient === event.recipientId && same(row.body, row.queue_body)
        && await invoiceEmailBodySha256(row.body) === runtime.events[i].bodySha256, 'RECEIPT_DRIFT');
    }
    return state;
  };
  const receipt = (state, index) => state.receipts.find(row => row.id === EVENTS[index].id);
  const untouched = row => row.status === 'EN_ATTENTE' && row.sent === false && row.sent_at === null
    && row.attempts === 0 && row.first_attempt === null && row.reservation === null && row.dispatch === null
    && Array.isArray(row.traces) && row.traces.length === 0;
  const initial = await snapshot(); must(EVENTS.every((_, i) => untouched(receipt(initial, i))), 'PREVIOUS_ATTEMPT_REQUIRES_RECONCILIATION');

  const report = { schemaVersion: 1, project: PROJECT, targetSha: contract.targetSha, runtimeSha256: contract.runtimeSha256,
    status: 'PREFLIGHT_PASSED', recordedAt: new Date().toISOString(), anchorInsertions: 0, anchorsPrepared: 0,
    reservations: 0, transportCalls: 0, acknowledgements: 0,
    anchorOnlyRowsAreProviderSuccess: false, stageRawEmail24hCounterIncludesAnchors: true,
    ambiguous: false, receiptVerifiedInInbox: false, paymentCreated: false, invoiceCreated: false, events: [] };
  const intentPath = contract.intentPath;
  const descriptor = openSync(intentPath, 'wx', 0o600);
  const save = () => { writeFileSync(intentPath, JSON.stringify(report, null, 2) + '\n', { mode: 0o600 }); const fd = openSync(intentPath, 'r'); fsyncSync(fd); closeSync(fd); };
  fsyncSync(descriptor); closeSync(descriptor); save();
  const { createClient } = require('@supabase/supabase-js');
  const allowedRpc = new Set(['fn_reserver_email_facturation', 'fn_acquitter_email_facturation']);
  const readTables = new Set(['email_queue','factures','factures_honoraires','missions','soignants','etablissements','emails_envoyes']);
  const scopedFetch = async (input, options) => {
    const url = new URL(typeof input === 'string' || input instanceof URL ? String(input) : input.url);
    const method = options?.method || (typeof input === 'object' && 'method' in input ? input.method : 'GET');
    const anchorPost = method === 'POST' && url.pathname === '/rest/v1/emails_envoyes';
    if (anchorPost) {
      let row; try { row = JSON.parse(options.body); } catch { throw new Refusal('ANCHOR_BODY_REFUSED'); }
      must(row && !Array.isArray(row)
        && Object.keys(row).sort().join(',') === 'destinataire_email,destinataire_id,idempotency_key,provider_id,statut,sujet,type'
        && row.idempotency_key === EVENTS[activeIndex]?.key && row.type === EVENTS[activeIndex]?.type
        && row.destinataire_id === EVENTS[activeIndex]?.recipientId && row.destinataire_email === 'gabrielle@jolene.app'
        && row.sujet === ANCHOR_SUBJECT && row.statut === 'ERREUR' && row.provider_id === null
        && url.searchParams.get('on_conflict') === 'idempotency_key'
        && new Headers(options.headers).get('Prefer')?.includes('resolution=ignore-duplicates'), 'ANCHOR_BODY_REFUSED');
    }
    must(url.origin === STAGE && ((method === 'POST' && (anchorPost || url.pathname === '/functions/v1/send-email'
      || allowedRpc.has(url.pathname.replace('/rest/v1/rpc/', ''))))
      || (method === 'GET' && (readTables.has(url.pathname.replace('/rest/v1/', ''))
        || [E, S].some(id => url.pathname === `/auth/v1/admin/users/${id}`)))), 'TRANSPORT_SCOPE_REFUSED');
    return fetch(input, { ...options, redirect: 'error', signal: AbortSignal.timeout(20_000) });
  };
  const sb = createClient(STAGE, serviceKey, { auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false }, global: { fetch: scopedFetch } });
  const reservations = new Map(), anchors = new Map(); let activeIndex = -1;
  const onlyAnchor = (row, index) => row.traces.length === 1 && row.traces[0].key === EVENTS[index].key
    && row.traces[0].type === EVENTS[index].type && row.traces[0].recipient_id === EVENTS[index].recipientId
    && row.traces[0].recipient_email === 'gabrielle@jolene.app' && row.traces[0].status === 'ERREUR'
    && row.traces[0].provider_id === null && row.traces[0].subject === ANCHOR_SUBJECT
    && row.traces[0].created_at === anchors.get(EVENTS[index].id);
  const rpcClient = { async rpc(name, args) {
    must(allowedRpc.has(name) && args.p_email_id === EVENTS[activeIndex]?.id, 'RPC_SCOPE_REFUSED');
    if (name === 'fn_reserver_email_facturation') { report.reservations++; must(report.reservations <= 3, 'EXTRA_RESERVATION_REFUSED'); }
    else report.acknowledgements++;
    report.status = name === 'fn_reserver_email_facturation' ? 'RESERVATION_ATTEMPTED' : 'ACKNOWLEDGEMENT_ATTEMPTED'; save();
    const result = await sb.rpc(name, args);
    if (result.error) { report.ambiguous = true; save(); return { data: null, error: new Error('RECEIPT_RPC_UNCERTAIN') }; }
    if (name === 'fn_reserver_email_facturation') {
      must(result.data?.statut === 'RESERVE' && typeof result.data.reservation === 'string', 'RESERVATION_NOT_FRESH');
      reservations.set(args.p_email_id, result.data.reservation);
    }
    return result;
  } };
  try {
    for (const [index, event] of EVENTS.entries()) {
      activeIndex = index; await verifyDeployment();
      const before = await snapshot(); must(untouched(receipt(before, index)), 'TARGET_ALREADY_ATTEMPTED');
      for (let prior = 0; prior < index; prior++) {
        const done = receipt(before, prior);
        must(done.status === 'ENVOYE' && done.attempts === 1 && done.reservation === null
          && done.dispatch?.statut === 'ENVOYE' && done.traces.length === 1
          && sha(done.dispatch.provider_id) === report.events[prior].providerIdSha256, 'COMPLETED_RECEIPT_DRIFT');
      }
      // Toute la source est contrôlée avant cet effet de bord TEST volontaire.
      const expectedBody = receipt(before, index).body;
      const source = await stagingInvoiceEmailScope(sb, { ...expectedBody, idempotency_key: event.key }, true, get);
      must(source?.emailId === event.id && source.key === event.key, 'ANCHOR_SOURCE_REFUSED');
      const virgin = receipt(await snapshot(), index); must(untouched(virgin), 'ANCHOR_REQUIRES_VIRGIN_LEDGER');
      report.status = 'ANCHOR_INSERTION_ATTEMPTED'; report.anchorInsertions++; save();
      const anchor = { idempotency_key: event.key, destinataire_id: event.recipientId, destinataire_email: source.recipient,
        type: event.type, sujet: ANCHOR_SUBJECT, statut: 'ERREUR', provider_id: null };
      // DEFAULT serveur pour cree_le ; une réponse perdue ferme le run.
      let prepared;
      try { prepared = await sb.from('emails_envoyes').upsert(anchor, { onConflict: 'idempotency_key', ignoreDuplicates: true }); }
      catch { report.ambiguous = true; save(); throw new Refusal('ANCHOR_INSERTION_UNCERTAIN'); }
      if (prepared.error) { report.ambiguous = true; save(); throw new Refusal('ANCHOR_INSERTION_UNCERTAIN'); }
      const anchored = receipt(await snapshot(), index);
      must(anchored.traces.length === 1 && typeof anchored.traces[0].created_at === 'string', 'ANCHOR_READBACK_REQUIRED');
      anchors.set(event.id, anchored.traces[0].created_at);
      must(onlyAnchor(anchored, index) && anchored.status === 'EN_ATTENTE' && anchored.attempts === 0
        && anchored.dispatch === null && anchored.reservation === null
        && Math.abs(Date.now() - Date.parse(anchored.traces[0].created_at)) < 60_000, 'ANCHOR_NOT_RECONCILED');
      must(await admitStagingInvoiceEmail(sb, { ...expectedBody, idempotency_key: event.key }, true, get), 'ANCHOR_ADMISSION_REFUSED');
      report.anchorsPrepared++; report.status = 'ANCHOR_CONFIRMED_WITHOUT_PROVIDER'; save();
      const outcome = await traiterEmailFacturation(rpcClient, event.id, async (body, key) => {
        must(key === event.key && await invoiceEmailBodySha256(body) === runtime.events[index].bodySha256, 'RESERVED_BODY_DRIFT');
        await verifyDeployment(); const reserved = receipt(await snapshot(), index);
        must(reserved.status === 'EN_ATTENTE' && reserved.attempts === 1 && reserved.reservation === reservations.get(event.id)
          && reserved.dispatch === null && onlyAnchor(reserved, index), 'RESERVATION_DRIFT');
        must(await admitStagingInvoiceEmail(sb, { ...body, idempotency_key: key }, true, get), 'ADMISSION_REFUSED');
        report.status = 'TRANSPORT_ATTEMPTED'; report.transportCalls++; must(report.transportCalls <= 3, 'EXTRA_TRANSPORT_REFUSED'); save();
        const { data, error } = await sb.functions.invoke('send-email', { body: { ...body, idempotency_key: key } });
        if (error || !data || data.success !== true || data.pending || data.skipped) { report.ambiguous = true; save(); return 'pending'; }
        return 'sent';
      });
      must(outcome === 'envoye' && !report.ambiguous, 'STOP_FOR_MANUAL_RECONCILIATION');
      const after = await snapshot(), row = receipt(after, index);
      const fingerprint = await invoiceEmailBodySha256({ type: row.body.type, destinataire_id: event.recipientId,
        destinataire_email: 'gabrielle@jolene.app', data: row.body.data });
      must(row.status === 'ENVOYE' && row.sent === true && !!row.sent_at && row.attempts === 1 && row.reservation === null
        && row.dispatch?.statut === 'ENVOYE' && row.dispatch.request_fingerprint === fingerprint
        && typeof row.dispatch.provider_id === 'string' && row.dispatch.provider_id.length > 5
        && row.traces.length === 1 && row.traces[0].provider_id === row.dispatch.provider_id
        && row.traces[0].created_at === anchors.get(event.id)
        && row.traces[0].recipient_id === event.recipientId && row.traces[0].recipient_email === 'gabrielle@jolene.app'
        && row.traces[0].type === event.type && row.traces[0].key === event.key
        && ['ENVOYE','DELIVRE','OUVERT'].includes(row.traces[0].status), 'ACCEPTANCE_NOT_RECONCILED');
      report.events.push({ type: event.type, family: event.family, recipientRole: event.role, queueIdSha256: sha(event.id), bodySha256: runtime.events[index].bodySha256,
        idempotencyKeySha256: sha(event.key), providerIdSha256: sha(row.dispatch.provider_id), providerAccepted: true, queueAcknowledged: true });
      must(new Set(report.events.map(item => item.providerIdSha256)).size === report.events.length, 'PROVIDER_ID_REUSED');
      report.status = 'EVENT_RECONCILED'; save();
    }
    report.status = 'PROVIDER_ACCEPTED_AWAITING_INBOX_PROOF'; report.completedAt = new Date().toISOString(); save();
    process.stdout.write(JSON.stringify(report) + '\n');
  } catch (error) {
    report.status = 'STOPPED_NO_AUTOMATIC_RETRY'; report.code = error instanceof Refusal ? error.code : 'RUNNER_STOPPED';
    report.ambiguous = report.ambiguous || report.transportCalls > report.events.length
      || report.anchorInsertions > report.anchorsPrepared; save();
    process.stdout.write(JSON.stringify(report) + '\n'); process.exitCode = 1;
  } finally { managementToken = ''; serviceKey = ''; }
}

if (process.argv.length !== 4 || process.argv[2] !== '--execute') {
  process.stdout.write('SOURCE_ONLY_CLOSED: no remote call without --execute and a reviewed fresh contract.\n');
} else {
  main(process.argv[3]).catch(error => {
    process.stdout.write(JSON.stringify({ status: 'REFUSED_BEFORE_COMPLETION', code: error instanceof Refusal ? error.code : 'RUNNER_STOPPED', receiptVerifiedInInbox: false }) + '\n');
    process.exitCode = 1;
  });
}
