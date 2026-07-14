import { describe, expect, it } from 'vitest';
import { estDernierProprietaireActif, type MembreEquipeMinimal } from './equipeEtablissement';

const proprietaire: MembreEquipeMinimal = { id: 'owner-1', role: 'PROPRIETAIRE', actif: true };
const rh: MembreEquipeMinimal = { id: 'rh-1', role: 'RH', actif: true };

describe('estDernierProprietaireActif', () => {
  it('protège l’unique propriétaire actif', () => {
    expect(estDernierProprietaireActif(proprietaire, [proprietaire, rh])).toBe(true);
  });

  it('autorise la gestion d’un propriétaire quand un second propriétaire reste actif', () => {
    const second = { ...proprietaire, id: 'owner-2' };
    expect(estDernierProprietaireActif(proprietaire, [proprietaire, second, rh])).toBe(false);
  });

  it('ne bloque ni les autres rôles ni un ancien propriétaire inactif', () => {
    expect(estDernierProprietaireActif(rh, [proprietaire, rh])).toBe(false);
    expect(estDernierProprietaireActif({ ...proprietaire, actif: false }, [proprietaire])).toBe(false);
  });
});
