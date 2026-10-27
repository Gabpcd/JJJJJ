import assert from 'node:assert/strict';
import test from 'node:test';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { MissionRecord, MissionSlot } from '../data/types';
import { getMissionRemuneration } from '../data/presentation';
import { EstablishmentGateway } from './gateway';
import { DEMO_ESTABLISHMENT_CONTEXT } from './demo';
import { establishmentResourceKey, type EstablishmentContext } from './types';

const context: EstablishmentContext = {
  ...DEMO_ESTABLISHMENT_CONTEXT, userId: 'member-rh', etablissementId: 'establishment-a', email: 'rh@example.invalid', membershipRole: 'RH',
};
const record = (patch: Partial<MissionRecord> = {}): MissionRecord => ({
  id: 'mission-1', etablissement_id: context.etablissementId, intitule: 'Mission réelle de fixture unitaire', description: null,
  service: 'Médecine', profession_requise: 'IDE', specialite_medicale_requise: null, accepte_non_specialises: null,
  debut_le: '2026-11-01T08:00:00Z', fin_le: '2026-11-01T16:00:00Z', duree_heures: 8, nb_creneaux: 1,
  taux_horaire_base: 27.36, taux_rist_plafonne: 27.36, rist_plafond_applique: true, total_brut: 218.88, net_a_payer: 172.15,
  est_urgente: false, niveau_urgence: 0, statut: 'TERMINEE', type_contrat_recherche: 'SALARIE', boostee_le: null,
  mode_remuneration: 'HORAIRE', retrocession_pct: null, ...patch,
});
const slot = (patch: Partial<MissionSlot> = {}): MissionSlot => ({ id: 'slot-1', mission_id: 'mission-1', debut: '2026-11-01T08:00:00Z', fin: '2026-11-01T16:00:00Z', est_pause: false, type_creneau: 'PREVISIONNEL', ...patch });
interface Call { source: string; params?: unknown; operations: Array<[string, ...unknown[]]>; }
interface Response { data: unknown; error: unknown; count?: number | null; }
const ok = (data: unknown, count?: number | null): Response => ({ data, error: null, count });
const has = (call: Call, operation: string, ...args: unknown[]) => call.operations.some(entry => JSON.stringify(entry) === JSON.stringify([operation, ...args]));

/** Transport tests only. These do not simulate or validate deployed RLS. */
function transport(handler: (call: Call) => Response | Promise<Response>) {
  const calls: Call[] = [];
  class Query implements PromiseLike<Response> {
    constructor(private readonly call: Call) { calls.push(call); }
    op(name: string, ...args: unknown[]) { this.call.operations.push([name, ...args]); return this; }
    select(...args: unknown[]) { return this.op('select', ...args); }
    eq(...args: unknown[]) { return this.op('eq', ...args); }
    in(...args: unknown[]) { return this.op('in', ...args); }
    ilike(...args: unknown[]) { return this.op('ilike', ...args); }
    order(...args: unknown[]) { return this.op('order', ...args); }
    range(...args: unknown[]) { return this.op('range', ...args); }
    abortSignal(...args: unknown[]) { return this.op('abortSignal', ...args); }
    maybeSingle(...args: unknown[]) { return this.op('maybeSingle', ...args); }
    then<TResult1 = Response, TResult2 = never>(
      resolve?: ((value: Response) => TResult1 | PromiseLike<TResult1>) | null,
      reject?: ((reason: unknown) => TResult2 | PromiseLike<TResult2>) | null,
    ): PromiseLike<TResult1 | TResult2> { return Promise.resolve().then(() => handler(this.call)).then(resolve, reject); }
  }
  const client = {
    from: (source: string) => new Query({ source, operations: [] }),
    rpc: (source: string, params?: unknown) => new Query({ source, params, operations: [] }),
  } as unknown as SupabaseClient;
  return { gateway: new EstablishmentGateway(client), calls };
}
function standard(call: Call): Response {
  if (call.source === 'fn_mon_etablissement_complet') return ok({ id: context.etablissementId, nom: 'Clinique A', siret: 'fixture', statut_verification: 'VERIFIE', stripe_customer_id: 'not-for-ui', iban_last4: 'not-for-ui' });
  if (call.source === 'missions') return ok(call.operations.some(([name]) => name === 'maybeSingle') ? record() : [record()], 1);
  if (call.source === 'mission_creneaux') return ok([slot()], 1);
  throw new Error(`Unexpected call ${call.source}`);
}

