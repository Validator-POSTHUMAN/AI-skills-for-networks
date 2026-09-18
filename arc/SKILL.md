---
name: arc-node-ops
description: "Operate Arc Network nodes: arc-node-execution and arc-node-consensus deployment, arcup and Docker installs, snapshot bootstrap and el-profile choices, relay-endpoint follow health, the arc RPC namespace, wall-clock hardfork deadlines, RPC exposure hardening, incident triage, and concise operator reports."
---

# Arc Node Ops

Use this skill for Arc Network node operations: installing and running
`arc-node-execution` and `arc-node-consensus`, bootstrapping from snapshots,
serving RPC, monitoring follow health, hardening exposure, keeping up with
wall-clock fork deadlines, and triaging incidents.

Operator-neutral and provider-neutral. It assumes no particular hosting
provider, cloud or RPC customer, and contains no production hosts or
credentials.

## Read this first: what an Arc node is not

An Arc node is a **follower**. It verifies every block against the validator
set's signatures and re-executes every transaction locally, but it proposes
nothing, holds no consensus stake and cannot be slashed. Anyone may run one; no
permission and no stake are required.

Do not carry proof-of-stake reflexes across. There is no double-sign risk, no
slashing-protection database, no key-uniqueness proof and no unbonding clock.
**Restarting an Arc node is safe. Replacing its data directory is safe** — it is
reconstructible from a snapshot.

One file is not: the **consensus-layer private key** in `$ARC_CONSENSUS`,
written once by `arc-node-consensus init`. It is the node's network identity, it
cannot be recovered, and the obvious fix for a half-extracted snapshot — clear
the directory and re-download — destroys it.

The failures that do matter:

| Failure | Cost |
|---|---|
| Node stops following and nothing says so | stale answers, delivered confidently |
| Missed fork timestamp | off the canonical chain at a wall-clock moment |
| RPC published with the quickstart namespace list | `debug_traceTransaction` as a remote DoS |
| `--el-profile` left at its default | archive flags on a minimal restore; only another full restore fixes it |

## The failure that looks healthy

A follow node reaches the network entirely through **relay endpoints** over
HTTPS and WebSocket. When they stop answering, the node does not crash. Both
processes stay `active (running)`, `eth_blockNumber` answers instantly, and the
answer is old.

**Alert on block-number progress and on hash agreement with an independent
RPC. Never on the process being up.** Sample the height twice — one reading
cannot distinguish "advancing" from "stopped a second ago" — and compare the
block **hash** at a common height, because two chains can sit at the same
number.

## Forks are wall-clock, not block heights

There is no on-chain upgrade plan to query, no approaching height, and no
warning in the logs the day before.

| Network | Fork | Timestamp | Wall clock | Requires |
|---|---|---|---|---|
| Arc Testnet | Zero8 | `1788447600` | 2026-09-03 15:00 UTC | `v0.8.0` |
| Arc mainnet | Zero7 + Zero8 | `1789052400` | 2026-09-10 15:00 UTC | `v0.8.0` |

Both have passed. `v0.8.0` is mandatory on both networks today.

Testnet activates about a week before mainnet, which is the entire operational
value of running a testnet node here: it is an early warning that a release is
about to become mandatory, not a rehearsal of a signing procedure.

## Source priority

1. Live output from the target host: `eth_chainId`, `arc_getVersion`,
   `eth_blockNumber` sampled twice, unit state, `ss`, disk, logs from **both**
   layers.
2. `arc_getVersion` against the official public RPC — what the fleet runs.
3. Local operator inventory and runbooks.
4. Official sources:
   - https://github.com/circlefin/arc-node — source, releases, `arcup`,
     `deployments/docker-compose.yml`
   - https://github.com/circlefin/arc-node/releases — **the release source of
     truth**
   - https://docs.arc.io/arc/tutorials/run-an-arc-node — the fork deadlines
     live in the banner on this page
   - https://docs.arc.io/arc/references/node-requirements — ports, sizing,
     relay endpoints, Versions table
   - https://docs.arc.io/arc/references/evm-differences — before anything that
     touches balances, history or gas

