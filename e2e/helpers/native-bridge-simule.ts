import type { Page } from '@playwright/test';

/** Simulates the Capacitor bridge only. No APNs/FCM delivery or store install is claimed. */
export async function simulerBridgeNatif(page: Page, platform: 'ios' | 'android', update = 1) {
  await page.addInitScript(({ platform, update }) => {
    const w = window as any;
    const callbacks = new Map<string, { plugin: string; event: string; callback: Function }>();
    const state = { permission: 'granted', update, storeOpened: false, calls: [] as string[], next: 0,
      files: {} as Record<string, string>, fileSizes: {} as Record<string, number>, shares: [] as { url: string; data: string }[],
      emit(plugin: string, event: string, value: unknown) { for (const listener of callbacks.values()) if (listener.plugin === plugin && listener.event === event) listener.callback(value); },
    };
    w.__native = state;
    Object.defineProperty(state, 'listeners', { get: () => [...callbacks.values()].map(({ plugin, event }) => ({ plugin, event })) });
    w.CapacitorCustomPlatform = { name: platform };
    const plugins: Record<string, string[]> = {
      App: ['getInfo', 'getLaunchUrl', 'getState'], AppUpdate: ['getAppUpdateInfo', 'openAppStore'],
      PushNotifications: ['checkPermissions', 'requestPermissions', 'register', 'unregister', 'removeAllListeners'],
      Network: ['getStatus'], SplashScreen: ['hide'], StatusBar: ['setStyle', 'setBackgroundColor'],
      Keyboard: ['setResizeMode', 'setScroll', 'setAccessoryBarVisible', 'hide'],
      Preferences: ['get', 'set', 'remove'], Haptics: ['impact', 'selectionStart', 'selectionEnd', 'selectionChanged'],
      NativeBiometric: ['isAvailable'],
      Filesystem: ['mkdir', 'readdir', 'writeFile', 'getUri', 'deleteFile'], Share: ['share'],
    };
    w.Capacitor = {
      PluginHeaders: Object.entries(plugins).map(([name, methods]) => ({ name, methods: [
        ...methods.map(name => ({ name, rtype: 'promise' })), { name: 'addListener', rtype: 'callback' }, { name: 'removeListener', rtype: 'promise' },
      ] })),
      nativeCallback(plugin: string, method: string, options: any, callback: Function) {
        const key = String(++state.next); callbacks.set(key, { plugin, event: options.eventName, callback }); return key;
      },
      async nativePromise(plugin: string, method: string, options: any = {}) {
        state.calls.push(`${plugin}.${method}`);
        if (method === 'removeListener') { callbacks.delete(options.callbackId); return {}; }
        if (method === 'removeAllListeners') { for (const [key, value] of callbacks) if (value.plugin === plugin) callbacks.delete(key); return {}; }
        if (plugin === 'AppUpdate') {
          if (method === 'openAppStore') { state.storeOpened = true; return {}; }
          if (state.update === -1) throw Error('Simulation hors-ligne');
          return { currentVersionName: '1.0.6', currentVersionCode: '23', availableVersionName: '1.0.7', availableVersionCode: '24', updateAvailability: state.update };
        }
        if (plugin === 'App' && method === 'getInfo') return { id: 'app.jolene', version: '1.0.6', build: '23' };
        if (plugin === 'App' && method === 'getState') return { isActive: true };
        if (plugin === 'Network') return { connected: true, connectionType: 'wifi' };
        if (plugin === 'NativeBiometric') return { isAvailable: false };
        if (plugin === 'Filesystem') {
          if (method === 'readdir') return { files: Object.keys(state.files).filter(path => path.startsWith(`${options.path}/`)).map(path => ({ name: path.slice(options.path.length + 1), type: 'file', size: state.fileSizes[path] ?? atob(state.files[path]).length })) };
          if (method === 'writeFile') { state.files[options.path] = options.data; return { uri: `file:///cache/${options.path}` }; }
          if (method === 'getUri') return { uri: `file:///cache/${options.path}` };
          if (method === 'deleteFile') { delete state.files[options.path]; delete state.fileSizes[options.path]; }
          return {};
        }
        if (plugin === 'Share' && method === 'share') {
          const data = state.files[options.url.replace('file:///cache/', '')];
          if (!data) throw Error('Fichier de partage absent');
          state.shares.push({ url: options.url, data }); return { activityType: 'cible-simulee' };
        }
        if (plugin === 'PushNotifications') {
          if (method.includes('Permissions')) return { receive: state.permission };
          if (method === 'register') state.emit(plugin, 'registration', { value: 'native-fixture-token' });
        }
        if (plugin === 'Preferences') {
          if (method === 'get') return { value: localStorage.getItem(options.key) };
          if (method === 'set') localStorage.setItem(options.key, options.value);
          if (method === 'remove') localStorage.removeItem(options.key);
        }
        return {};
      },
    };
    localStorage.setItem('push_permission_asked', 'later');
  }, { platform, update });
}
