import assert from 'node:assert/strict';
import test from 'node:test';
import type { SupabaseClient } from '@supabase/supabase-js';
import { availability, parsePresenceCode, PRESENCE_STAGING_ORIGIN } from './business';
import { SupabasePresenceGateway } from './supabaseGateway';
import { createPresenceServerClock } from './serverClock';
import { createPresenceAttemptJournal } from './attemptJournal';
import type { PresenceContext, PresenceMission, PresenceProof, PresenceSegment, PresenceAttemptReceipt } from './types';

const ids = {
  user: '10000000-0000-4000-8000-000000000001', other: '10000000-0000-4000-8000-000000000002',
  etab: '20000000-0000-4000-8000-000000000001', admin: '20000000-0000-4000-8000-000000000002',
  missionA: '30000000-0000-4000-8000-000000000001', missionB: '30000000-0000-4000-8000-000000000002',
  planned: '40000000-0000-4000-8000-000000000001', effective: '40000000-0000-4000-8000-000000000002',
  proof: '50000000-0000-4000-8000-000000000001', prior: '50000000-0000-4000-8000-000000000002',
  contract: '60000000-0000-4000-8000-000000000001', attempt: '70000000-0000-4000-8000-000000000001',
};
const serverTime = '2026-10-27T10:00:00.000Z';
const caregiver: PresenceContext = { kind: 'soignant', userId: ids.user, epoch: 1 };
const employer: PresenceContext = { kind: 'etablissement', userId: ids.admin, etablissementId: ids.etab, epoch: 2 };
const mission = (id = ids.missionA): PresenceMission => ({ id, etablissement_id: ids.etab, soignant_assigne_id: ids.user,
  intitule: id === ids.missionA ? 'Mission A fictive' : 'Mission B fictive', service: 'Recette', statut: 'EN_COURS',
  debut_le: '2026-10-27T10:00:00.000Z', fin_le: '2026-10-27T18:00:00.000Z', nb_creneaux: 1 });
const planned = (id = ids.missionA): PresenceSegment => ({ id: ids.planned, mission_id: id,
  debut: '2026-10-27T10:00:00.000Z', fin: '2026-10-27T18:00:00.000Z', est_pause: false, type_creneau: 'PREVISIONNEL' });
const effective = (id = ids.missionA): PresenceSegment => ({ id: ids.effective, mission_id: id,
  debut: serverTime, fin: null, est_pause: false, type_creneau: 'EFFECTIF' });
const proof = (id = ids.missionA): PresenceProof => ({ id: ids.proof, mission_id: id, soignant_id: ids.user,
  numero_scan: 1, type_scan: 'OUVERTURE', scanne_le: serverTime, horodatage_arrondi: serverTime,
  creneau_effectif_id: ids.effective, validation_etab_requise: false, valide_par_etab: false });

