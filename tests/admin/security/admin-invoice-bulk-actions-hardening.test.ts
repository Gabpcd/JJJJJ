import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { encoderCelluleCsv } from '@/lib/csv';

const source = readFileSync(
  'src/components/admin/BoutonsBulkFactures.tsx',
  'utf8',
);

describe('actions bulk des factures admin au lancement', () => {
  it('ne propose aucune mutation de statut sans RPC auditée', () => {
    expect(source).not.toContain("from('factures')");
    expect(source).not.toContain('.update({ statut })');
    expect(source).not.toContain("marquer('PAYEE')");
    expect(source).not.toContain("marquer('IMPAYEE')");
    expect(source).not.toContain('Marquer payées');
    expect(source).not.toContain('Marquer impayées');
    expect(source).not.toContain("from '@/integrations/supabase/client'");
  });

  it('conserve uniquement l’export CSV non mutateur et explique la restriction', () => {
    expect(source).toContain('const exportCsv = async () =>');
    expect(source).toContain('Export CSV');
    expect(source).toContain(
      'Les changements de statut se font depuis la fiche avec leur justificatif.',
    );
  });

  it('neutralise les formules, retours ligne et guillemets dans chaque cellule', () => {
    expect(encoderCelluleCsv('=HYPERLINK("https://evil.test")')).toBe(
      `"'=HYPERLINK(""https://evil.test"")"`,
    );
    expect(encoderCelluleCsv('  +1+1')).toBe(`"'  +1+1"`);
    expect(encoderCelluleCsv('-2+3')).toBe(`"'-2+3"`);
    expect(encoderCelluleCsv('@SUM(A1:A2)')).toBe(`"'@SUM(A1:A2)"`);
    expect(encoderCelluleCsv('Clinique\r\n"Jolene"')).toBe(
      `"Clinique ""Jolene"""`,
    );
    expect(encoderCelluleCsv(120.5)).toBe('"120.5"');
  });
});
