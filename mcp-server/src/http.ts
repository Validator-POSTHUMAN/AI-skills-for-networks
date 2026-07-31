import { createHash, timingSafeEqual } from "node:crypto";
import { performance } from "node:perf_hooks";
import { createMcpExpressApp } from "@modelcontextprotocol/express";
import { createMcpHandler } from "@modelcontextprotocol/server";
import type { Request as ExpressRequest, Response as ExpressResponse } from "express";
import { catalogMode, createSkillCatalogServer, type CatalogMode } from "./server.js";

const LOOPBACK_HOSTS = ["127.0.0.1", "localhost", "::1"];
const MAX_RATE_LIMIT_KEYS = 10_000;

export interface AuditRecord {
  timestamp: string;
  event: "mcp_request";
  mode: "metadata";
  clientKeyId: string;
  method: string;
  name?: string;
  status: number;
  durationMs: number;
}

interface HttpOptions {
  host?: string;
  allowedHosts?: string[];
  mode?: CatalogMode;
  requireAuth?: boolean;
  apiKeys?: Set<string>;
  rateLimitPerMinute?: number;
  ipRateLimitPerMinute?: number;
  auditSink?: (record: AuditRecord) => void;
}

type WindowResult = "allowed" | "limited" | "capacity";

function csv(value: string | undefined): string[] {
  return [...new Set((value ?? "").split(",").map((item) => item.trim().toLowerCase()).filter(Boolean))];
}

function secretValues(value: string | undefined): string[] {
  return [...new Set((value ?? "").split(",").map((item) => item.trim()).filter(Boolean))];
}

function originHostnames(value: string | undefined): string[] {
  return csv(value).map((item) => {
    try {
      return new URL(item).hostname.toLowerCase();
    } catch {
      return item;
    }
  });
}

function booleanSetting(value: string | undefined, fallback: boolean): boolean {
  if (value === undefined || value === "") return fallback;
  if (["1", "true", "yes"].includes(value.toLowerCase())) return true;
  if (["0", "false", "no"].includes(value.toLowerCase())) return false;
  throw new Error("MCP_REQUIRE_AUTH must be true or false");
}

function digest(value: string): Buffer {
  return createHash("sha256").update(value).digest();
}

function keyId(value: string): string {
  return digest(value).toString("hex").slice(0, 16);
}

function matchedKey(candidate: string, expected: string[]): string | undefined {
  if (!candidate) return undefined;
  const candidateDigest = digest(candidate);
  for (const value of expected) {
    if (timingSafeEqual(candidateDigest, digest(value))) return keyId(value);
  }
  return undefined;
}

function bearerToken(request: ExpressRequest): string {
  const value = request.headers.authorization ?? "";
  return value.startsWith("Bearer ") ? value.slice(7) : "";
}

function boundedWireName(value: unknown): string | undefined {
  return typeof value === "string" && /^[a-z0-9_/-]{1,80}$/.test(value) ? value : undefined;
}

function auditFields(request: ExpressRequest): { method: string; name?: string } {
  const body = request.body as { method?: unknown; params?: { name?: unknown } } | undefined;
  const method = boundedWireName(body?.method) ?? "unknown";
  const name = boundedWireName(body?.params?.name);
  return { method, ...(name ? { name } : {}) };
}

function validRate(value: number, setting: string): number {
  if (!Number.isInteger(value) || value < 1 || value > 10_000) {
    throw new Error(`${setting} must be an integer between 1 and 10000`);
  }
  return value;
}

function takeWindow(
  windows: Map<string, { start: number; count: number }>,
  subject: string,
  limit: number,
  now: number,
): WindowResult {
  let window = windows.get(subject);
  if (window && now - window.start >= 60_000) {
    windows.delete(subject);
    window = undefined;
  }
  if (!window) {
    if (windows.size >= MAX_RATE_LIMIT_KEYS) {
      for (const [key, candidate] of windows) {
        if (now - candidate.start >= 60_000) windows.delete(key);
      }
    }
    if (windows.size >= MAX_RATE_LIMIT_KEYS) return "capacity";
    window = { start: now, count: 0 };
    windows.set(subject, window);
  }
  window.count += 1;
  return window.count > limit ? "limited" : "allowed";
}

function rejectWindow(response: ExpressResponse, result: WindowResult): boolean {
  if (result === "allowed") return false;
  if (result === "limited") {
    response.setHeader("Retry-After", "60");
    response.status(429).json({ error: "Rate limit exceeded" });
  } else {
    response.status(503).json({ error: "Rate limiter capacity reached" });
  }
  return true;
}

async function forwardToMcpHandler(
  handler: ReturnType<typeof createMcpHandler>,
  request: ExpressRequest,
  response: ExpressResponse,
): Promise<void> {
  const headers = new Headers();
  for (const [name, value] of Object.entries(request.headers)) {
    if (typeof value === "string") headers.set(name, value);
    else if (Array.isArray(value)) headers.set(name, value.join(", "));
  }
  headers.delete("authorization");
  headers.delete("cookie");
  const hasBody = !["GET", "HEAD"].includes(request.method) && request.body !== undefined;
  const webRequest = new Request(`${request.protocol}://${request.get("host")}${request.originalUrl}`, {
    method: request.method,
    headers,
    ...(hasBody ? { body: JSON.stringify(request.body) } : {}),
  });
  const result = await handler.fetch(webRequest, { parsedBody: request.body });
  response.status(result.status);
  result.headers.forEach((value, name) => response.setHeader(name, value));
  response.end(Buffer.from(await result.arrayBuffer()));
}

