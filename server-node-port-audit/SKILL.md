---
name: "server-node-port-audit"
description: "Audit servers to identify blockchain nodes, listening ports, and effective network exposure."
---

# Server node and port audit

Use when asked to inspect an authorized server, discover blockchain node processes or containers, map their ports, or verify whether RPC, API, metrics, admin, P2P, or gossip listeners are effectively public.

This is a read-only audit skill. It contains procedure only.

## Data boundary

- Never embed operator IP addresses, hostnames, SSH users, chain placement, allowlists, credentials, or private service URLs in this skill or its support files.
- Resolve the target and expected role at runtime from the workspace's canonical inventory and network pages.
- Treat inventory as a lookup aid and current live state as truth.
- Do not copy runtime inventory into skill files, evals, logs, or public messages.
- Never open, print, or search key material, wallet files, environment variables, credential stores, config backups, or secret-bearing runtime state.
- Do not use full `docker inspect` output; it may expose environment secrets.
- Update the separate knowledge base after a verified meaningful audit. Do not make the skill a second inventory.

For a future MCP wrapper, pass an opaque inventory reference such as `target_ref`; resolve it inside the authorized runtime. Do not expose raw connection details in tool schemas or results unless the caller is authorized.

## Authority and scope

Before probing:

1. Confirm the target is owned or explicitly authorized.
2. Resolve the exact connection target from canonical knowledge. Never brute-force SSH usernames, addresses, or credentials.
3. Record the audit mode: local inventory, remote read-only inspection, external reachability verification, or all three.
4. Identify the expected server role, environment, and whether it may be a signing validator.
5. Keep the audit diagnostic-only unless the operator separately authorizes changes.

Do not restart services, edit firewall or proxy rules, recreate containers, change configuration, or remove stale rules during this workflow. Report proposed remediation separately.

Use exact documented targets and exact discovered or approved ports. Do not run broad address scans, arbitrary port ranges, recursive peer crawling, or third-party internet scanners without separate explicit approval.

## Workflow

### 1. Establish host identity

Collect only the minimum safe context:

- host alias or opaque inventory reference
- OS and virtualization/container context
- active, staged, fenced, or retired status
- expected workloads from canonical knowledge
- whether the session is local or SSH
- audit vantage points available

If live identity conflicts with inventory, stop treating the inventory mapping as authoritative and report documentation drift.

### 2. Collect local listeners and workloads

Prefer concise, structured commands from [references/probe-matrix.md](references/probe-matrix.md).

Collect:

- TCP and UDP listeners with process ownership
- running and failed systemd services
- Docker or Podman container names, images, and published ports
- reverse-proxy presence
- firewall framework presence
- IPv4 and IPv6 bind state

Do not dump complete process environments, unit environments, container inspection JSON, shell history, arbitrary logs, or all configuration files.

### 3. Identify blockchain nodes

Correlate at least two signals where possible:

- executable, process, unit, container, or image name
- safe command-line arguments
- data/home directory name
- known client configuration path
- chain-aware RPC response
- expected workload from canonical knowledge

Record the client and chain as `confirmed`, `probable`, or `unknown`. Do not infer a chain from a port number alone.

Limit configuration reads to explicitly selected, non-sensitive bind and port fields. Treat all unrelated configuration categories as out of scope.

### 4. Build the port map

For each relevant listener, record:

- protocol and port
- bind address and address family
- owning process, service, or container
- client and chain identity
- role: P2P/gossip, RPC, REST, gRPC, WebSocket, metrics, admin, engine/authenticated API, or unknown
- validator relation: signing, non-signing full node, sentry, auxiliary, or unknown
- intended access: public-by-design, trusted-source only, loopback/local, reverse-proxied, or unknown

Keep public P2P/gossip separate from RPC/API/admin exposure.

### 5. Determine effective exposure

A listener is not classified from its bind address alone. Trace the complete path:

- local bind address
- host firewall default policy and matching rules
- nftables or iptables rules
- Docker or Podman published ports and forwarding chains
- `DOCKER-USER` or equivalent policy
- IPv6 listener and IPv6 firewall path
- reverse-proxy routes
- provider or cloud firewall, when visible
- external reachability from an authorized vantage outside ordinary allowlists

Important cases:

- `0.0.0.0` does not prove internet reachability.
- A loopback RPC may still be public through a reverse proxy.
- Docker-published ports may bypass an assumed UFW restriction.
- IPv4 may be closed while global IPv6 remains reachable.
- A firewall allowlist is stale if its source is no longer a current trusted host in canonical knowledge.

External verification must target only the exact authorized host and exact port. Do not use public scanning services by default.

### 6. Verify protocol identity safely

Use read-only protocol calls only:

- CometBFT: `/status` for network, sync state, height, and validator voting power
- EVM JSON-RPC: `eth_chainId` and optionally `web3_clientVersion`
- Starknet JSON-RPC: `starknet_chainId`
- NEAR JSON-RPC: `status`
- Solana JSON-RPC: `getHealth` and `getVersion`
- gRPC: a real node-info or status request when the service supports it

Do not submit transactions or call mutating/admin methods. When health matters, compare height or freshness with more than one independent trusted reference.

A zero voting power response is not proof that a host is safely non-signing. Confirm its infrastructure role separately.

### 7. Classify every relevant port

Use one verdict:

- `PUBLIC_BY_DESIGN`: required public P2P/gossip or explicitly approved public API
- `PUBLIC_UNEXPECTED`: RPC/API/admin/metrics is externally reachable without recorded approval
- `TRUSTED_ONLY`: effective source restriction is verified
- `LOCAL_ONLY`: bound to loopback or otherwise locally confined, with no public proxy path
- `REVERSE_PROXY_PUBLIC`: local backend is public through a proxy
- `BLOCKED`: listener exists but the tested external path is blocked
- `CLOSED`: no listener or connection refusal on the scoped port
- `UNKNOWN`: evidence is incomplete or contradictory

Never call a port closed based only on UFW output or open based only on `ss`.

### 8. Verify and report

For a diagnostic-only request, explicitly confirm that no mutation was performed.

Report:

- audit scope and vantage points
- nodes and clients found
- concise port map
- effective exposure verdicts
- evidence for unexpected exposure
- chain identity, sync/freshness, and signing relation when verified
- stale allowlists or documentation drift
- unknowns and exact next checks
- remediation suggestions requiring separate approval

On a public chat surface, summarize findings without raw private inventory. Put detailed host mappings only in the authorized knowledge base.

## Completion gate

The audit is complete only when:

- every relevant listener has an owner or is marked unknown
- Docker/container forwarding, host firewall, IPv6, and reverse-proxy paths were considered
- unexpected public exposure was tested externally from an authorized vantage when possible
- protocol identity was checked rather than guessed from ports
- signing and non-signing roles were not inferred from voting power alone
- no secrets were opened or printed
- no production mutation occurred
- documentation drift is reported and, when authorized, corrected in the separate canonical knowledge base
