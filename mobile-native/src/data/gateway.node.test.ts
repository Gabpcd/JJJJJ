import assert from 'node:assert/strict';
import test from 'node:test';
import type { SupabaseClient } from '@supabase/supabase-js';
import { enrichMission, filterMissions } from './business';
import { DEMO_CONTEXT, DemoGateway } from './demoGateway';
import { formatMissionPeriod, getMissionRemuneration } from './presentation';
import { SupabaseMissionGateway } from './supabaseGateway';
import { validateMobileAccess } from './types';
import type { EtablissementSummary, MissionReadContext, MissionRecord, MissionSlot } from './types';

const now = () => new Date('2026-10-26T10:00:00Z');
const context: MissionReadContext = {
  ...DEMO_CONTEXT, userId: 'user-1', email: 'soignant@example.invalid',
  profile: { ...DEMO_CONTEXT.profile, id: 'user-1' },
};
const establishment: EtablissementSummary = {
  id: 'etab-1', nom: 'Établissement de test', adresse_ville: 'Paris', adresse_code_postal: '75011',
  adresse_lat: 48.8566, adresse_lng: 2.3522, type: 'CLINIQUE',
};
const record = (overrides: Partial<MissionRecord> = {}): MissionRecord => ({
  id: 'mission-1', intitule: 'Mission de test unitaire', description: null, service: 'Médecine',
  profession_requise: 'IDE', specialite_medicale_requise: null, accepte_non_specialises: null,
  debut_le: '2026-10-27T08:00:00Z', fin_le: '2026-10-27T16:00:00Z', duree_heures: 8, nb_creneaux: 1,
  taux_horaire_base: 26.75, taux_rist_plafonne: 26.75, rist_plafond_applique: true,
  total_brut: 214, net_a_payer: 167.11, est_urgente: false, niveau_urgence: 0,
  statut: 'OUVERTE', etablissement_id: establishment.id, type_contrat_recherche: 'SALARIE',
  boostee_le: null, mode_remuneration: 'HORAIRE', retrocession_pct: null, ...overrides,
});
const slot = (overrides: Partial<MissionSlot> = {}): MissionSlot => ({
  id: 'slot-1', mission_id: 'mission-1', debut: '2026-10-27T08:00:00Z', fin: '2026-10-27T16:00:00Z',
  est_pause: false, type_creneau: 'PREVISIONNEL', ...overrides,
});
const mission = (overrides: Partial<MissionRecord> = {}, slots = [slot()]) =>
  enrichMission(record(overrides), context, establishment, slots);

interface Call { source: string; params?: unknown; operations: Array<[string, ...unknown[]]>; }
interface Response { data: unknown; error: unknown; count?: number | null; }
type Handler = (call: Call) => Response | Promise<Response>;

/** Models query transport only; these tests make no claim about deployed RLS. */
function transport(handler: Handler) {
  const calls: Call[] = [];
  class Query implements PromiseLike<Response> {
    constructor(private readonly call: Call) { calls.push(call); }
    private op(name: string, ...args: unknown[]) { this.call.operations.push([name, ...args]); return this; }
    select(...args: unknown[]) { return this.op('select', ...args); }
    eq(...args: unknown[]) { return this.op('eq', ...args); }
    gte(...args: unknown[]) { return this.op('gte', ...args); }
    order(...args: unknown[]) { return this.op('order', ...args); }
    limit(...args: unknown[]) { return this.op('limit', ...args); }
    or(...args: unknown[]) { return this.op('or', ...args); }
    in(...args: unknown[]) { return this.op('in', ...args); }
    range(...args: unknown[]) { return this.op('range', ...args); }
    abortSignal(...args: unknown[]) { return this.op('abortSignal', ...args); }
    maybeSingle(...args: unknown[]) { return this.op('maybeSingle', ...args); }
    then<TResult1 = Response, TResult2 = never>(
      onfulfilled?: ((value: Response) => TResult1 | PromiseLike<TResult1>) | null,
      onrejected?: ((reason: unknown) => TResult2 | PromiseLike<TResult2>) | null,
    ): PromiseLike<TResult1 | TResult2> {
      return Promise.resolve().then(() => handler(this.call)).then(onfulfilled, onrejected);
    }
  }
  const client = {
    from: (source: string) => new Query({ source, operations: [] }),
    rpc: (source: string, params?: unknown) => new Query({ source, params, operations: [] }),
  } as unknown as SupabaseClient;
  return { calls, gateway: new SupabaseMissionGateway(client, now) };
}
const ok = (data: unknown, count?: number | null): Response => ({ data, error: null, count });
function normal(call: Call): Response {
  if (call.source === 'missions') return ok(call.operations.some(([name]) => name === 'maybeSingle') ? record() : [record()]);
  if (call.source === 'fn_etablissements_safe') return ok([establishment]);
  if (call.source === 'mission_creneaux') return ok([slot()], 1);
  throw new Error(`Unexpected transport: ${call.source}`);
}
const hasOperation = (call: Call, name: string, ...args: unknown[]) =>
  call.operations.some(operation => JSON.stringify(operation) === JSON.stringify([name, ...args]));

