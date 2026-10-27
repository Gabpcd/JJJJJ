import assert from 'node:assert/strict';
import test from 'node:test';
import type { SupabaseClient } from '@supabase/supabase-js';
import { DEMO_CONTEXT, DemoGateway } from '../../data/demoGateway';
import type { MissionReadContext } from '../../data/types';
import { createApplicationController } from './controller';
import { DemoMissionWorkflowGateway } from './demoGateway';
import { SupabaseMissionWorkflowGateway } from './supabaseGateway';
import { acceptanceEmailJobs, sendAcceptanceEmails } from './acceptanceEmails';
import { applicationAction, applicationDisplayStatus, hasActiveAssignment, type ApplicationSnapshot, type ApplyResult, type MissionWorkflowGateway } from './types';

const context: MissionReadContext = { ...DEMO_CONTEXT, userId: 'soignant-test', profile: { ...DEMO_CONTEXT.profile, id: 'soignant-test' } };
async function sample(): Promise<ApplicationSnapshot> {
  const snapshot = await new DemoMissionWorkflowGateway(new DemoGateway(() => new Date('2026-10-27T10:00:00Z')))
    .readApplication(DEMO_CONTEXT, 'demo-mission-001');
  assert.ok(snapshot);
  return { ...snapshot, userId: context.userId, mission: { ...snapshot.mission, id: 'mission-test', intitule: 'Mission de transport unitaire' } };
}
function deferred<T>() { let resolve!: (value: T) => void; const promise = new Promise<T>(done => { resolve = done; }); return { promise, resolve }; }
function fakeGateway(snapshot: ApplicationSnapshot, apply: MissionWorkflowGateway['apply']): MissionWorkflowGateway {
  return { mode: 'supabase', listMine: async () => ({ rows: [], page: 0, hasMore: false }), readApplication: async () => snapshot, apply,
    retryAcceptanceEmails: async () => [] };
}

test('controller permits one explicit send and ignores its response after disposal', async () => {
  const snapshot = await sample(); const pending = deferred<ApplyResult>(); let calls = 0;
  const controller = createApplicationController(fakeGateway(snapshot, async () => { calls++; return pending.promise; }), context, snapshot.mission.id);
  await controller.refresh();
  const first = controller.submit({ message: 'Disponible' });
  await controller.submit({ message: 'Second appui' });
  assert.equal(calls, 1); assert.equal(controller.getSnapshot().submitting, true);
  controller.dispose(); const disposedState = controller.getSnapshot();
  pending.resolve({ kind: 'confirmed', snapshot: { ...snapshot, assignedTo: context.userId }, documentsToComplete: false });
  await first; assert.equal(controller.getSnapshot(), disposedState);
});

test('uncertain mutation requires a successful explicit reread before another send', async () => {
  const snapshot = await sample(); let calls = 0;
  const controller = createApplicationController(fakeGateway(snapshot, async () => {
    calls++; return { kind: 'unconfirmed', snapshot: null, message: 'À vérifier' };
  }), context, snapshot.mission.id);
  await controller.refresh(); await controller.submit({ message: '' }); await controller.submit({ message: '' });
  assert.equal(calls, 1); assert.equal(controller.getSnapshot().needsRecheck, true);
  await controller.refresh(); assert.equal(controller.getSnapshot().needsRecheck, false);
  await controller.submit({ message: '' }); assert.equal(calls, 2); controller.dispose();
});

test('late read cannot overwrite a more recent read', async () => {
  const snapshot = await sample(); const older = deferred<ApplicationSnapshot>(); let reads = 0;
  const gateway = fakeGateway(snapshot, async () => { throw new Error('Not used'); });
  gateway.readApplication = async () => ++reads === 1 ? older.promise : { ...snapshot, assignedTo: context.userId };
  const controller = createApplicationController(gateway, context, snapshot.mission.id);
  const first = controller.refresh(); await controller.refresh(); older.resolve(snapshot); await first;
  assert.equal(controller.getSnapshot().data?.assignedTo, context.userId); controller.dispose();
});

