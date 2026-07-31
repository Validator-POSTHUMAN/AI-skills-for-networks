import { McpServer } from "@modelcontextprotocol/server";
import * as z from "zod/v4";
import {
  listSkillFiles,
  loadCatalog,
  publicSkillMetadata,
  readSkillFile,
  repositoryRoot,
  type PublicSkillMetadata,
  type SkillEntry,
} from "./catalog.js";

const PUBLIC_LIST_TTL_MS = 60_000;
const PUBLIC_READ_TTL_MS = 300_000;
const CAPABILITY_ID = z.string().regex(/^[a-z0-9][a-z0-9-]*$/);

export type CatalogMode = "metadata" | "source";

interface ServerOptions {
  mode?: CatalogMode;
  root?: string;
}

export function catalogMode(value = process.env.POSTHUMAN_MCP_MODE): CatalogMode {
  if (!value || value === "metadata") return "metadata";
  if (value === "source") return "source";
  throw new Error("POSTHUMAN_MCP_MODE must be metadata or source");
}

function asText(value: unknown) {
  return { content: [{ type: "text" as const, text: JSON.stringify(value, null, 2) }] };
}

function asError(error: unknown) {
  return { ...asText({ error: error instanceof Error ? error.message : "Request failed" }), isError: true };
}

function selectEntry<T extends { id: string }>(entries: T[], id: string): T {
  const entry = entries.find((candidate) => candidate.id === id);
  if (!entry) throw new Error(`Unknown capability: ${id}`);
  return entry;
}

export async function createSkillCatalogServer(options: ServerOptions = {}): Promise<McpServer> {
  const root = options.root ?? repositoryRoot();
  const mode = options.mode ?? catalogMode();
  const loaded = await loadCatalog(root);
  const catalog = { ...loaded, skills: [...loaded.skills].sort((left, right) => left.id.localeCompare(right.id)) };
  const registry = await Promise.all(
    catalog.skills.map((entry) => publicSkillMetadata(root, catalog.version, entry)),
  );
  const server = new McpServer(
    { name: "posthuman-capability-registry", version: "0.2.0" },
    {
      instructions: "Metadata-only discovery for reviewed public POSTHUMAN validator capabilities.",
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
    "list_capabilities",
    {
      description: "List POSTHUMAN capability metadata without returning skill source or private knowledge.",
      inputSchema: z.object({
        category: z.string().optional(),
        query: z.string().max(120).optional(),
      }).strict(),
      annotations: readOnly,
    },
    async ({ category, query }) => {
      const normalizedCategory = category?.toLowerCase() ?? "";
      const normalizedQuery = query?.toLowerCase().trim() ?? "";
      const capabilities = registry.filter((entry) => {
        const matchesCategory = !normalizedCategory || entry.category.toLowerCase() === normalizedCategory;
        const haystack = `${entry.id} ${entry.title} ${entry.description}`.toLowerCase();
        return matchesCategory && (!normalizedQuery || haystack.includes(normalizedQuery));
      });
      return asText({ version: catalog.version, count: capabilities.length, capabilities });
    },
  );

  server.registerTool(
    "get_capability_metadata",
    {
      description: "Return integrity and discovery metadata for one POSTHUMAN capability.",
      inputSchema: z.object({ id: CAPABILITY_ID }).strict(),
      annotations: readOnly,
    },
    async ({ id }) => {
      try {
        return asText({ capability: selectEntry<PublicSkillMetadata>(registry, id) });
      } catch (error) {
        return asError(error);
      }
    },
  );

  server.registerTool(
    "search_capabilities",
    {
      description: "Search capability metadata. Skill source and private knowledge are not searched.",
      inputSchema: z.object({
        query: z.string().min(2).max(120),
        limit: z.number().int().min(1).max(20).optional(),
      }).strict(),
      annotations: readOnly,
    },
    async ({ query, limit }) => {
      const normalizedQuery = query.toLowerCase().trim();
      const capabilities = registry.filter((entry) => {
        const haystack = `${entry.id} ${entry.title} ${entry.description}`.toLowerCase();
        return haystack.includes(normalizedQuery);
      }).slice(0, limit ?? 10);
      return asText({ query: normalizedQuery, count: capabilities.length, capabilities });
    },
  );

  if (mode === "source") {
    server.registerTool(
      "read_skill_source",
      {
        description: "Read a public skill file in explicitly enabled trusted local stdio mode.",
        inputSchema: z.object({
          id: CAPABILITY_ID,
          file: z.string().optional(),
        }).strict(),
        annotations: readOnly,
      },
      async ({ id, file }) => {
        try {
          const entry = selectEntry<SkillEntry>(catalog.skills, id);
          const selectedFile = file ?? "SKILL.md";
          const [text, files] = await Promise.all([
            readSkillFile(root, entry, selectedFile),
            listSkillFiles(root, entry),
          ]);
          return asText({ id: entry.id, file: selectedFile, files, text });
        } catch (error) {
          return asError(error);
        }
      },
    );
  }

  server.registerResource(
    "registry",
    "skills://registry",
    {
      title: "POSTHUMAN capability registry",
      description: "Metadata and integrity digests for reviewed public capabilities.",
      mimeType: "application/json",
      cacheHint: { ttlMs: PUBLIC_READ_TTL_MS, cacheScope: "public" },
    },
    async (uri) => ({
      contents: [{
        uri: uri.href,
        mimeType: "application/json",
        text: JSON.stringify({ version: catalog.version, mode: "metadata", capabilities: registry }, null, 2),
      }],
    }),
  );

  return server;
}
