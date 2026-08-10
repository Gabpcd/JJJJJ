import { act, renderHook } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { useChargementProlonge } from './useChargementProlonge';

describe('useChargementProlonge', () => {
  afterEach(() => {
    vi.useRealTimers();
  });

  it('affiche un recours après le délai et le masque dès que le chargement aboutit', () => {
    vi.useFakeTimers();
    const { result, rerender } = renderHook(
      ({ enCours }) => useChargementProlonge(enCours, 12_000),
      { initialProps: { enCours: true } },
    );

    act(() => vi.advanceTimersByTime(11_999));
    expect(result.current.estProlonge).toBe(false);

    act(() => vi.advanceTimersByTime(1));
    expect(result.current.estProlonge).toBe(true);

    rerender({ enCours: false });
    expect(result.current.estProlonge).toBe(false);
  });

  it('redémarre le délai quand l’utilisateur relance le chargement', () => {
    vi.useFakeTimers();
    const { result } = renderHook(() => useChargementProlonge(true, 12_000));

    act(() => vi.advanceTimersByTime(12_000));
    expect(result.current.estProlonge).toBe(true);

    act(() => result.current.reinitialiser());
    expect(result.current.estProlonge).toBe(false);

    act(() => vi.advanceTimersByTime(12_000));
    expect(result.current.estProlonge).toBe(true);
  });
});
