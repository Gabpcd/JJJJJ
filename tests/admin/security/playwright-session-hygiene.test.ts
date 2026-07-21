import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const migrationInitiale = readFileSync(
  'supabase/migrations/20260720172500_hygiene_sessions_playwright.sql',
  'utf8',
);
const migration = readFileSync(
  'supabase/migrations/20260720173000_accelerer_hygiene_sessions_playwright.sql',
  'utf8',
);
const config = readFileSync('playwright.config.ts', 'utf8');
const setup = readFileSync('e2e/global-setup.ts', 'utf8');
const teardown = readFileSync('e2e/global-teardown.ts', 'utf8');
const helper = readFileSync('e2e/helpers/nettoyage-sessions-playwright.ts', 'utf8');
const workflow = readFileSync('.github/workflows/playwright-e2e.yml', 'utf8');

describe('hygiène des sessions Auth Playwright', () => {
  it('borne strictement la purge aux deux comptes CI sans supprimer leurs utilisateurs', () => {
    expect(migration).toContain("'playwright-soignant@jolene.app'");
    expect(migration).toContain("'playwright-etab@jolene.app'");
    expect(migration).toContain('DELETE FROM auth.refresh_tokens');
    expect(migration).toContain('DELETE FROM auth.sessions');
    expect(migration).not.toMatch(/DELETE\s+FROM\s+auth\.users/i);
    expect(migration).not.toContain('marie.lefevre@jolene-demo.dev');
    expect(migration).not.toContain('admin@jolene.app');
    expect(migrationInitiale).not.toMatch(/DELETE\s+FROM\s+auth\.users/i);
  });

  it('réserve la RPC au service role et retire le cron concurrent de production', () => {
    expect(migration).toMatch(/REVOKE ALL[\s\S]+FROM PUBLIC, anon, authenticated;/);
    expect(migration).toMatch(/GRANT EXECUTE[\s\S]+TO service_role;/);
    expect(migration).toContain("'jolene_nettoyer_sessions_playwright'");
    expect(migration).toContain('cron.unschedule');
    expect(migration).not.toContain('cron.schedule(');
    expect(migration).toContain('LIMIT 1000');
  });

  it('nettoie avant le run et au teardown sans bloquer une PR précédant le déploiement', () => {
    expect(config).toContain("globalTeardown: './e2e/global-teardown.ts'");
    expect(setup).toContain("nettoyerSessionsPlaywright(admin, '2 hours')");
    expect(teardown).toContain("nettoyerSessionsPlaywright(admin, '0 seconds')");
    expect(helper).toContain('console.warn');
    expect(helper).toContain('AbortController');
    expect(helper).toContain('20_000');
    expect(workflow).toContain('auth/v1/logout');
    expect(workflow).toContain('access_token');
    expect(workflow).toContain('::add-mask::$E2E_TEST_PASSWORD');
    expect(workflow).toContain('steps.playwright-tests.outcome');
    expect(workflow).toContain('for tentative in 1 2 3');
  });
});