**Circle's documentation lags its own mainnet.** As of 2026-09-18 the
`node-requirements` Versions table and the relay-endpoint table both list only
Arc Testnet, while the run-a-node page states the mainnet upgrade deadline and
`arc_getVersion` on `rpc.mainnet.arc.io` returns `v0.8.0`. Read the chain, then
the releases page, then the table — in that order.

## Architecture

Two processes on one host, talking over IPC:

- **`arc-node-execution`** — execution layer, Reth-based. JSON-RPC `8545`,
  WebSocket `8546`, Engine API `8551` (not used in IPC mode), metrics `9001`,
  P2P `30303` on RPC provider nodes only.
- **`arc-node-consensus`** — consensus layer, Malachite-based. Fetches
  finalized blocks from relay endpoints, verifies signatures, drives the EL.
  RPC `31000`, metrics `29000`, P2P `27000` on RPC provider nodes only.

Sockets: `$ARC_RUN/reth.ipc` and `$ARC_RUN/auth.ipc`, default `/run/arc`.

**Start the EL first, always.** The CL connects to those sockets at startup and
fails if they are absent.

The RPC transport between the layers is **deprecated in `v0.8.0` and removed in
`v0.9.0`**. Same host, IPC.

## Operational facts worth not re-deriving

| Fact | Value |
|---|---|
| Arc mainnet chain ID | `5042` / `0x13b2` |
| Arc Testnet chain ID | `5042002` / `0x4cef52` |
| Arc Devnet chain ID | `5042001` |
| Chain spec names | `arc-mainnet`, `arc-testnet`, `arc-devnet`, `arc-localdev` |
| Current release | `v0.8.0`, tag commit `66ad2d5aa6d9b41e8f689812004be4c7233a9e16` |
| Gas token | USDC — **18 decimals natively, 6 as ERC-20** |
| Mempool `maxFeePerGas` floor | 20 Gwei |
| Base-fee cap | 20,000 gwei |
| Block gas limit | `10,000,000`–`200,000,000`, default `30,000,000` |
| USDC system emitter | `0xffffFFFfFFffffffffffffffFfFFFfffFFFfFFfE` |
| Denylist proxy, mainnet | `0x3600000000000000000000000000000000000004` |
| glibc required by prebuilt binaries | **2.39+** — Ubuntu 24.04 yes, Debian 12 no |
| Genesis sync | **not supported** — snapshot only |
| Snapshot format from `v0.8.0` | Reth **V2** |
| Testnet snapshot size | ~68 GB EL + ~16 GB CL compressed; ~103 GB + ~36 GB extracted |

Chain IDs, gas limits, fee config and the denylist address read from
`crates/shared/src/chain_ids.rs` and `crates/execution-config/src/chainspec.rs`
at tag `v0.8.0`. Mainnet snapshot sizes are **not published**; do not quote the
testnet figures for mainnet.

Five traps that outdate a runbook:

- **Every Circle quickstart targets `arc-testnet`,** including the published
  `docker-compose.yml`. A mainnet deployment made by changing the RPC URLs and
  not `--chain` is a testnet node pointed at mainnet relays. Finish every
  deployment with `cast chain-id`.
- **`--el-profile` defaults to `minimal`,** including when an explicit manifest
  URL is passed. No in-place conversion exists.
- **Never pass a presigned snapshot manifest URL.** Reth derives component URLs
  by string concatenation, so the query string lands between the path and the
  filename and every component 404s. Use `--chain`.
- **Automatic snapshot resolution has no fallback.** It requires a storage-v2
  listing for that chain; if there is none it fails, and the failure is the
  answer.