test('missing persisted planning, unknown attribution and incomplete profile cannot authorize a request', async () => {
  const snapshot = await sample(); assert.equal(applicationAction(snapshot), 'POSTULER');
  assert.equal(applicationAction({ ...snapshot, attribution: 'PREMIER_ARRIVE' }), 'ACCEPTER');
  assert.equal(applicationAction({ ...snapshot, attribution: null }), null);
  assert.equal(applicationAction({ ...snapshot, exactPersistedPlanning: false }), null);
  assert.equal(applicationAction({ ...snapshot, canApply: false }), null);
  assert.equal(applicationAction({ ...snapshot, assignedTo: 'another-person' }), null);
});

test('demo applications are local, explicit, isolated by account, and visible in My missions', async () => {
  const demo = new DemoMissionWorkflowGateway(); const before = await demo.readApplication(DEMO_CONTEXT, 'demo-mission-001');
  assert.ok(before); assert.equal(demo.mode, 'demo');
  const result = await demo.apply(DEMO_CONTEXT, before, { message: 'Fictif' });
  assert.equal(result.kind, 'confirmed');
  const list = await demo.listMine(DEMO_CONTEXT, 'candidatures');
  assert.equal(list.rows.length, 1); assert.equal(list.rows[0].applicationStatus, 'EN_ATTENTE');
  assert.equal((await demo.listMine(DEMO_CONTEXT, 'actives')).rows.length, 0);
  await assert.rejects(demo.listMine(context, 'candidatures'), /démonstration/);
});

