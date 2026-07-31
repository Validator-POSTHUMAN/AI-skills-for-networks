# Validator Skills MCP

Read-only Model Context Protocol server for the public skills in this
repository. It serves only paths explicitly listed in `catalog.json`; it has no
access to operator inventories, credentials, private knowledge bases, or
production systems.

## Requirements

- Node.js 20 or newer
- `npm ci`
- `npm test`

The server uses the split Model Context Protocol TypeScript SDK v2 packages
and implements the 2026-07-28 protocol revision while retaining the SDK's
legacy compatibility path.

## Local stdio

```bash
npm run build
npm run start:stdio
```

The stdio transport reserves stdout for MCP JSON-RPC. Diagnostics go to
stderr.

## Remote HTTP

The HTTP transport is stateless and binds to loopback by default:

```bash
npm run build
MCP_PORT=3000 npm run start:http
```

For a non-loopback bind, set an explicit Host allowlist:

```bash
MCP_HOST=0.0.0.0 \
MCP_ALLOWED_HOSTS=skills.example.org \
MCP_PORT=3000 \
npm run start:http
```

Deploy behind TLS and rate limiting. Requests with an `Origin` header are
rejected unless that origin's hostname appears in `MCP_ALLOWED_ORIGINS`
(full origin URLs are accepted and normalized to hostnames). The server
does not provide authentication because all catalog content is public and
read-only; add authentication at the reverse proxy if deployment policy
requires it.

Endpoints:

- `GET /healthz`
- `POST /mcp`

## Tools

- `list_skills` — list or filter catalog metadata
- `get_skill` — read `SKILL.md` or a bounded bundled public file
- `search_skills` — search public metadata and skill instructions

The server rejects path traversal, symlinks, unlisted file classes, oversized
files, unlisted Host headers, and browser origins that were not allowlisted.
HTTP serving is stateless and does not issue or accept `Mcp-Session-Id` state.
Modern clients can use `server/discover`; list/read responses carry public
cache hints. No multi-round-trip, sampling, roots, or mutation capability is
registered.