- **The legacy `arc.network` domain has a testnet form and no mainnet form.**
  `rpc.testnet.arc.network` still answers; `rpc.mainnet.arc.network` does not
  resolve. `snapshots.arc.network` is still the snapshot host.

## What this skill helps agents do

- Verify a node in the right order: `eth_chainId`, `arc_getVersion`,
  `eth_blockNumber` twice, then a hash comparison against an independent RPC.
- Diagnose a frozen height as a relay-endpoint, disk-latency or backpressure
  problem, testing outbound reachability **from the node host**.
- Read `0x0` through its four real causes: missing IPC sockets, CL started
  before EL, interrupted snapshot extraction, `$ARC_RUN` mismatch.
- Treat `arc-snapshots` refusing without `--force` as correct behaviour
  protecting unmarked data, and know `FORCE_SNAPSHOT_RESTORE=true` does
  nothing.
- Review exposure from what Circle's quickstart actually sets
  (`eth,net,web3,txpool,trace,debug`) and from listeners rather than from
  `ufw status`, because Docker writes its rules first.
- Verify a public node with `rpc_modules` and an
  `eth_newPendingTransactionFilter` probe that must return `-32001`.
- Separate the two USDC representations without ever summing them.
- Recognise `GLIBC_2.39 not found` as a distribution problem with no flag that
  fixes it, and `Address already in use` on the CL as a port collision that
  leaves `arc_getCertificate` silently broken while the node looks healthy.

## Safety boundaries

Read-only by default. This skill broadcasts no transaction, moves no funds,
generates or handles no keys, and mutates no node state without operator
approval.

Explicit approval required before:

- deleting or replacing a data directory, even though it is reconstructible;
- running `arc-snapshots --force`;
- anything that touches `$ARC_CONSENSUS`, which holds the unrecoverable network
  identity;
- changing `--chain`, start flags or unit files on a production node;
- restarting a node that serves production RPC;
- binding any port to a non-loopback address.

Credential handling: the EL↔CL JWT, if separated hosts are in use, is never
printed or pasted. Provider RPC URLs may carry an API key in the path — redact
the path, not only the host. Avoid `docker compose config` in a shared
terminal; it prints the resolved environment.

## Diagnostic order

Work down. Stop when a step explains the symptom.

1. Both units: active? restarting? Read the **EL** logs first when the height
   is `0x0`, the **CL** logs first when it was advancing and stopped.
2. `ls -l $ARC_RUN` — both IPC sockets present?
3. `eth_chainId` — right network at all?
4. `eth_blockNumber`, twice, 30 s apart.
5. Block **hash** at a common height against an independent RPC.
6. Relay endpoints reachable from the node host; all three configured?
7. `arc_getVersion` local against the official RPC.
8. Disk free and disk **write latency**; memory against backpressure settings.
9. `ss -ltnp` for anything off loopback; `rpc_modules` for namespaces.
10. Fork schedule against the running version.

## Reporting

What was checked, what was found, what was done, what remains. For an Arc node
the report is incomplete without:

- the running release, and the release the fleet reports via `arc_getVersion`;
- local head, reference head, and **hash agreement** at a common height;
- two height samples, not one;
- which ports are bound off loopback and which namespaces `rpc_modules` shows;
- the next known fork timestamp and whether the running version satisfies it.

## `scripts/arc-healthcheck.sh`

Read-only. Runs no mutating RPC, changes nothing, prints no credential.

```bash
arc-healthcheck.sh --local --chain-id 5042
arc-healthcheck.sh --host <user>@<host> --chain-id 5042 \
  --reference https://rpc.mainnet.arc.io
```

It samples the height twice, compares the block hash against the reference
rather than the height alone, checks `arc_getVersion` against the fleet, and
fails when RPC, metrics or the CL RPC listen off loopback.

A passing check is evidence, not proof.

*Arc is a trademark of Circle Internet Group, Inc. and/or its affiliates.*
