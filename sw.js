/* Control de Gastos · funcionamiento sin conexión (fase 6).
   - La app (index.html, config.js, librerías, letras, íconos) se guarda en el teléfono: abre aunque no haya internet.
   - Las lecturas de la base de datos van primero a internet; si no hay, se usa la última copia guardada de cada consulta.
   - Lo que se registra sin conexión lo guarda la app en una cola y lo envía al volver internet (no pasa por aquí).
   Cambia VERSION cuando cambie esta lista para que el teléfono tome la nueva. */
const VERSION = 'v2';
const APP = 'cg-app-' + VERSION, LIB = 'cg-lib', DATOS = 'cg-datos';
const PRE = ['./', 'index.html', 'config.js', 'guia.html', 'manifest.webmanifest', 'icon-180.png', 'icon-192.png', 'icon-512.png',
  'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4/dist/umd/supabase.js'];
self.addEventListener('install', e => {
  e.waitUntil(caches.open(APP).then(c => Promise.all(PRE.map(u => c.add(new Request(u, {cache: 'reload'})).catch(() => null)))).then(() => self.skipWaiting()));
});
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k.startsWith('cg-app-') && k !== APP).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener('message', e => { if (e.data === 'limpiarDatos') e.waitUntil(caches.delete(DATOS)); });
const avisar = msg => self.clients.matchAll({includeUncontrolled: true}).then(cs => cs.forEach(c => c.postMessage(msg)));
self.addEventListener('fetch', e => {
  const req = e.request; if (req.method !== 'GET') return;
  const url = new URL(req.url);
  // Base de datos (Supabase): internet primero; sin internet, la última copia de esa misma consulta.
  if (url.hostname.endsWith('.supabase.co')) {
    if (!(url.pathname.startsWith('/rest/v1/') || url.pathname === '/auth/v1/user')) return;
    e.respondWith(fetch(req).then(res => { if (res.ok) { const cp = res.clone(); caches.open(DATOS).then(c => c.put(req.url, cp)); } return res; })
      .catch(() => caches.open(DATOS).then(c => c.match(req.url)).then(r => { avisar({tipo: 'sinRed'}); return r || new Response(JSON.stringify({message: 'Sin conexión y sin copia guardada de estos datos', code: 'offline'}), {status: 503, headers: {'Content-Type': 'application/json'}}); })));
    return;
  }
  // La app misma: internet primero (para tener siempre la última versión); sin internet, la guardada.
  if (url.origin === self.location.origin) {
    e.respondWith(fetch(req).then(res => { if (res.ok) { const cp = res.clone(); caches.open(APP).then(c => c.put(req, cp)); } return res; })
      .catch(() => caches.open(APP).then(c => c.match(req, {ignoreSearch: true}).then(r => r || (req.mode === 'navigate' ? c.match('index.html') : null))).then(r => r || Response.error())));
    return;
  }
  // Librerías y letras: de la copia guardada; si no está, de internet y se guarda.
  if (/(cdn\.jsdelivr\.net|cdnjs\.cloudflare\.com|fonts\.googleapis\.com|fonts\.gstatic\.com)$/.test(url.hostname)) {
    e.respondWith(caches.open(LIB).then(c => c.match(req).then(r => r || caches.match(req).then(r2 => r2 || fetch(req).then(res => { if (res.ok || res.type === 'opaque') c.put(req, res.clone()); return res; })))));
  }
});
