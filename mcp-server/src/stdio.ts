import { serveStdio } from "@modelcontextprotocol/server/stdio";
import { catalogMode, createSkillCatalogServer } from "./server.js";

const mode = catalogMode();
const handle = serveStdio(() => createSkillCatalogServer({ mode }), {
  onerror: (error) => process.stderr.write(`MCP stdio error: ${error.message}\n`),
});

process.on("SIGINT", () => void handle.close().then(() => {
  process.exitCode = 0;
}));
