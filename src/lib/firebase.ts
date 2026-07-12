import { memoriserTokenPushAppareil } from './pushDeviceToken';

const firebaseConfig = {
  apiKey: "AIzaSyBWhTy5scThcxUMtFq8spPdg2ViD0E-x6s",
  authDomain: "jolene-app-d91fd.firebaseapp.com",
  projectId: "jolene-app-d91fd",
  storageBucket: "jolene-app-d91fd.firebasestorage.app",
  messagingSenderId: "54202049729",
  appId: "1:54202049729:web:d29deb3c77a916e3b5a040"
};

const VAPID_KEY = 'BAr9zposDcY2jnUEbKvYsck5Scf_iyvO3xth-w2vsRdU3v5SFSfeY0rHgALkc7FZQbbZIT7bboMsY-J6xnniYfQ';

// No Firebase SDK import — use native Web Push API to avoid React dual-instance conflicts

function urlBase64ToUint8Array(base64String: string): Uint8Array {
  const padding = '='.repeat((4 - (base64String.length % 4)) % 4);
  const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
  const rawData = atob(base64);
  const outputArray = new Uint8Array(rawData.length);
  for (let i = 0; i < rawData.length; ++i) {
    outputArray[i] = rawData.charCodeAt(i);
  }
  return outputArray;
}

function detecterPlateforme(): 'WEB' | 'IOS' | 'ANDROID' {
  const ua = navigator.userAgent;
  if (/android/i.test(ua)) return 'ANDROID';
  if (/iPad|iPhone|iPod/.test(ua)) return 'IOS';
  return 'WEB';
}

export async function demanderPermissionPush(
  userId: string,
  supabase: { from: (table: string) => any; rpc: (fn: string, params?: any) => any }
): Promise<string | null> {
  if (typeof window === 'undefined' || !('serviceWorker' in navigator) || !('PushManager' in window)) {
    return null;
  }

  const permission = await Notification.requestPermission();
  if (permission !== 'granted') return null;

  // Register / get the Firebase SW
  let registration = await navigator.serviceWorker.getRegistration('/firebase-messaging-sw.js');
  if (!registration) {
    registration = await navigator.serviceWorker.register('/firebase-messaging-sw.js');
    await navigator.serviceWorker.ready;
  }

  const applicationServerKey = urlBase64ToUint8Array(VAPID_KEY);
  const subscription = await registration.pushManager.subscribe({
    userVisibleOnly: true,
    applicationServerKey: applicationServerKey.buffer as ArrayBuffer,
  });

  const token = JSON.stringify(subscription);
  const plateforme = detecterPlateforme();

  const { error } = await supabase.rpc('fn_upsert_token_push' as any, {
    p_token: token,
    p_plateforme: plateforme,
  });
  if (error) throw error;
  memoriserTokenPushAppareil(token);

  return token;
}

export function ecouterMessagesForeground(
  callback: (payload: { title?: string; body?: string; lien?: string }) => void
): () => void {
  if (typeof window === 'undefined' || !('serviceWorker' in navigator)) {
    return () => {};
  }

  const handler = (event: MessageEvent) => {
    const data = event.data;
    if (data && (data.type === 'PUSH_RECEIVED' || data.notification || data.data)) {
      callback({
        title: data.notification?.title || data.data?.titre || data.title,
        body: data.notification?.body || data.data?.corps || data.body,
        lien: data.data?.lien || data.lien,
      });
    }
  };

  navigator.serviceWorker.addEventListener('message', handler);
  return () => navigator.serviceWorker.removeEventListener('message', handler);
}

// Re-export config for reference only (used by the SW separately)
export { firebaseConfig };
