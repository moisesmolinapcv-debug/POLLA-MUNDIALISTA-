const CACHE_NAME = 'polla-parley-v14';
const ASSETS = [
  './',
  './index.html',
  './style.css',
  './app.js',
  './supabase-js.js',
  './world_cup_data.js',
  './qrcode.min.js',
  './manifest.json',
  './Icono Oficial de la App.png'
];

// Install Event - cache core assets
self.addEventListener('install', (e) => {
  e.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      console.log('[Service Worker] Caching App Shell');
      return cache.addAll(ASSETS);
    })
  );
  self.skipWaiting();
});

// Activate Event - clear old caches
self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys().then((keys) => {
      return Promise.all(
        keys.map((key) => {
          if (key !== CACHE_NAME) {
            console.log('[Service Worker] Removing old cache', key);
            return caches.delete(key);
          }
        })
      );
    })
  );
  self.clients.claim();
});

// Fetch Event - network-first for code/manifest, cache-first for images
self.addEventListener('fetch', (e) => {
  // Avoid non-GET requests
  if (e.request.method !== 'GET') {
    return;
  }

  const isSameOrigin = e.request.url.startsWith(self.location.origin);
  const isFlagCDN = e.request.url.startsWith('https://flagcdn.com/');
  const isSupabase = e.request.url.startsWith('https://blqglkqywmchqrtsqcxi.supabase.co');

  // Allow caching for local files, flagcdn flag images, and Supabase GET requests
  if (!isSameOrigin && !isFlagCDN && !isSupabase) {
    return;
  }

  const isImage = e.request.destination === 'image' || 
                  e.request.url.match(/\.(png|jpg|jpeg|gif|svg|ico)$/i);

  if (isImage) {
    // Cache-First strategy for images
    e.respondWith(
      caches.match(e.request).then((cachedResponse) => {
        if (cachedResponse) {
          return cachedResponse;
        }
        return fetch(e.request).then((networkResponse) => {
          if (networkResponse && networkResponse.status === 200) {
            const responseToCache = networkResponse.clone();
            caches.open(CACHE_NAME).then((cache) => {
              cache.put(e.request, responseToCache);
            });
          }
          return networkResponse;
        }).catch(() => {
          // Graceful fallback if offline
          return caches.match('./Icono Oficial de la App.png');
        });
      })
    );
  } else {
    // Network-First strategy for HTML, JS, CSS, JSON, manifest
    e.respondWith(
      fetch(e.request)
        .then((networkResponse) => {
          if (networkResponse && networkResponse.status === 200) {
            const responseToCache = networkResponse.clone();
            caches.open(CACHE_NAME).then((cache) => {
              cache.put(e.request, responseToCache);
            });
          }
          return networkResponse;
        })
        .catch(() => {
          return caches.match(e.request).then((cachedResponse) => {
            if (cachedResponse) {
              return cachedResponse;
            }
            // Graceful failure
          });
        })
    );
  }
});

// Push event listener - displays notification received from push service
self.addEventListener('push', (event) => {
  const defaultTitle = '⚽ Polla Mundialista';
  const defaultBody  = 'Novedades de la Quiniela. ¡Entra a ver!';
  let title    = defaultTitle;
  let body     = defaultBody;
  let tag      = 'general';
  let urlHint  = './';

  if (event.data) {
    try {
      const d = event.data.json();
      title   = d.title   || defaultTitle;
      body    = d.body    || defaultBody;
      tag     = d.data?.tag    || 'general';
      urlHint = d.data?.url    || './';
    } catch {
      body = event.data.text() || defaultBody;
    }
  }

  // Map tag prefix to deep-link section
  const section = tag.startsWith('result') || tag.startsWith('reminder')
    ? '#pronosticos'
    : tag.startsWith('leaderboard')
      ? '#clasificacion'
      : '';

  const options = {
    body,
    tag,
    icon:    './Icono Oficial de la App.png',
    badge:   './Icono Oficial de la App.png',
    vibrate: [150, 80, 150],
    renotify: true,
    data: { url: urlHint + section },
    actions: [
      { action: 'open',    title: '🏆 Ver tabla'    },
      { action: 'matches', title: '⚽ Ver partidos' }
    ]
  };

  event.waitUntil(self.registration.showNotification(title, options));
});

// Click event listener - focus or open the app when clicking a notification
self.addEventListener('notificationclick', (event) => {
  event.notification.close();

  // Route based on which action button was tapped
  let target = event.notification.data?.url || './';
  if (event.action === 'open')    target = './#clasificacion';
  if (event.action === 'matches') target = './#pronosticos';

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
      for (const client of list) {
        if (client.url.includes(self.location.origin) && 'focus' in client) {
          client.navigate(target);
          return client.focus();
        }
      }
      if (clients.openWindow) return clients.openWindow(target);
    })
  );
});
