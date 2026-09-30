import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const read = (path: string) => readFileSync(path, 'utf8');
const before = read('supabase/migrations/20260903201000_securiser_cloture_anticipee_admin.sql');
const migration = read('supabase/migrations/20260930085055_verrouiller_cloture_mission_tenant.sql');
const body = (sql: string) => sql.match(/AS \$function\$([\s\S]*?)\$function\$/)![1];

describe('recapture bornée de la clôture mission', () => {
  it('vérifie le fingerprint réellement recapturé avant le CREATE', () => {
    const hash = createHash('md5').update(body(before)).digest('hex');
    expect(hash).toBe('1ea8780f088275804470e8211da98bfb');
    expect(migration.indexOf(`pg_catalog.md5(p.prosrc) = '${hash}'`))
      .toBeLessThan(migration.indexOf('CREATE OR REPLACE FUNCTION'));
  });

  it('conserve intégralement les branches métier et les effets de la version LIVE', () => {
    const marker = "  IF v_mission.statut <> 'EN_COURS' THEN";
    expect(body(migration).slice(body(migration).indexOf(marker)))
      .toBe(body(before).slice(body(before).indexOf(marker)));
  });

  it('conserve les ACL et raccorde une suite runtime sous rollback à la CI', () => {
    expect(migration).not.toMatch(/^(?:GRANT|REVOKE)\s/gm);
    const sqlPath = 'tests/security/cloture-mission-tenant.test.sql';
    expect(read('.github/workflows/validate-pr.yml')).toContain(sqlPath);
    expect(read(sqlPath)).not.toMatch(/DISABLE TRIGGER|CREATE OR REPLACE FUNCTION|session_replication_role/);
    expect(read(sqlPath).trim()).toMatch(/ROLLBACK;$/);
  });
});
