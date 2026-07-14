import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(
  join(
    process.cwd(),
    'supabase/migrations/20260714005000_durcir_advisors_prelaunch.sql',
  ),
  'utf8',
);

describe('durcissements Supabase pre-lancement', () => {
  it('fige le search_path et retire les triggers des RPC publiques', () => {
    expect(migration).toContain('ALTER FUNCTION public.fn_trg_bloquer_documents_sante()');
    expect(migration).toContain('SET search_path = pg_catalog, public');
    expect(migration).toContain("p.prorettype = 'pg_catalog.trigger'::regtype");
    expect(migration).toContain('FROM PUBLIC, anon, authenticated');
  });

  it('reserve la liste attente prevoyance aux comptes connectes', () => {
    expect(migration).toMatch(
      /REVOKE ALL ON FUNCTION public\.fn_inscrire_liste_attente_prevoyance\(text, text\)[\s\S]*FROM PUBLIC, anon;/,
    );
    expect(migration).toMatch(
      /GRANT EXECUTE ON FUNCTION public\.fn_inscrire_liste_attente_prevoyance\(text, text\)[\s\S]*TO authenticated, service_role;/,
    );
  });

  it('indexe les trois cles etrangeres signalees', () => {
    expect(migration.match(/CREATE INDEX IF NOT EXISTS/g)).toHaveLength(3);
    expect(migration).toContain('escrow_release_queue (mission_id)');
    expect(migration).toContain('stripe_refunds_queue (paiement_escrow_id)');
    expect(migration).toContain('utilisateurs_bloques (bloque_id)');
  });

  it('conserve les frontieres RLS avec des helpers evalues une fois', () => {
    expect(migration.match(/soignant_id = \(SELECT auth\.uid\(\)\)/g)?.length)
      .toBeGreaterThanOrEqual(5);
    expect(migration).toContain('etablissement_id = (SELECT public.mon_etablissement_id())');
    expect(migration).toContain('OR (SELECT public.est_admin())');
    expect(migration).toContain('FOR SELECT TO authenticated');
  });

  it('ne modifie ni ne masque aucune donnee de demonstration', () => {
    expect(migration).not.toMatch(/\bUPDATE\s+public\./i);
    expect(migration).not.toMatch(/\bDELETE\s+FROM\s+public\./i);
    expect(migration).not.toMatch(/\bTRUNCATE\b/i);
    expect(migration).not.toMatch(/est_compte_test|@jolene(?:-demo)?\./i);
  });
});
