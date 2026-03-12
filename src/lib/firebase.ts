const firebaseConfig = {
  apiKey: "AIzaSyCsj-tfliVxZl3F9ncrtnHR-5xJu3B16vQ",
  authDomain: "soin-direct.firebaseapp.com",
  projectId: "soin-direct",
  storageBucket: "soin-direct.firebasestorage.app",
  messagingSenderId: "983137696907",
  appId: "1:983137696907:web:08decd33bbd6d51e8fe88e"
};

const VAPID_KEY = 'BGFrObLlznxsrpnyW8fmPSC9zE29tAw0Tvu_qss8JhpTjrDBC3FCJVjRWC1zwVctLBYcXgzKLDC6OUIp5EVHHqs';

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
  supabase: { from: (table: string) => any }
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

  const subscription = await registration.pushManager.subscribe({
    userVisibleOnly: true,
    applicationServerKey: urlBase64ToUint8Array(VAPID_KEY),
  });

  const token = JSON.stringify(subscription);
  const plateforme = detecterPlateforme();

  await supabase.from('tokens_push').upsert(
    { utilisateur_id: userId, token, plateforme },
    { onConflict: 'token' }
  );

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
