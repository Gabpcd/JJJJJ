import { mkdtempSync, readFileSync, rmSync, writeFileSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { parse } from 'yaml';
import { describe, expect, it } from 'vitest';

const read = (file: string) => readFileSync(join(process.cwd(), file), 'utf8');
const workflow = parse(read('.github/workflows/deploy-supabase.yml'));
type Step = { name?: string; run?: string; if?: string; env?: Record<string, string> };
const steps = Object.values(workflow.jobs).flatMap((job) => (job as { steps: Step[] }).steps);
const activationName = 'Activer une seule fois les futures inscriptions publiques en production';
const step = steps.find((candidate) => candidate.name === activationName)!;
const prod = 'flripxtsyegjshnhzjkz';

function runActivation(options: { ref?: string; url?: string; code?: string; body?: unknown } = {}) {
  const dir = mkdtempSync(join(tmpdir(), 'jolene-activation-'));
  const capture = join(dir, 'request.json');
  const summary = join(dir, 'summary.md');
  const response = [{ activation: { success: true, active: true, activation_effectuee: true, planifiee: false } }];
  try {
    // Le vrai shell du workflow s'exécute ; seul curl est remplacé. Aucun accès réseau.
    writeFileSync(join(dir, 'curl'), `#!${process.execPath}\n` + String.raw`
const fs=require('node:fs');
const args=process.argv.slice(2);
fs.writeFileSync(process.env.FAKE_CAPTURE,JSON.stringify(args));
fs.writeFileSync(args[args.indexOf('-o')+1],process.env.FAKE_BODY);
process.stdout.write(process.env.FAKE_CODE);
`, { mode: 0o700 });
    const run = step.run!.replaceAll('/tmp/inscriptions-activation.json', join(dir, 'response.json'));
    const result = spawnSync('bash', ['-c', run], {
      encoding: 'utf8', timeout: 5_000,
      env: {
        ...process.env, PATH: `${dir}:${process.env.PATH}`,
        SUPABASE_PROJECT_REF: options.ref ?? prod,
        SUPABASE_URL: options.url ?? `https://${prod}.supabase.co`,
        SUPABASE_ACCESS_TOKEN: 'fake-local-no-access', GITHUB_STEP_SUMMARY: summary,
        FAKE_CAPTURE: capture, FAKE_CODE: options.code ?? '200',
        FAKE_BODY: JSON.stringify(options.body ?? response),
      },
    });
    return {
      status: result.status,
      request: existsSync(capture) ? JSON.parse(readFileSync(capture, 'utf8')) as string[] : null,
      summary: existsSync(summary) ? readFileSync(summary, 'utf8') : '',
      output: result.stdout + result.stderr,
    };
  } finally { rmSync(dir, { recursive: true, force: true }); }
}

describe('ouverture des futures inscriptions publiques', () => {
  it('reste la dernière mutation après les sondes réussies, sans exécution forcée ni voie staging', () => {
    const index = steps.indexOf(step);
    expect(index).toBeGreaterThan(steps.findIndex((candidate) => candidate.name === 'Sonder puis activer les crons Edge critiques'));
    expect(steps[index + 1].name).toBe('Summary');
    expect(step.if).toBeUndefined(); // success() implicite : jamais always().
    expect(step.env?.SUPABASE_ACCESS_TOKEN).toBe('${{ secrets.SUPABASE_ACCESS_TOKEN }}');
    expect(read('.github/workflows/deploy-supabase-staging.yml')).not.toContain('fn_activer_inscriptions_publiques_planifiees');
    expect(read('.github/workflows/validate-pr.yml')).toContain('tests/security/activation-inscriptions-publiques.test.sql');
  });

  it.each([
    { ref: 'mejpriaetwgtcstbgfid' },
    { url: 'https://mejpriaetwgtcstbgfid.supabase.co' },
    { ref: '' },
    { url: '' },
  ])('refuse une cible autre que la production avant le moindre appel : %j', (options) => {
    const result = runActivation(options);
    expect(result.status).toBe(1);
    expect(result.request).toBeNull();
    expect(result.summary).toBe('');
  });

  it('appelle le contrat privé atomique et vérifie sa réponse avant de confirmer l’ouverture', () => {
    const result = runActivation();
    expect(result.status).toBe(0);
    const args = result.request!;
    expect(args).toContain(`https://api.supabase.com/v1/projects/${prod}/database/query`);
    const payload = JSON.parse(args[args.indexOf('--data') + 1]);
    expect(payload.query).toMatch(/SELECT private\.fn_activer_inscriptions_publiques_planifiees\(\s*'flripxtsyegjshnhzjkz', 'EDGE_PROBES_OK'\s*\) AS activation;/);
    expect(result.summary).toContain('Futures inscriptions publiques actives ; stock test conservé');
    expect(result.output).not.toContain('fake-local-no-access');
  });

  it('accepte une fermeture conservée sans annoncer de réouverture', () => {
    const result = runActivation({ body: [{ activation: { success: true, active: false, activation_effectuee: false, planifiee: false } }] });
    expect(result.status).toBe(0);
    expect(result.summary).toContain('Fermeture volontaire conservée');
    expect(result.summary).not.toContain('publiques actives');
  });

  it.each([
    { code: '503' },
    { body: [] },
    { body: [{ activation: { success: true, active: 'true', activation_effectuee: true, planifiee: false } }] },
    { body: [{ activation: { success: true, active: true, activation_effectuee: true, planifiee: true } }] },
  ])('échoue explicitement si le résultat reste inconnu ou invalide : %j', (options) => {
    const result = runActivation(options);
    expect(result.status).toBe(1);
    expect(result.summary).toBe('');
    expect(result.output).toContain('Activation des inscriptions non confirmée');
  });

  it('ne réécrit aucun stock ni aucune garde de cohorte ou de transport dans la migration', () => {
    const migration = read('supabase/migrations/20260925143334_activation_future_inscriptions_publiques.sql');
    expect(migration).not.toMatch(/\bUPDATE\s+public\.(soignants|etablissements)\b/i);
    expect(migration).not.toMatch(/CREATE\s+(?:OR REPLACE\s+)?FUNCTION\s+(?:public\.|private\.)?fn_comptes_meme_cohorte_test/i);
    expect(migration).not.toMatch(/\b(DISABLE TRIGGER|ALTER POLICY|CREATE POLICY|DROP POLICY)\b/i);
    expect(migration).not.toContain('raw_user_meta_data');
  });
});
