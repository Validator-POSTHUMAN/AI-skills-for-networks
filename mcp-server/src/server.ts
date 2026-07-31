import { McpServer } from "@modelcontextprotocol/server";
import * as z from "zod/v4";
import { listSkillFiles, loadCatalog, readSkillFile, repositoryRoot, type SkillEntry } from "./catalog.js";

const root = repositoryRoot();
const PUBLIC_LIST_TTL_MS = 60_000;
const PUBLIC_READ_TTL_MS = 300_000;

function asText(value: unknown) {
  return { content: [{ type: "text" as const, text: JSON.stringify(value, null, 2) }] };
}

function selectEntry(skills: SkillEntry[], id: string): SkillEntry {
  const entry = skills.find((candidate) => candidate.id === id);
  if (!entry) throw new Error(`Unknown skill: ${id}`);
  return entry;
}

export async function createSkillCatalogServer(): Promise<McpServer> {
  const loaded = await loadCatalog(root);
  const catalog = { ...loaded, skills: [...loaded.skills].sort((left, right) => left.id.localeCompare(right.id)) };
  const server = new McpServer(
    { name: "posthuman-validator-skills", version: "0.2.0" },
    {
      instructions: "Read-only access to the public POSTHUMAN validator skills catalog.",
      cacheHints: {
        "server/discover": { ttlMs: PUBLIC_LIST_TTL_MS, cacheScope: "public" },
        "tools/list": { ttlMs: PUBLIC_LIST_TTL_MS, cacheScope: "public" },
        "resources/list": { ttlMs: PUBLIC_LIST_TTL_MS, cacheScope: "public" },
        "resources/read": { ttlMs: PUBLIC_READ_TTL_MS, cacheScope: "public" },
      },
    },
  );

  const readOnly = { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false };

  server.registerTool(
    "list_skills",
    {
      description: "List public validator skills, optionally filtered by category or text.",
      inputSchema: z.object({
        category: z.string().optional(),
        query: z.string().max(120).optional(),
      }).strict(),
      annotations: readOnly,
    },
    async ({ category, query }) => {
      const normalizedCategory = category?.toLowerCase() ?? "";
      const normalizedQuery = query?.toLowerCase().trim() ?? "";
      const skills = catalog.skills.filter((entry) => {
        const matchesCategory = !normalizedCategory || entry.category.toLowerCase() === normalizedCategory;
        const haystack = `${entry.id} ${entry.title} ${entry.description}`.toLowerCase();
        return matchesCategory && (!normalizedQuery || haystack.includes(normalizedQuery));
      });
      return asText({ version: catalog.version, count: skills.length, skills });
    },
  );

  server.registerTool(
    "get_skill",
    {
      description: "Read a public skill instruction or one of its bundled public files.",
      inputSchema: z.object({
        id: z.string(),
        file: z.string().optional(),
      }).strict(),
      annotations: readOnly,
    },
    async ({ id, file }) => {
      try {
        const entry = selectEntry(catalog.skills, id);
        const selectedFile = file ?? "SKILL.md";
        const [text, files] = await Promise.all([
          readSkillFile(root, entry, selectedFile),
          listSkillFiles(root, entry),
        ]);
        return asText({ skill: entry, file: selectedFile, files, text });
      } catch (error) {
        return { ...asText({ error: error instanceof Error ? error.message : "Request failed" }), isError: true };
      }
    },
  );

  server.registerTool(
    "search_skills",
    {
      description: "Search public skill metadata and instruction text.",
      inputSchema: z.object({
        query: z.string().min(2).max(120),
        limit: z.number().int().min(1).max(20).optional(),
      }).strict(),
      annotations: readOnly,
    },
    async ({ query, limit }) => {
      const normalizedQuery = query.toLowerCase().trim();
      const maxMatches = limit ?? 10;
      const matches: SkillEntry[] = [];
      for (const entry of catalog.skills) {
        const body = await readSkillFile(root, entry);
        const haystack = `${entry.id} ${entry.title} ${entry.description} ${body}`.toLowerCase();
        if (haystack.includes(normalizedQuery)) matches.push(entry);
        if (matches.length >= maxMatches) break;
      }
      return asText({ query: normalizedQuery, count: matches.length, skills: matches });
    },
  );

  server.registerResource(
    "catalog",
    "skills://catalog",
    {
      title: "Public validator skills catalog",
      mimeType: "application/json",
      cacheHint: { ttlMs: PUBLIC_READ_TTL_MS, cacheScope: "public" },
    },
    async (uri) => ({
      contents: [{ uri: uri.href, mimeType: "application/json", text: JSON.stringify(catalog, null, 2) }],
    }),
  );

  for (const entry of catalog.skills) {
    server.registerResource(
      entry.id,
      `skills://${entry.id}/SKILL.md`,
      {
        title: entry.title,
        description: entry.description,
        mimeType: "text/markdown",
        cacheHint: { ttlMs: PUBLIC_READ_TTL_MS, cacheScope: "public" },
      },
      async (uri) => ({
        contents: [{ uri: uri.href, mimeType: "text/markdown", text: await readSkillFile(root, entry) }],
      }),
    );
  }

  return server;
}
