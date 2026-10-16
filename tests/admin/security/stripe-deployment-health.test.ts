import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { parse } from 'yaml';
import { describe, expect, it } from 'vitest';

const workflow = parse(readFileSync('.github/workflows/deploy-supabase.yml', 'utf8'));
type Step = { name?: string; run?: string; if?: string };
const steps: Step[] = workflow.jobs['deploy-functions'].steps;
const step = steps.find(candidate => candidate.name === 'Vérifier la configuration Stripe production')!;
const complete = {
  deployment_ready: true, configured: true, reachable: true, authenticated: true, livemode: true, mode: 'live',
  webhook_secret_configured: true, platform_webhook_secret_configured: true, connect_webhook_secret_configured: true,
  webhook_secrets_distinct: true, webhook_endpoint_active: true, webhook_events_complete: true,
  platform_webhook_endpoint_active: true, platform_webhook_events_complete: true, platform_webhook_api_version_ok: true,
  connect_webhook_endpoint_active: true, connect_webhook_events_complete: true, connect_webhook_api_version_ok: true,
  expected_webhook_api_version: '2026-02-25.clover', customer_tenant_links_checked: true, customer_tenant_links_ok: true,
  customer_tenant_links_total: 2, customer_tenant_links_valid: 2, customer_tenant_links_adoptable_legacy: 0,
  customer_tenant_links_indeterminate: 0, connect_release_checked: true, connect_release_open: false, production_ready: false,
};
function runHealth(body: unknown = complete, code = '503', raw = false) {
  const dir = mkdtempSync(join(tmpdir(), 'jolene-stripe-deploy-'));
  const capture = join(dir, 'requests.jsonl');
  writeFileSync(capture, '');
  try {
    // Exécution du vrai shell et du vrai filtre jq, seul transport remplacé.
    // Les retries sont conservés ; sleep est neutralisé dans ce banc sans réseau.
    writeFileSync(join(dir, 'curl'), `#!${process.execPath}\n` + String.raw`
const fs=require('node:fs'), args=process.argv.slice(2);
fs.appendFileSync(process.env.FAKE_CAPTURE,JSON.stringify(args)+'\n');
fs.writeFileSync(args[args.indexOf('-o')+1],process.env.FAKE_BODY);
process.stdout.write(process.env.FAKE_CODE);
`, { mode: 0o700 });
    writeFileSync(join(dir, 'sleep'), '#!/bin/sh\nexit 0\n', { mode: 0o700 });
    const result = spawnSync('bash', ['-c', step.run!.replaceAll('/tmp/stripe-health.json', join(dir, 'response.json'))], {
      encoding: 'utf8', timeout: 5_000,
      env: { ...process.env, PATH: `${dir}:${process.env.PATH}`, SUPABASE_URL: 'https://example.invalid',
        SUPABASE_SERVICE_ROLE_KEY: 'service-fixture', FAKE_CAPTURE: capture, FAKE_CODE: code,
        FAKE_BODY: raw ? String(body) : JSON.stringify(body) },
    });
    return { status: result.status, output: result.stdout + result.stderr,
      requests: readFileSync(capture, 'utf8').trim().split('\n').filter(Boolean).map(line => JSON.parse(line) as string[]) };
  } finally { rmSync(dir, { recursive: true, force: true }); }
}

describe('déploiement Stripe sans ouverture implicite de Connect', () => {
  it('conserve le contrôle avant les sondes et la réactivation normale des crons', () => {
    expect(steps.indexOf(step)).toBeLessThan(steps.findIndex(s => s.name === 'Sonder puis activer les crons Edge critiques'));
    expect(step.if).toBeUndefined();
    expect(step.run).not.toContain('fn_ops_activer');
    expect(step.run).not.toContain('fn_activer_inscriptions');
    expect(step.run).not.toContain('CONNECT_PRETRANSFER_V1');
  });
  it('accepte 503 uniquement pour une configuration complète dont Connect reste fermé', () => {
    const r = runHealth(); expect(r.status).toBe(0); expect(r.requests).toHaveLength(1);
    expect(r.output).toContain('paiement groupé libéral toujours fermé');
    expect(r.output).not.toContain('service-fixture');
    const args = r.requests[0]; expect(args).toContain('https://example.invalid/functions/v1/stripe-config-health');
    expect(args[args.indexOf('--data') + 1]).toBe('{}');
    expect(args[args.indexOf('-X') + 1]).toBe('POST');
  });
  it('accepte 200 uniquement lorsque Connect est effectivement ouvert', () => {
    const r = runHealth({ ...complete, connect_release_open: true, production_ready: true }, '200');
    expect(r.status).toBe(0); expect(r.requests).toHaveLength(1); expect(r.output).not.toContain('toujours fermé');
  });
  it.each(Object.entries(complete).filter(([, value]) => value === true).map(([key]) => key))(
    'refuse le prérequis %s absent, faux ou textuel dans un 503', (key) => {
      for (const value of [undefined, false, 'true']) {
        const r = runHealth({ ...complete, [key]: value }); expect(r.status).toBe(1); expect(r.requests).toHaveLength(3);
      }
    });
  it.each([
    ['mode', 'test'], ['expected_webhook_api_version', 'incorrect'], ['customer_tenant_links_total', -1],
    ['customer_tenant_links_total', 1.5], ['customer_tenant_links_total', '2'], ['customer_tenant_links_valid', 1],
    ['customer_tenant_links_adoptable_legacy', 1], ['customer_tenant_links_indeterminate', 1],
    ['connect_release_open', true], ['connect_release_open', undefined], ['production_ready', true],
    ['production_ready', undefined],
  ])('refuse un contrat incomplet ou contradictoire : %s=%s', (key, value) => {
    expect(runHealth({ ...complete, [String(key)]: value }).status).toBe(1);
  });
  it.each(['200', '201', '202', '401', '429', '500', '502', '000'])(
    'refuse un état fermé avec HTTP %s', (code) => { expect(runHealth(complete, code).status).toBe(1); });
  it('refuse l’état ouvert en 503, un 503 partiel, JSON invalide et corps non objet', () => {
    for (const body of [{ ...complete, connect_release_open: true, production_ready: true },
      { deployment_ready: true, production_ready: false, connect_release_open: false }, {}, null, []]) {
      expect(runHealth(body).status).toBe(1);
    }
    expect(runHealth('<html>upstream error</html>', '503', true).status).toBe(1);
  });
});
