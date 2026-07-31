import assert from "node:assert/strict";
import { test } from "node:test";
import { Client } from "@modelcontextprotocol/client";
import { StdioClientTransport } from "@modelcontextprotocol/client/stdio";
import { fileURLToPath } from "node:url";

test("stdio negotiates MCP 2026-07-28 and serves the public catalog", async () => {
  const entry = fileURLToPath(new URL("../src/stdio.js", import.meta.url));
  const transport = new StdioClientTransport({ command: process.execPath, args: [entry] });
  const client = new Client(
    { name: "catalog-test", version: "1.0.0" },
    { versionNegotiation: { mode: "auto" } },
  );
  try {
    await client.connect(transport);
    assert.equal(client.getProtocolEra(), "modern");
    assert.equal(client.getNegotiatedProtocolVersion(), "2026-07-28");

    const discovery = await client.discover();
    assert.ok(discovery.supportedVersions.includes("2026-07-28"));

    const tools = await client.listTools();
    assert.deepEqual(tools.tools.map((tool) => tool.name).sort(), ["get_skill", "list_skills", "search_skills"]);
    assert.equal(tools.cacheScope, "public");
    assert.equal(tools.ttlMs, 60_000);

    const result = await client.callTool({ name: "get_skill", arguments: { id: "validator-upgrade" } });
    assert.equal(result.isError, undefined);
    assert.match(JSON.stringify(result.content), /Validator upgrade/i);

    const resource = await client.readResource({ uri: "skills://validator-upgrade/SKILL.md" });
    const firstContent = resource.contents[0];
    assert.ok(firstContent && "text" in firstContent);
    assert.match(firstContent.text, /validator upgrade/i);
    assert.equal(resource.cacheScope, "public");
    assert.equal(resource.ttlMs, 300_000);
  } finally {
    await client.close();
  }
});
