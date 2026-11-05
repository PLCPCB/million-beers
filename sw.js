// 1 Million Chinese Beers : l'app s'ouvre tout de suite depuis la copie du téléphone,
// puis la page se met à jour en arrière-plan (la page vérifie version.json et recharge si besoin).
const CACHE = 'mcb-v5';
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', e => e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim())));

// La page : toujours revalidée auprès de GitHub (sinon le cache HTTP peut servir l'ancienne version pendant 10 min).
const fetchPage = url => fetch(url, {cache: 'no-cache', credentials: 'same-origin'})
  .then(r => r.redirected ? new Response(r.body, {status: r.status, statusText: r.statusText, headers: r.headers}) : r);

self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== location.origin) return;            // Supabase & co : jamais touchés
  if (req.mode === 'navigate'){
    e.respondWith(caches.open(CACHE).then(async c => {
      const cached = await c.match('app');
      const net = fetchPage(req.url).then(r => { if (r.ok || r.status === 404) c.put('app', r.clone()); return r; });
      if (cached){ e.waitUntil(net.catch(() => {})); return cached; }   // ouverture instantanée
      return net.catch(() => caches.match('app'));
    }));
    return;
  }
  if (url.search) return;                                // version.json?t=…, ?shell=… : réseau direct, jamais mis en cache
  if (url.pathname.includes('/fonts/') || url.pathname.includes('/icons/')){
    e.respondWith(caches.match(req).then(r => r || fetch(req).then(res => {    // polices et icônes : ne changent pas
      if (res.ok){ const copy = res.clone(); caches.open(CACHE).then(c => c.put(req, copy)); }
      return res;
    })));
    return;
  }
  e.respondWith(fetch(req).then(res => {                 // le reste : réseau d'abord, copie pour le hors ligne
    if (res.ok){ const copy = res.clone(); caches.open(CACHE).then(c => c.put(req, copy)); }
    return res;
  }).catch(() => caches.match(req)));
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
