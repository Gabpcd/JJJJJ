/* eslint-disable no-undef */
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
  const title = payload.notification?.title || payload.data?.titre || 'Soin Direct';
  const body = payload.notification?.body || payload.data?.corps || '';
  const lien = payload.data?.lien || '/';

  self.registration.showNotification(title, {
    body,
    icon: '/favicon.ico',
    badge: '/favicon.ico',
    data: { lien },
  });
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const lien = event.notification.data?.lien || '/';
  event.waitUntil(clients.openWindow(lien));
});
