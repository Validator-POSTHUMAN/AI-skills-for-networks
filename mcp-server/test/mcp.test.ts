import assert from "node:assert/strict";
import { test } from "node:test";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import { fileURLToPath } from "node:url";

test("stdio MCP lists and reads public skills", async () => {
  const entry = fileURLToPath(new URL("../src/stdio.js", import.meta.url));
  const transport = new StdioClientTransport({ command: process.execPath, args: [entry] });
  const client = new Client({ name: "catalog-test", version: "1.0.0" });
  try {
    await client.connect(transport);
    const tools = await client.listTools();
    assert.deepEqual(tools.tools.map((tool) => tool.name).sort(), ["get_skill", "list_skills", "search_skills"]);
    const result = await client.callTool({ name: "get_skill", arguments: { id: "validator-upgrade" } });
    assert.equal(result.isError, undefined);
    assert.match(JSON.stringify(result.content), /Validator upgrade/i);
  } finally {
    await client.close();
  }
});