interface QuerySpec {
  source: string; args?: Record<string, unknown>; projection?: string; filters: Record<string, unknown>;
  range?: [number, number]; single?: boolean; count?: boolean; signal?: AbortSignal; authorization?: string; retry?: boolean;
}
function fixture() {
  const secure = new Map<string, string>();
  const storageState = { failReadAfterSet: false, nextReadFails: false, failDelete: false, failAllRead: false, failReadAfterDelete: false,
    failReadForPhase: null as PresenceAttemptReceipt['phase'] | null,
    failSetForPhase: null as PresenceAttemptReceipt['phase'] | null,
    afterSet: null as (() => void) | null, afterDelete: null as (() => void) | null };
  const storage = {
    async getItemAsync(key: string) {
      if (storageState.nextReadFails || storageState.failAllRead) { storageState.nextReadFails = false; throw new Error('Keychain read failure'); }
      return secure.get(key) ?? null;
    },
    async setItemAsync(key: string, value: string) {
      const phase = (JSON.parse(value) as PresenceAttemptReceipt).phase;
      if (storageState.failSetForPhase === phase) throw new Error('Keychain write failure');
      secure.set(key, value);
      if (storageState.failReadAfterSet || storageState.failReadForPhase === phase) storageState.nextReadFails = true;
      storageState.afterSet?.();
    },
    async deleteItemAsync(key: string) { if (storageState.failDelete) throw new Error('Keychain delete failure'); secure.delete(key);
      storageState.afterDelete?.();
      if (storageState.failReadAfterDelete) storageState.nextReadFails = true; },
  };
  const env = {
    current: { ...caregiver } as PresenceContext | null, userId: ids.user, token: 'fixture-access-A', confirmed: true,
    role: 'SOIGNANT', test: true, consent: false, displayCode: true, lecture: true, readContracts: true,
    origin: PRESENCE_STAGING_ORIGIN, rows: [mission()] as PresenceMission[], segments: [planned()] as PresenceSegment[],
    proofs: [] as PresenceProof[], target: ids.missionA, commit: true, loseResponse: false, sqlError: null as string | null,
    rpcCalls: [] as QuerySpec[], queries: [] as QuerySpec[], afterRpc: null as (() => void) | null,
    pauseRpc: null as Promise<void> | null, afterBaseline: null as (() => void) | null,
    pageCap: 100, wrongProofOwner: false, clockFails: false, rawCodeForCaregiver: false,
    scanType: 'OUVERTURE' as 'OUVERTURE' | 'FERMETURE',
    contractError: false, caregiverEstEtab: null as unknown,
    signedForPointage: true as unknown, eligibilityError: false,
  };
  const commit = () => {
    if (!env.proofs.some(row => row.id === ids.proof)) env.proofs.push({ ...proof(env.target), type_scan: env.scanType });
    if (!env.segments.some(row => row.id === ids.effective)) env.segments.push(effective(env.target));
    if (env.scanType === 'FERMETURE') {
      const segment = env.segments.find(row => row.id === ids.effective)!;
      segment.debut = '2026-10-27T09:00:00.000Z'; segment.fin = serverTime;
    }
  };
  async function execute(query: QuerySpec) {
    env.queries.push(query);
    if (query.signal?.aborted) throw Object.assign(new Error('cancelled'), { name: 'AbortError' });
    assert.equal(query.authorization, 'Bearer fixture-access-A', 'each query uses the captured JWT');
    if (query.source === 'fn_get_my_role') return { data: { role: env.role }, error: null };
    if (query.source === 'fn_contrat_signe_pour_pointage') {
      assert.deepEqual(query.args, { p_mission_id: ids.missionA });
      return { data: env.signedForPointage, error: env.eligibilityError ? { message: 'fixture unavailable' } : null };
    }
    if (query.source === 'contrats_mission' && env.contractError) return { data: null, count: null, error: { message: 'fixture unavailable' } };
    if (query.source === 'fn_mes_permissions_etab') return { data: { success: true, etablissement_id: ids.etab, role: 'RH' }, error: null };
    if (query.source === 'fn_a_permission_etablissement') return { data: query.args?.p_permission === 'lecture_pointage' ? env.lecture
      : query.args?.p_permission === 'pointage' ? env.displayCode : env.readContracts, error: null };
    if (query.source === 'fn_scanner_code_pointage') {
      assert.equal(query.retry, false);
      assert.equal(secure.size, 1, 'the durable journal must exist before network invocation');
      const receipt = JSON.parse([...secure.values()][0]); assert.equal(receipt.userId, ids.user); assert.equal(receipt.enteredCode, '123456');
      assert.equal(receipt.version, 2); assert.equal(receipt.phase, 'started', 'the started barrier must be durable before invocation');
      env.rpcCalls.push(query); if (env.pauseRpc) await env.pauseRpc;
      if (env.sqlError) return { data: null, error: { code: env.sqlError, message: 'fixture refusal' } };
      if (env.commit) commit(); env.afterRpc?.();
      if (env.loseResponse) throw new Error('response lost');
      return { data: { nouveau_code: '987654', nouveau_hmac: 'fixture-new-secret', creneau_effectif_id: ids.effective,
        type_scan_effectue: env.scanType, numero_scan: 1, horodatage_effectif: serverTime }, error: null };
    }
    if (query.source === 'fn_etat_pointage_mission') {
      const row = env.rows.find(item => item.id === query.args?.p_mission_id)!;
      const segments = env.segments.filter(item => item.mission_id === row.id && item.type_creneau === 'EFFECTIF');
      return { error: null, data: { statut: row.statut, intitule: row.intitule, prochain_type_scan: segments.some(item => !item.fin) ? 'FERMETURE' : 'OUVERTURE',
        nb_scans: env.proofs.length, segment_ouvert: segments.some(item => !item.fin), segments: segments.map(({ id, debut, fin }) => ({ id, debut, fin })),
        est_etab: env.current?.kind === 'etablissement' ? true : env.caregiverEstEtab,
        code_pointage_actif: env.current?.kind === 'etablissement' || env.rawCodeForCaregiver ? '123456' : null } };
    }
    let data: any[];
    if (query.source === 'soignants') data = [{ id: ids.user, est_compte_test: env.test, consentement_gps: env.consent }];
    else if (query.source === 'etablissements') data = [{ id: ids.etab, est_compte_test: env.test }];
    else if (query.source === 'missions') data = env.rows;
    else if (query.source === 'mission_creneaux') data = env.segments;
    else if (query.source === 'contrats_mission') data = [{ id: ids.contract, mission_id: ids.missionA,
      etablissement_id: ids.etab, soignant_id: ids.user, statut: 'SIGNE_COMPLET', cree_le: serverTime }];
    else if (query.source === 'scans_pointage') {
      assert.equal(query.filters.soignant_id, ids.user);
      assert.equal(query.filters.code_saisi, '123456'); assert.equal(query.filters.id_terminal, 'fixture-device');
      assert(!query.projection!.includes('code_saisi')); assert(!query.projection!.includes('latitude'));
      data = env.proofs.map(item => ({ ...item }));
      if (env.wrongProofOwner) data = data.map(item => ({ ...item, soignant_id: ids.other }));
      env.afterBaseline?.(); env.afterBaseline = null;
    } else throw new Error(`unexpected source ${query.source}`);
    data = data.filter(row => Object.entries(query.filters).every(([key, value]) =>
      ['code_saisi', 'id_terminal'].includes(key) || (Array.isArray(value) ? value.includes(row[key]) : row[key] === value)));
    const count = data.length;
    if (query.range) data = data.slice(query.range[0], Math.min(query.range[1] + 1, query.range[0] + env.pageCap));
    return { data: query.single ? data[0] ?? null : data, count: query.count ? count : null, error: null };
  }
  function builder(source: string, args?: Record<string, unknown>) {
    const query: QuerySpec = { source, args, filters: {} };
    const chain: any = {
      select(projection: string, options?: { count?: string }) { query.projection = projection; query.count = options?.count === 'exact'; return chain; },
      eq(key: string, value: unknown) { query.filters[key] = value; return chain; },
      in(key: string, value: unknown[]) { query.filters[key] = value; return chain; },
      order() { return chain; }, range(start: number, end: number) { query.range = [start, end]; return chain; },
      setHeader(key: string, value: string) { assert.equal(key, 'Authorization'); query.authorization = value; return chain; },
      abortSignal(signal: AbortSignal) { query.signal = signal; return chain; },
      retry(value: boolean) { query.retry = value; return chain; },
      maybeSingle() { query.single = true; return chain; },
      then(resolve: (value: unknown) => void, reject: (reason: unknown) => void) { return execute(query).then(resolve, reject); },
    };
    return chain;
  }
  const client = {
    storage: { from: (bucket: string) => ({ getPublicUrl: (key: string) => ({ data: { publicUrl: `${env.origin}/storage/v1/object/public/${bucket}/${key}` } }) }) },
    auth: { getSession: async () => ({ data: { session: { access_token: env.token, user: { id: env.userId } } }, error: null }),
      getUser: async (token: string) => { assert.equal(token, 'fixture-access-A'); return { data: { user: { id: env.userId,
        email_confirmed_at: env.confirmed ? serverTime : null } }, error: null }; } },
    from: (source: string) => builder(source), rpc: (source: string, args?: Record<string, unknown>) => builder(source, args),
  } as unknown as SupabaseClient;
  let gpsCalls = 0;
  const options = { currentSession: () => env.current, terminalId: 'fixture-device', newAttemptId: () => ids.attempt,
    journal: createPresenceAttemptJournal(storage),
    clock: { read: async () => { if (env.clockFails) throw new Error('offline'); return serverTime; } },
    gps: { locate: async () => { gpsCalls += 1; return { kind: 'denied' as const }; } } };
  return { env, client, options, gateway: new SupabasePresenceGateway(client, options), commit, gpsCalls: () => gpsCalls,
    secure, storage, storageState };
}