interface Call { source: string; params?: any; operations: Array<[string, ...any[]]> }
interface Response { data: any; error: unknown; count?: number | null }
/** Transport doubles only; no deployed database, RLS, SMS or provider is exercised here. */
function transport(snapshot: ApplicationSnapshot, options: { refused?: boolean; choice?: boolean; unreadable?: boolean; otherUser?: boolean;
  changeAccountDuringIdentityCheck?: boolean; direct?: boolean; emailFailureOnce?: boolean; unknownMutationSuccess?: boolean; missingReference?: boolean; currentStatus?: string } = {}) {
  const calls: Call[] = []; let sent = false; let sessionUser = context.userId; let emailFailed = false;
  const confirmed = { ...snapshot, application: { id: 'application-test', statut: 'EN_ATTENTE', type_contrat_choisi: 'SALARIE' } };
  const handle = (call: Call): Response => {
    if (call.source === 'fn_confirmer_action_planning_v1') {
      sent = true;
      if (options.choice) return { data: { choix_requis: true, options: [{ value: 'SALARIE', label: 'Salarié' }, { value: 'LIBERAL', label: 'Libéral' }] }, error: null };
      if (options.refused) return { data: { success: false, error: 'Le planning a changé.' }, error: null };
      if (options.unknownMutationSuccess) return { data: null, error: new Error('Response lost after commit') };
      return { data: { success: true, docs_a_completer: true, contrat_id: options.direct && !options.missingReference ? 'contract-test' : undefined }, error: null };
    }
    if (sent && options.unreadable) return { data: null, error: new Error('Network') };
    if (call.source === 'missions') return { data: {
      ...snapshot.mission, mode_attribution: options.direct ? 'PREMIER_ARRIVE' : 'CANDIDATURE',
      statut: options.currentStatus ?? (options.direct && sent ? 'ASSIGNEE' : snapshot.mission.statut),
      soignant_assigne_id: options.direct && sent ? context.userId : null, type_contrat_applique: options.direct && sent ? 'SALARIE' : null,
      modifie_le: options.missingReference ? null : '2026-10-27T10:00:00+00:00',
    }, error: null };
    if (call.source === 'fn_mon_profil_soignant_complet') return { data: {
      id: context.userId, prenom: 'Camille', nom: 'Recette', profession: 'IDE', date_naissance: '1990-01-01', telephone: 'test', rpps_verifie: true, tous_documents_valides: false,
    }, error: null };
    if (call.source === 'candidatures') return { data: sent && !options.refused && !options.choice && !options.direct ? [confirmed.application] : [], error: null };
    if (call.source === 'fn_etablissements_safe') return { data: [snapshot.mission.etablissements], error: null };
    if (call.source === 'mission_creneaux') return { data: snapshot.mission.creneaux_planifies.map(slot => ({ ...slot, mission_id: snapshot.mission.id })), error: null, count: snapshot.mission.creneaux_planifies.length };
    throw new Error(`Unexpected ${call.source}`);
  };
  class Query implements PromiseLike<Response> {
    constructor(private readonly call: Call) { calls.push(call); }
    op(name: string, ...args: any[]) { this.call.operations.push([name, ...args]); return this; }
    select(...args: any[]) { return this.op('select', ...args); } eq(...args: any[]) { return this.op('eq', ...args); }
    in(...args: any[]) { return this.op('in', ...args); } order(...args: any[]) { return this.op('order', ...args); }
    limit(...args: any[]) { return this.op('limit', ...args); } range(...args: any[]) { return this.op('range', ...args); }
    maybeSingle(...args: any[]) { return this.op('maybeSingle', ...args); } abortSignal(...args: any[]) { return this.op('abortSignal', ...args); }
    setHeader(...args: any[]) { return this.op('setHeader', ...args); }
    then<TResult1 = Response, TResult2 = never>(onfulfilled?: ((value: Response) => TResult1 | PromiseLike<TResult1>) | null,
      onrejected?: ((reason: unknown) => TResult2 | PromiseLike<TResult2>) | null): PromiseLike<TResult1 | TResult2> {
      return Promise.resolve().then(() => handle(this.call)).then(onfulfilled, onrejected);
    }
  }
  const client = {
    from: (source: string) => new Query({ source, operations: [] }), rpc: (source: string, params?: any) => new Query({ source, params, operations: [] }),
    auth: {
      getSession: async () => ({ data: { session: { access_token: 'unit-test-token-bound-to-original-user', user: { id: options.otherUser ? 'other' : sessionUser } } }, error: null }),
      getUser: async () => { if (options.changeAccountDuringIdentityCheck) sessionUser = 'other'; return { data: { user: { id: context.userId } }, error: null }; },
    },
    functions: { invoke: async (source: string, params: any) => {
      calls.push({ source, params, operations: [] });
      if (options.emailFailureOnce && params.body.type === 'MISSION_ACCEPTEE_SOIGNANT' && !emailFailed) {
        emailFailed = true; return { data: null, error: new Error('Email transport unavailable') };
      }
      return { data: { success: true }, error: null };
    } },
  } as unknown as SupabaseClient;
  return { gateway: new SupabaseMissionWorkflowGateway(client), calls };
}

test('authenticated action sends the displayed slots and fixed JWT then confirms a persisted application', async () => {
  const snapshot = await sample(); const { gateway, calls } = transport(snapshot, { changeAccountDuringIdentityCheck: true });
  const result = await gateway.apply(context, snapshot, { message: ' Disponible ', contractChoice: 'SALARIE' });
  assert.equal(result.kind, 'confirmed');
  const mutations = calls.filter(call => call.source === 'fn_confirmer_action_planning_v1'); assert.equal(mutations.length, 1);
  assert.deepEqual(mutations[0].params, { p_mission_id: snapshot.mission.id, p_action: 'POSTULER',
    p_creneaux_confirmes: snapshot.mission.creneaux_planifies.map(slot => ({ debut: slot.debut, fin: slot.fin })), p_message: 'Disponible', p_choix_contrat: 'SALARIE', p_candidature_id: null });
  assert.deepEqual(mutations[0].operations, [['setHeader', 'Authorization', 'Bearer unit-test-token-bound-to-original-user']]);
  assert.ok(calls.find(call => call.source === 'candidatures'));
});

