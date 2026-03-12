import { initializeApp } from 'firebase/app';
import { getMessaging, getToken, onMessage, isSupported } from 'firebase/messaging';

const firebaseConfig = {
  apiKey: "AIzaSyCsj-tfliVxZl3F9ncrtnHR-5xJu3B16vQ",
  authDomain: "soin-direct.firebaseapp.com",
  projectId: "soin-direct",
  storageBucket: "soin-direct.firebasestorage.app",
  messagingSenderId: "983137696907",
  appId: "1:983137696907:web:08decd33bbd6d51e8fe88e"
};

const VAPID_KEY = 'BGFrObLlznxsrpnyW8fmPSC9zE29tAw0Tvu_qss8JhpTjrDBC3FCJVjRWC1zwVctLBYcXgzKLDC6OUIp5EVHHqs';

const app = initializeApp(firebaseConfig);

let messagingInstance: ReturnType<typeof getMessaging> | null = null;

async function getMessagingInstance() {
  if (messagingInstance) return messagingInstance;
  const supported = await isSupported();
  if (!supported) return null;
  messagingInstance = getMessaging(app);
  return messagingInstance;
}

export async function demanderPermissionPush(
  userId: string,
  supabase: { from: (table: string) => any }
) {
  const permission = await Notification.requestPermission();
  if (permission !== 'granted') {
    return null;
  }

  const messaging = await getMessagingInstance();
  if (!messaging) return null;

  const token = await getToken(messaging, {
    vapidKey: VAPID_KEY,
    serviceWorkerRegistration: await navigator.serviceWorker.register('/firebase-messaging-sw.js'),
  });

  if (token) {
    const plateforme = detecterPlateforme();
    await supabase.from('tokens_push').upsert(
      {
        utilisateur_id: userId,
        token,
        plateforme,
      },
      { onConflict: 'token' }
    );
  }

  return token;
}

function detecterPlateforme(): 'WEB' | 'IOS' | 'ANDROID' {
  const ua = navigator.userAgent;
  if (/android/i.test(ua)) return 'ANDROID';
  if (/iPad|iPhone|iPod/.test(ua)) return 'IOS';
  return 'WEB';
}

export async function ecouterMessagesForeground(
  callback: (payload: { title?: string; body?: string; lien?: string }) => void
) {
  const messaging = await getMessagingInstance();
  if (!messaging) return () => {};

  return onMessage(messaging, (payload) => {
    callback({
      title: payload.notification?.title || payload.data?.titre,
      body: payload.notification?.body || payload.data?.corps,
      lien: payload.data?.lien,
    });
  });
}

export { app };