test('a six-digit QR is accepted; URLs or arbitrary digit extraction are not', () => {
  assert.equal(parsePresenceCode(' 123456 '), '123456');
  for (const code of ['https://example.test/123456', '12 34 56', '12345', '1234567']) assert.throws(() => parsePresenceCode(code));
});
test('existing planning, signed-contract and opening-window rules are reused; an open period can close', () => {
  const contracts = [{ id: ids.contract, mission_id: ids.missionA, etablissement_id: ids.etab, soignant_id: ids.user, statut: 'SIGNE_COMPLET', cree_le: serverTime }];
  assert.equal(availability(mission(), [planned()], contracts, serverTime).availability.action, 'OUVERTURE');
  assert.equal(availability(mission(), [planned()], contracts, '2026-10-27T09:44:00Z').availability.reason, 'HORS_CRENEAU');
  assert.equal(availability({ ...mission(), nb_creneaux: 2 }, [planned()], contracts, serverTime).availability.reason, 'PLANNING_INCOMPLETE');
  assert.equal(availability(mission(), [planned()], [], serverTime).availability.reason, 'CONTRAT');
  assert.equal(availability(mission(), [planned()], contracts, null).availability.reason, 'SERVER_TIME_UNAVAILABLE');
  assert.equal(availability({ ...mission(), nb_creneaux: 2 }, [effective()], null, null).availability.action, 'FERMETURE');
});
test('production and a substituted runtime context are rejected before a business query', async () => {
  const f = fixture(); f.env.origin = 'https://production.supabase.co';
  assert.throws(() => new SupabasePresenceGateway(f.client, f.options));
  await assert.rejects(f.gateway.list({ ...caregiver, userId: ids.other }), { code: 'SESSION_CHANGED' });
  assert.equal(f.env.queries.length, 0);
});
test('unconfirmed identity and a non-test account cannot scan', async () => {
  const f = fixture(); f.env.confirmed = false;
  await assert.rejects(f.gateway.scan(caregiver, '123456'), { code: 'INVALID_SCOPE' });
  f.env.confirmed = true; f.env.test = false;
  await assert.rejects(f.gateway.scan(caregiver, '123456'), { code: 'TEST_NOT_ADMITTED' });
  assert.equal(f.env.rpcCalls.length, 0);
});
test('code for another assigned mission confirms that actual mission, with no supplied missionId or next secret', async () => {
  const f = fixture(); f.env.rows.push(mission(ids.missionB)); f.env.target = ids.missionB;
  const result = await f.gateway.scan(caregiver, '123456');
  assert.equal(result.kind, 'confirmed'); assert.equal(result.mission?.id, ids.missionB);
  assert.equal(result.mission?.intitule, 'Mission B fictive'); assert.equal(result.proof?.scanne_le, serverTime);
  assert.deepEqual(Object.keys(f.env.rpcCalls[0].args!).sort(), ['p_code', 'p_metadata']);
  assert(!JSON.stringify(result).includes('987654')); assert(!JSON.stringify(result).includes('fixture-new-secret'));
  assert.equal(await f.gateway.pending(caregiver), null); assert.equal(f.gpsCalls(), 0);
});
test('GPS refusal remains explicit and never sends fabricated coordinates', async () => {
  const f = fixture(); f.env.consent = true;
  const result = await f.gateway.scan(caregiver, '123456');
  assert.equal(result.kind, 'confirmed'); assert.equal(result.gps, 'denied'); assert.equal(f.gpsCalls(), 1);
  assert.deepEqual(f.env.rpcCalls[0].args?.p_metadata, { id_terminal: 'fixture-device' });
});
test('a lost RPC response can be confirmed only by its new stored proof and effective segment', async () => {
  const f = fixture(); f.env.loseResponse = true;
  const result = await f.gateway.scan(caregiver, '123456'); assert.equal(result.kind, 'confirmed');
  assert.equal(f.env.rpcCalls.length, 1);
});
test('departure is confirmed against the stored end of the exact EFFECTIF period', async () => {
  const f = fixture(); f.env.scanType = 'FERMETURE';
  const result = await f.gateway.scan(caregiver, '123456'); assert.equal(result.kind, 'confirmed');
  assert.equal(result.proof?.type_scan, 'FERMETURE'); assert.equal(result.segment?.fin, serverTime);
});
test('RPC success without a stored proof locks new scans; read-only reconciliation later confirms it', async () => {
  const f = fixture(); f.env.commit = false;
  const first = await f.gateway.scan(caregiver, '123456'); assert.equal(first.kind, 'unconfirmed');
  assert.equal(first.mission, null); assert.deepEqual(await f.gateway.pending(caregiver), { attemptId: ids.attempt, gps: 'not_requested' });
  await assert.rejects(f.gateway.scan(caregiver, '654321'), { code: 'RECONCILIATION_REQUIRED' });
  f.commit(); const second = await f.gateway.reconcile(caregiver, ids.attempt);
  assert.equal(second.kind, 'confirmed'); assert.equal(f.env.rpcCalls.length, 1);
});
test('old proofs cannot prove the new attempt and an unrelated effective period cannot confirm it', async () => {
  const f = fixture(); f.env.proofs.push({ ...proof(), id: ids.prior }); f.env.commit = false; f.env.loseResponse = true;
  assert.equal((await f.gateway.scan(caregiver, '123456')).kind, 'unconfirmed');
  f.commit(); f.env.segments.find(row => row.id === ids.effective)!.debut = '2026-10-27T11:00:00Z';
  assert.equal((await f.gateway.reconcile(caregiver, ids.attempt)).kind, 'unconfirmed');
});
test('cancelling after commit preserves the pending attempt and a new session epoch can only reconcile it', async () => {
  const f = fixture(); const controller = new AbortController(); f.env.afterRpc = () => controller.abort();
  await assert.rejects(f.gateway.scan(caregiver, '123456', controller.signal), { name: 'AbortError' });
  assert.equal((await f.gateway.pending(caregiver))?.attemptId, ids.attempt);
  const resumed = { ...caregiver, epoch: 2 }; f.env.current = resumed;
  assert.equal((await f.gateway.reconcile(resumed, ids.attempt)).kind, 'confirmed'); assert.equal(f.env.rpcCalls.length, 1);
});
test('account substitution during the RPC cannot expose the result to the new account', async () => {
  const f = fixture(); f.env.afterRpc = () => { f.env.current = { ...caregiver, userId: ids.other }; f.env.userId = ids.other; };
  await assert.rejects(f.gateway.scan(caregiver, '123456'), { code: 'SESSION_CHANGED' });
  assert.equal(await f.gateway.pending(f.env.current!), null);
  f.env.current = { ...caregiver, epoch: 3 }; f.env.userId = ids.user;
  assert.equal((await f.gateway.reconcile(f.env.current, ids.attempt)).kind, 'confirmed');
});
test('two taps cannot issue two account-wide RPCs', async () => {
  const f = fixture(); let release!: () => void;
  f.env.pauseRpc = new Promise<void>(resolve => { release = resolve; });
  const first = f.gateway.scan(caregiver, '123456');
  await assert.rejects(f.gateway.scan(caregiver, '123456'), { code: 'BUSY' });
  release(); assert.equal((await first).kind, 'confirmed'); assert.equal(f.env.rpcCalls.length, 1);
});
test('a PostgreSQL transaction refusal is rejected, unlike a lost response', async () => {
  const f = fixture(); f.env.sqlError = 'P0002';
  assert.equal((await f.gateway.scan(caregiver, '123456')).kind, 'rejected'); assert.equal(await f.gateway.pending(caregiver), null);
});
test('token refresh mid-operation never replaces the captured JWT', async () => {
  const f = fixture(); f.env.afterBaseline = () => { f.env.token = 'fixture-access-B'; };
  assert.equal((await f.gateway.scan(caregiver, '123456')).kind, 'confirmed');
  assert(f.env.queries.every(query => query.authorization === 'Bearer fixture-access-A'));
});
test('an explicit PostgREST admission refusal survives cleanup failure and unlocks after reconnect without resending', async () => {
  for (const code of ['PGRST202', 'PGRST300', 'PGRST301', 'PGRST302', 'PGRST303']) {
    const f = fixture(); f.env.sqlError = code; f.storageState.failDelete = true;
    assert.equal((await f.gateway.scan(caregiver, '123456')).kind, 'unconfirmed');
    assert.equal((await f.options.journal.read(ids.user))?.rejectionCode, code);
    assert.equal(f.env.proofs.length, 0);
    f.storageState.failDelete = false; f.env.current = { ...caregiver, epoch: caregiver.epoch + 1 };
    const restarted = new SupabasePresenceGateway(f.client, { ...f.options, journal: createPresenceAttemptJournal(f.storage) });
    const result = await restarted.reconcile(f.env.current, ids.attempt);
    assert.equal(result.kind, 'rejected'); assert.equal(await restarted.pending(f.env.current), null);
    assert.equal(f.env.rpcCalls.length, 1, 'Reconnection and recovery must not resend a refused RPC');
    f.env.sqlError = null;
    assert.equal((await restarted.scan(f.env.current, '123456')).kind, 'confirmed', 'A new explicit attempt is possible after reauthentication');
    assert.equal(f.env.rpcCalls.length, 2); assert.equal(f.env.proofs.length, 1);
  }
});
test('unknown PostgREST errors remain ambiguous even if no proof is immediately visible', async () => {
  const f = fixture(); f.env.sqlError = 'PGRSTX00';
  assert.equal((await f.gateway.scan(caregiver, '123456')).kind, 'unconfirmed');
  assert.equal((await f.options.journal.read(ids.user))?.rejectionCode, null);
  await assert.rejects(f.gateway.scan(caregiver, '123456'), { code: 'RECONCILIATION_REQUIRED' });
  assert.equal(f.env.rpcCalls.length, 1);
});
test('state read never exposes an active code to a caregiver, even if a response unexpectedly contains it', async () => {
  const f = fixture(); const details = await f.gateway.read(caregiver, ids.missionA);
  assert.equal(details.establishmentCode, null); assert.equal(details.availability.action, 'OUVERTURE');
  f.env.rawCodeForCaregiver = true;
  await assert.rejects(f.gateway.read(caregiver, ids.missionA), { code: 'INVALID_SCOPE' });
});
test('the LIVE nullable establishment marker accepts only null or false for an assigned caregiver', async () => {
  const f = fixture();
  for (const marker of [null, false]) {
    f.env.caregiverEstEtab = marker;
    assert.equal((await f.gateway.read(caregiver, ids.missionA)).availability.action, 'OUVERTURE');
  }
  for (const marker of [undefined, true, 'false', 0]) {
    f.env.caregiverEstEtab = marker;
    await assert.rejects(f.gateway.read(caregiver, ids.missionA), { code: 'UNAVAILABLE' });
  }
  f.env.caregiverEstEtab = null;
  f.env.rows[0].soignant_assigne_id = ids.other;
  await assert.rejects(f.gateway.read(caregiver, ids.missionA));
});
test('unavailable server time blocks an opening offer, while an existing arrival can still be closed', async () => {
  const f = fixture(); f.env.clockFails = true;
  assert.equal((await f.gateway.read(caregiver, ids.missionA)).availability.reason, 'SERVER_TIME_UNAVAILABLE');
  f.env.segments.push(effective());
  assert.equal((await f.gateway.read(caregiver, ids.missionA)).availability.action, 'FERMETURE');
});
test('unreadable contracts do not hide a verified departure code; opening remains unavailable', async () => {
  const f = fixture(); f.env.current = employer; f.env.userId = ids.admin; f.env.role = 'ADMIN_ETABLISSEMENT';
  f.env.contractError = true;
  const before = await f.gateway.read(employer, ids.missionA);
  assert.equal(before.availability.canScan, false); assert.equal(before.availability.reason, 'CONTRACT_UNAVAILABLE');
  assert.equal(before.establishmentCode, null);
  f.env.segments.push(effective());
  const after = await f.gateway.read(employer, ids.missionA);
  assert.equal(after.availability.action, 'FERMETURE'); assert.equal(after.availability.canScan, true);
  assert.equal(after.establishmentCode, '123456'); assert.equal(after.hasOpenSegment, true);
});
test('an establishment uses its resolved ID, and code display requires pointage permission', async () => {
  const f = fixture(); f.env.current = employer; f.env.userId = ids.admin; f.env.role = 'ADMIN_ETABLISSEMENT';
  assert.equal((await f.gateway.read(employer, ids.missionA)).establishmentCode, '123456');
  const scoped = f.env.queries.find(query => query.source === 'missions'); assert.equal(scoped?.filters.etablissement_id, ids.etab);
  assert.notEqual(scoped?.filters.etablissement_id, ids.admin);
  f.env.displayCode = false; assert.equal((await f.gateway.read(employer, ids.missionA)).establishmentCode, null);
  f.env.lecture = false; await assert.rejects(f.gateway.read(employer, ids.missionA), { code: 'INVALID_SCOPE' });
});
test('POINTAGE_ONLY obtains the arrival QR through a signature predicate without reading any contract', async () => {
  const f = fixture(); f.env.current = employer; f.env.userId = ids.admin; f.env.role = 'ADMIN_ETABLISSEMENT';
  f.env.readContracts = false;
  const signed = await f.gateway.read(employer, ids.missionA);
  assert.equal(signed.establishmentCode, '123456'); assert.equal(signed.contractStatus, 'SIGNE_COMPLET');
  assert.equal(signed.availability.action, 'OUVERTURE');
  assert(!f.env.queries.some(query => query.source === 'contrats_mission'));
  f.env.signedForPointage = false;
  const unsigned = await f.gateway.read(employer, ids.missionA);
  assert.equal(unsigned.establishmentCode, null); assert.equal(unsigned.contractStatus, null);
  assert.equal(unsigned.availability.reason, 'CONTRAT');
  assert.equal(f.env.rpcCalls.length, 0);
});
test('POINTAGE_ONLY never treats a missing, malformed or failed signature predicate as eligibility', async () => {
  const f = fixture(); f.env.current = employer; f.env.userId = ids.admin; f.env.role = 'ADMIN_ETABLISSEMENT';
  f.env.readContracts = false;
  for (const value of [null, undefined, 'true', 1, { signed: true }]) {
    f.env.signedForPointage = value;
    const details = await f.gateway.read(employer, ids.missionA);
    assert.equal(details.establishmentCode, null); assert.equal(details.availability.reason, 'CONTRACT_UNAVAILABLE');
  }
  f.env.signedForPointage = true; f.env.eligibilityError = true;
  assert.equal((await f.gateway.read(employer, ids.missionA)).establishmentCode, null);
  f.env.segments.push(effective());
  const departure = await f.gateway.read(employer, ids.missionA);
  assert.equal(departure.availability.action, 'FERMETURE'); assert.equal(departure.establishmentCode, '123456');
  assert(!f.env.queries.some(query => query.source === 'contrats_mission'));
});
test('planning pagination handles a server page cap rather than silently dropping periods', async () => {
  const f = fixture(); f.env.pageCap = 1; f.env.rows[0].nb_creneaux = 2;
  f.env.segments.push({ ...planned(), id: '40000000-0000-4000-8000-000000000003', debut: '2026-10-28T10:00:00Z', fin: '2026-10-28T18:00:00Z' });
  const details = await f.gateway.read(caregiver, ids.missionA); assert.equal(details.planned.length, 2); assert.equal(details.planningComplete, true);
});
test('camera denial or cancellation does not call the mutation', async () => {
  const f = fixture();
  assert.deepEqual(await f.gateway.captureCode(caregiver, { scan: async () => ({ kind: 'denied' }) }), { kind: 'denied' });
  assert.deepEqual(await f.gateway.captureCode(caregiver, { scan: async () => ({ kind: 'cancelled' }) }), { kind: 'cancelled' });
  assert.equal(f.env.rpcCalls.length, 0);
});
test('HTTP server time requires the expected authenticated user and a Date header', async () => {
  const key = 'sb_publishable_fixture_only_1234567890';
  const request = async (_url: any, init: any) => {
    assert.equal(init.redirect, 'error'); assert.equal(init.headers.Authorization, 'Bearer fixture');
    return new Response(JSON.stringify({ id: ids.user }), { status: 200, headers: { Date: 'Tue, 27 Oct 2026 10:00:00 GMT' } });
  };
  const clock = createPresenceServerClock(key, request as typeof fetch);
  assert.equal(await clock.read({ userId: ids.user, authorization: 'Bearer fixture' }), serverTime);
  await assert.rejects(clock.read({ userId: ids.other, authorization: 'Bearer fixture' }), { code: 'UNAVAILABLE' });
  const noDate = createPresenceServerClock(key, (async () => new Response(JSON.stringify({ id: ids.user }))) as typeof fetch);
  await assert.rejects(noDate.read({ userId: ids.user, authorization: 'Bearer fixture' }));
});