test('mobile admission requires a confirmed soignant session', () => {
  assert.equal(validateMobileAccess(null, 'SOIGNANT').allowed, false);
  assert.equal(validateMobileAccess({ id: 'a' }, 'SOIGNANT').allowed, false);
  assert.equal(validateMobileAccess({ id: 'a', email_confirmed_at: 'date' }, 'ETABLISSEMENT').allowed, false);
  assert.equal(validateMobileAccess({ id: 'a', email_confirmed_at: 'date' }, 'ADMIN').allowed, false);
  assert.deepEqual(validateMobileAccess({ id: 'a', email_confirmed_at: 'date' }, 'SOIGNANT'), { allowed: true });
});

test('professional hierarchy is directional and an explicit filter stays exact', () => {
  const rows = ['IDE', 'IADE', 'IBODE', 'MEDECIN'].map(profession_requise => mission({ id: profession_requise, profession_requise }));
  const iade = { ...context, profile: { ...context.profile, profession: 'IADE' } };
  assert.deepEqual(filterMissions(rows, context).map(m => m.id), ['IDE']);
  assert.deepEqual(filterMissions(rows, iade).map(m => m.id), ['IDE', 'IADE']);
  assert.deepEqual(filterMissions(rows, iade, { profession: 'IADE' }).map(m => m.id), ['IADE']);
});

test('liberal compatibility preserves the salaried option and legacy contract marker', () => {
  const rows = [mission({ id: 'salary' }), mission({ id: 'liberal', type_contrat_recherche: 'LIBERAL' }),
    mission({ id: 'legacy', type_contrat_recherche: null, description: '[CONTRAT:LIBERAL] Description' })];
  const salaryOnly = { ...context, profile: { ...context.profile, types_contrat_acceptes: '["CDD"]', type_exercice: 'SALARIE' } };
  const liberalOnly = { ...context, profile: { ...context.profile, types_contrat_acceptes: '["LIBERAL"]', type_exercice: 'LIBERAL' } };
  assert.deepEqual(filterMissions(rows, salaryOnly).map(m => m.id), ['salary']);
  assert.equal(filterMissions(rows, liberalOnly).length, 3);
  assert.deepEqual(filterMissions(rows, liberalOnly, { typeContrat: 'LIBERAL' }).map(m => m.id), ['liberal', 'legacy']);
});

test('fixtures are hidden for ordinary accounts; unknown coordinates remain discoverable', () => {
  const ordinary = mission();
  const hidden = mission({ id: 'fixture', intitule: '[pw-test:xyz] fixture' });
  const distant = { ...ordinary, id: 'distant', distance_km: 100 };
  const unknown = { ...ordinary, id: 'unknown', distance_km: null };
  assert.deepEqual(filterMissions([ordinary, hidden, distant, unknown], context, { rayonKm: 20 }).map(m => m.id), ['mission-1', 'unknown']);
  assert.equal(filterMissions([hidden], { ...context, email: 'playwright-test@example.invalid' }).length, 1);
  assert.equal(filterMissions([ordinary], context, { ville: '750' }).length, 1);
  assert.equal(filterMissions([ordinary], context, { ville: 'Lyon' }).length, 0);
});

