import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { act, renderHook } from '@testing-library/react';
import type { ReactNode } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { useMemoireExploration } from './useMemoireExploration';

describe('mémoire de navigation Explorer', () => {
  beforeEach(() => { localStorage.clear(); window.history.replaceState({}, '', '/'); });
  afterEach(() => vi.useRealTimers());

  function contexte() {
    const client = new QueryClient();
    const wrapper = ({ children }: { children: ReactNode }) => <QueryClientProvider client={client}>{children}</QueryClientProvider>;
    return { client, wrapper };
  }

  it('restaure la recherche et la pagination après une visite du détail ou d’un autre onglet', () => {
    const { wrapper } = contexte();
    const premiere = renderHook(() => useMemoireExploration('compte-a'), { wrapper });
    act(() => {
      premiere.result.current.modifier('vue', 'liste');
      premiere.result.current.modifier('villeRecherche', 'Paris');
      premiere.result.current.modifier('profession', 'IDE');
      premiere.result.current.modifier('nbAffiche', 60);
    });
    premiere.unmount();
    const retour = renderHook(() => useMemoireExploration('compte-a'), { wrapper });
    expect(retour.result.current.etat).toMatchObject({ vue: 'liste', villeRecherche: 'Paris', profession: 'IDE', nbAffiche: 60 });
    expect(sessionStorage.length).toBe(0);
    expect(localStorage.length).toBe(0);
  });

  it('isole les comptes et oublie les recherches quand la session vide son cache', () => {
    const { wrapper, client } = contexte();
    const a = renderHook(() => useMemoireExploration('compte-a'), { wrapper });
    act(() => a.result.current.modifier('villeRecherche', 'Lyon'));
    a.unmount();
    const b = renderHook(() => useMemoireExploration('compte-b'), { wrapper });
    expect(b.result.current.etat.villeRecherche).toBe('');
    b.unmount();
    client.clear();
    const reconnecte = renderHook(() => useMemoireExploration('compte-a'), { wrapper });
    expect(reconnecte.result.current.etat.villeRecherche).toBe('');
  });

  it('respecte une vue explicite dans le lien, même après avoir mémorisé une autre vue', () => {
    const { wrapper } = contexte();
    const premier = renderHook(() => useMemoireExploration('compte-a'), { wrapper });
    act(() => premier.result.current.modifier('vue', 'carte'));
    premier.unmount();
    window.history.replaceState({}, '', '/?vue=liste');
    const lien = renderHook(() => useMemoireExploration('compte-a'), { wrapper });
    expect(lien.result.current.etat.vue).toBe('liste');
  });

  it('conserve les préférences en mémoire pendant une longue visite d’un autre écran', () => {
    vi.useFakeTimers();
    const { wrapper } = contexte();
    const premier = renderHook(() => useMemoireExploration('compte-a'), { wrapper });
    act(() => premier.result.current.modifier('villeRecherche', 'Lille'));
    premier.unmount();
    act(() => vi.advanceTimersByTime(30 * 60_000));
    const retour = renderHook(() => useMemoireExploration('compte-a'), { wrapper });
    expect(retour.result.current.etat.villeRecherche).toBe('Lille');
  });
});
