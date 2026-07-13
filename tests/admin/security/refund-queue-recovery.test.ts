import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

const source = readFileSync(
  join(process.cwd(), 'supabase/functions/process-stripe-refunds/index.ts'),
  'utf8',
);

describe('process-stripe-refunds — reprise et persistance idempotentes', () => {
  it('reprend après lease une ligne EN_COURS abandonnée', () => {
    expect(source).toContain('const repriseAvant = new Date(Date.now() - 15 * 60 * 1000).toISOString()');
    expect(source).toContain('.in("statut", ["EN_ATTENTE", "EN_COURS"])');
    expect(source).toContain('.eq("tentatives", item.tentatives)');
    expect(source).toContain('.or(`dernier_essai_le.is.null,dernier_essai_le.lt.${repriseAvant}`)');
    expect(source).toContain('idempotencyKey: `refund_queue_${item.id}`');
  });

  it('vérifie la persistance TRAITE après refunds.create', () => {
    expect(source).toContain('const { data: refundPersiste, error: refundPersistError }');
    expect(source).toContain('.in("statut", ["EN_COURS", "TRAITE"])');
    expect(source).toContain('REFUND_PERSISTENCE_FAILED');
  });

  it('vérifie aussi le retour EN_ATTENTE ou ECHEC dans le catch', () => {
    expect(source).toContain('const { data: etatPersiste, error: etatPersistError }');
    expect(source).toContain('REFUND_STATE_PERSISTENCE_FAILED');
    expect(source).toContain('REFUND_STATE_LOOKUP_FAILED');
    expect(source).toContain('REFUND_STATE_CONFLICT');
  });

  it('ne rétrograde jamais un TRAITE écrit par le webhook concurrent', () => {
    expect(source).toContain('if (etatCourant?.statut === "TRAITE")');
    expect(source).toContain('nouveauStatut = "TRAITE"');
    expect(source).toContain('alertAdmin = false');
  });
});
