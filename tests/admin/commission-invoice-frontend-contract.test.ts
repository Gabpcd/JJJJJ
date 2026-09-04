import { describe, expect, it } from 'vitest';
import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const adminFacturation = fs.readFileSync(path.join(root, 'src/pages/admin/AdminFacturation.tsx'), 'utf8');
const detailFacture = fs.readFileSync(path.join(root, 'src/pages/DetailFacture.tsx'), 'utf8');
const paiementVirement = fs.readFileSync(path.join(root, 'src/components/PaiementVirement.tsx'), 'utf8');

describe('parcours frontend des factures de commission', () => {
  it('permet à l’admin de traiter explicitement les factures de recette', () => {
    expect(adminFacturation).toContain('Inclure les factures de test dans la file à traiter');
    expect(adminFacturation).toContain("inclureTestsDansFile && perimetreFacture(f) === 'TEST'");
    expect(adminFacturation).toContain('sans les inclure dans les totaux ni les exports comptables de production');
  });

  it('aligne le détail établissement et admin sur les totaux du document émis', () => {
    expect(detailFacture).toContain('normaliserLignesFactureCommission');
    expect(adminFacturation).toContain('normaliserLignesFactureCommission');
    expect(detailFacture).toContain('Les montants de commission affichés ci-dessous sont ceux du document émis');
  });

  it('expose des commandes et un champ de référence accessibles', () => {
    expect(adminFacturation).toContain("Afficher'} les missions de la facture");
    expect(paiementVirement).toContain('htmlFor="reference-virement-commission"');
    expect(paiementVirement).toContain('id="reference-virement-commission"');
  });
});
