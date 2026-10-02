import { readFileSync } from 'node:fs';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import {
  estSessionCheckout, etatRetourConnect, lireSuiviRemboursementConnect,
  type SuiviRemboursementConnect,
} from '../../../src/lib/suiviRemboursementConnect';

const { rpc, from } = vi.hoisted(() => ({ rpc: vi.fn(), from: vi.fn() }));
vi.mock('@/integrations/supabase/client', () => ({ supabase: { rpc, from } }));
import ts from 'typescript';

const checkout = readFileSync('src/components/StripeEmbeddedCheckout.tsx', 'utf8');
const detail = readFileSync('src/pages/DetailMission.tsx', 'utf8');
const facturation = readFileSync('src/pages/FacturationEtablissement.tsx', 'utf8');
const migration = readFileSync(
  'supabase/migrations/20260801212950_dedupliquer_revenus_connect_soignant.sql',
  'utf8',
);

// Exécuter les callbacks réellement présents dans la page, sans React, réseau
// ni recopie de leur logique. L'extraction AST exige une seule déclaration.
function callback<T>(name: string, scope: Record<string, unknown>): T {
  const source = ts.createSourceFile('FacturationEtablissement.tsx', facturation, ts.ScriptTarget.Latest, true, ts.ScriptKind.TSX);
  const declarations: ts.VariableDeclaration[] = [];
  function visit(node: ts.Node) {
    if (ts.isVariableDeclaration(node) && ts.isIdentifier(node.name) && node.name.text === name) declarations.push(node);
    ts.forEachChild(node, visit);
  }
  visit(source);
  expect(declarations).toHaveLength(1);
  const initializer = declarations[0].initializer!;
  const expression = ts.isCallExpression(initializer) ? initializer.arguments[0] : initializer;
  expect(ts.isArrowFunction(expression)).toBe(true);
  const js = ts.transpileModule(`const callback = ${expression.getText(source)};`, {
    compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext },
  }).outputText;
  return new Function(...Object.keys(scope), `${js}; return callback;`)(...Object.values(scope)) as T;
}

type PaymentContext = { missionId?: string; factureHonoraireId?: string; checkoutSessionId?: string };
const contexte = { missionId: 'mission', factureHonoraireId: 'facture', checkoutSessionId: 'cs_fixture_id' };
const args = { p_facture_honoraire_id: 'facture', p_checkout_session_id: 'cs_fixture_id' };
const erreurLecture = 'Impossible de vérifier le paiement pour le moment. Consultez son suivi avant de réessayer.';
const inconnu = 'Le retour Stripe ne permet pas d’identifier exactement ce paiement. Consultez son suivi avant de réessayer.';

function suivi(paiement_statut: string | null = 'PAYE'): SuiviRemboursementConnect {
  return {
    facture_honoraire_id: 'facture', mission_id: 'mission', checkout_session_id_filtre: 'cs_fixture_id',
    source: 'CONNECT_AVANT_TRANSFERT', visibilite_montants: 'TOTAL_ETABLISSEMENT',
    paiement_statut, operations: [], lecture_complete: true,
  };
}

type Reponse = { data: unknown; error: unknown };
// Seul le transport RPC est simulé. Le lecteur, le parseur et la décision de
// retour sont ceux du produit. Ce mock ne prétend pas exercer le RBAC SQL.
function transport(repondre: (signal: AbortSignal, appel: number) => Reponse | Promise<Reponse>) {
  const signals: AbortSignal[] = [];
  rpc.mockImplementation((nom: string, params: unknown) => {
    expect(nom).toBe('fn_suivi_remboursements_connect_facture');
    expect(params).toEqual(args);
    const appel = rpc.mock.calls.length;
    let signal: AbortSignal;
    const query = {
      abortSignal(s: AbortSignal) { signal = s; signals.push(s); return query; },
      then(resolve: (v: Reponse) => unknown, reject: (e: unknown) => unknown) {
        expect(signal).toBeInstanceOf(AbortSignal);
        return Promise.resolve().then(() => repondre(signal, appel)).then(resolve, reject);
      },
    };
    return query;
  });
  return signals;
}