const receipt = (userId = ids.user, attemptId = ids.attempt): PresenceAttemptReceipt => ({
  version: 2, phase: 'prepared', userId, attemptId, sessionEpoch: 1, terminalId: 'fixture-device', enteredCode: '123456',
  baselineProofIds: [], gps: 'not_requested', rejectionCode: null,
});
test('durable receipts are versioned and isolated by user, with no JWT, next code or coordinates', async () => {
  const f = fixture(); await f.options.journal.write(ids.user, receipt());
  await f.options.journal.write(ids.other, receipt(ids.other));
  assert.equal(f.secure.size, 2); assert.equal((await f.options.journal.read(ids.user))?.userId, ids.user);
  assert.equal((await f.options.journal.read(ids.other))?.userId, ids.other);
  const text = [...f.secure.values()].join('');
  assert(!text.includes('fixture-access')); assert(!text.includes('latitude')); assert(!text.includes('longitude'));
  assert(!text.includes('nouveau_code')); assert(!text.includes('nouveau_hmac'));
});
test('CAS prevents overwriting or clearing a different unresolved attempt', async () => {
  const f = fixture(); await f.options.journal.write(ids.user, receipt());
  const otherAttempt = '70000000-0000-4000-8000-000000000002';
  await assert.rejects(f.options.journal.write(ids.user, receipt(ids.user, otherAttempt)), { code: 'RECONCILIATION_REQUIRED' });
  await assert.rejects(f.options.journal.clear(ids.user, otherAttempt), { code: 'RECONCILIATION_REQUIRED' });
  assert.equal((await f.options.journal.read(ids.user))?.attemptId, ids.attempt);
});
test('SecureStore writes then readback fails: no RPC, and known-not-started CAS cleanup is attempted', async () => {
  const f = fixture(); f.storageState.failReadAfterSet = true;
  await assert.rejects(f.gateway.scan(caregiver, '123456'), { code: 'JOURNAL_UNAVAILABLE' });
  assert.equal(f.env.rpcCalls.length, 0); assert.equal(f.secure.size, 0);
});
test('failed cleanup of a known non-sent attempt can be closed after restart without sending a scan', async () => {
  const f = fixture(); f.storageState.failReadAfterSet = true; f.storageState.failDelete = true;
  await assert.rejects(f.gateway.scan(caregiver, '123456'), { code: 'JOURNAL_UNAVAILABLE' });
  assert.equal(f.env.rpcCalls.length, 0); assert.equal(f.secure.size, 1);
  f.storageState.failReadAfterSet = false;
  assert.equal((await f.options.journal.read(ids.user))?.phase, 'not_sent');
  await assert.rejects(f.gateway.scan(caregiver, '123456'), { code: 'RECONCILIATION_REQUIRED' });
  const restarted = new SupabasePresenceGateway(f.client, { ...f.options, terminalId: 'new-process-device',
    journal: createPresenceAttemptJournal(f.storage) });
  f.storageState.failDelete = false;
  const result = await restarted.reconcile(caregiver, ids.attempt);
  assert.equal(result.kind, 'rejected'); assert.match(result.message, /Aucun pointage n’a été envoyé/);
  assert.equal(await restarted.pending(caregiver), null);
  assert.equal(f.env.rpcCalls.length, 0);
});

