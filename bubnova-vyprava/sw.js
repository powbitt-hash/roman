// Offline: vlastné súbory vrátane písiem z vyrovnávacej pamäte, ostatné zo siete s uložením.
const CACHE = 'bubny-v2';
const FILES = ['./', 'index.html', 'manifest.webmanifest', 'icon-192.png', 'icon-512.png',
  'fonts/baloo2-latin.woff2', 'fonts/baloo2-latin-ext.woff2', 'fonts/nunito-latin.woff2', 'fonts/nunito-latin-ext.woff2'];
self.addEventListener('install', e => e.waitUntil(caches.open(CACHE).then(c => c.addAll(FILES)).then(() => self.skipWaiting())));
self.addEventListener('activate', e => e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim())));
self.addEventListener('fetch', e => {
  if (e.request.method !== 'GET') return;
  e.respondWith(fetch(e.request).then(r => { const copy = r.clone(); caches.open(CACHE).then(c => c.put(e.request, copy)).catch(() => {}); return r; }).catch(() => caches.match(e.request, { ignoreSearch: true })));
});
