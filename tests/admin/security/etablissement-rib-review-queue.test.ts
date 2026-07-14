import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const edge = readFileSync(
  'supabase/functions/verify-rib-etablissement/index.ts',
  'utf8',
);
const helper = readFileSync(
  'supabase/functions/_shared/establishment-review.ts',
  'utf8',
);
const migration = readFileSync(
  'supabase/migrations/20260714066000_helpers_revue_et_revocation.sql',
  'utf8',
);

describe('file durable de revue du RIB établissement', () => {
  it('réutilise la file idempotente commune et résout la revue après succès', () => {
    expect(edge).toContain('openEstablishmentReview');
    expect(edge).toContain('resolveEstablishmentReview');
    expect(edge).toContain('"VERIFY_RIB_ETABLISSEMENT"');
    expect(helper).toContain("| 'VERIFY_RIB_ETABLISSEMENT'");
    expect(migration.match(/'VERIFY_RIB_ETABLISSEMENT'/g)?.length).toBeGreaterThanOrEqual(2);
    expect(migration).toContain('pg_advisory_xact_lock');
    expect(migration).toContain("r.statut IN ('EN_ATTENTE', 'EN_COURS_REVUE', 'ESCALADE')");
  });

  it('met timeout, panne réseau, erreur API, parse et doute en revue réelle', () => {
    for (const cause of [
      'AI_TIMEOUT',
      'AI_NETWORK_ERROR',
      'AI_HTTP_',
      'AI_PARSE_ERROR',
      'ANTIFRAUD_INCOMPLETE',
      'FALSIFICATION_INDICATORS',
      'AI_INCONCLUSIVE',
    ]) {
      expect(edge).toContain(cause);
    }
    expect(edge).toContain('if (coherent === null)');
    expect(edge).toContain('return mettreEnRevue(');
    expect(edge).toContain('code: "REVIEW_QUEUE_FAILED"');
    expect(edge).toContain('status: 503');
  });

  it('fige le snapshot exact sans exposer l’IBAN complet', () => {
    const reviewContext = edge.match(
      /const mettreEnRevue = async[\s\S]*?return new Response\(JSON\.stringify\(\{[\s\S]*?status: 202,/,
    )?.[0] ?? '';
    expect(reviewContext).toContain('verification_source_version: sourceVersion');
    expect(reviewContext).toContain('verification_source_version_apres_verdict: sourceVersion + 1');
    expect(reviewContext).toContain('rib_s3_key: ribPath');
    expect(reviewContext).toContain('rib_source_sha256_v1: ribSourceSha256');
    expect(reviewContext).toContain('iban_last4: ibanLastFour');
    expect(reviewContext).toContain('iban_fingerprint_sha256_v1: ibanFingerprint');
    expect(reviewContext).not.toContain('iban_extrait:');
    expect(reviewContext).not.toContain('iban: ibanNormalise');
    expect(edge).toContain('sanitizeBankAnalysis');
  });
});
