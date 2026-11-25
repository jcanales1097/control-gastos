/* Control de Gastos · funcionamiento sin conexión (fase 6).
   - La app (index.html, config.js, librerías, letras, íconos) se guarda en el teléfono: abre aunque no haya internet.
   - Las lecturas de la base de datos van primero a internet; si no hay, se usa la última copia guardada de cada consulta.
   - Lo que se registra sin conexión lo guarda la app en una cola y lo envía al volver internet (no pasa por aquí).
   Cambia VERSION cuando cambie esta lista para que el teléfono tome la nueva. */
const VERSION = 'v4';
const APP = 'cg-app-' + VERSION, LIB = 'cg-lib-2', DATOS = 'cg-datos';   // cg-lib-2: las librerías ahora se piden con huella SRI (CORS); la copia vieja no sirve
const PRE = ['./', 'index.html', 'config.js', 'guia.html', 'manifest.webmanifest', 'icon-180.png', 'icon-192.png', 'icon-512.png',
  'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4/dist/umd/supabase.js'];
self.addEventListener('install', e => {
  e.waitUntil(caches.open(APP).then(c => Promise.all(PRE.map(u => c.add(new Request(u, {cache: 'reload'})).catch(() => null)))).then(() => self.skipWaiting()));
});
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => (k.startsWith('cg-app-') && k !== APP) || k === 'cg-lib').map(k => caches.delete(k)))).then(() => self.clients.claim()));
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
  // La app misma: internet primero (para tener siempre la última versión), pero si tarda más de 3 s o no hay internet se abre la
  // guardada al instante (con señal débil ya no se queda en blanco); la descarga sigue por detrás y queda para la próxima vez.
  if (url.origin === self.location.origin) {
    const guardada = () => caches.open(APP).then(c => c.match(req, {ignoreSearch: true}).then(r => r || (req.mode === 'navigate' ? c.match('index.html') : null)));
    const red = fetch(req).then(res => { if (res.ok) { const cp = res.clone(); caches.open(APP).then(c => c.put(req, cp)); } return res; });
    e.respondWith(new Promise(ok => {
      let listo = false; const dar = r => { if (!listo && r) { listo = true; ok(r); } };
      const t = setTimeout(() => guardada().then(dar), 3000);
      red.then(r => { clearTimeout(t); dar(r); }).catch(() => { clearTimeout(t); guardada().then(r => { dar(r || Response.error()); if (!r) ok(Response.error()); }); });
    }));
    e.waitUntil(red.catch(() => null));
    return;
  }
  // Librerías y letras: de la copia guardada; si no está, de internet y se guarda.
  if (/(cdn\.jsdelivr\.net|fonts\.googleapis\.com|fonts\.gstatic\.com)$/.test(url.hostname)) {
    e.respondWith(caches.open(LIB).then(c => c.match(req).then(r => r || caches.match(req).then(r2 => r2 || fetch(req).then(res => { if (res.ok || (res.type === 'opaque' && url.hostname.startsWith('fonts.'))) c.put(req, res.clone()); return res; })))));
  }
});
