import assert from "node:assert/strict";
import { test } from "node:test";
import { Client } from "@modelcontextprotocol/client";
import { StreamableHTTPClientTransport } from "@modelcontextprotocol/client";
import { request } from "node:http";
import type { AddressInfo } from "node:net";
import { createHttpApp } from "../src/http.js";

const MODERN = "2026-07-28";
const META = {
  "io.modelcontextprotocol/protocolVersion": MODERN,
  "io.modelcontextprotocol/clientInfo": { name: "raw-test", version: "1.0.0" },
  "io.modelcontextprotocol/clientCapabilities": {},
};

async function listen() {
  const listener = createHttpApp().listen(0, "127.0.0.1");
  await new Promise<void>((resolve, reject) => {
    listener.once("listening", resolve);
    listener.once("error", reject);
  });
  return listener;
}

async function close(listener: ReturnType<ReturnType<typeof createHttpApp>["listen"]>) {
  await new Promise<void>((resolve, reject) => listener.close((error) => error ? reject(error) : resolve()));
}

function modernHeaders(method: string, name?: string): Record<string, string> {
  return {
    "content-type": "application/json",
    "mcp-protocol-version": MODERN,
    "mcp-method": method,
    ...(name ? { "mcp-name": name } : {}),
  };
}

test("stateless HTTP negotiates MCP 2026-07-28 and exposes the public catalog", async () => {
  const listener = await listen();
  const port = (listener.address() as AddressInfo).port;
  const transport = new StreamableHTTPClientTransport(new URL(`http://127.0.0.1:${port}/mcp`));
  const client = new Client(
    { name: "http-catalog-test", version: "1.0.0" },
    { versionNegotiation: { mode: "auto" } },
  );
  try {
    const health = await fetch(`http://127.0.0.1:${port}/healthz`);
    assert.equal(health.status, 200);
    assert.deepEqual(await health.json(), { status: "ok", mode: "read-only" });

    await client.connect(transport);
    assert.equal(client.getProtocolEra(), "modern");
    assert.equal(client.getNegotiatedProtocolVersion(), MODERN);
    assert.equal(transport.sessionId, undefined);

    const discovery = await client.discover();
    assert.ok(discovery.supportedVersions.includes(MODERN));
    assert.equal(discovery.cacheScope, "public");
    assert.deepEqual(Object.keys(discovery.capabilities).sort(), ["resources", "tools"]);

    const tools = await client.listTools();
    assert.equal(tools.cacheScope, "public");
    assert.equal(tools.ttlMs, 60_000);

    const result = await client.callTool({ name: "list_skills", arguments: { category: "operations" } });
    assert.equal(result.isError, undefined);
    assert.match(JSON.stringify(result.content), /validator-upgrade/);
  } finally {
    await client.close();
    await close(listener);
  }
});

test("legacy MCP clients remain compatible without sessions", async () => {
  const listener = await listen();
  const port = (listener.address() as AddressInfo).port;
  const transport = new StreamableHTTPClientTransport(new URL(`http://127.0.0.1:${port}/mcp`));
  const client = new Client({ name: "legacy-http-test", version: "1.0.0" });
  try {
    await client.connect(transport);
    assert.equal(client.getProtocolEra(), "legacy");
    assert.equal(transport.sessionId, undefined);
    const tools = await client.listTools();
    assert.deepEqual(tools.tools.map((tool) => tool.name).sort(), ["get_skill", "list_skills", "search_skills"]);
  } finally {
    await client.close();
    await close(listener);
  }
});

test("modern routing headers are enforced and HTTP stays sessionless", async () => {
  const listener = await listen();
  const port = (listener.address() as AddressInfo).port;
  const endpoint = `http://127.0.0.1:${port}/mcp`;
  const body = JSON.stringify({ jsonrpc: "2.0", id: 1, method: "tools/list", params: { _meta: META } });
  try {
    const accepted = await fetch(endpoint, { method: "POST", headers: modernHeaders("tools/list"), body });
    assert.equal(accepted.status, 200);
    assert.equal(accepted.headers.get("mcp-session-id"), null);
    const acceptedJson = await accepted.json() as { result?: { tools?: unknown[]; ttlMs?: number; cacheScope?: string } };
    assert.ok((acceptedJson.result?.tools?.length ?? 0) >= 3);
    assert.equal(acceptedJson.result?.ttlMs, 60_000);
    assert.equal(acceptedJson.result?.cacheScope, "public");

    const missingMethod = await fetch(endpoint, {
      method: "POST",
      headers: { "content-type": "application/json", "mcp-protocol-version": MODERN },
      body,
    });
    assert.equal(missingMethod.status, 400);

    const mismatchedMethod = await fetch(endpoint, {
      method: "POST",
      headers: modernHeaders("resources/list"),
      body,
    });
    assert.equal(mismatchedMethod.status, 400);

    const callBody = JSON.stringify({
      jsonrpc: "2.0",
      id: 2,
      method: "tools/call",
      params: { name: "list_skills", arguments: {}, _meta: META },
    });
    const missingName = await fetch(endpoint, {
      method: "POST",
      headers: modernHeaders("tools/call"),
      body: callBody,
    });
    assert.equal(missingName.status, 400);
  } finally {
    await close(listener);
  }
});

test("server/discover works without initialize", async () => {
  const listener = await listen();
  const port = (listener.address() as AddressInfo).port;
  try {
    const response = await fetch(`http://127.0.0.1:${port}/mcp`, {
      method: "POST",
      headers: modernHeaders("server/discover"),
      body: JSON.stringify({ jsonrpc: "2.0", id: "probe", method: "server/discover", params: { _meta: META } }),
    });
    assert.equal(response.status, 200);
    const payload = await response.json() as { result?: { supportedVersions?: string[]; ttlMs?: number; cacheScope?: string } };
    assert.ok(payload.result?.supportedVersions?.includes(MODERN));
    assert.equal(payload.result?.ttlMs, 60_000);
    assert.equal(payload.result?.cacheScope, "public");
  } finally {
    await close(listener);
  }
});

test("HTTP rejects unlisted Host and Origin headers", async () => {
  const listener = await listen();
  const port = (listener.address() as AddressInfo).port;
  try {
    const hostStatus = await new Promise<number | undefined>((resolve, reject) => {
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
    assert.equal(hostStatus, 403);

    const origin = await fetch(`http://127.0.0.1:${port}/healthz`, {
      headers: { Origin: "https://untrusted.example" },
    });
    assert.equal(origin.status, 403);
  } finally {
    await close(listener);
  }
});
