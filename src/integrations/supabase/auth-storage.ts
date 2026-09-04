import { Capacitor } from '@capacitor/core';

/**
 * Conserve la politique web existante (session fermée avec l'onglet) tout en
 * gardant une session native après la destruction du WebView par iOS/Android.
 * Le stockage reste isolé dans le sandbox de l'application et Supabase le
 * nettoie lors d'un signOut explicite.
 */
export function getSupabaseAuthStorage(): Storage | undefined {
  if (typeof window === 'undefined') return undefined;

  return Capacitor.isNativePlatform()
    ? window.localStorage
    : window.sessionStorage;
}
