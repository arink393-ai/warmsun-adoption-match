/* 只快取自己站上的靜態外殼（HTML／icons），Supabase 與其他外部來源一律
   直接打網路、不快取——這個網站的核心內容全部是即時資料（申請狀態、
   對話、揭露層級），快取到就等於讓使用者看著過期的畫面做決定。
   策略是 network-first：連得上網路就一律用最新的，只有離線時才退回快取。 */
const CACHE = 'warmsun-shell-v1';
const SHELL = ['./index.html', './dashboard.html',
  './icons/icon-192.png', './icons/icon-512.png'];

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(CACHE).then((c) => c.addAll(SHELL)));
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);
  if (url.origin !== location.origin || event.request.method !== 'GET') return;
  event.respondWith(
    fetch(event.request)
      .then((res) => {
        const copy = res.clone();
        caches.open(CACHE).then((c) => c.put(event.request, copy));
        return res;
      })
      .catch(() => caches.match(event.request))
  );
});