export function createHttpApp(options: HttpOptions = {}) {
  const host = options.host ?? process.env.MCP_HOST ?? "127.0.0.1";
  const mode = options.mode ?? catalogMode();
  const configuredHosts = options.allowedHosts ?? csv(process.env.MCP_ALLOWED_HOSTS);
  const allowedHosts = configuredHosts.length > 0 ? configuredHosts : LOOPBACK_HOSTS;
  const requireAuth = options.requireAuth
    ?? booleanSetting(process.env.MCP_REQUIRE_AUTH, !LOOPBACK_HOSTS.includes(host));
  const apiKeys = [...(options.apiKeys ?? new Set(secretValues(process.env.MCP_BEARER_KEYS)))];
  const rateLimitPerMinute = options.rateLimitPerMinute
    ?? Number(process.env.MCP_RATE_LIMIT_PER_MINUTE ?? "60");
  const ipRateLimitPerMinute = options.ipRateLimitPerMinute
    ?? Number(process.env.MCP_IP_RATE_LIMIT_PER_MINUTE ?? "30");
  const auditSink = options.auditSink
    ?? ((record: AuditRecord) => process.stderr.write(`${JSON.stringify(record)}\n`));
  const keyWindows = new Map<string, { start: number; count: number }>();
  const ipWindows = new Map<string, { start: number; count: number }>();

  if (mode === "source") {
    throw new Error("Source mode is restricted to trusted local stdio transport");
  }
  if (!LOOPBACK_HOSTS.includes(host) && configuredHosts.length === 0) {
    throw new Error("MCP_ALLOWED_HOSTS is required for a non-loopback HTTP bind");
  }
  if (!LOOPBACK_HOSTS.includes(host) && !requireAuth) {
    throw new Error("HTTP authentication cannot be disabled for a non-loopback bind");
  }
  if (requireAuth && apiKeys.length === 0) {
    throw new Error("MCP_BEARER_KEYS is required when HTTP authentication is enabled");
  }
  if (apiKeys.some((value) => value.length < 32)) {
    throw new Error("MCP_BEARER_KEYS entries must contain at least 32 characters");
  }
  validRate(rateLimitPerMinute, "MCP_RATE_LIMIT_PER_MINUTE");
  validRate(ipRateLimitPerMinute, "MCP_IP_RATE_LIMIT_PER_MINUTE");

  const app = createMcpExpressApp({
    host,
    allowedHosts,
    allowedOrigins: originHostnames(process.env.MCP_ALLOWED_ORIGINS),
    jsonLimit: "256kb",
  });
  const handler = createMcpHandler(() => createSkillCatalogServer({ mode: "metadata" }), {
    onerror: (error) => process.stderr.write(`MCP request failed: ${error.message}\n`),
  });

  app.disable("x-powered-by");
  if (LOOPBACK_HOSTS.includes(host)) app.set("trust proxy", "loopback");
  app.get("/healthz", (_request, response) => response.json({
    status: "ok",
    mode: "metadata",
    authentication: requireAuth ? "required" : "loopback-optional",
  }));

  app.use("/mcp", (request, response, next) => {
    const started = performance.now();
    response.on("finish", () => {
      const fields = auditFields(request);
      try {
        auditSink({
          timestamp: new Date().toISOString(),
          event: "mcp_request",
          mode: "metadata",
          clientKeyId: response.locals.mcpClientKeyId ?? "anonymous",
          ...fields,
          status: response.statusCode,
          durationMs: Math.max(0, Math.round(performance.now() - started)),
        });
      } catch {
        process.stderr.write("MCP audit sink failed\n");
      }
    });
    next();
  });

  app.use("/mcp", (request, response, next) => {
    const subject = `ip:${keyId(request.ip ?? request.socket.remoteAddress ?? "unknown")}`;
    if (rejectWindow(response, takeWindow(ipWindows, subject, ipRateLimitPerMinute, Date.now()))) return;
    next();
  });

  app.use("/mcp", (request, response, next) => {
    if (!requireAuth) {
      response.locals.mcpClientKeyId = "loopback";
      next();
      return;
    }
    const id = matchedKey(bearerToken(request), apiKeys);
    if (!id) {
      response.status(401).json({ error: "Authentication required" });
      return;
    }
    response.locals.mcpClientKeyId = id;
    next();
  });

  app.use("/mcp", (request, response, next) => {
    if (response.locals.mcpClientKeyId !== "loopback") {
      const subject = `key:${response.locals.mcpClientKeyId}`;
      if (rejectWindow(response, takeWindow(keyWindows, subject, rateLimitPerMinute, Date.now()))) return;
    }
    next();
  });

  app.all("/mcp", async (request, response) => {
    try {
      await forwardToMcpHandler(handler, request, response);
    } catch (error) {
      if (!response.headersSent) response.status(500).json({ error: "MCP request failed" });
      process.stderr.write(`MCP adapter failed: ${error instanceof Error ? error.message : "unknown error"}\n`);
    }
  });
  return app;
}

if (process.argv[1] && import.meta.url === new URL(`file://${process.argv[1]}`).href) {
  const host = process.env.MCP_HOST ?? "127.0.0.1";
  const port = Number(process.env.MCP_PORT ?? "3000");
  createHttpApp().listen(port, host, () => {
    process.stderr.write(`POSTHUMAN capability MCP listening on ${host}:${port}\n`);
  });
}