test('establishment scope uses resolved establishment, not member user id; past/statuses remain readable', async () => {
  const { gateway, calls } = transport(standard);
  const { missions, nextOffset } = await gateway.listMissions(context);
  assert.equal(missions[0].statut, 'TERMINEE');
  assert.equal(nextOffset, null);
  assert.ok(has(calls[0], 'eq', 'etablissement_id', context.etablissementId));
  assert.ok(!has(calls[0], 'eq', 'etablissement_id', context.userId));
  assert.ok(!calls[0].operations.some(([name]) => name === 'gte'));
  assert.ok(!calls[0].operations.some(([name, key]) => name === 'eq' && key === 'profession_requise'));
  assert.equal(missions[0].taux_horaire_base, 27.36);
  assert.equal(missions[0].taux_rist_plafonne, 27.36);
  assert.equal(missions[0].total_brut, 218.88);
  assert.equal(missions[0].net_a_payer, 172.15);
});

test('profile is restricted to identity and status fields, response scope is checked', async () => {
  const { gateway } = transport(standard);
  const result = await gateway.getProfile(context);
  assert.equal(result?.id, context.etablissementId);
  assert.equal(result?.nom, 'Clinique A');
  assert.equal(result?.contrat_service_signe, null);
  assert.ok(!('stripe_customer_id' in result!));
  assert.ok(!('iban_last4' in result!));
  await assert.rejects(transport(() => ok({ id: context.userId, nom: 'Wrong scope' })).gateway.getProfile(context), /ne correspond pas/);
});

test('missing read permission or malformed context performs no request', async () => {
  const { gateway, calls } = transport(standard);
  for (const invalid of [{ ...context, etablissementId: '' }, { ...context, userId: '' },
    { ...context, permissions: { ...context.permissions, lecture: false } },
    { ...context, permissions: { ...context.permissions, paiement: undefined } } as unknown as EstablishmentContext]) {
    await assert.rejects(gateway.getProfile(invalid));
    await assert.rejects(gateway.listMissions(invalid));
    await assert.rejects(gateway.getMission('mission-1', invalid));
  }
  assert.equal(calls.length, 0);
});

test('list and detail reject another establishment, substitutions and duplicate records', async () => {
  for (const rows of [[record({ etablissement_id: 'other' })], [record(), record()]]) {
    await assert.rejects(transport(() => ok(rows, rows.length)).gateway.listMissions(context), /ne correspondent pas/);
  }
  await assert.rejects(transport(() => ok(record({ id: 'other' }))).gateway.getMission('mission-1', context), /ne correspondent pas/);
});

test('detail re-reads id and scope and respects access lost after list', async () => {
  let denied = false;
  const { gateway, calls } = transport(call => call.source === 'missions' && denied ? ok(null) : standard(call));
  assert.equal((await gateway.getMission('mission-1', context))?.id, 'mission-1');
  denied = true;
  assert.equal(await gateway.getMission('mission-1', context), null);
  for (const call of calls.filter(call => call.source === 'missions')) {
    assert.ok(has(call, 'eq', 'id', 'mission-1'));
    assert.ok(has(call, 'eq', 'etablissement_id', context.etablissementId));
  }
});

