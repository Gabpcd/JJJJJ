import React from 'react';
import { act, render } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import { memoriserSaisie, reprendreSaisie } from '@/lib/saisieInscriptionEnCours';

const m = vi.hoisted(() => ({
  ecouteur: null as null | ((event: string, session: unknown) => void),
  // Client de requêtes stable, comme dans l'application : sinon l'écoute de
  // session se réabonne à chaque rendu et relit une session vide.
  client: { clear: () => {} },
}));
vi.mock('@sentry/react', () => ({ setUser: vi.fn() }));
vi.mock('@tanstack/react-query', () => ({ useQueryClient: () => m.client }));
vi.mock('@/lib/pushNative', () => ({ initNativePush: vi.fn(), resetNativePushListeners: vi.fn() }));
vi.mock('@capacitor/core', () => ({ Capacitor: { isNativePlatform: () => false } }));
vi.mock('@/integrations/supabase/client', () => ({
  SUPABASE_URL: 'http://127.0.0.1:8895',
  SUPABASE_PUBLISHABLE_KEY: 'fixture-key',
  supabase: {
    rpc: vi.fn(async () => ({ data: null, error: null })),
    auth: {
      onAuthStateChange: (ecouteur: (event: string, session: unknown) => void) => {
        m.ecouteur = ecouteur;
        return { data: { subscription: { unsubscribe: vi.fn() } } };
      },
      getSession: async () => ({ data: { session: null } }),
    },
  },
}));

import { AuthProvider } from './AuthContext';

const session = (id: string) => ({ user: { id, email: `${id}@example.invalid`, user_metadata: {} } });
const brouillon = { prenom: '' };
const memoriser = (id: string) => memoriserSaisie({ user_id: id, type_compte: 'SOIGNANT', donnees: brouillon }, { prenom: 'Camille' });
const garde = (id: string) => reprendreSaisie({ user_id: id, type_compte: 'SOIGNANT', donnees: brouillon }).depuisOnglet;
const evenement = (event: string, s: unknown) => act(() => { m.ecouteur!(event, s); });
// La lecture initiale de session (vide ici) doit être terminée avant les événements.
const monter = async () => { render(<AuthProvider><div /></AuthProvider>); await act(async () => {}); };

describe('AuthProvider — la saisie d’inscription ne survit pas à la session (revue B8 #1137, m2)', () => {
  it('efface la saisie quand la session se termine sans le bouton « Se déconnecter »', async () => {
    await monter();
    await evenement('SIGNED_IN', session('u1'));
    memoriser('u1');
    await evenement('TOKEN_REFRESHED', session('u1'));
    expect(garde('u1')).toBe(true);
    // Expiration, déconnexion dans un autre onglet, réinitialisation du mot de passe.
    await evenement('SIGNED_OUT', null);
    expect(garde('u1')).toBe(false);
  });

  it('garde la saisie à la première connexion et quand la session se rafraîchit', async () => {
    await monter();
    memoriser('u1');
    await evenement('INITIAL_SESSION', session('u1'));
    await evenement('SIGNED_IN', session('u1'));
    await evenement('TOKEN_REFRESHED', session('u1'));
    expect(garde('u1')).toBe(true);
  });

  it('efface la saisie quand un autre compte se connecte dans le même onglet', async () => {
    await monter();
    await evenement('SIGNED_IN', session('u1'));
    memoriser('u1');
    await evenement('SIGNED_IN', session('u2'));
    expect(garde('u1')).toBe(false);
  });
});
