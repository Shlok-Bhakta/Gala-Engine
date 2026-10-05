const test = require("node:test");
const assert = require("node:assert/strict");
const http2 = require("node:http2");
const { sendDevice } = require("./apns.js");

for (const [code, reason, expected] of [[200, "", "sent"], [410, "Unregistered", "expired"],
  [400, "BadDeviceToken", "expired"], [403, "BadCertificate", "failed"]]) {
  test(`APNs ${code} ${reason} produces ${expected}`, async () => {
    const server = http2.createServer();
    server.on("stream", (stream, headers) => {
      assert.equal(headers[":path"], "/3/device/aabb");
      assert.equal(headers["apns-topic"], "com.galaengine.app");
      assert.equal(headers["apns-push-type"], "alert");
      assert.equal(headers["apns-collapse-id"].length, 64);
      let body = "";
      stream.setEncoding("utf8");
      stream.on("data", (chunk) => { body += chunk; });
      stream.on("end", () => {
        const payload = JSON.parse(body);
        assert.equal(payload.aps.alert.title, "Yala update ready");
        assert.equal(payload.project, "yala");
        stream.respond({ ":status": code });
        stream.end(reason ? JSON.stringify({ reason }) : "");
      });
    });
    await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
    const client = http2.connect(`http://127.0.0.1:${server.address().port}`);
    try {
      const result = await sendDevice(client, { token: "aabb", environment: "development", registered_at: 1 },
        { title: "Yala update ready", project: "yala" });
      assert.equal(result.status, expected);
      assert.equal(result.reason, reason);
      assert.equal(result.registered_at, 1);
    } finally {
      client.destroy();
      await new Promise((resolve) => server.close(resolve));
    }
  });
}
