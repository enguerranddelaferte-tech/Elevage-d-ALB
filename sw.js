// Service worker : met l'application en cache pour qu'elle s'ouvre même avec un réseau faible.
// Après une modification des fichiers, augmentez le numéro de version ci-dessous.
const VERSION = 'ecurie-v38';
const APP = [
  './',
  './index.html',
  './manifest.webmanifest',
  './icons/icon-192.png',
  './icons/icon-512.png',
  './icons/icon-maskable-512.png',
  './icons/apple-touch-icon.png'
];
// Bibliothèque de connexion à la base : mise en cache dès l'installation (ouverture hors ligne).
const LIBS = ['https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4/dist/umd/supabase.js'];

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(VERSION).then((c) => c.addAll(APP).then(() => c.addAll(LIBS).catch(() => {}))).then(() => self.skipWaiting()));
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

// Notifications envoyées par l'écurie (annulation de cours, message, facture…), même appli fermée.
self.addEventListener('push', (event) => {
  let d = {};
  try { d = event.data ? event.data.json() : {}; } catch (e) { d = { titre: event.data ? event.data.text() : '' }; }
  const titre = d.titre || "Élevage d'ALB";
  event.waitUntil(Promise.all([
    self.registration.showNotification(titre, {
      body: d.texte || '', icon: './icons/icon-192.png', badge: './icons/icon-192.png',
      tag: d.tag || undefined, data: { lien: d.lien || '' }, lang: 'fr'
    }),
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((cs) => cs.forEach((c) => c.postMessage({ type: 'notif' })))
  ]));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const lien = (event.notification.data && event.notification.data.lien) || '';
  const url = new URL('./' + (lien ? '#' + lien : ''), self.registration.scope).href;
  event.waitUntil(self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((cs) => {
    const c = cs.find((x) => x.url.startsWith(self.registration.scope));
    if (c) { c.postMessage({ type: 'goto', lien }); return c.focus(); }
    return self.clients.openWindow(url);
  }));
});
