import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const detailMission = readFileSync(
  resolve(process.cwd(), 'src/pages/DetailMission.tsx'),
  'utf8',
);

describe('contexte financier du détail établissement/admin', () => {
  it('charge et transmet le type et le secteur public de l’établissement', () => {
    expect(detailMission).toContain(
      'etablissements(nom, type, est_secteur_public, adresse_ville, adresse_departement,',
    );
    expect(detailMission).toMatch(
      /<DecompositionFinanciere[\s\S]*?mission=\{m\}[\s\S]*?etablissement=\{m\.etablissements\}[\s\S]*?role=\{isAdmin \? 'ADMIN' : 'ETAB'\}/,
    );
  });
});
