// Service worker : met l'application en cache pour qu'elle s'ouvre même avec un réseau faible.
// Après une modification des fichiers, augmentez le numéro de version ci-dessous.
const VERSION = 'ecurie-v12';
const APP = [
  './',
  './index.html',
  './manifest.webmanifest',
  './icons/icon-192.png',
  './icons/icon-512.png',
  './icons/icon-maskable-512.png',
  './icons/apple-touch-icon.png'
];

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(VERSION).then((c) => c.addAll(APP)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== VERSION).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

function networkFirst(req, key) {
  return fetch(req)
    .then((res) => { if (res && res.ok) { const copy = res.clone(); caches.open(VERSION).then((c) => c.put(key || req, copy)); } return res; })
    .catch(() => caches.match(key || req));
}

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);

  // Données de la base (Supabase) : jamais mises en cache par le service worker.
  if (/\.supabase\.(co|in)$/.test(url.hostname)) return;

  // Page et configuration : réseau d'abord (mises à jour immédiates), cache si hors ligne.
  if (req.mode === 'navigate') { event.respondWith(networkFirst(req, './index.html')); return; }
  if (url.origin === self.location.origin && url.pathname.endsWith('/config.js')) { event.respondWith(networkFirst(req)); return; }

  // Polices, bibliothèque de connexion et fichiers de l'appli : cache d'abord, puis réseau.
  const cdn = url.hostname === 'fonts.googleapis.com' || url.hostname === 'fonts.gstatic.com' || url.hostname === 'cdn.jsdelivr.net';
  if (cdn || url.origin === self.location.origin) {
    event.respondWith(
      caches.match(req).then((hit) => hit || fetch(req).then((res) => {
        if (res && (res.ok || res.type === 'opaque')) { const copy = res.clone(); caches.open(VERSION).then((c) => c.put(req, copy)); }
        return res;
      }))
    );
  }
});
