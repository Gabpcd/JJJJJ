import { describe, expect, it } from 'vitest';
import {
  MENTION_SIMULATION_PAIE,
  simulationPaieIncoherente,
  totauxBulletinsPayes,
} from './bulletinPaieUi';

describe('bulletinPaieUi', () => {
  it('additionne uniquement les bulletins payés', () => {
    expect(totauxBulletinsPayes([
      { statut: 'PAYE', salaire_brut: 500, net_avant_impot: 390, total_cotisations_salariales: 110 },
      { statut: 'EMIS', salaire_brut: 600, net_avant_impot: 468, total_cotisations_salariales: 132 },
      { statut: 'ANNULE', salaire_brut: 700, net_avant_impot: 546, total_cotisations_salariales: 154 },
    ])).toEqual({ brut: 500, netAvantImpot: 390, cotisations: 110 });
  });

  it('qualifie explicitement le document de simulation sans PAS', () => {
    expect(MENTION_SIMULATION_PAIE).toContain('document non officiel');
    expect(MENTION_SIMULATION_PAIE).toContain('prélèvement à la source');
  });

  it('compare la simulation active au calcul de cotisations complet', () => {
    expect(simulationPaieIncoherente(
      { statut: 'EMIS', salaire_brut: 7.56, net_avant_impot: 5.94 },
      { salaire_brut: 7.56, net_avant_impot: 5.94 },
    )).toBe(false);

    expect(simulationPaieIncoherente(
      { statut: 'EMIS', salaire_brut: 471.9, net_avant_impot: 370.19 },
      { salaire_brut: 7.56, net_avant_impot: 5.94 },
    )).toBe(true);
  });

  it('conserve sans alerte les archives annulées après rectification', () => {
    expect(simulationPaieIncoherente(
      { statut: 'ANNULE', salaire_brut: 471.9, net_avant_impot: 370.19 },
      { salaire_brut: 7.56, net_avant_impot: 5.94 },
    )).toBe(false);
  });
});
