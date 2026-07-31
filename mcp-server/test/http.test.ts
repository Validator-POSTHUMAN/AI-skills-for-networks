import assert from "node:assert/strict";
import { test } from "node:test";
import { Client, StreamableHTTPClientTransport } from "@modelcontextprotocol/client";
import { request } from "node:http";
import type { AddressInfo } from "node:net";
import { createHttpApp, type AuditRecord } from "../src/http.js";

const MODERN = "2026-07-28";
const META = {
  "io.modelcontextprotocol/protocolVersion": MODERN,
  "io.modelcontextprotocol/clientInfo": { name: "raw-test", version: "1.0.0" },
  "io.modelcontextprotocol/clientCapabilities": {},
};

async function listen(options?: Parameters<typeof createHttpApp>[0]) {
  const listener = createHttpApp(options).listen(0, "127.0.0.1");
  await new Promise<void>((resolve, reject) => {
    listener.once("listening", resolve);
    listener.once("error", reject);
  });
  return listener;
}

async function close(listener: ReturnType<ReturnType<typeof createHttpApp>["listen"]>) {
  await new Promise<void>((resolve, reject) => listener.close((error) => error ? reject(error) : resolve()));
}

function modernHeaders(method: string, name?: string, token?: string): Record<string, string> {
  return {
    "content-type": "application/json",
    "mcp-protocol-version": MODERN,
    "mcp-method": method,
    ...(name ? { "mcp-name": name } : {}),
    ...(token ? { authorization: `Bearer ${token}` } : {}),
  };
}

function modernBody(method: string, params: Record<string, unknown> = {}, id: number | string = 1): string {
  return JSON.stringify({ jsonrpc: "2.0", id, method, params: { ...params, _meta: META } });
}

test("stateless HTTP negotiates MCP 2026-07-28 and exposes metadata only", async () => {
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
    assert.deepEqual(await health.json(), {
      status: "ok",
      mode: "metadata",
      authentication: "loopback-optional",
    });

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
    assert.deepEqual(tools.tools.map((tool) => tool.name).sort(), [
      "get_capability_metadata",
      "list_capabilities",
      "search_capabilities",
    ]);

    const result = await client.callTool({ name: "list_capabilities", arguments: { category: "operations" } });
    const output = JSON.stringify(result.content);
    assert.equal(result.isError, undefined);
    assert.match(output, /validator-upgrade/);
    assert.doesNotMatch(output, /"path"|Preconditions|Rollback/);

    const resource = await client.readResource({ uri: "skills://registry" });
    const firstContent = resource.contents[0];
    assert.ok(firstContent && "text" in firstContent);
    assert.match(firstContent.text, /contentSha256/);
    assert.doesNotMatch(firstContent.text, /"path"|Preconditions|Rollback/);
    assert.equal(resource.cacheScope, "public");
    assert.equal(resource.ttlMs, 300_000);
  } finally {
    await client.close();
    await close(listener);
  }
});

test("legacy MCP clients remain metadata-only and sessionless", async () => {
  const listener = await listen();
  const port = (listener.address() as AddressInfo).port;
  const transport = new StreamableHTTPClientTransport(new URL(`http://127.0.0.1:${port}/mcp`));
  const client = new Client({ name: "legacy-http-test", version: "1.0.0" });
  try {
    await client.connect(transport);
    assert.equal(client.getProtocolEra(), "legacy");
    assert.equal(transport.sessionId, undefined);
    const tools = await client.listTools();
    assert.deepEqual(tools.tools.map((tool) => tool.name).sort(), [
      "get_capability_metadata",
      "list_capabilities",
      "search_capabilities",
    ]);
  } finally {
    await client.close();
    await close(listener);
  }
});