test('a process stopped with only prepared can close that receipt without any business RPC or proof', async () => {
  const f = fixture(); await f.options.journal.write(ids.user, receipt());
  const restarted = new SupabasePresenceGateway(f.client, { ...f.options, terminalId: 'new-process-device',
    journal: createPresenceAttemptJournal(f.storage) });
  assert.equal((await restarted.reconcile(caregiver, ids.attempt)).kind, 'rejected');
  assert.equal(f.secure.size, 0); assert.equal(f.env.rpcCalls.length, 0);
  assert.equal(f.env.queries.filter(query => query.source === 'scans_pointage').length, 0);
});

test('a started write that persisted but failed its readback never invokes RPC and preserves non-sent through failed cleanup', async () => {
  const f = fixture(); f.storageState.failReadForPhase = 'started'; f.storageState.failDelete = true;
  await assert.rejects(f.gateway.scan(caregiver, '123456'), { code: 'JOURNAL_UNAVAILABLE' });
  assert.equal(f.env.rpcCalls.length, 0);
  assert.equal((await f.options.journal.read(ids.user))?.phase, 'not_sent');
  f.storageState.failReadForPhase = null; f.storageState.failDelete = false;
  const restarted = new SupabasePresenceGateway(f.client, { ...f.options, journal: createPresenceAttemptJournal(f.storage) });
  assert.equal((await restarted.reconcile(caregiver, ids.attempt)).kind, 'rejected');
  assert.equal(f.secure.size, 0); assert.equal(f.env.rpcCalls.length, 0);
});

