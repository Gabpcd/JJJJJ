import { describe, expect, it, vi } from 'vitest';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import {
  PGRST202_FALLBACK_FLAG,
  isPgrst202EligibilityFallbackAllowed,
} from '../../../e2e/helpers/liberal-eligibility-policy';
import {
  olderActiveRuns,
  waitForOlderPlaywrightRuns,
} from '../../../scripts/ci/wait-for-older-playwright-runs.mjs';
import {
  deployPathWasChanged,
  waitForSupabaseDeploy,
} from '../../../scripts/ci/wait-for-supabase-deploy.mjs';

const jsonResponse = (body: unknown) => ({
  ok: true,
  status: 200,
  json: async () => body,
  text: async () => JSON.stringify(body),
});

const workflow = readFileSync(
  join(process.cwd(), '.github/workflows/playwright-e2e.yml'),
  'utf8',
);
const validateWorkflow = readFileSync(
  join(process.cwd(), '.github/workflows/validate-pr.yml'),
  'utf8',
);
const penaltyMigration = readFileSync(
  join(process.cwd(), 'supabase/migrations/20260714154908_appliquer_penalite_empechement.sql'),
  'utf8',
);
const e2eSeedHelper = readFileSync(
  join(process.cwd(), 'e2e/helpers/seed.ts'),
  'utf8',
);

describe('file FIFO Playwright', () => {
  it('attend uniquement les runs actifs plus anciens, dans leur ordre FIFO', () => {
    expect(olderActiveRuns([
      { id: 9, run_number: 9, status: 'queued' },
      { id: 8, run_number: 8, status: 'in_progress' },
      { id: 7, run_number: 7, status: 'completed' },
      { id: 10, run_number: 10, status: 'queued' },
      { id: 6, run_number: 6, status: 'waiting' },
    ], { id: 9, run_number: 9 })).toEqual([
      { id: 6, run_number: 6, status: 'waiting' },
      { id: 8, run_number: 8, status: 'in_progress' },
    ]);
  });

  it('ne démarre qu’après la fin du run plus ancien sans jamais l’annuler', async () => {
    let inProgressPoll = 0;
    const fetchImpl = vi.fn(async (url: string) => {
      if (url.endsWith('/actions/runs/12')) {
        return jsonResponse({ id: 12, run_number: 12, workflow_id: 42 });
      }
      if (url.includes('status=in_progress')) {
        inProgressPoll += 1;
        return jsonResponse({
          workflow_runs: inProgressPoll === 1
            ? [
                { id: 12, run_number: 12, status: 'in_progress' },
                { id: 11, run_number: 11, status: 'in_progress' },
              ]
            : [{ id: 12, run_number: 12, status: 'in_progress' }],
        });
      }
      return jsonResponse({ workflow_runs: [] });
    });
    let clock = 0;

    await waitForOlderPlaywrightRuns({
      env: {
        GITHUB_TOKEN: 'token-test',
        GITHUB_REPOSITORY: 'Gabpcd/JJJJJ',
        GITHUB_RUN_ID: '12',
        PLAYWRIGHT_FIFO_MAX_WAIT_MS: '1000',
        PLAYWRIGHT_FIFO_POLL_INTERVAL_MS: '10',
      },
      fetchImpl,
      sleep: async (milliseconds: number) => { clock += milliseconds; },
      now: () => clock,
      log: { log: vi.fn() },
    });

    expect(fetchImpl).toHaveBeenCalledTimes(7);
    expect(fetchImpl.mock.calls.every(([url]) => !String(url).includes('/cancel'))).toBe(true);
  });

  it('est câblée sur les jobs PR et main sans concurrency GitHub annulable', () => {
    expect(workflow).not.toMatch(/^concurrency:/m);
    expect(workflow.match(/wait-for-older-playwright-runs\.mjs/g)).toHaveLength(2);
    expect(workflow).toContain('actions: read');
  });
});

