#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const http2 = require("node:http2");
const crypto = require("node:crypto");

function sendDevice(client, entry, payload) {
  return new Promise((resolve) => {
    let status = 0;
    let body = "";
    const request = client.request({
      ":method": "POST", ":path": `/3/device/${entry.token}`,
      "apns-topic": "com.galaengine.app", "apns-push-type": "alert",
      "apns-priority": "10", "apns-expiration": String(Math.floor(Date.now() / 1000) + 3600),
      "apns-collapse-id": crypto.createHash("sha256").update(payload.project).digest("hex"),
    });
    request.setTimeout(10000, () => request.destroy(new Error("APNs request timed out")));
    request.on("response", (headers) => { status = headers[":status"]; });
    request.setEncoding("utf8");
    request.on("data", (chunk) => { body += chunk; });
    request.on("error", () => resolve({ token: entry.token, environment: entry.environment,
      status: "failed", reason: "ConnectionError" }));
    request.on("end", () => {
      let reason = "";
      try { reason = JSON.parse(body).reason || ""; } catch {}
      resolve({ token: entry.token, environment: entry.environment,
        registered_at: entry.registered_at,
        status: status === 200 ? "sent" : ["Unregistered", "BadDeviceToken", "DeviceTokenNotForTopic"].includes(reason)
          ? "expired" : "failed", reason });
    });
    request.end(JSON.stringify({ aps: { alert: { title: payload.title, body: "Open Gala to view the latest build." },
      sound: "default" }, project: payload.project }));
  });
}

async function main() {
  const [root, rawPayload] = process.argv.slice(2);
  if (!root || !rawPayload) throw new Error("Usage: apns.js <Gala root> <JSON payload>");
  const entries = JSON.parse(fs.readFileSync(path.join(root, "apns-subscriptions.json"), "utf8"));
  const payload = JSON.parse(rawPayload);
  const cert = fs.readFileSync(path.join(root, "apns", "apns-cert.pem"));
  const key = fs.readFileSync(path.join(root, "apns", "apns-key.pem"));
  const results = [];
  for (const environment of ["development", "production"]) {
    const group = entries.filter((entry) => entry.environment === environment);
    if (!group.length) continue;
    const host = environment === "development" ? "api.sandbox.push.apple.com" : "api.push.apple.com";
    const client = http2.connect(`https://${host}`, { cert, key });
    client.on("error", () => {});
    client.setTimeout(12000, () => client.destroy());
    try { results.push(...await Promise.all(group.map((entry) => sendDevice(client, entry, payload)))); }
    finally { client.destroy(); }
  }
  process.stdout.write(JSON.stringify({ registered: entries.length,
    sent: results.filter((r) => r.status === "sent").length,
    failed: results.filter((r) => r.status !== "sent").length, results }) + "\n");
}

module.exports = { sendDevice };
if (require.main === module) {
  main().catch(() => { process.stderr.write("APNs sender failed; check certificates and subscriptions.\n"); process.exitCode = 1; });
}
