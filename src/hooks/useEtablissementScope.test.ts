import { renderHook } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { useEtablissementScope } from './useEtablissementScope';

const mocks = vi.hoisted(() => ({
  auth: { user: { id: 'utilisateur-id' } as { id: string } | null },
  role: {
    role: 'INCONNU',
    etablissement_id: null as string | null,
    loading: false,
    resolved: false,
    error: null as Error | null,
    retry: vi.fn(),
  },
}));

vi.mock('@/contexts/AuthContext', () => ({ useAuth: () => mocks.auth }));
vi.mock('@/hooks/useRole', () => ({ useRole: () => mocks.role }));

describe('useEtablissementScope — aucun fallback ambigu', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.auth.user = { id: 'utilisateur-id' };
    Object.assign(mocks.role, {
      role: 'INCONNU',
      etablissement_id: null,
      loading: false,
      resolved: false,
      error: null,
    });
  });

  it('ne transforme jamais une erreur de rôle en scope user.id', () => {
    mocks.role.error = new Error('RPC indisponible');
    mocks.role.etablissement_id = 'scope-perime-a-ne-pas-utiliser';

    const { result } = renderHook(() => useEtablissementScope());

    expect(result.current.etablissementId).toBeNull();
    expect(result.current.resolved).toBe(false);
    expect(result.current.error?.message).toBe('RPC indisponible');
  });

  it('exige etablissement_id pour un membre ADMIN_ETABLISSEMENT', () => {
    Object.assign(mocks.role, { role: 'ADMIN_ETABLISSEMENT', resolved: true });

    const { result } = renderHook(() => useEtablissementScope());

    expect(result.current.etablissementId).toBeNull();
  });

  it('utilise en priorité l’identifiant explicite résolu par le serveur', () => {
    Object.assign(mocks.role, {
      role: 'ADMIN_ETABLISSEMENT',
      etablissement_id: 'etablissement-explicite',
      resolved: true,
    });

    const { result } = renderHook(() => useEtablissementScope());

    expect(result.current.etablissementId).toBe('etablissement-explicite');
  });

  it('tolère user.id uniquement pour l’ancien rôle ETABLISSEMENT confirmé', () => {
    Object.assign(mocks.role, { role: 'ETABLISSEMENT', resolved: true, error: null });

    const { result } = renderHook(() => useEtablissementScope());

    expect(result.current.etablissementId).toBe('utilisateur-id');
    expect(result.current.retry).toBe(mocks.role.retry);
  });
});
