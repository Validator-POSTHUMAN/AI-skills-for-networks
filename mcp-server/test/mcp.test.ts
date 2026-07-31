import assert from "node:assert/strict";
import { test } from "node:test";
import { Client } from "@modelcontextprotocol/client";
import { StdioClientTransport } from "@modelcontextprotocol/client/stdio";
import { fileURLToPath } from "node:url";

const MODERN = "2026-07-28";
const ENTRY = fileURLToPath(new URL("../src/stdio.js", import.meta.url));

test("stdio negotiates MCP 2026-07-28 and defaults to metadata-only", async () => {
  const transport = new StdioClientTransport({ command: process.execPath, args: [ENTRY] });
  const client = new Client(
    { name: "catalog-test", version: "1.0.0" },
    { versionNegotiation: { mode: "auto" } },
  );
  try {
    await client.connect(transport);
    assert.equal(client.getProtocolEra(), "modern");
    assert.equal(client.getNegotiatedProtocolVersion(), MODERN);

    const discovery = await client.discover();
    assert.ok(discovery.supportedVersions.includes(MODERN));

    const tools = await client.listTools();
    assert.deepEqual(tools.tools.map((tool) => tool.name).sort(), [
      "get_capability_metadata",
      "list_capabilities",
      "search_capabilities",
    ]);
    assert.equal(tools.cacheScope, "public");
    assert.equal(tools.ttlMs, 60_000);

    const result = await client.callTool({ name: "get_capability_metadata", arguments: { id: "validator-upgrade" } });
    const output = JSON.stringify(result.content);
    assert.equal(result.isError, undefined);
    assert.match(output, /Validator upgrade/i);
    assert.match(output, /contentSha256/);
    assert.doesNotMatch(output, /"path"|Preconditions|Rollback/);

    const resource = await client.readResource({ uri: "skills://registry" });
    const firstContent = resource.contents[0];
    assert.ok(firstContent && "text" in firstContent);
    assert.match(firstContent.text, /contentSha256/);
    assert.doesNotMatch(firstContent.text, /"path"|Preconditions|Rollback/);
  } finally {
    await client.close();
  }
});

test("trusted stdio source mode must be enabled explicitly", async () => {
  const transport = new StdioClientTransport({
    command: process.execPath,
    args: [ENTRY],
    env: { POSTHUMAN_MCP_MODE: "source" },
  });
  const client = new Client(
    { name: "source-mode-test", version: "1.0.0" },
    { versionNegotiation: { mode: "auto" } },
  );
  try {
    await client.connect(transport);
    const tools = await client.listTools();
    assert.ok(tools.tools.some((tool) => tool.name === "read_skill_source"));
    const result = await client.callTool({
      name: "read_skill_source",
      arguments: { id: "validator-upgrade" },
    });
    assert.equal(result.isError, undefined);
    assert.match(JSON.stringify(result.content), /validator upgrade/i);
  } finally {
    await client.close();
  }
});
