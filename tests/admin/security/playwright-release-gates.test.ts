import { describe, expect, it, vi } from 'vitest';
import { X509Certificate } from 'node:crypto';
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
  join(process.cwd(), 'supabase/migrations/20260714135000_appliquer_penalite_empechement.sql'),
  'utf8',
);
const historicPenaltyMigration = readFileSync(
  join(process.cwd(), 'supabase/migrations/20260714154908_appliquer_penalite_empechement.sql'),
  'utf8',
);
const penaltyFinalizer = readFileSync(
  join(process.cwd(), 'supabase/migrations/20260714162000_restaurer_empechement_canonique.sql'),
  'utf8',
);
const e2eSeedHelper = readFileSync(
  join(process.cwd(), 'e2e/helpers/seed.ts'),
  'utf8',
);
const supabaseProdCa = readFileSync(
  join(process.cwd(), 'config/certs/supabase-prod-ca-2021.crt'),
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

  it('borne les phases empêchement et isole le pool réel des comptes démo', () => {
    const rpcStart = penaltyMigration.indexOf(
      'CREATE OR REPLACE FUNCTION public.fn_declarer_empechement_imperieux',
    );
    const penaltyRpc = penaltyMigration.slice(rpcStart);
    const guardStart = penaltyMigration.indexOf(
      'CREATE OR REPLACE FUNCTION private.fn_guard_contexte_empechement_mission',
    );
    const guardEnd = penaltyMigration.indexOf(
      'DROP TRIGGER IF EXISTS dec_00_guard_empechement',
      guardStart,
    );
    const contextGuard = penaltyMigration.slice(guardStart, guardEnd);
    const lockIndex = penaltyRpc.indexOf('pg_advisory_xact_lock');
    const rowLockIndex = penaltyRpc.indexOf('FOR UPDATE');
    const quotaIndex = penaltyRpc.indexOf('SELECT count(*) INTO v_n12');
    const openIndex = penaltyRpc.indexOf(
      "set_config('jolene.system_update', 'true', true)",
    );
    const penaltyIndex = penaltyRpc.indexOf('score_fiabilite = GREATEST');
    const closeIndex = penaltyRpc.indexOf(
      "'jolene.system_update', v_previous_system_update, true",
    );
    const exceptionIndex = penaltyRpc.indexOf('EXCEPTION WHEN OTHERS', closeIndex);
    const exceptionCloseIndex = penaltyRpc.indexOf(
      "'jolene.system_update', v_previous_system_update, true",
      exceptionIndex,
    );

    expect(rpcStart).toBeGreaterThan(-1);
    expect(lockIndex).toBeGreaterThan(-1);
    expect(rowLockIndex).toBeGreaterThan(lockIndex);
    expect(quotaIndex).toBeGreaterThan(rowLockIndex);
    expect(openIndex).toBeGreaterThan(-1);
    expect(penaltyIndex).toBeGreaterThan(openIndex);
    expect(closeIndex).toBeGreaterThan(penaltyIndex);
    expect(exceptionIndex).toBeGreaterThan(closeIndex);
    expect(exceptionCloseIndex).toBeGreaterThan(exceptionIndex);
    expect(penaltyRpc).toContain('WHERE id = v_soignant_id');
    expect(penaltyRpc).toContain('v_audit_result := fn_ecrire_audit_safe');
    expect(penaltyRpc).toContain('private.fn_resynchroniser_compteurs_soignant');
    expect(penaltyRpc).toContain('v_notifications_avant');
    expect(penaltyRpc).toContain("n.type IN ('MISSION_URGENTE', 'POOL_URGENCE')");
    expect(penaltyRpc).toContain("v_m.statut = 'ASSIGNEE'");
    expect(penaltyRpc).toContain("v_context := 'FLAG:'");
    expect(penaltyRpc).toContain("v_context := 'CLOSE:'");
    expect(penaltyRpc).toContain("v_context := 'REPLACEMENT:'");
    expect(penaltyRpc).toContain('INSERT INTO public.missions');
    expect(penaltyRpc).toContain('remplacement_de_mission_id');
    expect(penaltyRpc).toContain("'mission_remplacement_id', v_remplacement_id");
    expect(penaltyRpc).toContain('v_previous_empechement_context');
    expect(penaltyRpc).toContain('v_previous_empechement_validated');
    expect(penaltyRpc).not.toContain('debut_le = GREATEST(debut_le');
    expect(penaltyRpc).not.toContain("set_config('jolene.system_update', '', true)");
    expect(guardStart).toBeGreaterThan(-1);
    expect(guardEnd).toBeGreaterThan(guardStart);
    expect(contextGuard).toContain("PERFORM set_config('jolene.empechement_mission_validated', '', true)");
    expect(contextGuard).toContain("v_expected := 'FLAG:'");
    expect(contextGuard).toContain("v_expected := 'CLOSE:'");
    expect(contextGuard).toContain("v_expected := 'REPLACEMENT:'");
    expect(contextGuard).toContain('to_jsonb(NEW) - ARRAY[');
    expect(penaltyMigration).toContain('CREATE TRIGGER dec_00_guard_empechement');
    expect(penaltyMigration).toContain(
      'v_soignant.est_compte_test IS DISTINCT FROM v_mission.est_compte_test',
    );
    expect(penaltyMigration).toContain("ja.action = 'ANNULATION_EMPECHEMENT_IMPERIEUX'");
    expect(penaltyMigration).toContain("ja.details @> '{\"depassement\": true}'::jsonb");
    expect(penaltyMigration).toContain('count(DISTINCT ja.id_ressource)');
    expect(penaltyMigration).toContain(
      "current_setting('app.test_bypass_protections', true) = 'true'",
    );
    expect(penaltyMigration).toContain(
      'CREATE OR REPLACE FUNCTION public.fn_escrow_reserver_tentative_debit',
    );
    expect(penaltyMigration).toContain(
      'CREATE OR REPLACE FUNCTION public.fn_escrow_reserver_release',
    );
    expect(penaltyMigration).toContain(
      'CREATE OR REPLACE FUNCTION public.fn_trg_bloquer_paiement_manuel_escrow',
    );
    expect(penaltyMigration).toContain("'RECONCILIATION_HEURES_REQUISE'");
    expect(penaltyRpc).toContain("SET statut = 'ANNULEE_PAR_SOIGNANT'");
    expect(penaltyRpc).toContain('soignant_assigne_id = v_soignant_id');
    expect(penaltyRpc).toContain('public.fn_blocage_publication_etab');
    expect(penaltyRpc).toContain("cm.type_contrat IN ('CDD', 'CDDU', 'VACATION')");
    expect(penaltyMigration).toContain(
      "'No-show — rapprochement financier requis ⚠️'",
    );
    expect(penaltyMigration).toContain('WITH RECURSIVE ascendance AS');
    expect(penaltyMigration).toContain(
      'est_urgente, niveau_urgence, garantie_remplacement,',
    );
    expect(penaltyMigration).toContain("statut IN ('EMISE', 'EN_RETARD')");
    expect(penaltyMigration).toContain('date_echeance < current_date');
    expect(penaltyMigration).toContain('FROM PUBLIC, anon');
  });

  it('restaure la RPC canonique après la migration historique déjà en production', () => {
    const marker = 'CREATE OR REPLACE FUNCTION public.fn_declarer_empechement_imperieux';
    const canonicalRpc = penaltyMigration.slice(penaltyMigration.lastIndexOf(marker)).trim();
    const finalRpc = penaltyFinalizer.slice(penaltyFinalizer.indexOf(marker)).trim();

    expect(historicPenaltyMigration).toContain("WHERE id = auth.uid()");
    expect(historicPenaltyMigration).not.toContain('pg_advisory_xact_lock');
    expect(finalRpc).toBe(canonicalRpc);
    expect(finalRpc).toContain('pg_advisory_xact_lock');
    expect(finalRpc).toContain('RESOLUTION_FINANCIERE_MANUELLE_REQUISE');
    expect(finalRpc).toContain("v_context := 'REPLACEMENT:'");
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
    expect(validateWorkflow).toContain(
      'sslmode=verify-full&sslrootcert=./config/certs/supabase-prod-ca-2021.crt',
    );
    expect(validateWorkflow).not.toContain('rejectUnauthorized: false');
    expect(validateWorkflow.match(/npm run test:schema/g)).toHaveLength(1);
    expect(validateWorkflow).not.toContain('secrets.SUPABASE_DB_URL');
    expect(validateWorkflow).not.toContain('SUPABASE_DB_URL absent');

    const certificate = new X509Certificate(supabaseProdCa);
    expect(certificate.subject).toContain('CN=Supabase Root 2021 CA');
    expect(certificate.issuer).toBe(certificate.subject);
    expect(certificate.fingerprint256).toBe(
      '80:70:25:AD:50:D4:ED:21:9D:2C:9C:7D:29:9C:00:4F:82:4E:B0:0C:F7:F6:5A:FE:F6:07:D0:7B:72:E6:CA:FA',
    );
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
