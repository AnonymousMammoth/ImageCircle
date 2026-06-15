const CACHE_NAME = 'imagecircle-shell-v1';
const SHELL_ASSETS = [
  '/',
  '/app.css',
  '/js/utils.js',
  '/js/state.js',
  '/js/api.js',
  '/js/router.js',
  '/js/components/shell.js',
  '/js/components/login.js',
  '/js/components/forcePasswordChange.js',
  '/js/components/home.js',
  '/js/components/storiesTray.js',
  '/js/components/storyViewer.js',
  '/js/components/postCard.js',
  '/js/components/comments.js',
  '/js/components/composer.js',
  '/js/components/camera.js',
  '/js/components/profile.js',
  '/js/components/search.js',
  '/js/components/notifications.js',
  '/js/components/settings.js',
  '/js/app.js',
  '/icons/icon-192x192.png',
  '/icons/icon-512x512.png'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(SHELL_ASSETS))
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener('fetch', (event) => {
  const { request } = event;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);

  // API and media: always try network first; offline users see errors gracefully.
  if (url.pathname.startsWith('/api/') || url.pathname.startsWith('/media/')) {
    event.respondWith(fetch(request).catch(() => caches.match(request)));
    return;
  }

  // Navigation / shell assets: cache first, fallback to network and update cache.
  event.respondWith(
    caches.match(request).then((cached) => {
      if (cached) return cached;
      return fetch(request)
        .then((response) => {
          if (response && response.status === 200 && response.type === 'basic') {
            const clone = response.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(request, clone));
          }
          return response;
        })
        .catch(() => caches.match('/'));
    })
  );
});
