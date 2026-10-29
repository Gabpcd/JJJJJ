import 'react-native-url-polyfill/auto';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import * as Crypto from 'expo-crypto';
import * as SecureStore from 'expo-secure-store';
import { AppState, Platform } from 'react-native';
import { DEMO_CONTEXT, DemoGateway } from '../data/demoGateway';
import { SupabaseMissionGateway } from '../data/supabaseGateway';
import type { MissionGateway } from '../data/types';
import { DemoAccountGateway, SupabaseAccountGateway, type NativeAccountGateway } from '../account';
import { resolveNativeAccount } from '../account/resolveContext';
import { readNativeConfig } from './config';
import { createNativeSessionController, type NativeSessionController } from './controller';
import { createSecureSessionStorage } from './secureSessionStorage';
import { createDocumentRuntime, type NativeDocumentRuntime } from '../documents/runtime';
import { createDocumentUploadJournal } from '../documents/uploadJournal';
import { createDemoDocumentMedia } from '../documents/demoMedia';
import { createExpoDocumentMediaAdapter } from '../media/documents';
import { SupabaseDocumentGateway, createOriginalSigningTransport } from '../workflows/documents';
import { DemoDocumentGateway, type DemoDocumentSession } from '../workflows/documents/demoGateway';
import { createDemoDocumentUploadJournal } from '../workflows/documents/demoJournal';
import { DEMO_DOCUMENT_SCENARIO_OUTCOMES } from '../workflows/documents/demoScenario';
import { contractScenario, createContractRuntime, nativeContractContext } from '../contracts/runtime';
import type { ContractGateway } from '../workflows/contracts/types';
import { createPresenceRuntime, nativePresenceContext, presenceScenario, type NativePresenceRuntime } from '../presence/runtime';
import { SupabasePresenceGateway, createPresenceAttemptJournal, createPresenceServerClock } from '../workflows/presence';
import { DemoPresenceGateway } from '../workflows/presence/demoGateway';
import { createExpoPresenceSensors } from '../media/presence/expoAdapter';