test('when both non-sent persistence and cleanup fail, a possibly stored started phase is never downgraded or abandoned', async () => {
  const f = fixture(); f.storageState.failReadForPhase = 'started';
  f.storageState.failSetForPhase = 'not_sent'; f.storageState.failDelete = true;
  await assert.rejects(f.gateway.scan(caregiver, '123456'), { code: 'JOURNAL_UNAVAILABLE' });
  assert.equal((await f.options.journal.read(ids.user))?.phase, 'started');
  f.storageState.failReadForPhase = null; f.storageState.failSetForPhase = null; f.storageState.failDelete = false;
  const restarted = new SupabasePresenceGateway(f.client, { ...f.options, journal: createPresenceAttemptJournal(f.storage) });
  assert.equal((await restarted.reconcile(caregiver, ids.attempt)).kind, 'unconfirmed');
  assert.equal(f.secure.size, 1); assert.equal(f.env.rpcCalls.length, 0);
});

test('phase transitions cannot downgrade started, revive non-sent, or recreate a cleared attempt at started', async () => {
  const f = fixture(); const prepared = receipt(); const started = { ...prepared, phase: 'started' as const };
  await f.options.journal.write(ids.user, prepared); await f.options.journal.write(ids.user, started);
  await assert.rejects(f.options.journal.write(ids.user, prepared), { code: 'RECONCILIATION_REQUIRED' });
  await assert.rejects(f.options.journal.clear(ids.user, ids.attempt, 'prepared'), { code: 'RECONCILIATION_REQUIRED' });
  await f.options.journal.write(ids.user, { ...started, phase: 'not_sent' });
  await assert.rejects(f.options.journal.write(ids.user, started), { code: 'RECONCILIATION_REQUIRED' });
  await f.options.journal.clear(ids.user, ids.attempt, 'not_sent');
  await assert.rejects(f.options.journal.write(ids.user, started), { code: 'RECONCILIATION_REQUIRED' });
});

