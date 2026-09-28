self.addEventListener("push", event => {
  let data = {};
  try { data = event.data ? event.data.json() : {}; } catch (_) {}
  event.waitUntil(self.registration.showNotification(data.title || "Gala build ready", {
    body: data.body || "Tap to install the update.",
    icon: "/gala/icon-512.png",
    tag: "gala-" + (data.project || "build"),
    data: {url: data.url || "/gala/"}
  }));
});
self.addEventListener("notificationclick", event => {
  event.notification.close();
  const url = new URL(event.notification.data.url, self.location.origin);
  if (url.origin !== self.location.origin || !url.pathname.startsWith("/gala/")) return;
  event.waitUntil(clients.openWindow(url.href));
});
