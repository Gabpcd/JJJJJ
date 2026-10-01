import { readFileSync } from 'node:fs';
import { describe, expect, it, vi } from 'vitest';
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

type PaymentContext = { missionId?: string; factureHonoraireId?: string };
function finalisation() {
  const scope = {
    verifierStatutConnect: vi.fn().mockResolvedValue('CONFIRME'), charger: vi.fn(),
    toast: { success: vi.fn(), error: vi.fn(), info: vi.fn() }, capturerErreurSentry: vi.fn(),
    setConnectConfirming: vi.fn(), setShowConnectCheckout: vi.fn(),
    setConnectClientSecret: vi.fn(), setConnectPaymentContext: vi.fn(),
  };
  return { scope, run: callback<(context?: PaymentContext) => Promise<void>>('finaliserRetourConnect', scope) };
}

describe('Facturation — confirmation Stripe Connect par pièce fail-closed', () => {
  it('attend le callback asynchrone en conservant l’état de confirmation', () => {
    expect(checkout).toContain('onComplete?: () => void | Promise<void>');
    expect(checkout).toContain('setConfirming(true)');
    expect(checkout).toContain('await onComplete?.()');
    expect(checkout).toContain('finally');
    expect(checkout).not.toContain("toast.success('Paiement envoyé avec succès !')");
  });

  it('retire le Checkout mission-only de la fiche et confirme uniquement la facture du tenant', () => {
    expect(detail).not.toContain('StripeEmbeddedCheckout');
    expect(detail).not.toContain('payerMissionStripeConnectAvecGenerationAuto');
    expect(detail).not.toContain('connectClientSecret');
    expect(detail).toContain('<WorkflowPaiementMission');
    const verificationConnect = facturation.slice(
      facturation.indexOf('const verifierStatutConnect'),
      facturation.indexOf('const finaliserRetourConnect'),
    );
    expect(verificationConnect).toContain(".from('stripe_transfers')");
    expect(verificationConnect).toContain(".select('statut')");
    expect(verificationConnect).toContain(".eq('mission_id', missionId)");
    expect(verificationConnect).toContain(".eq('etablissement_id', etablissementId)");
    expect(verificationConnect).toContain(".eq('facture_honoraire_id', factureHonoraireId)");
    // Le retour rechargeable est qualifié par facture ; la page ne prétend
    // pas conserver une session Checkout exacte comme l'ancien détail.
    expect(verificationConnect).toContain("if (!etablissementId || !factureHonoraireId) return 'EN_ATTENTE'");
    expect(verificationConnect).toContain("['CHARGE_REUSSI', 'TRANSFERE', 'PAYE'].includes(statut)");
    expect(verificationConnect).toContain("statut === 'ECHOUE'");
    expect(facturation).toContain("toast.success('Paiement confirmé et enregistré.')");
    expect(facturation).toContain("toast.error('Le paiement Stripe a échoué. Aucun paiement n’a été enregistré.')");
    expect(facturation).toContain('La confirmation est encore en cours');
    expect(facturation).not.toContain('Les honoraires du soignant ont été transmis via Stripe');
  });

  it.each(['CHARGE_REUSSI', 'TRANSFERE', 'PAYE', 'ECHOUE', 'EN_ATTENTE'])(
    'ignore les succès d’une autre pièce/mission/établissement et lit le statut %s de la pièce sélectionnée', async (statut) => {
      const rows = [
        { etablissement_id: 'autre-etab', mission_id: 'mission', facture_honoraire_id: 'facture', statut: 'PAYE' },
        { etablissement_id: 'etab', mission_id: 'autre-mission', facture_honoraire_id: 'facture', statut: 'PAYE' },
        { etablissement_id: 'etab', mission_id: 'mission', facture_honoraire_id: 'autre-facture', statut: 'PAYE' },
        { etablissement_id: 'etab', mission_id: 'mission', facture_honoraire_id: 'facture', statut },
      ];
      const filters: [string, string][] = [];
      const query = {
        select: vi.fn().mockReturnThis(), order: vi.fn().mockReturnThis(), limit: vi.fn().mockReturnThis(),
        eq(key: string, value: string) { filters.push([key, value]); return this; },
        maybeSingle: vi.fn(async () => ({ data: rows.filter(row => filters.every(([key,value]) => row[key as keyof typeof row] === value))[0], error: null })),
      };
      const from = vi.fn(() => query);
      const run = callback<(mission?: string, facture?: string) => Promise<string>>('verifierStatutConnect', { supabase: { from }, etablissementId: 'etab' });
      expect(await run('mission')).toBe('EN_ATTENTE');
      expect(from).not.toHaveBeenCalled();
      expect(await run('mission', 'facture')).toBe(statut === 'ECHOUE' ? 'ECHEC' : statut === 'EN_ATTENTE' ? 'EN_ATTENTE' : 'CONFIRME');
      expect(filters).toEqual([['etablissement_id','etab'],['mission_id','mission'],['facture_honoraire_id','facture']]);
    },
  );

  it('un retour sans FK recharge sans recherche globale ni confirmation', async () => {
    const { run, scope } = finalisation();
    await run({ missionId: 'mission' });
    expect(scope.verifierStatutConnect).not.toHaveBeenCalled();
    expect(scope.toast.success).not.toHaveBeenCalled();
    expect(scope.toast.info).toHaveBeenCalledWith(expect.stringContaining('sans facture identifiée'));
    expect(scope.charger).toHaveBeenCalledOnce();
    expect(scope.setConnectConfirming.mock.calls).toEqual([[true],[false]]);
  });

  it('une lecture de confirmation en erreur reste non confirmée et libère l’attente', async () => {
    const { run, scope } = finalisation();
    scope.verifierStatutConnect.mockRejectedValue(new Error('lecture indisponible'));
    await run({ missionId: 'mission', factureHonoraireId: 'facture' });
    expect(scope.toast.success).not.toHaveBeenCalled();
    expect(scope.toast.error).toHaveBeenCalledWith('Impossible de confirmer le paiement pour le moment. Son statut reste en attente, sans le déclarer payé.');
    expect(scope.setConnectConfirming.mock.calls).toEqual([[true],[false]]);
  });

  it('réutilise le client_secret préparé pour la FK et confirme sans deuxième invocation de paiement', async () => {
    const helper = vi.fn().mockResolvedValue({ result: { client_secret: 'cs_fixture_secret', total: 72 }, error: null });
    const setSecret = vi.fn(), setContext = vi.fn();
    const prepare = callback<(mission: string, facture?: string) => Promise<void>>('payerStripeConnect', {
      canManagePayments: true, missionsARapprocher: new Set(),
      supabase: { auth: { getSession: vi.fn().mockResolvedValue({ data: { session: { access_token: 'fixture-token' } } }) } },
      payerMissionStripeConnectAvecGenerationAuto: helper, setConnectPayingId: vi.fn(),
      setConnectClientSecret: setSecret, setConnectPaymentContext: setContext,
      setShowConnectCheckout: vi.fn(), setConnectDecomposition: vi.fn(), charger: vi.fn(),
      toast: { loading: vi.fn(), error: vi.fn(), info: vi.fn(), success: vi.fn(), dismiss: vi.fn() },
      extraireMessageErreur: (error: { code: string }) => error.code,
    });
    await prepare('mission');
    expect(helper).not.toHaveBeenCalled();
    await prepare('mission', 'facture');
    expect(helper).toHaveBeenCalledWith('mission', 'fixture-token', expect.any(Function), 'facture');
    expect(setSecret).toHaveBeenCalledWith('cs_fixture_secret');
    expect(setContext).toHaveBeenCalledWith({ missionId: 'mission', factureHonoraireId: 'facture' });
    const { run, scope } = finalisation();
    await run(setContext.mock.calls[0][0]);
    expect(scope.verifierStatutConnect).toHaveBeenCalledWith('mission', 'facture');
    expect(scope.toast.success).toHaveBeenCalledWith('Paiement confirmé et enregistré.');
    expect(helper).toHaveBeenCalledOnce();
    const provider = facturation.slice(facturation.indexOf('<EmbeddedCheckoutProvider'), facturation.indexOf('</EmbeddedCheckoutProvider>'));
    expect(provider).toContain('clientSecret: connectClientSecret');
    expect(provider).toContain('finaliserRetourConnect(connectPaymentContext ?? undefined)');
    expect(provider).not.toContain('fetchClientSecret');
    expect(provider).not.toContain('.invoke(');
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
