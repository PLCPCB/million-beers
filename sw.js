// 1 Million Chinese Beers : réseau d'abord, dernière version gardée pour ouvrir l'app sans réseau.
const CACHE = 'mcb-v1';
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', e => e.waitUntil(self.clients.claim()));
self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET' || new URL(req.url).origin !== location.origin) return;   // Supabase & co : jamais touchés
  const isPage = req.mode === 'navigate';
  e.respondWith(fetch(req).then(res => {
    if (res.ok || (isPage && res.status === 404)) {
      const copy = res.clone(); caches.open(CACHE).then(c => c.put(isPage ? 'app' : req, copy));
    }
    return res;
  }).catch(() => caches.match(isPage ? 'app' : req).then(r => r || caches.match('app'))));
});
