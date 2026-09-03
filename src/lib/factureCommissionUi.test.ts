import { describe, expect, it } from 'vitest';
import { normaliserLignesFactureCommission } from './factureCommissionUi';

describe('normaliserLignesFactureCommission', () => {
  it('fait primer les totaux figés de la facture sur une mission recalculée', () => {
    const [ligne] = normaliserLignesFactureCommission([
      {
        id: 'mission-1',
        montant_commission_ht: 70.79,
        montant_commission_tva: 14.16,
        montant_commission_ttc: 84.95,
      },
    ], { montant_ht: 0.95, montant_tva: 0.19, montant_ttc: 1.14 });

    expect(ligne).toMatchObject({
      id: 'mission-1',
      montant_commission_ht: 0.95,
      montant_commission_tva: 0.19,
      montant_commission_ttc: 1.14,
      ecart_avec_mission_courante: true,
    });
  });

  it('répartit une facture groupée au centime et conserve exactement ses totaux', () => {
    const lignes = normaliserLignesFactureCommission([
      { id: 'a', montant_commission_ht: 1 },
      { id: 'b', montant_commission_ht: 1 },
      { id: 'c', montant_commission_ht: 1 },
    ], { montant_ht: 1, montant_tva: 0.2, montant_ttc: 1.2 });

    expect(lignes.reduce((somme, ligne) => somme + Number(ligne.montant_commission_ht), 0)).toBeCloseTo(1, 2);
    expect(lignes.reduce((somme, ligne) => somme + Number(ligne.montant_commission_tva), 0)).toBeCloseTo(0.2, 2);
    expect(lignes.reduce((somme, ligne) => somme + Number(ligne.montant_commission_ttc), 0)).toBeCloseTo(1.2, 2);
  });

  it('ne signale rien lorsque la ligne et le document concordent', () => {
    const [ligne] = normaliserLignesFactureCommission([
      { montant_commission_ht: 10, montant_commission_tva: 2, montant_commission_ttc: 12 },
    ], { montant_ht: 10, montant_tva: 2, montant_ttc: 12 });

    expect(ligne.ecart_avec_mission_courante).toBe(false);
  });
});
