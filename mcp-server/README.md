# Validator Skills MCP

POSTHUMAN-owned Model Context Protocol server and capability registry. Its safe
default is metadata-only: it advertises reviewed capability descriptions and
SHA-256 digests without returning skill source. It has no access to operator
inventories, credentials, private knowledge bases, or production systems.

Private knowledge must never be mounted into this public process. Anything
returned to a public client can be copied; authentication and quotas reduce
abuse but do not make public output private.

## Requirements

- Node.js 20 or newer
- `npm ci`
- `npm test`

The split Model Context Protocol TypeScript SDK v2 implements the 2026-07-28
protocol revision while retaining the SDK's legacy compatibility path.

## Local stdio

```bash
npm run build
npm run start:stdio
```

The default exposes metadata only. Trusted local stdio clients may explicitly
enable source compatibility:

```bash
POSTHUMAN_MCP_MODE=source npm run start:stdio
```

HTTP rejects source mode. Stdout is reserved for MCP JSON-RPC; diagnostics use
stderr.

## Remote HTTP

HTTP is stateless and binds to loopback by default:

```bash
npm run build
MCP_PORT=3000 npm run start:http
```

For a public reverse-proxy deployment, keep the process on loopback and set:

```text
MCP_HOST=127.0.0.1
MCP_PORT=3000
MCP_ALLOWED_HOSTS=skills.example.org
MCP_ALLOWED_ORIGINS=skills.example.org
MCP_REQUIRE_AUTH=true
MCP_BEARER_KEYS=<credential delivered outside git and argv>
MCP_RATE_LIMIT_PER_MINUTE=60
MCP_IP_RATE_LIMIT_PER_MINUTE=30
POSTHUMAN_MCP_MODE=metadata
```

`MCP_BEARER_KEYS` accepts comma-separated keys so rotation can overlap old and new
credentials. Each key must contain at least 32 characters. Remove the old key
after clients migrate. Never place keys in the repository, service unit,
process arguments, or shell history.

Non-loopback mode fails closed without a Host allowlist. Authentication can be
required independently of bind address, which is mandatory behind a loopback
reverse proxy. The application enforces bounded per-IP and per-key
fixed-window quotas; the reverse proxy must add TLS and an independent request
limit. Loopback proxy hops are trusted only for client-address resolution.

Requests with an `Origin` header are rejected unless that origin's hostname is
allowlisted. Full origin URLs are accepted and normalized to hostnames.

Endpoints:

- `GET /healthz`
- `POST /mcp`

## Public surface

- `list_capabilities` — list or filter metadata;
- `get_capability_metadata` — return metadata and canonical `SKILL.md` digest;
- `search_capabilities` — search metadata only;
- `skills://registry` — metadata registry resource.

Every tool is annotated read-only, non-destructive, idempotent, and closed
world. Modern clients can use `server/discover`; list/read responses carry
public cache hints. The server registers no mutation, sampling, roots, prompt,
task, or multi-round-trip capability and uses no `Mcp-Session-Id` state.

## Security and audit behavior

The server rejects path traversal, symlinks, unlisted file classes, oversized
files, source mode over HTTP, unlisted Host/Origin values, missing bearer
credentials when required, malformed modern routing headers, and over-limit
requests. Authorization and cookie headers are removed before MCP dispatch.

Each `/mcp` response emits a content-free JSON audit record to stderr with
timestamp, method, optional tool name, keyed client fingerprint, status, and
duration. It does not record tokens, IP addresses, request IDs, arguments,
responses, prompts, skill source, headers, or cookies. Use the service journal
retention policy rather than adding payload logging.

Deployment templates and rollback gates are in [`deploy/README.md`](deploy/README.md).
