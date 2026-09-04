import { beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  isNativePlatform: vi.fn(),
}));

vi.mock('@capacitor/core', () => ({
  Capacitor: {
    isNativePlatform: mocks.isNativePlatform,
  },
}));

import { getSupabaseAuthStorage } from './auth-storage';

describe('getSupabaseAuthStorage', () => {
  beforeEach(() => {
    mocks.isNativePlatform.mockReset();
  });

  it('persiste la session dans le sandbox local de l’app native', () => {
    mocks.isNativePlatform.mockReturnValue(true);

    expect(getSupabaseAuthStorage()).toBe(window.localStorage);
  });

  it('conserve une session éphémère sur le web', () => {
    mocks.isNativePlatform.mockReturnValue(false);

    expect(getSupabaseAuthStorage()).toBe(window.sessionStorage);
  });
});