test('a different current user cannot issue the action', async () => {
  const snapshot = await sample(); const { gateway, calls } = transport(snapshot, { otherUser: true });
  await assert.rejects(gateway.apply(context, snapshot, { message: '' }), /session a changé/);
  assert.equal(calls.length, 0);
});

test('readback failure is not success; server choice and rejection remain distinct', async () => {
  const snapshot = await sample();
  assert.equal((await transport(snapshot, { unreadable: true }).gateway.apply(context, snapshot, { message: '' })).kind, 'unconfirmed');
  const choice = await transport(snapshot, { choice: true }).gateway.apply(context, snapshot, { message: '' });
  assert.equal(choice.kind, 'choice'); if (choice.kind === 'choice') assert.deepEqual(choice.options.map(item => item.value), ['SALARIE', 'LIBERAL']);
  const refusal = await transport(snapshot, { refused: true }).gateway.apply(context, snapshot, { message: '' });
  assert.equal(refusal.kind, 'rejected'); if (refusal.kind === 'rejected') assert.match(refusal.message, /planning a changé/);
});

test('an accepted assignment survives email failure; retry sends only the missing email with identical idempotency body', async () => {
  const snapshot = { ...await sample(), attribution: 'PREMIER_ARRIVE' };
  const { gateway, calls } = transport(snapshot, { direct: true, emailFailureOnce: true });
  const result = await gateway.apply(context, snapshot, { message: '' });
  assert.equal(result.kind, 'confirmed');
  if (result.kind !== 'confirmed') return;
  assert.equal(result.snapshot.assignedTo, context.userId);
  assert.deepEqual(result.snapshot.acceptanceEmails?.map(receipt => receipt.state), ['failed', 'sent']);
  const before = calls.filter(call => call.source === 'send-email'); assert.equal(before.length, 2);
  const firstBody = JSON.parse(JSON.stringify(before[0].params.body));
  assert.equal(firstBody.type, 'MISSION_ACCEPTEE_SOIGNANT');
  assert.equal(firstBody.idempotency_key, 'native-acceptance:mission-test:soignant-test:contract-test:soignant');
  assert.equal(firstBody.data.prenom, 'Camille'); assert.equal(firstBody.data.mission_id, snapshot.mission.id);
  assert.equal(before[1].params.body.destinataire_id, snapshot.mission.etablissement_id);
  assert.deepEqual(before[0].params.headers, { Authorization: 'Bearer unit-test-token-bound-to-original-user' });
  const receipts = await gateway.retryAcceptanceEmails(context, snapshot.mission.id);
  assert.deepEqual(receipts.map(receipt => receipt.state), ['sent', 'sent']);
  const after = calls.filter(call => call.source === 'send-email'); assert.equal(after.length, 3);
  assert.deepEqual(after[2].params.body, firstBody);
  assert.equal(calls.filter(call => call.source === 'fn_confirmer_action_planning_v1').length, 1);
  assert.deepEqual((await gateway.readApplication(context, snapshot.mission.id))?.acceptanceEmails?.map(receipt => receipt.state), ['sent', 'sent']);
});

test('unknown assignment response is reconciled and timestamp fallback yields a stable email reference', async () => {
  const snapshot = { ...await sample(), attribution: 'PREMIER_ARRIVE' };
  const { gateway, calls } = transport(snapshot, { direct: true, unknownMutationSuccess: true });
  const result = await gateway.apply(context, snapshot, { message: '' });
  assert.equal(result.kind, 'confirmed');
  const emails = calls.filter(call => call.source === 'send-email');
  assert.equal(emails.length, 2);
  assert.equal(emails[0].params.body.idempotency_key, 'native-acceptance:mission-test:soignant-test:2026-10-27T10:00:00.000Z:soignant');
  assert.equal(calls.filter(call => call.source === 'fn_confirmer_action_planning_v1').length, 1);
});

