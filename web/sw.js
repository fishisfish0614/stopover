// 经停 Stopover service worker — push notifications only.
// Deliberately no fetch handler and no offline cache: the page always loads fresh from the server.
self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", e => e.waitUntil(self.clients.claim()));

self.addEventListener("push", e => {
  let d = {};
  try { d = e.data ? e.data.json() : {}; } catch (_) { d = { body: e.data ? e.data.text() : "" }; }
  const data = d.data || {};
  e.waitUntil(self.registration.showNotification(d.title || "经停", {
    body: d.body || "",
    icon: "icon-192.png",
    badge: "icon-192.png",
    data,
    tag: data.share_id ? "share-" + data.share_id : (data.target || data.city || undefined),
  }));
});

self.addEventListener("notificationclick", e => {
  e.notification.close();
  const d = e.notification.data || {};
  const url = new URL(d.city ? "./?city=" + encodeURIComponent(d.city) : "./", self.registration.scope).href;
  e.waitUntil(self.clients.matchAll({ type: "window", includeUncontrolled: true }).then(list => {
    for (const c of list) {
      if (c.url.startsWith(self.registration.scope) && "focus" in c) {
        c.postMessage({ type: "open", city: d.city || "", target: d.target || "", share_id: d.share_id || null });
        return c.focus();
      }
    }
    return self.clients.openWindow(url);
  }));
});
