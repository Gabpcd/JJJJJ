import { afterEach, describe, expect, it, vi } from 'vitest';
import { relancerLectureReseau } from './relancerLectureReseau';

const coupure = { data: null, status: 0, error: { message: 'TypeError: Load failed' } };
const succes = { data: { total_paye: 42 }, status: 200, error: null };

describe('reprise des lectures réseau', () => {
  afterEach(() => vi.useRealTimers());

  it('récupère une coupure WebKit avec une seule nouvelle requête', async () => {
    vi.useFakeTimers();
    const lire = vi.fn().mockResolvedValueOnce(coupure).mockResolvedValueOnce(succes);
    const resultat = relancerLectureReseau(lire, () => true);
    await vi.advanceTimersByTimeAsync(300);
    expect(await resultat).toEqual(succes);
    expect(lire).toHaveBeenCalledTimes(2);
  });

  it('rend l’échec persistant au composant après la reprise bornée', async () => {
    vi.useFakeTimers();
    const lire = vi.fn().mockResolvedValue(coupure);
    const resultat = relancerLectureReseau(lire, () => true);
    await vi.advanceTimersByTimeAsync(300);
    expect(await resultat).toEqual(coupure);
    expect(lire).toHaveBeenCalledTimes(2);
  });

  it.each([
    { data: null, status: 403, error: { message: 'TypeError: Load failed' } },
    { data: null, status: 0, error: { message: 'AbortError: The operation was aborted.' } },
    { data: null, status: 400, error: { message: 'permission denied', code: '42501' } },
    { data: { error: 'Accès refusé' }, status: 200, error: null },
    succes,
  ])('ne rejoue pas les réponses HTTP, métier ou annulations (%j)', async reponse => {
    const lire = vi.fn().mockResolvedValue(reponse);
    expect(await relancerLectureReseau(lire, () => true)).toEqual(reponse);
    expect(lire).toHaveBeenCalledTimes(1);
  });

  it('annule la reprise lorsqu’on quitte la page pendant le délai', async () => {
    vi.useFakeTimers();
    let active = true;
    const lire = vi.fn().mockResolvedValue(coupure);
    const resultat = relancerLectureReseau(lire, () => active);
    await vi.advanceTimersByTimeAsync(150);
    active = false;
    await vi.advanceTimersByTimeAsync(150);
    expect(await resultat).toEqual(coupure);
    expect(lire).toHaveBeenCalledTimes(1);
  });
});
