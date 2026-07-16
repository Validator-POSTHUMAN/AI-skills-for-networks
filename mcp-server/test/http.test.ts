import assert from "node:assert/strict";
import { test } from "node:test";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StreamableHTTPClientTransport } from "@modelcontextprotocol/sdk/client/streamableHttp.js";
import { request } from "node:http";
import type { AddressInfo } from "node:net";
import { createHttpApp } from "../src/http.js";

test("stateless HTTP MCP is healthy and exposes the public catalog", async () => {
  const listener = createHttpApp().listen(0, "127.0.0.1");
  await new Promise<void>((resolve, reject) => {
    listener.once("listening", resolve);
    listener.once("error", reject);
  });
  const port = (listener.address() as AddressInfo).port;
  const client = new Client({ name: "http-catalog-test", version: "1.0.0" });
  try {
    const health = await fetch(`http://127.0.0.1:${port}/healthz`);
    assert.equal(health.status, 200);
    assert.deepEqual(await health.json(), { status: "ok", mode: "read-only" });

    await client.connect(new StreamableHTTPClientTransport(new URL(`http://127.0.0.1:${port}/mcp`)));
    const result = await client.callTool({ name: "list_skills", arguments: { category: "operations" } });
    assert.equal(result.isError, undefined);
    assert.match(JSON.stringify(result.content), /validator-upgrade/);
  } finally {
    await client.close();
    await new Promise<void>((resolve, reject) => listener.close((error) => error ? reject(error) : resolve()));
  }
});

test("HTTP rejects an unlisted Host header", async () => {
  const listener = createHttpApp().listen(0, "127.0.0.1");
  await new Promise<void>((resolve) => listener.once("listening", resolve));
  const port = (listener.address() as AddressInfo).port;
  try {
    const status = await new Promise<number | undefined>((resolve, reject) => {
      const probe = request({
        host: "127.0.0.1",
        port,
        path: "/healthz",
        headers: { Host: "untrusted.example" },
      }, (response) => {
        response.resume();
        response.on("end", () => resolve(response.statusCode));
      });
      probe.on("error", reject);
      probe.end();
    });
    assert.equal(status, 421);
  } finally {
    await new Promise<void>((resolve, reject) => listener.close((error) => error ? reject(error) : resolve()));
  }
});
