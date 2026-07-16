import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { createSkillCatalogServer } from "./server.js";

const server = await createSkillCatalogServer();
await server.connect(new StdioServerTransport());

process.on("SIGINT", async () => {
  await server.close();
  process.exit(0);
});