function finalisation() {
  const scope = {
    confirmationConnectRef: { current: null as AbortController | null },
    estSessionCheckout, etatRetourConnect, lireSuiviRemboursementConnect,
    charger: vi.fn().mockResolvedValue(undefined),
    toast: { success: vi.fn(), error: vi.fn(), info: vi.fn() }, capturerErreurSentry: vi.fn(),
    setSuiviConnect: vi.fn(), setConnectConfirming: vi.fn(), setShowConnectCheckout: vi.fn(),
    setConnectClientSecret: vi.fn(), setConnectPaymentContext: vi.fn(),
  };
  return { scope, run: callback<(context?: PaymentContext) => Promise<void>>('finaliserRetourConnect', scope) };
}

beforeEach(() => {
  vi.useFakeTimers(); rpc.mockReset(); from.mockReset();
  from.mockImplementation(() => { throw new Error('Lecture directe/globalisée interdite dans le retour'); });
});
afterEach(() => { expect(vi.getTimerCount()).toBe(0); vi.useRealTimers(); });

describe('Facturation — confirmation Stripe Connect par pièce et Session fail-closed', () => {
  it('attend le callback asynchrone en conservant l’état de confirmation', () => {
    expect(checkout).toContain('onComplete?: () => void | Promise<void>');
    expect(checkout).toContain('setConfirming(true)');
    expect(checkout).toContain('await onComplete?.()');
    expect(checkout).toContain('finally');
    expect(checkout).not.toContain("toast.success('Paiement envoyé avec succès !')");
  });

  it('retire le Checkout mission-only et lie le retour à la Session explicite', () => {
    expect(detail).not.toContain('StripeEmbeddedCheckout');
    expect(detail).not.toContain('payerMissionStripeConnectAvecGenerationAuto');
    expect(detail).not.toContain('connectClientSecret');
    expect(detail).toContain('<WorkflowPaiementMission');
    const retour = facturation.slice(facturation.indexOf('const finaliserRetourConnect'), facturation.indexOf('const erreurScope'));
    expect(retour).toContain('lireSuiviRemboursementConnect(context.factureHonoraireId, context.checkoutSessionId, controller.signal)');
    expect(retour).not.toContain(".from('stripe_transfers')");
    expect(retour).toContain("searchParams.get('session_id')");
    expect(retour).toContain('canReadFinance');
    expect(retour).toContain('etablissementId');
    expect(facturation).not.toContain('Aucun paiement n’a été enregistré.');
    expect(facturation).not.toContain('Les honoraires du soignant ont été transmis via Stripe');
  });

  it.each(['CHARGE_REUSSI', 'TRANSFERE', 'PAYE'])(
    'confirme %s seulement après la lecture exacte de la facture et de la Session', async (statut) => {
      transport(() => ({ data: suivi(statut), error: null }));
      const { run, scope } = finalisation(); await run(contexte);
      expect(rpc).toHaveBeenCalledExactlyOnceWith('fn_suivi_remboursements_connect_facture', args);
      expect(from).not.toHaveBeenCalled();
      expect(scope.toast.success).toHaveBeenCalledExactlyOnceWith('Paiement confirmé et enregistré.');
      expect(scope.charger).toHaveBeenCalledOnce();
      expect(scope.setConnectConfirming.mock.calls).toEqual([[true], [false]]);
    },
  );

  it.each([
    undefined, { missionId: 'mission' },
    { ...contexte, factureHonoraireId: undefined },
    { ...contexte, checkoutSessionId: undefined },
    { ...contexte, checkoutSessionId: '' },
    { ...contexte, checkoutSessionId: 'cs_invalide/etranger' },
  ])('un retour incomplet ou Session invalide ne lit ni ne confirme : %j', async (ctx: PaymentContext | undefined) => {
    const { run, scope } = finalisation(); await run(ctx);
    expect(rpc).not.toHaveBeenCalled(); expect(from).not.toHaveBeenCalled();
    expect(scope.toast.success).not.toHaveBeenCalled();
    expect(scope.toast.info).toHaveBeenCalledWith(inconnu);
    expect(scope.charger).toHaveBeenCalledOnce();
    expect(scope.setConnectConfirming.mock.calls).toEqual([[true], [false]]);
    if (ctx?.factureHonoraireId) expect(scope.setSuiviConnect).toHaveBeenCalledWith({ factureId: 'facture' });
  });

  it.each([
    { facture_honoraire_id: 'facture-etrangere' },
    { checkout_session_id_filtre: 'cs_etrangere' },
    { mission_id: 'mission-etrangere' },
    { lecture_complete: false },
  ])('refuse une réponse étrangère ou incomplète : %j', async (delta) => {
    transport(() => ({ data: { ...suivi(), ...delta }, error: null }));
    const { run, scope } = finalisation(); await run(contexte);
    expect(rpc).toHaveBeenCalledOnce(); expect(scope.toast.success).not.toHaveBeenCalled();
    expect(scope.toast.error).toHaveBeenCalledWith(erreurLecture);
    expect(scope.setConnectConfirming.mock.calls).toEqual([[true], [false]]);
  });

  it.each([
    { code: '42501', message: 'refus tenant serveur' },
    { code: 'NETWORK', message: 'lecture indisponible' },
  ])('un refus serveur de tenant ou une erreur de lecture reste non confirmé : %j', async (error) => {
    transport(() => ({ data: null, error }));
    const { run, scope } = finalisation(); await run(contexte);
    expect(scope.toast.success).not.toHaveBeenCalled();
    expect(scope.toast.error).toHaveBeenCalledExactlyOnceWith(erreurLecture);
    expect(scope.toast.error.mock.calls.flat().join(' ')).not.toContain(error.message);
    expect(scope.setConnectConfirming.mock.calls).toEqual([[true], [false]]);
  });

  it.each(['ECHOUE', 'REMBOURSE'])('le statut historique %s exige un suivi sans inventer une annulation', async (statut) => {
    transport(() => ({ data: suivi(statut), error: null }));
    const { run, scope } = finalisation(); await run(contexte);
    expect(scope.toast.success).not.toHaveBeenCalled();
    expect(scope.toast.error).not.toHaveBeenCalled();
    expect(scope.toast.info).toHaveBeenCalledWith(expect.stringContaining('nécessite une vérification'));
    expect(scope.setSuiviConnect).toHaveBeenCalledWith({ factureId: 'facture', checkoutSessionId: 'cs_fixture_id' });
    expect(rpc).toHaveBeenCalledOnce();
  });

  it.each(['READY', 'PENDING', 'REQUIRES_ACTION', 'SUCCEEDED', 'FAILED', 'CANCELED', 'REVIEW'] as const)(
    'l’opération courante %s prime sur un paiement historiquement PAYE', async (statut) => {
      const data = suivi('PAYE');
      data.operations.push({ id: 'operation', checkout_session_id: 'cs_fixture_id', statut,
        montant_honoraires_centimes: 6000, montant_commission_centimes: 1080, montant_total_centimes: 7080,
        cree_le: '2026-10-01T10:00:00Z', mis_a_jour_le: null,
        succeeded_at: ['SUCCEEDED', 'REVIEW'].includes(statut) ? '2026-10-01T10:05:00Z' : null,
        review_code: statut === 'REVIEW' ? 'REFUND_RETURNED_AFTER_SUCCESS' : null });
      transport(() => ({ data, error: null }));
      const { run, scope } = finalisation(); await run(contexte);
      expect(scope.toast.success).not.toHaveBeenCalled();
      expect(scope.toast.info).toHaveBeenCalledWith('Un remboursement est suivi pour ce paiement. Consultez son état actuel.');
      expect(scope.setSuiviConnect).toHaveBeenCalledWith({ factureId: 'facture', checkoutSessionId: 'cs_fixture_id' });
      expect(rpc).toHaveBeenCalledOnce();
    },
  );

  it.each(['EN_ATTENTE', null])('borne à huit lectures la confirmation encore absente (%s)', async (statut) => {
    transport(() => ({ data: suivi(statut), error: null }));
    const { run, scope } = finalisation(); const pending = run(contexte);
    await vi.advanceTimersByTimeAsync(19_000); await pending;
    expect(rpc).toHaveBeenCalledTimes(8);
    expect(scope.toast.success).not.toHaveBeenCalled();
    expect(scope.toast.info).toHaveBeenCalledWith(expect.stringContaining('n’est pas disponible pour le moment'));
    expect(scope.setConnectConfirming.mock.calls).toEqual([[true], [false]]);
  });

  it('annule une lecture bloquée à 30 secondes et libère la confirmation sans succès', async () => {
    const signals = transport(signal => new Promise((_resolve, reject) => {
      signal.addEventListener('abort', () => reject(new Error('transport annulé')), { once: true });
    }));
    const { run, scope } = finalisation(); const pending = run(contexte);
    await vi.advanceTimersByTimeAsync(29_999);
    expect(signals[0].aborted).toBe(false); expect(scope.toast.error).not.toHaveBeenCalled();
    await vi.advanceTimersByTimeAsync(1); await pending;
    expect(signals[0].aborted).toBe(true); expect(rpc).toHaveBeenCalledOnce();
    expect(scope.toast.success).not.toHaveBeenCalled();
    expect(scope.toast.error).toHaveBeenCalledWith(erreurLecture);
    expect(scope.setConnectConfirming.mock.calls).toEqual([[true], [false]]);
  });

  it('ignore une ancienne lecture rendue après une nouvelle vérification', async () => {
    let liberer!: (v: Reponse) => void;
    const premiere = new Promise<Reponse>(resolve => { liberer = resolve; });
    const signals = transport((_signal, n) => n === 1 ? premiere : { data: suivi(), error: null });
    const { run, scope } = finalisation(); const ancien = run(contexte);
    await vi.advanceTimersByTimeAsync(0);
    await run(contexte);
    expect(signals[0].aborted).toBe(true);
    liberer({ data: suivi('PAYE'), error: null }); await ancien;
    expect(scope.toast.success).toHaveBeenCalledOnce(); expect(scope.toast.error).not.toHaveBeenCalled();
    expect(scope.setConnectConfirming.mock.calls).toEqual([[true], [true], [false]]);
  });

  it('réutilise le client_secret et sa Session préparés, sans deuxième invocation de paiement', async () => {
    const helper = vi.fn().mockResolvedValue({ result: { client_secret: 'cs_fixture_secret', checkout_session_id: 'cs_fixture_id', total: 72 }, error: null });
    const setSecret = vi.fn(), setContext = vi.fn();
    const prepare = callback<(mission: string, facture?: string) => Promise<void>>('payerStripeConnect', {
      canManagePayments: true, missionsARapprocher: new Set(), estSessionCheckout, stripePromise: Promise.resolve({ fixture: true }),
      supabase: { auth: { getSession: vi.fn().mockResolvedValue({ data: { session: { access_token: 'fixture-token' } } }) } },
      payerMissionStripeConnectAvecGenerationAuto: helper, setConnectPayingId: vi.fn(),
      setConnectClientSecret: setSecret, setConnectPaymentContext: setContext,
      setShowConnectCheckout: vi.fn(), setConnectDecomposition: vi.fn(), charger: vi.fn(),
      toast: { loading: vi.fn(), error: vi.fn(), info: vi.fn(), success: vi.fn(), dismiss: vi.fn() },
      extraireMessageErreur: (error: { code: string }) => error.code,
    });
    await prepare('mission'); expect(helper).not.toHaveBeenCalled();
    await prepare('mission', 'facture');
    expect(helper).toHaveBeenCalledExactlyOnceWith('mission', 'fixture-token', expect.any(Function), 'facture');
    expect(setSecret).toHaveBeenCalledWith('cs_fixture_secret');
    expect(setContext).toHaveBeenCalledWith(contexte);
    transport(() => ({ data: suivi(), error: null }));
    const { run, scope } = finalisation(); await run(setContext.mock.calls[0][0]);
    expect(rpc).toHaveBeenCalledExactlyOnceWith('fn_suivi_remboursements_connect_facture', args);
    expect(scope.toast.success).toHaveBeenCalledWith('Paiement confirmé et enregistré.');
    expect(helper).toHaveBeenCalledOnce();
    const provider = facturation.slice(facturation.indexOf('<EmbeddedCheckoutProvider'), facturation.indexOf('</EmbeddedCheckoutProvider>'));
    expect(provider).toContain('clientSecret: connectClientSecret');
    expect(provider).toContain('finaliserRetourConnect(connectPaymentContext ?? undefined)');
    expect(provider).not.toContain('fetchClientSecret'); expect(provider).not.toContain('.invoke(');
    const edgeFunction = readFileSync('supabase/functions/stripe-connect-pay-mission/index.ts', 'utf8');
    expect(edgeFunction).toContain('checkout_session_id: derniereSessionMission.id');
    expect(edgeFunction).toContain('checkout_session_id: session.id');
  });

  it('exécute atomiquement la migration avec un search_path vide', () => {
    expect(migration.trimStart().startsWith('BEGIN;')).toBe(true);
    expect(migration).toContain("SET search_path TO ''");
    expect(migration.trimEnd().endsWith('COMMIT;')).toBe(true);
  });
});
