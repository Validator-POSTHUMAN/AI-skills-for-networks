import { serveStdio } from "@modelcontextprotocol/server/stdio";
import { createSkillCatalogServer } from "./server.js";

const handle = serveStdio(createSkillCatalogServer, {
  onerror: (error) => process.stderr.write(`MCP stdio error: ${error.message}\n`),
});

process.on("SIGINT", () => void handle.close().then(() => {
  process.exitCode = 0;
}));
