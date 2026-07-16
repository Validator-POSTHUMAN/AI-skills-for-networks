import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import {
  CallToolRequestSchema,
  ListResourcesRequestSchema,
  ListToolsRequestSchema,
  ReadResourceRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { listSkillFiles, loadCatalog, readSkillFile, repositoryRoot, type SkillEntry } from "./catalog.js";

const root = repositoryRoot();

function asText(value: unknown) {
  return { content: [{ type: "text" as const, text: JSON.stringify(value, null, 2) }] };
}

function selectEntry(skills: SkillEntry[], id: unknown): SkillEntry {
  if (typeof id !== "string") throw new Error("id must be a string");
  const entry = skills.find((candidate) => candidate.id === id);
  if (!entry) throw new Error(`Unknown skill: ${id}`);
  return entry;
}

export async function createSkillCatalogServer(): Promise<Server> {
  const catalog = await loadCatalog(root);
  const server = new Server(
    { name: "posthuman-validator-skills", version: "0.1.0" },
    { capabilities: { tools: {}, resources: {} } },
  );

  server.setRequestHandler(ListToolsRequestSchema, async () => ({
    tools: [
      {
        name: "list_skills",
        description: "List public validator skills, optionally filtered by category or text.",
        inputSchema: {
          type: "object",
          properties: {
            category: { type: "string" },
            query: { type: "string", maxLength: 120 },
          },
          additionalProperties: false,
        },
      },
      {
        name: "get_skill",
        description: "Read a public skill instruction or one of its bundled public files.",
        inputSchema: {
          type: "object",
          properties: {
            id: { type: "string" },
            file: { type: "string", default: "SKILL.md" },
          },
          required: ["id"],
          additionalProperties: false,
        },
      },
      {
        name: "search_skills",
        description: "Search public skill metadata and instruction text.",
        inputSchema: {
          type: "object",
          properties: {
            query: { type: "string", minLength: 2, maxLength: 120 },
            limit: { type: "integer", minimum: 1, maximum: 20, default: 10 },
          },
          required: ["query"],
          additionalProperties: false,
        },
      },
    ],
  }));

  server.setRequestHandler(CallToolRequestSchema, async (request) => {
    try {
      const args = request.params.arguments ?? {};
      if (request.params.name === "list_skills") {
        const category = typeof args.category === "string" ? args.category.toLowerCase() : "";
        const query = typeof args.query === "string" ? args.query.toLowerCase().trim() : "";
        const skills = catalog.skills.filter((entry) => {
          const matchesCategory = !category || entry.category.toLowerCase() === category;
          const haystack = `${entry.id} ${entry.title} ${entry.description}`.toLowerCase();
          return matchesCategory && (!query || haystack.includes(query));
        });
        return asText({ version: catalog.version, count: skills.length, skills });
      }

      if (request.params.name === "get_skill") {
        const entry = selectEntry(catalog.skills, args.id);
        const file = typeof args.file === "string" ? args.file : "SKILL.md";
        const [text, files] = await Promise.all([
          readSkillFile(root, entry, file),
          listSkillFiles(root, entry),
        ]);
        return asText({ skill: entry, file, files, text });
      }

      if (request.params.name === "search_skills") {
        if (typeof args.query !== "string" || args.query.trim().length < 2) throw new Error("query is required");
        const query = args.query.toLowerCase().trim();
        const limit = typeof args.limit === "number" ? Math.max(1, Math.min(20, Math.floor(args.limit))) : 10;
        const matches = [];
        for (const entry of catalog.skills) {
          const body = await readSkillFile(root, entry);
          const haystack = `${entry.id} ${entry.title} ${entry.description} ${body}`.toLowerCase();
          if (haystack.includes(query)) matches.push(entry);
          if (matches.length >= limit) break;
        }
        return asText({ query, count: matches.length, skills: matches });
      }

      throw new Error(`Unknown tool: ${request.params.name}`);
    } catch (error) {
      return { ...asText({ error: error instanceof Error ? error.message : "Request failed" }), isError: true };
    }
  });

  server.setRequestHandler(ListResourcesRequestSchema, async () => ({
    resources: [
      { uri: "skills://catalog", name: "Public validator skills catalog", mimeType: "application/json" },
      ...catalog.skills.map((entry) => ({
        uri: `skills://${entry.id}/SKILL.md`,
        name: entry.title,
        description: entry.description,
        mimeType: "text/markdown",
      })),
    ],
  }));

  server.setRequestHandler(ReadResourceRequestSchema, async (request) => {
    if (request.params.uri === "skills://catalog") {
      return { contents: [{ uri: request.params.uri, mimeType: "application/json", text: JSON.stringify(catalog, null, 2) }] };
    }
    const match = /^skills:\/\/([a-z0-9-]+)\/SKILL\.md$/.exec(request.params.uri);
    if (!match) throw new Error("Unknown resource URI");
    const entry = selectEntry(catalog.skills, match[1]);
    const text = await readSkillFile(root, entry);
    return { contents: [{ uri: request.params.uri, mimeType: "text/markdown", text }] };
  });

  return server;
}
