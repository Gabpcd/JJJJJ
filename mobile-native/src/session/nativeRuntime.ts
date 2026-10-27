import 'react-native-url-polyfill/auto';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import * as Crypto from 'expo-crypto';
import * as SecureStore from 'expo-secure-store';
import { Platform } from 'react-native';
import { DEMO_CONTEXT, DemoGateway } from '../data/demoGateway';
import { SupabaseMissionGateway } from '../data/supabaseGateway';
import type { MissionGateway } from '../data/types';
import { DemoAccountGateway, SupabaseAccountGateway, type NativeAccountGateway } from '../account';
import { resolveNativeAccount } from '../account/resolveContext';
import { readNativeConfig } from './config';
import { createNativeSessionController, type NativeSessionController } from './controller';
import { createSecureSessionStorage } from './secureSessionStorage';

// Same staging project as scripts/recette-fournisseurs/lib/manifest.mjs.
const STAGING_PROJECTS = ['mejpriaetwgtcstbgfid'] as const;
export interface NativeRuntime {
  controller: NativeSessionController;
  gateway: MissionGateway;
  client: SupabaseClient | null;
  accountGateway: NativeAccountGateway;
  configError: string | null;
}

async function boundedFetch(input: RequestInfo | URL, init?: RequestInit): Promise<Response> {
  const abort = new AbortController();
  const source = init?.signal;
  const cancel = () => abort.abort();
  source?.addEventListener('abort', cancel, { once: true });
  if (source?.aborted) abort.abort();
  const timeout = setTimeout(cancel, 15_000);
  try { return await fetch(input, { ...init, signal: abort.signal }); }
  finally { clearTimeout(timeout); source?.removeEventListener('abort', cancel); }
}

/** Create once per app lifecycle. No server is contacted in the default demo mode. */
export function createNativeRuntime(): NativeRuntime {
  const demo = () => {
    const controller = createNativeSessionController({ mode: 'demo', context: { ...DEMO_CONTEXT, kind: 'soignant' } });
    return { controller, gateway: new DemoGateway(), client: null, accountGateway: new DemoAccountGateway(controller), configError: null };
  };
  try {
    // Expo only substitutes explicit EXPO_PUBLIC variable references.
    const config = readNativeConfig({
      mode: process.env.EXPO_PUBLIC_JOLENE_MODE,
      url: process.env.EXPO_PUBLIC_SUPABASE_URL,
      publishableKey: process.env.EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
    }, STAGING_PROJECTS);
    if (config.mode === 'demo') return demo();
    if (Platform.OS === 'web') throw new Error('La connexion TEST de ce pilote nécessite l’application native et son stockage sécurisé.');
    const storage = createSecureSessionStorage({
      getItem: (key) => SecureStore.getItemAsync(key),
      setItem: (key, value) => SecureStore.setItemAsync(key, value, { keychainAccessible: SecureStore.WHEN_UNLOCKED_THIS_DEVICE_ONLY }),
      removeItem: (key) => SecureStore.deleteItemAsync(key),
    }, (value) => Crypto.digestStringAsync(Crypto.CryptoDigestAlgorithm.SHA256, value));
    const storageKey = `sb-${config.projectRef}-native-pilot-auth`;
    const client = createClient(config.url, config.publishableKey, {
      auth: { storage, storageKey, flowType: 'pkce', autoRefreshToken: true, persistSession: true, detectSessionInUrl: false },
      global: { fetch: boundedFetch },
    });
    void client.auth.stopAutoRefresh();
    const gateway = new SupabaseMissionGateway(client);
    const controller = createNativeSessionController({
      mode: 'staging',
      auth: {
        async getSession() {
          const { data, error } = await client.auth.getSession();
          if (error) throw error;
          return data.session;
        },
        subscribe(listener) {
          const { data } = client.auth.onAuthStateChange((_event, session) => { listener(session); });
          return () => data.subscription.unsubscribe();
        },
        async signIn(email, password) {
          const { data, error } = await client.auth.signInWithPassword({ email, password });
          if (error || !data.session) throw error ?? new Error('Session absente.');
          return data.session;
        },
        async signOut() {
          const { error } = await client.auth.signOut({ scope: 'local' });
          if (error) throw error;
        },
        clearStorage: async () => {
          await storage.removeItem(storageKey);
          await storage.removeItem(`${storageKey}-code-verifier`);
        },
        setForeground(foreground) { void (foreground ? client.auth.startAutoRefresh() : client.auth.stopAutoRefresh()); },
      },
      resolveContext: (session, signal) => resolveNativeAccount(client, gateway, session, signal),
    });
    return { controller, gateway, client, accountGateway: new SupabaseAccountGateway(client, controller), configError: null };
  } catch (error) {
    return { ...demo(), configError: error instanceof Error ? error.message : 'Configuration TEST invalide.' };
  }
}
