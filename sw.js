// 1 Million Chinese Beers : réseau d'abord, dernière version gardée pour ouvrir l'app sans réseau.
const CACHE = 'mcb-v3';
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

// Notifications push envoyées par Supabase
self.addEventListener('push', e => {
  let d = {}; try { d = e.data ? e.data.json() : {}; } catch { d = {title: '1M Beers', body: e.data && e.data.text()}; }
  e.waitUntil(self.registration.showNotification(d.title || '1M Beers', {
    body: d.body || '', tag: d.tag || undefined, renotify: !!d.tag,
    icon: '/million-beers/icons/icon-192.png', badge: '/million-beers/icons/badge-96.png',
    data: {url: '/million-beers/'}
  }));
});
self.addEventListener('notificationclick', e => {
  e.notification.close();
  e.waitUntil(self.clients.matchAll({type: 'window', includeUncontrolled: true}).then(list => {
    for (const c of list) if (c.url.includes('/million-beers/') && 'focus' in c) return c.focus();
    return self.clients.openWindow('/million-beers/');
  }));
});
