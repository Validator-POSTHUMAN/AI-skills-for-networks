import { createMcpExpressApp } from "@modelcontextprotocol/express";
import { createMcpHandler } from "@modelcontextprotocol/server";
import type { Request as ExpressRequest, Response as ExpressResponse } from "express";
import { createSkillCatalogServer } from "./server.js";

function csv(value: string | undefined): string[] {
  return [...new Set((value ?? "").split(",").map((item) => item.trim().toLowerCase()).filter(Boolean))];
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

export function createHttpApp() {
  const host = process.env.MCP_HOST ?? "127.0.0.1";
  const configuredHosts = csv(process.env.MCP_ALLOWED_HOSTS);
  const allowedHosts = configuredHosts.length > 0
    ? configuredHosts
    : ["127.0.0.1", "localhost", "::1"];

  if (!["127.0.0.1", "localhost", "::1"].includes(host) && configuredHosts.length === 0) {
    throw new Error("MCP_ALLOWED_HOSTS is required for a non-loopback HTTP bind");
  }

  const app = createMcpExpressApp({
    host,
    allowedHosts,
    allowedOrigins: originHostnames(process.env.MCP_ALLOWED_ORIGINS),
    jsonLimit: "1mb",
  });
  const handler = createMcpHandler(createSkillCatalogServer, {
    onerror: (error) => process.stderr.write(`MCP request failed: ${error.message}\n`),
  });

  app.disable("x-powered-by");
  app.get("/healthz", (_request, response) => response.json({ status: "ok", mode: "read-only" }));
  app.all("/mcp", (request, response) => void forwardToMcpHandler(handler, request, response));
  return app;
}

if (process.argv[1] && import.meta.url === new URL(`file://${process.argv[1]}`).href) {
  const host = process.env.MCP_HOST ?? "127.0.0.1";
  const port = Number(process.env.MCP_PORT ?? "3000");
  createHttpApp().listen(port, host, () => {
    process.stderr.write(`Validator skills MCP listening on ${host}:${port}\n`);
  });
}
