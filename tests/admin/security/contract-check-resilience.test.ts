import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const source = readFileSync('scripts/check-contrat-frontend-backend.mjs', 'utf8');

describe('résilience du contrôle front ↔ back', () => {
  it('relance uniquement les erreurs transitoires de la Management API', () => {
    expect(source).toContain('ATTENTES_RELANCE_MS');
    expect(source).toContain('res.status !== 429 && res.status < 500');
    expect(source).toContain('AbortSignal.timeout(45_000)');
    expect(source).toContain("'Management API /database/query'");
    expect(source).toContain("'Management API /functions'");
  });

  it('conserve un hard fail après épuisement des relances', () => {
    expect(source).toContain('throw derniereErreur');
    expect(source).toContain('process.exit(2)');
  });
});
