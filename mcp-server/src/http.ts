import express, { type Request } from "express";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import { createSkillCatalogServer } from "./server.js";

function csv(value: string | undefined): Set<string> {
  return new Set((value ?? "").split(",").map((item) => item.trim().toLowerCase()).filter(Boolean));
}

function requestHost(request: Request): string {
  return (request.headers.host ?? "").toLowerCase();
}

export function createHttpApp() {
  const app = express();
  const host = process.env.MCP_HOST ?? "127.0.0.1";
  const configuredHosts = csv(process.env.MCP_ALLOWED_HOSTS);
  const allowedHosts = configuredHosts.size > 0
    ? configuredHosts
    : new Set(["127.0.0.1", "localhost", "[::1]"]);
  const allowedOrigins = csv(process.env.MCP_ALLOWED_ORIGINS);

  if (!["127.0.0.1", "localhost", "::1"].includes(host) && configuredHosts.size === 0) {
    throw new Error("MCP_ALLOWED_HOSTS is required for a non-loopback HTTP bind");
  }

  app.disable("x-powered-by");
  app.use(express.json({ limit: "1mb" }));
  app.use((request, response, next) => {
    const hostname = requestHost(request).replace(/:\d+$/, "");
    if (!allowedHosts.has(hostname) && !allowedHosts.has(requestHost(request))) {
      response.status(421).json({ error: "Host is not allowed" });
      return;
    }
    const origin = request.headers.origin?.toLowerCase();
    if (origin && !allowedOrigins.has(origin)) {
      response.status(403).json({ error: "Origin is not allowed" });
      return;
    }
    next();
  });

  app.get("/healthz", (_request, response) => response.json({ status: "ok", mode: "read-only" }));
  app.post("/mcp", async (request, response) => {
    const server = await createSkillCatalogServer();
    const transport = new StreamableHTTPServerTransport({ sessionIdGenerator: undefined });
    response.on("close", () => void server.close());
    try {
      await server.connect(transport);
      await transport.handleRequest(request, response, request.body);
    } catch (error) {
      if (!response.headersSent) response.status(500).json({ error: "MCP request failed" });
      process.stderr.write(`MCP request failed: ${error instanceof Error ? error.message : "unknown error"}\n`);
    }
  });
  app.all("/mcp", (_request, response) => response.status(405).json({ error: "Use POST for stateless MCP" }));
  return app;
}

if (process.argv[1] && import.meta.url === new URL(`file://${process.argv[1]}`).href) {
  const host = process.env.MCP_HOST ?? "127.0.0.1";
  const port = Number(process.env.MCP_PORT ?? "3000");
  createHttpApp().listen(port, host, () => {
    process.stderr.write(`Validator skills MCP listening on ${host}:${port}\n`);
  });
}