test('recovery cannot clear a prepared receipt that advanced to started while identity was being checked', async () => {
  const f = fixture(); const prepared = receipt(); await f.options.journal.write(ids.user, prepared);
  const gateway = new SupabasePresenceGateway(f.client, { ...f.options, journal: { ...f.options.journal,
    async clear(userId, attemptId, phase) {
      await f.options.journal.write(userId, { ...prepared, phase: 'started' });
      return f.options.journal.clear(userId, attemptId, phase);
    } } });
  assert.equal((await gateway.reconcile(caregiver, ids.attempt)).kind, 'unconfirmed');
  assert.equal((await f.options.journal.read(ids.user))?.phase, 'started'); assert.equal(f.env.rpcCalls.length, 0);
});

test('recovery of prepared prevents an old operation from crossing its started barrier afterward', async () => {
  const f = fixture(); let entered!: () => void; let release!: () => void;
  const preparedWritten = new Promise<void>(resolve => { entered = resolve; });
  const paused = new Promise<void>(resolve => { release = resolve; });
  const gateway = new SupabasePresenceGateway(f.client, { ...f.options, journal: { ...f.options.journal,
    async write(userId, value) { await f.options.journal.write(userId, value);
      if (value.phase === 'prepared') { entered(); await paused; } } } });
  const sending = gateway.scan(caregiver, '123456'); await preparedWritten;
  assert.equal((await f.gateway.reconcile(caregiver, ids.attempt)).kind, 'rejected');
  release(); await assert.rejects(sending, { code: 'RECONCILIATION_REQUIRED' });
  assert.equal(f.env.rpcCalls.length, 0); assert.equal(f.secure.size, 0);
});

test('legacy receipts remain ambiguous, never upgraded to prepared or erased on an empty proof read', async () => {
  const f = fixture(); await f.options.journal.write(ids.user, receipt());
  const legacy: Record<string, unknown> = { ...receipt(), version: 1 }; delete legacy.phase;
  const key = [...f.secure.keys()][0]; f.secure.set(key, JSON.stringify(legacy));
  assert.equal((await f.options.journal.read(ids.user))?.phase, 'started');
  assert.equal((await f.gateway.reconcile(caregiver, ids.attempt)).kind, 'unconfirmed');
  assert.equal(f.secure.size, 1); assert.equal(JSON.parse(f.secure.get(key)!).version, 1);
  assert.equal(f.env.rpcCalls.length, 0);
});

test('account change during non-sent cleanup cannot expose the old result or erase another account receipt', async () => {
  const f = fixture(); await f.options.journal.write(ids.user, receipt());
  await f.options.journal.write(ids.other, receipt(ids.other));
  f.storageState.afterDelete = () => { f.env.current = { ...caregiver, userId: ids.other }; f.env.userId = ids.other; };
  await assert.rejects(f.gateway.reconcile(caregiver, ids.attempt), { code: 'SESSION_CHANGED' });
  assert.equal(await f.options.journal.read(ids.user), null);
  assert.equal((await f.options.journal.read(ids.other))?.attemptId, ids.attempt); assert.equal(f.env.rpcCalls.length, 0);
});