test('server errors never become demo data, successful empty lists or raw provider messages', async () => {
  const { gateway } = transport(() => ({ data: null, error: { message: 'secret provider details' } }));
  for (const request of [() => gateway.getProfile(context), () => gateway.listMissions(context), () => gateway.getMission('mission-1', context)]) {
    await assert.rejects(request, error => error instanceof Error && !error.message.includes('secret'));
  }
  await assert.rejects(transport(() => ok({ error: 'forbidden' })).gateway.getProfile(context));
  await assert.rejects(transport(() => ok(null, 0)).gateway.listMissions(context));
});

test('paging and status filters are server bound, search treats wildcard characters literally', async () => {
  const { gateway, calls } = transport(call => call.source === 'missions' ? ok([], 0) : standard(call));
  await gateway.listMissions(context, { offset: 50, status: 'OUVERTE', search: '  nuit_50%  ' });
  assert.ok(has(calls[0], 'range', 50, 99));
  assert.ok(has(calls[0], 'eq', 'statut', 'OUVERTE'));
  assert.ok(has(calls[0], 'ilike', 'intitule', '%nuit\\_50\\%%'));
  for (const filters of [{ offset: -1 }, { offset: 3 }, { status: 'UNKNOWN' }]) await assert.rejects(gateway.listMissions(context, filters));
  assert.equal(calls.length, 1);
});

test('fixture filtering does not lose pagination cursor or reveal fixture detail', async () => {
  const rows = Array.from({ length: 50 }, (_, index) => record({ id: `fixture-${index}`, intitule: `[pw-test:fixture] ${index}` }));
  const { gateway, calls } = transport(call => call.operations.some(([name]) => name === 'maybeSingle') ? ok(rows[0]) : ok(rows, 51));
  assert.deepEqual(await gateway.listMissions(context), { missions: [], nextOffset: 50 });
  assert.equal(await gateway.getMission('fixture-0', context), null);
  assert.ok(calls.every(call => call.source === 'missions'));
});

test('partial mission pages/count omission fail instead of skipping rows', async () => {
  for (const response of [ok([record()], 2), ok([record()]), ok([], 2), ok([record()], -1)]) {
    await assert.rejects(transport(() => response).gateway.listMissions(context), /incomplète/);
  }
});

test('missing expected schedule is explicitly incomplete without replacing it by the envelope', async () => {
  const { gateway } = transport(call => call.source === 'missions' ? ok(record({ nb_creneaux: 2, fin_le: '2026-11-03T16:00:00Z' })) : standard(call));
  const result = await gateway.getMission('mission-1', context);
  assert.equal(result?.planning_exact, false);
  assert.deepEqual(result?.creneaux_planifies, []);
  const none = transport(call => call.source === 'mission_creneaux' ? ok([], 0) : standard(call));
  assert.equal((await none.gateway.getMission('mission-1', context))?.planning_exact, false);
});

test('only legacy single-slot missions without an expected count use the shared bounded fallback', async () => {
  const { gateway } = transport(call => call.source === 'missions' ? ok(record({ nb_creneaux: null })) : ok([], 0));
  const result = await gateway.getMission('mission-1', context);
  assert.equal(result?.planning_exact, true);
  assert.equal(result?.creneaux_planifies.length, 1);
});

test('schedule rejects foreign, duplicate, wrong-kind and pause rows', async () => {
  for (const rows of [[slot({ mission_id: 'foreign' })], [slot(), slot()], [slot({ type_creneau: 'EFFECTIF' })], [slot({ est_pause: true })]]) {
    const { gateway } = transport(call => call.source === 'mission_creneaux' ? ok(rows, rows.length) : standard(call));
    await assert.rejects(gateway.getMission('mission-1', context), /incohérents/);
  }
});

