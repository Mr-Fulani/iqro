"use strict";

self.addEventListener("install", () => {
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener("push", (event) => {
  let payload = {};
  try {
    payload = event.data ? event.data.json() : {};
  } catch {
    payload = {};
  }

  const title = typeof payload.title === "string" ? payload.title : "Iqro";
  const body = typeof payload.body === "string" ? payload.body : "";
  const tag = typeof payload.tag === "string" ? payload.tag : "iqro-reminder";
  const signal = payload.signal;
  const url = safeRelativeUrl(payload.url);

  event.waitUntil(
    self.registration.showNotification(title, {
      body,
      tag,
      icon: "/icon",
      badge: "/icon",
      silent: signal === "silent",
      vibrate: signal === "vibration" ? [180, 80, 180] : undefined,
      data: { url },
    }),
  );
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const relativeUrl = safeRelativeUrl(event.notification.data?.url);
  const destination = new URL(relativeUrl, self.location.origin).href;

  event.waitUntil(
    self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((clients) => {
      for (const client of clients) {
        if (new URL(client.url).origin === self.location.origin && "focus" in client) {
          if ("navigate" in client) {
            return client.navigate(destination).then(() => client.focus());
          }
          return client.focus();
        }
      }
      return self.clients.openWindow ? self.clients.openWindow(destination) : undefined;
    }),
  );
});

function safeRelativeUrl(value) {
  if (typeof value !== "string" || !value.startsWith("/") || value.startsWith("//")) {
    return "/";
  }
  try {
    const parsed = new URL(value, self.location.origin);
    return parsed.origin === self.location.origin
      ? `${parsed.pathname}${parsed.search}${parsed.hash}`
      : "/";
  } catch {
    return "/";
  }
}