test('focus cancellation during non-sent cleanup suppresses presentation without sending or restoring a receipt', async () => {
  const f = fixture(); await f.options.journal.write(ids.user, receipt()); const controller = new AbortController();
  f.storageState.afterDelete = () => controller.abort();
  await assert.rejects(f.gateway.reconcile(caregiver, ids.attempt, controller.signal), { name: 'AbortError' });
  assert.equal(f.secure.size, 0); assert.equal(f.env.rpcCalls.length, 0);
});
test('corrupt or unreadable journal blocks scans without resetting the stored receipt', async () => {
  const f = fixture(); await f.options.journal.write(ids.user, receipt());
  const key = [...f.secure.keys()][0]; f.secure.set(key, '{broken');
  await assert.rejects(f.gateway.scan(caregiver, '123456'), { code: 'JOURNAL_UNAVAILABLE' });
  assert.equal(f.secure.get(key), '{broken'); assert.equal(f.env.rpcCalls.length, 0);
  f.storageState.failAllRead = true;
  await assert.rejects(f.gateway.scan(caregiver, '123456'), { code: 'JOURNAL_UNAVAILABLE' });
});
test('a fresh gateway after process loss uses the receipt terminal and only reconciles', async () => {
  const f = fixture(); f.env.commit = false;
  assert.equal((await f.gateway.scan(caregiver, '123456')).kind, 'unconfirmed');
  const restarted = new SupabasePresenceGateway(f.client, { ...f.options, terminalId: 'new-process-device',
    journal: createPresenceAttemptJournal(f.storage) });
  await assert.rejects(restarted.scan(caregiver, '123456'), { code: 'RECONCILIATION_REQUIRED' });
  f.commit(); assert.equal((await restarted.reconcile(caregiver, ids.attempt)).kind, 'confirmed');
  assert.equal(f.env.rpcCalls.length, 1); assert.equal(f.secure.size, 0);
});
test('a confirmed backend scan remains confirmed when cleanup fails, and a second scan stays blocked', async () => {
  const f = fixture(); f.storageState.failDelete = true;
  const result = await f.gateway.scan(caregiver, '123456'); assert.equal(result.kind, 'confirmed');
  if (result.kind === 'confirmed') assert.equal(result.journalStatus, 'unverified');
  assert.equal(f.secure.size, 1); await assert.rejects(f.gateway.scan(caregiver, '123456'), { code: 'RECONCILIATION_REQUIRED' });
  f.storageState.failDelete = false;
  assert.equal((await f.gateway.reconcile(caregiver, ids.attempt)).kind, 'confirmed'); assert.equal(f.env.rpcCalls.length, 1);
});
test('deletion succeeded but its readback failed: no false business failure or new scan before journal reread', async () => {
  const f = fixture(); f.storageState.failReadAfterDelete = true;
  const result = await f.gateway.scan(caregiver, '123456');
  assert.equal(result.kind, 'confirmed'); if (result.kind === 'confirmed') assert.equal(result.journalStatus, 'unverified');
  assert.equal(result.proof?.scanne_le, serverTime); assert.equal(f.secure.size, 0);
  await assert.rejects(f.gateway.scan(caregiver, '123456'), { code: 'RECONCILIATION_REQUIRED' });
  assert.equal(f.env.rpcCalls.length, 1);
  assert.equal(await f.gateway.pending(caregiver), null, 'explicit journal reread establishes durable absence');
  const fresh = new SupabasePresenceGateway(f.client, { ...f.options, journal: createPresenceAttemptJournal(f.storage) });
  assert.equal(await fresh.pending(caregiver), null);
});
test('a known transaction refusal persists across cleanup failure, so restart does not resend it', async () => {
  const f = fixture(); f.env.sqlError = '23514'; f.storageState.failDelete = true;
  assert.equal((await f.gateway.scan(caregiver, '123456')).kind, 'unconfirmed');
  assert.equal((await f.options.journal.read(ids.user))?.rejectionCode, '23514');
  const restarted = new SupabasePresenceGateway(f.client, { ...f.options, journal: createPresenceAttemptJournal(f.storage) });
  f.storageState.failDelete = false;
  assert.equal((await restarted.reconcile(caregiver, ids.attempt)).kind, 'rejected'); assert.equal(f.env.rpcCalls.length, 1);
});
test('account change during durable preparation clears only its own not-started receipt', async () => {
  const f = fixture();
  f.storageState.afterSet = () => { f.env.current = { ...caregiver, userId: ids.other }; f.env.userId = ids.other; };
  await assert.rejects(f.gateway.scan(caregiver, '123456'), { code: 'SESSION_CHANGED' });
  assert.equal(f.env.rpcCalls.length, 0); assert.equal(f.secure.size, 0);
});

test('GPS opt-in availability is read canonically without invoking GPS, scan or an account write', async () => {
  const f = fixture(); assert.equal(await f.gateway.readGpsConsent(caregiver), false);
  f.env.consent = true; assert.equal(await f.gateway.readGpsConsent(caregiver), true);
  assert.equal(f.gpsCalls(), 0); assert.equal(f.env.rpcCalls.length, 0);
  assert(f.env.queries.filter(q => q.source === 'soignants').every(q => q.filters.id === ids.user
    && q.projection === 'id,est_compte_test,consentement_gps'));
  assert(f.env.queries.every(q => ['fn_get_my_role', 'soignants'].includes(q.source)));
});