test('missing assignment reference is visible after reread and never replays assignment or sends an unsafe email', async () => {
  const snapshot = { ...await sample(), attribution: 'PREMIER_ARRIVE' };
  const { gateway, calls } = transport(snapshot, { direct: true, missingReference: true });
  const result = await gateway.apply(context, snapshot, { message: '' });
  assert.equal(result.kind, 'confirmed');
  const fresh = await gateway.readApplication(context, snapshot.mission.id);
  assert.equal(fresh?.assignedTo, context.userId);
  assert.deepEqual(fresh?.acceptanceEmails?.map(receipt => receipt.reason), ['preparation_failed', 'preparation_failed']);
  assert.equal(calls.filter(call => call.source === 'send-email').length, 0);
  assert.equal(calls.filter(call => call.source === 'fn_confirmer_action_planning_v1').length, 1);
});

test('email receipt distinguishes TEST suppression and pending reservation from accepted delivery request', async () => {
  const snapshot = await sample(); const jobs = acceptanceEmailJobs(snapshot, 'contract-test'); let attempts = 0;
  const client = { functions: { invoke: async (_name: string, options: any) => {
    attempts++;
    return { error: null, data: options.body.type === 'MISSION_ACCEPTEE_ETABLISSEMENT'
      ? { success: true, skipped: true, reason: 'test_account' }
      : attempts === 1 ? { success: true, pending: true } : { success: true, skipped: true, reason: 'idempotency_already_sent' } };
  } } } as unknown as SupabaseClient;
  assert.deepEqual((await sendAcceptanceEmails(client, 'test-token', jobs)).map(receipt => receipt.state), ['pending', 'skipped']);
  assert.deepEqual((await sendAcceptanceEmails(client, 'test-token', jobs)).map(receipt => receipt.state), ['sent', 'skipped']);
  assert.equal(attempts, 3);
});


test('cancelled or finished assignment is displayed as history and cannot resend acceptance emails', async () => {
  const snapshot = { ...await sample(), attribution: 'PREMIER_ARRIVE' };
  const options = { direct: true, emailFailureOnce: true, currentStatus: undefined as string | undefined };
  const { gateway, calls } = transport(snapshot, options);
  assert.equal((await gateway.apply(context, snapshot, { message: '' })).kind, 'confirmed');
  const sentBefore = calls.filter(call => call.source === 'send-email').length;
  for (const status of ['ANNULEE_PAR_ETABLISSEMENT', 'TERMINEE', 'EXPIREE']) {
    options.currentStatus = status;
    const fresh = await gateway.readApplication(context, snapshot.mission.id);
    assert.ok(fresh);
    fresh.application = { id: 'old-accepted', statut: 'ACCEPTEE', type_contrat_choisi: 'SALARIE' };
    assert.equal(applicationDisplayStatus(fresh), status);
    assert.equal(hasActiveAssignment(fresh), false);
    await assert.rejects(gateway.retryAcceptanceEmails(context, snapshot.mission.id), /plus active/);
    assert.equal(calls.filter(call => call.source === 'send-email').length, sentBefore);
  }
});


test('synthetic history keeps the cancelled assignment but refuses new actions and email retries', async () => {
  const demo = new DemoMissionWorkflowGateway();
  const history = await demo.listMine(DEMO_CONTEXT, 'passees');
  assert.equal(history.rows[0].status, 'ANNULEE_PAR_ETABLISSEMENT');
  const snapshot = await demo.readApplication(DEMO_CONTEXT, history.rows[0].id);
  assert.ok(snapshot);
  assert.equal(snapshot.assignedTo, DEMO_CONTEXT.userId);
  assert.equal(applicationDisplayStatus(snapshot), 'ANNULEE_PAR_ETABLISSEMENT');
  assert.equal((await demo.apply(DEMO_CONTEXT, snapshot, { message: '' })).kind, 'rejected');
  await assert.rejects(demo.retryAcceptanceEmails(DEMO_CONTEXT, snapshot.mission.id));
});