// Same staging project as scripts/recette-fournisseurs/lib/manifest.mjs.
const STAGING_PROJECTS = ['mejpriaetwgtcstbgfid'] as const;
export interface NativeRuntime {
  controller: NativeSessionController;
  gateway: MissionGateway;
  client: SupabaseClient | null;
  accountGateway: NativeAccountGateway;
  documents: NativeDocumentRuntime;
  contracts: ContractGateway;
  contractsScenario: boolean;
  presence: NativePresenceRuntime;
  presenceScenario: boolean;
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
  const currentDocumentsSession = (controller: NativeSessionController): DemoDocumentSession | null => {
    const snapshot = controller.getSnapshot();
    if (snapshot.status !== 'authenticated' || snapshot.context?.kind !== 'soignant') return null;
    return { userId: snapshot.context.userId, epoch: snapshot.epoch, profile: {
      profession: snapshot.context.profile?.profession, type_exercice: snapshot.context.profile?.type_exercice,
    } };
  };
  const currentPresenceSession = (controller: NativeSessionController) => {
    const snapshot = controller.getSnapshot();
    return snapshot.status === 'authenticated' ? nativePresenceContext(snapshot.context, snapshot.epoch) : null;
  };
  const demo = (documentsScenario = false, contractsScenario = false, presenceScenarioEnabled = false) => {
    const controller = createNativeSessionController({ mode: 'demo', context: { ...DEMO_CONTEXT, kind: 'soignant' } });
    const currentSession = () => currentDocumentsSession(controller);
    const documents = createDocumentRuntime({
      gateway: new DemoDocumentGateway({ currentSession, ...(documentsScenario ? { outcomes: DEMO_DOCUMENT_SCENARIO_OUTCOMES } : {}) }),
      uploadJournal: createDemoDocumentUploadJournal(), currentSession,
      createMedia: scope => createDemoDocumentMedia({ scope, currentSession, scenario: documentsScenario }),
    });
    const contracts = createContractRuntime({ mode: 'demo', scenario: contractsScenario,
      digestUtf8: value => Crypto.digestStringAsync(Crypto.CryptoDigestAlgorithm.SHA256, value),
      currentSession: () => {
        const snapshot = controller.getSnapshot();
        const account = snapshot.status === 'authenticated' ? snapshot.context : null;
        const context = nativeContractContext(account);
        return context && account ? { context, epoch: snapshot.epoch,
          canRead: account.kind === 'soignant' || account.kind === 'etablissement' && account.permissions.lecture,
          canSign: account.kind === 'soignant' || account.kind === 'etablissement' && account.permissions.contrats } : null;
      },
    });
    // The synthetic world is shared across demo role switches, never across real accounts.
    const presenceGateway = new DemoPresenceGateway({ currentSession: () => currentPresenceSession(controller),
      ...(presenceScenarioEnabled ? { scenario: 'uncertain-first-scan' as const } : {}) });
    const presence = createPresenceRuntime({ currentSession: () => currentPresenceSession(controller),
      createSession: () => ({ gateway: presenceGateway, readGpsConsent: async () => false }) });
    return { controller, gateway: new DemoGateway(), client: null, accountGateway: new DemoAccountGateway(controller), documents,
      contracts, contractsScenario, presence, presenceScenario: presenceScenarioEnabled, configError: null };
  };
  try {
    // Expo only substitutes explicit EXPO_PUBLIC variable references.
    const config = readNativeConfig({
      mode: process.env.EXPO_PUBLIC_JOLENE_MODE,
      url: process.env.EXPO_PUBLIC_SUPABASE_URL,
      publishableKey: process.env.EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
    }, STAGING_PROJECTS);
    const scenarioFlag = process.env.EXPO_PUBLIC_JOLENE_DOCUMENTS_SCENARIO?.trim() ?? '';
    if (!['', '0', '1'].includes(scenarioFlag)) throw new Error('Le scénario documentaire doit être explicitement activé avec 1, ou désactivé.');
    const documentsScenario = scenarioFlag === '1';
    if (documentsScenario && config.mode !== 'demo') throw new Error('Le scénario documentaire fictif est réservé au mode Démonstration. Désactivez-le pour utiliser TEST.');
    const contractsScenario = contractScenario(config.mode, process.env.EXPO_PUBLIC_JOLENE_CONTRACTS_SCENARIO);
    const presenceScenarioEnabled = presenceScenario(config.mode, process.env.EXPO_PUBLIC_JOLENE_PRESENCE_SCENARIO);
    if (config.mode === 'demo') return demo(documentsScenario, contractsScenario, presenceScenarioEnabled);
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
    // Raw SecureStore, separate keys/service from the auth tombstone/chunk adapter.
    // Logout never erases an unresolved upload receipt.
    const documentStoreOptions = { keychainService: 'jolene.native.documents.staging',
      keychainAccessible: SecureStore.WHEN_UNLOCKED_THIS_DEVICE_ONLY };
    const documents = createDocumentRuntime({
      gateway: new SupabaseDocumentGateway(client, () => Crypto.randomUUID(), createOriginalSigningTransport(config, boundedFetch)),
      uploadJournal: createDocumentUploadJournal({
        getItem: key => SecureStore.getItemAsync(key, documentStoreOptions),
        setItem: (key, value) => SecureStore.setItemAsync(key, value, documentStoreOptions),
        removeItem: key => SecureStore.deleteItemAsync(key, documentStoreOptions),
      }),
      currentSession: () => currentDocumentsSession(controller),
      createMedia: (scope, isCurrent) => createExpoDocumentMediaAdapter({ scope, isCurrent }),
    });
    const contracts = createContractRuntime({ mode: 'staging', client, config, fetch: boundedFetch,
      digestUtf8: value => Crypto.digestStringAsync(Crypto.CryptoDigestAlgorithm.SHA256, value) });
    // A separate raw SecureStore namespace preserves unresolved scans through logout/process restart.
    const presenceStoreOptions = { keychainService: 'jolene.native.presence.staging',
      keychainAccessible: SecureStore.WHEN_UNLOCKED_THIS_DEVICE_ONLY };
    const presenceJournal = createPresenceAttemptJournal({
      getItemAsync: key => SecureStore.getItemAsync(key, presenceStoreOptions),
      setItemAsync: (key, value) => SecureStore.setItemAsync(key, value, presenceStoreOptions),
      deleteItemAsync: key => SecureStore.deleteItemAsync(key, presenceStoreOptions),
    });
    const presenceClock = createPresenceServerClock(config.publishableKey, boundedFetch);
    // Recovery uses the terminal already persisted in the receipt, even after a process restart.
    const terminalId = `native-${Crypto.randomUUID()}`;
    const presence = createPresenceRuntime({ currentSession: () => currentPresenceSession(controller),
      createSession(context, isCurrent) {
        const sensors = context.kind === 'soignant' ? createExpoPresenceSensors({
          scope: { userId: context.userId, epoch: context.epoch }, isCurrent,
          isForeground: () => AppState.currentState === 'active',
        }) : undefined;
        const gateway = new SupabasePresenceGateway(client, { currentSession: () => currentPresenceSession(controller),
          terminalId, newAttemptId: () => Crypto.randomUUID(), clock: presenceClock, journal: presenceJournal, gps: sensors?.gps });
        return { gateway, sensors, readGpsConsent: signal => gateway.readGpsConsent(context, signal) };
      },
    });
    return { controller, gateway, client, accountGateway: new SupabaseAccountGateway(client, controller), documents,
      contracts, contractsScenario: false, presence, presenceScenario: false, configError: null };
  } catch (error) {
    return { ...demo(), configError: error instanceof Error ? error.message : 'Configuration TEST invalide.' };
  }
}