test('schedule filters consider later slots and Paris midnight, not a continuous envelope', () => {
  const later = slot({ id: 'slot-2', debut: '2026-10-30T23:30:00Z', fin: '2026-10-31T05:00:00Z' });
  const multi = mission({ fin_le: later.fin!, nb_creneaux: 2 }, [slot(), later]);
  assert.equal(multi.planning_exact, true);
  assert.equal(filterMissions([multi], context, { horaire: 'WEEKEND' }).length, 1);
  assert.equal(filterMissions([multi], context, { horaire: 'NUIT' }).length, 1);
  assert.equal(filterMissions([multi], context, { horaire: 'JOUR' }).length, 1);
  const incomplete = mission({ fin_le: later.fin!, nb_creneaux: 2 }, [slot()]);
  assert.equal(incomplete.planning_exact, false);
  assert.equal(filterMissions([incomplete], context, { horaire: 'JOUR' }).length, 0);
  assert.match(formatMissionPeriod(multi), /2 créneaux/);
  assert.match(formatMissionPeriod(incomplete), /planning à confirmer/);
});

test('presentation uses server hourly value and distinguishes retrocession', () => {
  assert.match(getMissionRemuneration(mission()), /26,75.*\/h/);
  assert.equal(getMissionRemuneration(mission({ mode_remuneration: 'RETROCESSION', retrocession_pct: 70 })), 'Rétrocession 70 % des honoraires');
  assert.equal(getMissionRemuneration(mission({ taux_horaire_base: null })), 'Taux non renseigné');
  assert.match(formatMissionPeriod(mission()), /09:00–17:00/);
});

test('list is bounded, authenticated-client only, and preserves full server amounts', async () => {
  const { gateway, calls } = transport(normal);
  const controller = new AbortController();
  const rows = await gateway.listMissions(context, { urgentesOnly: true, tauxMin: 20, etablissementId: 'etab-1' }, controller.signal);
  // Transport deliberately returns a nonurgent row: presentation filters must also reject it.
  assert.equal(rows.length, 0);
  const query = calls[0];
  assert.equal(hasOperation(query, 'eq', 'statut', 'OUVERTE'), true);
  assert.equal(hasOperation(query, 'gte', 'debut_le', now().toISOString()), true);
  assert.equal(hasOperation(query, 'eq', 'profession_requise', 'IDE'), true);
  assert.equal(hasOperation(query, 'eq', 'etablissement_id', 'etab-1'), true);
  assert.equal(hasOperation(query, 'gte', 'taux_horaire_base', 20), true);
  assert.equal(hasOperation(query, 'limit', 500), true);
  assert.deepEqual(calls.find(c => c.source === 'fn_etablissements_safe')?.params, { p_ids: ['etab-1'] });
  assert.equal(calls.every(c => c.operations.some(([name, signal]) => name === 'abortSignal' && signal === controller.signal)), true);
  const [result] = await gateway.listMissions(context);
  assert.equal(result.taux_horaire_base, 26.75);
  assert.equal(result.taux_rist_plafonne, 26.75);
  assert.equal(result.rist_plafond_applique, true);
  assert.equal(result.net_a_payer, 167.11);
  assert.equal(result.planning_exact, true);
});

test('detail always re-reads the requested id, including permissions lost since list', async () => {
  let denied = false;
  const { gateway, calls } = transport(call => call.source === 'missions' && denied ? ok(null) : normal(call));
  assert.equal((await gateway.getMission('mission-1', context))?.id, 'mission-1');
  denied = true;
  assert.equal(await gateway.getMission('mission-1', context), null);
  const reads = calls.filter(c => c.source === 'missions');
  assert.equal(reads.length, 2);
  assert.equal(reads.every(call => hasOperation(call, 'eq', 'id', 'mission-1')), true);
  assert.equal(reads.every(call => !call.operations.some(([name, column]) => name === 'eq' && column === 'statut')), true);
});

