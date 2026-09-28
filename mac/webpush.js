#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const webpush = require("web-push");

async function main() {
  const [action, root, rawPayload] = process.argv.slice(2);
  if (!root || !["init", "send"].includes(action)) {
    throw new Error("Usage: webpush.js init|send <Gala root> [JSON payload]");
  }
  const keyPath = path.join(root, "vapid.json");
  if (!fs.existsSync(keyPath)) {
    const keys = webpush.generateVAPIDKeys();
    fs.writeFileSync(keyPath, JSON.stringify(keys) + "\n", { mode: 0o600, flag: "wx" });
  }
  const keys = JSON.parse(fs.readFileSync(keyPath, "utf8"));
  if (action === "init") {
    process.stdout.write(JSON.stringify({ publicKey: keys.publicKey }) + "\n");
    return;
  }
  webpush.setVapidDetails("mailto:gala@localhost", keys.publicKey, keys.privateKey);
  const listPath = path.join(root, "subscriptions.json");
  const entries = fs.existsSync(listPath) ? JSON.parse(fs.readFileSync(listPath, "utf8")) : [];
  const payload = JSON.stringify(JSON.parse(rawPayload));
  const results = await Promise.allSettled(entries.map(async (entry) => {
    try {
      await webpush.sendNotification(entry.subscription, payload, { TTL: 3600 });
      return { endpoint: entry.subscription.endpoint, status: "sent" };
    } catch (error) {
      return {
        endpoint: entry.subscription.endpoint,
        status: [404, 410].includes(error.statusCode) ? "expired" : "failed",
        error: String(error.message),
      };
    }
  }));
  const values = results.map((item) => item.value);
  process.stdout.write(JSON.stringify({ sent: values.filter((item) => item.status === "sent").length,
    failed: values.filter((item) => item.status === "failed").length,
    registered: entries.length, results: values }) + "\n");
}

main().catch((error) => { process.stderr.write(String(error) + "\n"); process.exitCode = 1; });