test('schedule reads beyond 500 rows without truncation and rejects changing counts', async () => {
  const slots = Array.from({ length: 501 }, (_, index) => slot({ id: `slot-${index}`, debut: new Date(Date.parse('2026-11-01T08:00:00Z') + index * 86_400_000).toISOString(), fin: new Date(Date.parse('2026-11-01T16:00:00Z') + index * 86_400_000).toISOString() }));
  let changeCount = false;
  const { gateway, calls } = transport(call => {
    if (call.source === 'missions') return ok(record({ nb_creneaux: 501, fin_le: slots[500].fin! }));
    const offset = Number(call.operations.find(([name]) => name === 'range')?.[1]);
    return ok(slots.slice(offset, offset + 500), changeCount && offset ? 500 : 501);
  });
  assert.equal((await gateway.getMission('mission-1', context))?.creneaux_planifies.length, 501);
  assert.ok(calls.some(call => has(call, 'range', 500, 999)));
  changeCount = true;
  await assert.rejects(gateway.getMission('mission-1', context), /a changé/);
});

test('null/zero/retrocession amounts retain their meaning, invalid numeric values fail', async () => {
  for (const rate of [null, 0]) {
    const { gateway } = transport(call => call.source === 'missions' ? ok(record({ taux_horaire_base: rate })) : standard(call));
    const result = (await gateway.getMission('mission-1', context))!;
    assert.equal(result.taux_horaire_base, rate);
    assert.match(getMissionRemuneration(result), rate === null ? /non renseigné/ : /0,00/);
  }
  const retrocession = transport(call => call.source === 'missions' ? ok(record({ mode_remuneration: 'RETROCESSION', retrocession_pct: 70 })) : standard(call));
  assert.equal(getMissionRemuneration((await retrocession.gateway.getMission('mission-1', context))!), 'Rétrocession 70 % des honoraires');
  await assert.rejects(transport(() => ok(record({ taux_horaire_base: NaN }))).gateway.getMission('mission-1', context));
});

test('abort is forwarded and prevents results after cancellation', async () => {
  const controller = new AbortController();
  const { gateway, calls } = transport(standard);
  await gateway.getMission('mission-1', context, controller.signal);
  assert.ok(calls.every(call => call.operations.some(([name, value]) => name === 'abortSignal' && value === controller.signal)));
  controller.abort();
  await assert.rejects(gateway.getProfile(context, controller.signal), { name: 'AbortError' });
  const during = new AbortController();
  const late = transport(call => { during.abort(); return standard(call); });
  await assert.rejects(late.gateway.getMission('mission-1', context, during.signal), { name: 'AbortError' });
  assert.equal(late.calls.length, 1);
});

test('demo is explicit and isolated from ordinary contexts; returned objects do not mutate fixtures', async () => {
  const demo = new EstablishmentGateway(null, () => new Date('2026-10-27T10:00:00Z'));
  assert.equal(demo.mode, 'demo');
  await assert.rejects(demo.getProfile(context), /démonstration/);
  const profile = (await demo.getProfile(DEMO_ESTABLISHMENT_CONTEXT))!;
  profile.nom = 'mutated';
  assert.notEqual((await demo.getProfile(DEMO_ESTABLISHMENT_CONTEXT))?.nom, 'mutated');
  const list = await demo.listMissions(DEMO_ESTABLISHMENT_CONTEXT, { status: 'OUVERTE' });
  assert.equal(list.missions.length, 2);
  assert.ok(list.missions.every(row => row.statut === 'OUVERTE' && row.etablissement_id === DEMO_ESTABLISHMENT_CONTEXT.etablissementId));
  const detail = await demo.getMission('demo-etab-mission-001', DEMO_ESTABLISHMENT_CONTEXT);
  assert.equal(detail?.planning_exact, true);
  assert.equal(detail?.creneaux_planifies.length, 2);
});

test('resource keys invalidate another member, scope, permission or mode immediately', () => {
  const original = establishmentResourceKey(context, 'list', 'supabase');
  for (const changed of [{ ...context, userId: 'other' }, { ...context, etablissementId: 'other' },
    { ...context, email: 'playwright-other@example.invalid' }, { ...context, permissions: { ...context.permissions, lecture: false } }]) {
    assert.notEqual(establishmentResourceKey(changed, 'list', 'supabase'), original);
  }
  assert.notEqual(establishmentResourceKey(context, 'list', 'demo'), original);
});
