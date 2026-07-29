// ─── Cache Configuration ───
// v7 (2026-07-29) : identité visuelle canonique disponible hors connexion.
// v6 (2026-05-04) : ne plus intercepter les requêtes cross-origin (corrige
// l'iframe Turnstile bloqué par SOP en mode normal — incognito OK car pas
// de SW persistant).
const CACHE_VERSION = 'jolene-v7';
const STATIC_CACHE = `static-${CACHE_VERSION}`;
const API_CACHE = `api-${CACHE_VERSION}`;

// Only cache offline fallback — everything else network-only for instant updates
const STATIC_ASSETS = [
  '/offline.html',
  '/icon-192x192.png',
];

// ─── Web Push (VAPID, no Firebase) ───
self.addEventListener('push', (event) => {
  let data = {};
  try { data = event.data?.json() || {}; } catch { /* invalid payload */ }

  const title = data.title || data.notification?.title || 'Jolene';
  const body = data.body || data.notification?.body || '';
  const url = data.data?.url || data.data?.lien || '/';

  event.waitUntil(
    self.registration.showNotification(title, {
      body,
      icon: '/icon-192x192.png',
      badge: '/icon-192x192.png',
      data: { url },
      vibrate: [200, 100, 200],
      tag: 'jolene-notification',
      renotify: true,
    })
  );

  // Forward to open clients
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clients) => {
      clients.forEach((client) => {
        client.postMessage({
          type: 'PUSH_RECEIVED',
          notification: { title, body },
          data: data.data || {},
        });
      });
    })
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const url = event.notification.data?.url || '/';
  event.waitUntil(
    self.clients.matchAll({ type: 'window' }).then((windowClients) => {
      // Focus existing window if available
      for (const client of windowClients) {
        if (client.url.includes('jolene') && 'focus' in client) {
          client.focus();
          client.navigate(url);
          return;
        }
      }
      // Open new window
      return self.clients.openWindow(url);
    })
  );
});

// ─── Install: Pre-cache static assets ───
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(STATIC_CACHE).then((cache) => cache.addAll(STATIC_ASSETS))
  );
  self.skipWaiting();
});

// ─── Activate: Clean old caches, notify clients ───
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys
          .filter((k) => k !== STATIC_CACHE && k !== API_CACHE)
          .map((k) => caches.delete(k))
      )
    ).then(() => {
      self.clients.matchAll({ type: 'window' }).then((windowClients) => {
        windowClients.forEach((client) => {
          client.postMessage({ type: 'SW_UPDATED' });
        });
      });
      return self.clients.claim();
    })
  );
});

// ─── Fetch: Only cache fonts/images, let JS/HTML/CSS/API go to network ───
self.addEventListener('fetch', (event) => {
  const { request } = event;
  const url = new URL(request.url);

  if (request.method !== 'GET') return;
  if (!url.protocol.startsWith('http')) return;

  // CRITIQUE : ne JAMAIS intercepter les requêtes cross-origin. `event.respondWith()`
  // sur une response cross-origin altère le contexte d'origin perçu par le browser,
  // ce qui casse les iframes (Turnstile, Stripe Elements) avec une erreur SOP
  // "Blocked a frame with origin 'X' from accessing a frame with origin 'Y'".
  // Cf. bug 2026-05-04 (Turnstile login KO en mode normal, OK en incognito sans SW).
  // Le browser fait la requête nativement quand on `return` sans respondWith.
  if (url.origin !== self.location.origin) return;

  // Only cache fonts and static images — NEVER cache JS/HTML/CSS to avoid
  // version mismatch after deployments
  if (isCacheableAsset(url)) {
    event.respondWith(cacheFirst(request));
    return;
  }

  // Everything else (JS, HTML, CSS, API, navigations) → always go to network
  // Only fall back to cache if offline
  event.respondWith(networkOnly(request));
});

function isCacheableAsset(url) {
  const ext = url.pathname.split('.').pop()?.toLowerCase();
  // Only cache truly static immutable assets (fonts, images)
  const cacheableExts = ['woff', 'woff2', 'ttf', 'otf', 'png', 'jpg', 'jpeg', 'svg', 'webp', 'ico', 'gif', 'avif'];
  return cacheableExts.includes(ext);
}

async function networkOnly(request) {
  try {
    return await fetch(request);
  } catch {
    // Offline fallback only
    if (request.mode === 'navigate') {
      const offlinePage = await caches.match('/offline.html');
      if (offlinePage) return offlinePage;
    }
    return new Response('Hors connexion', { status: 503 });
  }
}

async function cacheFirst(request) {
  const cached = await caches.match(request);
  if (cached) return cached;
  try {
    const response = await fetch(request);
    if (response.ok) {
      const cache = await caches.open(STATIC_CACHE);
      cache.put(request, response.clone());
    }
    return response;
  } catch {
    return new Response('', { status: 503 });
  }
}

async function networkFirst(request) {
  try {
    const response = await fetch(request);
    if (response.ok) {
      const cache = await caches.open(API_CACHE);
      cache.put(request, response.clone());
    }
    return response;
  } catch {
    const cached = await caches.match(request);
    return cached || new Response('{"error":"offline"}', {
      status: 503,
      headers: { 'Content-Type': 'application/json' },
    });
  }
}

async function navigationHandler(request) {
  try {
    const response = await fetch(request);
    if (response.ok) {
      const cache = await caches.open(STATIC_CACHE);
      cache.put(request, response.clone());
    }
    return response;
  } catch {
    const cached = await caches.match(request);
    if (cached) return cached;
    const offlinePage = await caches.match('/offline.html');
    return offlinePage || new Response('Hors connexion', { status: 503 });
  }
}
