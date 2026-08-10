import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

const root = process.cwd();
const read = (path: string) => readFileSync(join(root, path), 'utf8');

const frontend = read('src/pages/ClassementSoignants.tsx');
const correction = read(
  'supabase/migrations/20260810161022_corriger_classement_et_inventaire_security_definer.sql',
);
const financeMigration = read(
  'supabase/migrations/20260803190000_corriger_coherence_metier_finances_litiges.sql',
);
const runtimeRegression = read(
  'tests/admin/security/database-runtime-lint-residual.test.sql',
);

describe('classement et inventaire SECURITY DEFINER', () => {
  it('affiche le prénom et le nom renvoyés par la RPC', () => {
    expect(frontend).toContain('nom: string;');
    expect(frontend).toContain('{s.prenom} {s.nom}');
  });

  it('borne la limite du classement à cinquante côté base', () => {
    expect(correction).toContain(
      'LEAST(GREATEST(COALESCE(p_limit, 20), 1), 50)',
    );
    expect(correction).toContain('LIMIT v_limit;');
    expect(correction).not.toContain('LIMIT p_limit;');
  });

  it('réserve le helper de rétractation au service_role', () => {
    expect(correction).toMatch(
      /REVOKE ALL ON FUNCTION public\.fn_dans_fenetre_retractation\(uuid\)[\s\S]{0,100}FROM PUBLIC, anon, authenticated;/,
    );
    expect(correction).toMatch(
      /GRANT EXECUTE ON FUNCTION public\.fn_dans_fenetre_retractation\(uuid\)[\s\S]{0,100}TO service_role;/,
    );
    expect(correction).toContain("'SERVICE_ONLY_REVOQUE'");
  });

  it('utilise partout le corps prosrc pour les empreintes corrigées', () => {
    expect(financeMigration).not.toMatch(/md5\(pg_get_functiondef\(/);
    expect(financeMigration.match(/md5\(p\.prosrc\)/g)).toHaveLength(5);
    expect(correction).toContain('pg_catalog.md5(p.prosrc)');

    for (const signature of [
      'fn_declarer_paiement_soignant_v2(uuid,numeric,numeric,text,text,date,boolean)',
      'fn_declarer_paiement_soignant(uuid,numeric,text,text,date,boolean)',
      'fn_diagnostic_coherence_financiere()',
      'fn_marquer_messages_lus(uuid)',
      'fn_obligations_financieres()',
      'fn_paiements_etablissement()',
    ]) {
      expect(correction).toContain(`'${signature}'`);
    }
  });

  it('compare uniquement les huit OID ciblés sans balayer tout pg_proc', () => {
    expect(correction).toContain('AS r(signature, procedure_oid)');
    expect(correction).toContain(
      'JOIN pg_catalog.pg_proc p ON p.oid = r.procedure_oid',
    );
    expect(correction).not.toContain('p.oid::regprocedure::text = i.signature');
    expect(runtimeRegression).toContain('AS r(signature, procedure_oid)');
    expect(runtimeRegression).toContain(
      'JOIN pg_proc p ON p.oid = r.procedure_oid',
    );
    expect(runtimeRegression).not.toContain(
      'p.oid::regprocedure::text = i.signature',
    );
  });
});
