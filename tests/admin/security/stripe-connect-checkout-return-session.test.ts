import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import ts from 'typescript';
import { describe, expect, it } from 'vitest';

const source = readFileSync('supabase/functions/stripe-connect-pay-mission/index.ts', 'utf8');
const ast = ts.createSourceFile('checkout.ts', source, ts.ScriptTarget.Latest, true);
const returns: ts.Expression[] = [];
const parameters: ts.Expression[] = [];
function visit(node: ts.Node) {
  if (ts.isCallExpression(node) && node.expression.getText(ast) === 'stripe.checkout.sessions.create') {
    const options = node.arguments[0];
    if (options && ts.isObjectLiteralExpression(options)) {
      for (const field of options.properties) {
        if (ts.isPropertyAssignment(field) && field.name.getText(ast) === 'return_url') returns.push(field.initializer);
      }
    }
  }
  if (ts.isVariableDeclaration(node) && node.name.getText(ast) === 'returnParams' && node.initializer) {
    parameters.push(node.initializer);
  }
  ts.forEachChild(node, visit);
}
visit(ast);

describe('Checkout embedded — retour lié à la Session exacte', () => {
  it.each([
    ['https://jolene.app', 'mission-fixture', 'facture-fixture'],
    ['http://localhost:5173', 'mission & autre', 'facture?#=autre'],
  ])('conserve le marqueur Stripe littéral et les paramètres encodés (%s)', (origin, missionId, factureId) => {
    expect(returns).toHaveLength(1);
    expect(parameters).toHaveLength(1);
    // Exécuter les deux expressions du handler réellement passé au SDK,
    // sans charger Deno, appeler Stripe, ni dupliquer leur construction.
    const url = runInNewContext(`const returnParams = ${parameters[0].getText(ast)}; ${returns[0].getText(ast)}`, {
      URLSearchParams, origin, mission_id: missionId, factureHonoraires: { id: factureId },
    });
    expect(typeof url).toBe('string');
    expect(url.endsWith('&session_id={CHECKOUT_SESSION_ID}')).toBe(true);
    expect(url).not.toContain('%7BCHECKOUT_SESSION_ID%7D');
    const parsed = new URL(url);
    expect(parsed.origin).toBe(origin);
    expect(parsed.pathname).toBe('/etablissement/facturation');
    expect([...parsed.searchParams.keys()]).toEqual(['paiement', 'mission', 'facture_honoraire', 'session_id']);
    expect(parsed.searchParams.get('paiement')).toBe('succes');
    expect(parsed.searchParams.get('mission')).toBe(missionId);
    expect(parsed.searchParams.get('facture_honoraire')).toBe(factureId);
    expect(parsed.searchParams.get('session_id')).toBe('{CHECKOUT_SESSION_ID}');
    expect(parsed.hash).toBe('');
  });
});
