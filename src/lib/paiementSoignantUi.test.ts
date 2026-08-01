import { describe, expect, it } from 'vitest';
import { indexerDernierPaiementParMission } from './paiementSoignantUi';

describe('paiementSoignantUi', () => {
  it('choisit explicitement le paiement le plus récent par mission quel que soit l ordre reçu', () => {
    const resultat = indexerDernierPaiementParMission([
      { id: 'ancien', mission_id: 'm1', statut: 'DECLARE', cree_le: '2026-07-01T10:00:00Z' },
      { id: 'autre', mission_id: 'm2', statut: 'CONFIRME', cree_le: '2026-07-02T10:00:00Z' },
      { id: 'recent', mission_id: 'm1', statut: 'CONFIRME', cree_le: '2026-07-03T10:00:00Z' },
    ]);

    expect((resultat.m1 as { statut: string }).statut).toBe('CONFIRME');
    expect(resultat.m2.id).toBe('autre');
  });

  it('prend en compte une mise à jour plus récente et départage par identifiant', () => {
    const resultat = indexerDernierPaiementParMission([
      { id: 'a', mission_id: 'm1', modifie_le: '2026-07-04T10:00:00Z' },
      { id: 'b', mission_id: 'm1', modifie_le: '2026-07-04T10:00:00Z' },
      { id: 'cree-apres', mission_id: 'm2', cree_le: '2026-07-06T10:00:00Z', date_paiement: '2026-07-01' },
      { id: 'paye-apres', mission_id: 'm2', cree_le: '2026-07-05T10:00:00Z', date_paiement: '2026-07-07' },
    ]);

    expect(resultat.m1.id).toBe('b');
    expect(resultat.m2.id).toBe('cree-apres');
  });
});