test('data errors never fall back to demonstration or an unrestricted query', async () => {
  const { gateway, calls } = transport(() => ({ data: null, error: { message: 'private server error' } }));
  await assert.rejects(gateway.listMissions(context), /Impossible de charger les missions/);
  await assert.rejects(gateway.getMission('mission-1', context), /Impossible de charger cette mission/);
  await assert.rejects(gateway.getRole(), /Impossible de vérifier/);
  assert.equal(calls.length, 3);
  await assert.rejects(gateway.listMissions({ ...context, userId: 'other-user' }), /ne correspond pas/);
  assert.equal(calls.length, 3);
});

test('profile identity and fixture suppression are checked before enrichment', async () => {
  const profileTransport = transport(() => ok({ ...context.profile, id: 'different-user' }));
  await assert.rejects(profileTransport.gateway.getProfile(context.userId), /ne correspond pas/);
  const { gateway, calls } = transport(() => ok(record({ intitule: '[playwright-test] Secret fixture' })));
  assert.equal(await gateway.getMission('mission-1', context), null);
  assert.equal(calls.length, 1);
  const substituted = transport(() => ok(record({ id: 'other-mission' })));
  await assert.rejects(substituted.gateway.getMission('mission-1', context), /ne correspond pas/);
});

test('slot pagination consumes all rows even when an intermediate page is shorter than requested', async () => {
  const second = slot({ id: 'slot-2', debut: '2026-10-29T08:00:00Z', fin: '2026-10-29T16:00:00Z' });
  const { gateway, calls } = transport(call => {
    if (call.source === 'missions') return ok(record({ nb_creneaux: 2, fin_le: second.fin!, duree_heures: 16 }));
    if (call.source === 'mission_creneaux') return ok(hasOperation(call, 'range', 0, 499) ? [slot()] : [second], 2);
    return normal(call);
  });
  const result = await gateway.getMission('mission-1', context);
  assert.equal(result?.creneaux_planifies.length, 2);
  assert.equal(result?.planning_exact, true);
  assert.equal(calls.some(call => hasOperation(call, 'range', 1, 500)), true);
});

test('missing, duplicate, substituted or changing slot pages fail closed', async t => {
  for (const [name, secondPage] of [
    ['missing', ok([], 2)], ['duplicate', ok([slot()], 2)],
    ['substitution', ok([slot({ id: 'slot-2', mission_id: 'another-mission' })], 2)],
    ['changed count', ok([slot({ id: 'slot-2' })], 3)], ['unknown count', ok([], null)],
  ] as const) {
    await t.test(name, async () => {
      const { gateway } = transport(call => call.source === 'mission_creneaux'
        ? (hasOperation(call, 'range', 0, 499) ? ok([slot()], 2) : secondPage) : normal(call));
      await assert.rejects(gateway.getMission('mission-1', context), /planning|créneaux/i);
    });
  }
});

test('aborted requests never expose late data or start fresh queries', async () => {
  const controller = new AbortController();
  const early = transport(normal);
  controller.abort();
  await assert.rejects(early.gateway.listMissions(context, {}, controller.signal), { name: 'AbortError' });
  assert.equal(early.calls.length, 0);
  const lateController = new AbortController();
  const late = transport(call => { lateController.abort(); return normal(call); });
  await assert.rejects(late.gateway.getMission('mission-1', context, lateController.signal), { name: 'AbortError' });
  assert.equal(late.calls.length, 1);
});

test('demonstration is explicit, synthetic and cannot accept a real profile context', async () => {
  const gateway = new DemoGateway(now);
  assert.equal(gateway.mode, 'demo');
  const rows = await gateway.listMissions(DEMO_CONTEXT);
  assert.equal(rows.length, 30);
  assert.equal(rows.every(row => row.intitule.startsWith('Démonstration')), true);
  assert.equal(rows.every(row => row.planning_exact), true);
  assert.equal((await gateway.getMission(rows[0].id, DEMO_CONTEXT))?.id, rows[0].id);
  await assert.rejects(gateway.listMissions(context), /profil fictif/);
  assert.equal(await gateway.getProfile(context.userId), null);
  const controller = new AbortController(); controller.abort();
  await assert.rejects(gateway.getMission(rows[0].id, DEMO_CONTEXT, controller.signal), { name: 'AbortError' });
});
