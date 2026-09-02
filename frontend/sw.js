/* Homzy service worker — Web Push for broker follow-up reminders.
   Kept tiny on purpose: it only shows pushed notifications and focuses the
   CRM when one is tapped. No offline caching (the app is online-only). */

self.addEventListener('install', function (e) { self.skipWaiting(); });
self.addEventListener('activate', function (e) { e.waitUntil(self.clients.claim()); });

self.addEventListener('push', function (event) {
  var data = {};
  try { data = event.data ? event.data.json() : {}; } catch (e) {
    data = { title: 'Homzy', body: (event.data && event.data.text()) || '' };
  }
  var title = data.title || 'Homzy';
  var options = {
    body: data.body || '',
    icon: '/assets/icon-192.png',
    badge: '/assets/icon-192.png',
    dir: 'rtl',
    lang: 'ar',
    tag: data.tag || 'homzy',
    renotify: true,
    data: { url: data.url || '/clients' }
  };
  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener('notificationclick', function (event) {
  event.notification.close();
  var url = (event.notification.data && event.notification.data.url) || '/clients';
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function (list) {
      for (var i = 0; i < list.length; i++) {
        var c = list[i];
        if (c.url.indexOf(url) !== -1 && 'focus' in c) return c.focus();
      }
      if (self.clients.openWindow) return self.clients.openWindow(url);
    })
  );
});
