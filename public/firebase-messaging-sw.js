/* eslint-disable no-undef */

// ─── Cache Configuration ───
const CACHE_VERSION = 'soin-direct-v1';
const STATIC_CACHE = `static-${CACHE_VERSION}`;
const API_CACHE = `api-${CACHE_VERSION}`;

const STATIC_ASSETS = [
  '/',
  '/offline.html',
  '/favicon.ico',
  '/icon-192x192.png',
  '/icon-512x512.png',
  '/og-default.png',
  '/manifest.json',
];

// ─── Firebase Messaging ───
importScripts('https://www.gstatic.com/firebasejs/10.12.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: "AIzaSyCsj-tfliVxZl3F9ncrtnHR-5xJu3B16vQ",
  authDomain: "soin-direct.firebaseapp.com",
  projectId: "soin-direct",
  storageBucket: "soin-direct.firebasestorage.app",
  messagingSenderId: "983137696907",
  appId: "1:983137696907:web:08decd33bbd6d51e8fe88e"
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const title = payload.notification?.title || payload.data?.titre || 'Jolene';
  const body = payload.notification?.body || payload.data?.corps || '';
  const lien = payload.data?.lien || '/';

  self.registration.showNotification(title, {
    body,
    icon: '/favicon.ico',
    badge: '/favicon.ico',
    data: { lien },
  });
});

// Forward foreground messages to client
self.addEventListener('push', (event) => {
  const allClients = self.clients.matchAll({ type: 'window', includeUncontrolled: true });
  event.waitUntil(
    allClients.then((clients) => {
      const data = event.data?.json?.() || {};
      clients.forEach((client) => {
        client.postMessage({
          type: 'PUSH_RECEIVED',
          notification: data.notification,
          data: data.data,
        });
      });
    })
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const lien = event.notification.data?.lien || '/';
  event.waitUntil(clients.openWindow(lien));
});

// ─── Install: Pre-cache static assets + offline page ───
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(STATIC_CACHE).then((cache) => cache.addAll(STATIC_ASSETS))
  );
  self.skipWaiting();
});

// ─── Activate: Clean old caches, notify clients of update ───
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys
          .filter((k) => k !== STATIC_CACHE && k !== API_CACHE)
          .map((k) => caches.delete(k))
      )
    ).then(() => {
      // Notify all clients that a new SW version is active
      self.clients.matchAll({ type: 'window' }).then((windowClients) => {
        windowClients.forEach((client) => {
          client.postMessage({ type: 'SW_UPDATED' });
        });
      });
      return self.clients.claim();
    })
  );
});

// ─── Fetch: Cache-first for statics, Network-first for API ───
self.addEventListener('fetch', (event) => {
  const { request } = event;
  const url = new URL(request.url);

  // Skip non-GET requests
  if (request.method !== 'GET') return;

  // Skip chrome-extension and other non-http schemes
  if (!url.protocol.startsWith('http')) return;

  // Network-first for Supabase API calls
  if (url.hostname.includes('supabase.co') || url.hostname.includes('supabase.in')) {
    event.respondWith(networkFirst(request));
    return;
  }

  // Cache-first for static assets (JS, CSS, fonts, images, icons)
  if (isStaticAsset(url)) {
    event.respondWith(cacheFirst(request));
    return;
  }

  // Network-first for navigation (HTML pages)
  if (request.mode === 'navigate') {
    event.respondWith(navigationHandler(request));
    return;
  }

  // Default: network with cache fallback
  event.respondWith(networkFirst(request));
});

function isStaticAsset(url) {
  const ext = url.pathname.split('.').pop()?.toLowerCase();
  const staticExts = ['js', 'css', 'woff', 'woff2', 'ttf', 'otf', 'eot', 'png', 'jpg', 'jpeg', 'svg', 'webp', 'ico', 'gif', 'avif'];
  return staticExts.includes(ext) || url.pathname.startsWith('/assets/');
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
    // Fallback to offline page
    const offlinePage = await caches.match('/offline.html');
    return offlinePage || new Response('Hors connexion', { status: 503 });
  }
}