test("modern routing headers are enforced and HTTP stays sessionless", async () => {
  const listener = await listen();
  const port = (listener.address() as AddressInfo).port;
  const endpoint = `http://127.0.0.1:${port}/mcp`;
  const body = modernBody("tools/list");
  try {
    const accepted = await fetch(endpoint, { method: "POST", headers: modernHeaders("tools/list"), body });
    assert.equal(accepted.status, 200);
    assert.equal(accepted.headers.get("mcp-session-id"), null);
    const acceptedJson = await accepted.json() as { result?: { tools?: unknown[]; ttlMs?: number; cacheScope?: string } };
    assert.equal(acceptedJson.result?.tools?.length, 3);
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

    const callBody = modernBody("tools/call", { name: "list_capabilities", arguments: {} }, 2);
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
      body: modernBody("server/discover", {}, "probe"),
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

test("HTTP authentication, quota, and audit records fail closed without secret echo", async () => {
  const records: AuditRecord[] = [];
  const secret = "fixture-api-key-with-enough-entropy";
  const listener = await listen({
    requireAuth: true,
    apiKeys: new Set([secret]),
    rateLimitPerMinute: 1,
    ipRateLimitPerMinute: 10,
    auditSink: (record) => records.push(record),
  });
  const port = (listener.address() as AddressInfo).port;
  const endpoint = `http://127.0.0.1:${port}/mcp`;
  const body = modernBody("tools/list");
  try {
    const unauthorized = await fetch(endpoint, {
      method: "POST",
      headers: modernHeaders("tools/list"),
      body,
    });
    assert.equal(unauthorized.status, 401);

    const accepted = await fetch(endpoint, {
      method: "POST",
      headers: modernHeaders("tools/list", undefined, secret),
      body,
    });
    assert.equal(accepted.status, 200);

    const limited = await fetch(endpoint, {
      method: "POST",
      headers: modernHeaders("tools/list", undefined, secret),
      body,
    });
    assert.equal(limited.status, 429);
    assert.equal(limited.headers.get("retry-after"), "60");

    assert.equal(records.length, 3);
    assert.deepEqual(records.map((record) => record.status), [401, 200, 429]);
    assert.notEqual(records[1]?.clientKeyId, "anonymous");
    const serialized = JSON.stringify(records);
    assert.doesNotMatch(serialized, new RegExp(secret));
    assert.doesNotMatch(serialized, /arguments|params|authorization|cookie|127\.0\.0\.1/);
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

test("HTTP rejects source mode and invalid limits", () => {
  assert.throws(() => createHttpApp({ mode: "source" }), /trusted local stdio/);
  assert.throws(() => createHttpApp({ rateLimitPerMinute: 0 }), /integer between 1 and 10000/);
  assert.throws(() => createHttpApp({ ipRateLimitPerMinute: 0 }), /integer between 1 and 10000/);
  assert.throws(
    () => createHttpApp({ requireAuth: true, apiKeys: new Set(["short-key"]) }),
    /at least 32 characters/,
  );
});

test("non-loopback configuration fails closed on Host and authentication", () => {
  assert.throws(
    () => createHttpApp({ host: "0.0.0.0" }),
    /MCP_ALLOWED_HOSTS is required/,
  );
  assert.throws(
    () => createHttpApp({ host: "0.0.0.0", allowedHosts: ["skills.example.org"], requireAuth: false }),
    /authentication cannot be disabled/,
  );
  assert.throws(
    () => createHttpApp({ host: "0.0.0.0", allowedHosts: ["skills.example.org"], requireAuth: true }),
    /MCP_BEARER_KEYS is required/,
  );
});

test("unauthenticated attempts are IP rate-limited before token verification", async () => {
  const listener = await listen({
    requireAuth: true,
    apiKeys: new Set(["unused-fixture-key-with-enough-entropy"]),
    ipRateLimitPerMinute: 1,
  });
  const port = (listener.address() as AddressInfo).port;
  const endpoint = `http://127.0.0.1:${port}/mcp`;
  const requestOptions = {
    method: "POST",
    headers: modernHeaders("tools/list"),
    body: modernBody("tools/list"),
  };
  try {
    assert.equal((await fetch(endpoint, requestOptions)).status, 401);
    assert.equal((await fetch(endpoint, requestOptions)).status, 429);
  } finally {
    await close(listener);
  }
});