describe('gate déploiement Supabase main', () => {
  it('reconnaît exactement les chemins qui déclenchent deploy-supabase.yml', () => {
    expect(deployPathWasChanged([{ filename: 'supabase/migrations/20260714.sql' }])).toBe(true);
    expect(deployPathWasChanged([{ filename: 'supabase/functions/foo/index.ts' }])).toBe(true);
    expect(deployPathWasChanged([{ filename: 'src/App.tsx' }])).toBe(false);
  });

  it('autorise uniquement la mutation interne bornée de la pénalité empêchement', () => {
    const openIndex = penaltyMigration.indexOf(
      "set_config('jolene.system_update', 'true', true)",
    );
    const penaltyIndex = penaltyMigration.indexOf('score_fiabilite = GREATEST');
    const closeIndex = penaltyMigration.indexOf(
      "set_config('jolene.system_update', '', true)",
    );

    expect(openIndex).toBeGreaterThan(-1);
    expect(penaltyIndex).toBeGreaterThan(openIndex);
    expect(closeIndex).toBeGreaterThan(penaltyIndex);
    expect(penaltyMigration).toContain('WHERE id = auth.uid()');
    expect(penaltyMigration).toContain('FROM PUBLIC, anon');
  });

  it('purge le compteur 3 200 h avant le profil Playwright éphémère', () => {
    const counterCleanupIndex = e2eSeedHelper.indexOf(
      "['suivi_conversion_3200h', 'soignant_id']",
    );
    const profileDeleteIndex = e2eSeedHelper.indexOf(".from('soignants' as any)\n      .delete()");

    expect(counterCleanupIndex).toBeGreaterThan(-1);
    expect(profileDeleteIndex).toBeGreaterThan(counterCleanupIndex);
  });

  it('attend le workflow exact et le succès du même SHA', async () => {
    const sha = 'a'.repeat(40);
    const responses = [
      { files: [{ filename: 'supabase/migrations/20260714.sql' }] },
      { id: 99, name: 'Deploy Supabase (migrations + edge functions)' },
      { workflow_runs: [{ id: 100, head_sha: sha, status: 'in_progress', html_url: 'run-100' }] },
      { workflow_runs: [{ id: 100, head_sha: sha, status: 'completed', conclusion: 'success', html_url: 'run-100' }] },
    ];
    const fetchImpl = vi.fn(async () => jsonResponse(responses.shift()));
    let clock = 0;

    await waitForSupabaseDeploy({
      env: {
        GITHUB_TOKEN: 'token-test',
        GITHUB_REPOSITORY: 'Gabpcd/JJJJJ',
        GITHUB_SHA: sha,
        GITHUB_EVENT_BEFORE: 'b'.repeat(40),
        SUPABASE_DEPLOY_MAX_WAIT_MS: '1000',
        SUPABASE_DEPLOY_POLL_INTERVAL_MS: '10',
      },
      fetchImpl,
      sleep: async (milliseconds: number) => { clock += milliseconds; },
      now: () => clock,
      log: { log: vi.fn() },
    });

    expect(fetchImpl).toHaveBeenCalledTimes(4);
    expect(String(fetchImpl.mock.calls[2][0])).toContain('branch=main&event=push');
  });

  it('teste réellement le schéma PROD après le deploy du même SHA', () => {
    const deployGateIndex = validateWorkflow.indexOf('node scripts/ci/wait-for-supabase-deploy.mjs');
    const schemaGuardIndex = validateWorkflow.indexOf('npm run test:schema');

    expect(deployGateIndex).toBeGreaterThan(-1);
    expect(schemaGuardIndex).toBeGreaterThan(deployGateIndex);
    expect(validateWorkflow.match(/github\.event_name == 'push' && github\.ref == 'refs\/heads\/main'/g)).toHaveLength(2);
    expect(validateWorkflow).toContain('actions: read');
    expect(validateWorkflow).toContain('contents: read');
    expect(validateWorkflow).toContain('PGPASSWORD: ${{ secrets.SUPABASE_DB_PASSWORD }}');
    expect(validateWorkflow).toContain('PGSSLMODE: verify-full');
    expect(validateWorkflow).toContain('aws-1-eu-west-1.pooler.supabase.com:5432/postgres');
    expect(validateWorkflow.match(/npm run test:schema/g)).toHaveLength(1);
    expect(validateWorkflow).not.toContain('secrets.SUPABASE_DB_URL');
    expect(validateWorkflow).not.toContain('SUPABASE_DB_URL absent');
  });
});

describe('repli PGRST202', () => {
  it('n’est activé que dans le job PR du workflow', () => {
    expect(workflow.match(/E2E_ALLOW_PGRST202_ELIGIBILITY_FALLBACK:/g)).toHaveLength(1);
    expect(workflow).toContain('wait-for-supabase-deploy.mjs');
  });

  it('reste absent par défaut et sur main', () => {
    expect(isPgrst202EligibilityFallbackAllowed({})).toBe(false);
    expect(isPgrst202EligibilityFallbackAllowed({
      GITHUB_EVENT_NAME: 'push',
      GITHUB_BASE_REF: '',
    })).toBe(false);
  });

  it('n’est autorisé qu’avec le flag explicite sur une PR vers main', () => {
    expect(isPgrst202EligibilityFallbackAllowed({
      [PGRST202_FALLBACK_FLAG]: 'true',
      GITHUB_EVENT_NAME: 'pull_request',
      GITHUB_BASE_REF: 'main',
    })).toBe(true);
  });

  it('refuse le flag même explicite sur main', () => {
    expect(() => isPgrst202EligibilityFallbackAllowed({
      [PGRST202_FALLBACK_FLAG]: 'true',
      GITHUB_EVENT_NAME: 'push',
      GITHUB_BASE_REF: '',
    })).toThrow('interdit hors pull_request vers main');
  });
});
