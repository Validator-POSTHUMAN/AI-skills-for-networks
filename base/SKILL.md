---
name: base-node-ops
description: "Operate Base (OP Stack L2) nodes: base-reth-node and base-consensus deployment, V2 snapshot restore, node-type and pruning choices, L1 derivation health, Flashblocks, RPC exposure and hardening, fork-deadline upgrades, incident triage, and concise operator reports."
---

# Base Node Ops

Use this skill for Base node operations: deploying `base-reth-node` and
`base-consensus`, restoring snapshots, choosing a node type, serving RPC,
monitoring derivation health, hardening exposure, keeping up with fork
deadlines, and triaging incidents.

Operator-neutral and provider-neutral. It assumes no particular hosting
provider, L1 provider, cloud or RPC customer, and contains no production hosts
or credentials.

## Read this first: what Base is not

A Base node is a **follower**. It derives the L2 chain from data the sequencer
posts to Ethereum L1 and from the sequencer's gossip feed. It does not propose
blocks, does not attest, holds no consensus key, has no stake and cannot be
slashed.

Do not carry Ethereum-staking reflexes across. There is no double-sign risk, no
slashing-protection database, no key uniqueness to prove and no unbonding clock.
**Restarting a Base node is safe. Deleting its data directory is safe.** Base is
one of the few places in validator operations where "wipe it and restore from a
snapshot" is a correct first move rather than a last resort.

The failures that do matter:

| Failure | Cost |
|---|---|
| Serving a chain the node stopped verifying | wrong answers, delivered with confidence, to every downstream consumer |
| Missing a fork deadline | the node leaves the canonical chain at a wall-clock timestamp, silently |
| RPC published to the internet | someone else's application on your hardware and your L1 bill |
| Node type chosen wrong | cannot be changed after initial sync; means a full resync |

## The failure that looks healthy

`optimism_syncStatus` reports several heads. Two of them decide everything:

- **`unsafe_l2`** comes from the sequencer's gossip feed. It advances every two
  seconds whether or not the node can reach Ethereum.
- **`safe_l2`** only advances when the node reads batches back from L1.

A node whose unsafe head is at the tip and whose safe head is frozen has stopped
verifying Ethereum and become a sequencer-trusting mirror. The process is up,
the logs are normal, `eth_blockNumber` climbs, `docker compose ps` is green, and
every height-based monitor reports success.

**Always check `unsafe_l2.number − safe_l2.number`. Never conclude from block
height alone.**

Frozen safe head is an L1 problem every time: execution RPC failing or
rate-limited, beacon endpoint pruned past the blob retention window, beacon
endpoint not serving blob sidecars, or the L1 node itself behind.

## Source Priority

1. Current command output from the target host: `optimism_syncStatus`,
   `eth_syncing`, `eth_chainId`, container or unit state, `ss`, disk, clock,
   and the logs of both services.
2. Local operator inventory and runbooks, if available.
3. Official sources:
   - https://github.com/base/base — source, releases, `docker-compose.yml`,
     `.env.mainnet`, and the two entrypoint scripts in `etc/scripts/node/`
   - https://github.com/base/base/releases — **the upgrade source of truth**
   - https://docs.base.org/specifications/node-operators/ — run, performance,
     snapshots, troubleshooting
   - https://docs.base.org/upgrades — fork schedule
   - https://chain.base.org/snapshots and https://base.org/stats
4. Community: the `🛠｜node-operators` channel in the Base Discord.

`base/node` is **archived** and read-only since 4 September 2026. Releases moved
to `base/base` at `v1.3.0`. Any instruction that starts with cloning `base/node`
is stale — say so rather than following it.

Never call a node healthy without live checks. Refresh the releases page before
quoting a version or a fork date.

## Architecture

Two processes, one image (`ghcr.io/base/node`):

- **`base-reth-node`** — execution layer. JSON-RPC `8545`, WS `8546`, Engine API
  `8551`, metrics `6060` in-container, P2P `30303` TCP+UDP, reth discv5 `9200`.
- **`base-consensus`** — rollup node, derivation. RPC `8545` in-container
  (published on `7545`), metrics `7300`, pprof `6060`, P2P `9222` TCP+UDP.

They authenticate over the Engine API with a shared hex JWT written from
`BASE_NODE_L2_ENGINE_AUTH_RAW`.

Both need an Ethereum L1 **execution RPC and beacon API**
(`BASE_NODE_L1_ETH_RPC`, `BASE_NODE_L1_BEACON`). An archive L1 is not required;
a full node is. The beacon endpoint must serve blob sidecars.

## Operational facts worth not re-deriving

| Fact | Value |
|---|---|
| Base Mainnet chain ID | `8453` / `0x2105` |
| Base Sepolia chain ID | `84532` / `0x14a34` |
| Block time | 2 s — 43,200 blocks/day |
| Mainnet sequencer | `https://mainnet-sequencer.base.org` |
| Flashblocks WS (mainnet) | `wss://mainnet.flashblocks.base.org/ws` |
| `RETH_CHAIN` / `BASE_NODE_NETWORK` | `base` or `base-sepolia` |
| reth `--full` retention | **10,064 blocks — about 5–6 hours on Base** |
| Published pruned snapshot distance | `1_339_200` (~31 days) |
| Storage formula | `(2 × chain size) + snapshot size + 20%` |
| Ingress ports | `30303` TCP+UDP, `9222` TCP+UDP |
| Egress ports for bootnodes | `30301` TCP+UDP, `9200` UDP |
| GPG fingerprint `baseup` requires | `5EFE7BCFCD85682711F9FC30904841FFEBD38BAD` |

Three traps that outdate older runbooks:

- **`--full` is not "a few days of history" on Base.** 10,064 blocks is five to
  six hours. Ethereum intuitions are wrong here by two orders of magnitude.
- **The node type is permanent.** Reth cannot convert archive ↔ full ↔ pruned
  after initial sync. Custom `RETH_PRUNING_ARGS` require the **archive**
  snapshot as the starting point and a distance above 10,064.
- **`basectl`'s mainnet preset expects the CL on `9545`**, while Compose
  publishes it on `7545`. Without an explicit `--cl-rpc`, the CL checks are
  **skipped**, not failed, and `doctor` still exits `0`.

## What this skill helps agents do

- Verify a node properly: `eth_chainId`, `eth_syncing`, then
  `optimism_syncStatus` for unsafe/safe/finalized, then an independent
  comparison against a public endpoint — height **and hash**.
- Catch the frozen-safe-head failure, and diagnose it as an L1, beacon or blob
  problem rather than a Base problem.
- Restore a V2 snapshot in the right order: download and place data first, node
  stopped, contents directly in the data directory, never nested.
- Pick a node type from what the consumers actually query, and say plainly when
  a request needs an archive node.
- Separate a routine release from a fork-critical one, and drive the upgrade to
  a verified safe head rather than to "the container is up".
- Review exposure, starting from the fact that the shipped `docker-compose.yml`
  publishes six ports on `0.0.0.0` past `ufw`, with `debug` in the RPC namespace
  list and wildcard CORS.
- Diagnose zero peers as blocked **egress** to `30301`/`9200`, not as a P2P bug.
- Recognise exit code `8` with `Could not retrieve public IP` as the rollup
  node's IP-discovery step failing, not as a node defect.

## Safety boundaries

Read-only by default. This skill does not broadcast transactions, move funds,
generate or handle keys, or mutate node state without operator approval.

Actions that require explicit operator approval before execution:

- deleting or replacing a data directory, even though it is reconstructible
- changing `NODE_TAG`, entrypoint flags or unit files on a production node
- restarting a node that serves production RPC traffic
- any `basectl` subcommand under `conductor`, `sequencer` or `proofs`, and
  `p2p add-peer`/`remove-peer`/`ban`/`unban` — these mutate state and none of
  them belong in routine follower-node operation
- exposing any port to a non-loopback address

Credential handling: `BASE_NODE_L1_ETH_RPC` and `BASE_NODE_L1_BEACON` normally
carry a provider API key in the URL. Never print them, never paste them into an
issue or a chat, and redact the path — not just the host — in any log handed to
a third party. `docker compose config` prints the resolved environment; do not
run it into a shared terminal.

`BASE_NODE_L2_ENGINE_AUTH_RAW` is committed to `.env.mainnet` as a public
constant, so every default Base node shares one engine secret. That is
survivable only because Compose does not publish `8551`. If the Engine API was
ever reachable, treat the chain data as untrusted and restore from a snapshot.
Recommend generating a per-node secret with `openssl rand -hex 32`.

## Diagnostic order

Work down. Stop when a step explains the symptom.

1. `docker compose ps` / `systemctl status` — is anything restarting or exited?
2. Logs from `base-consensus` first; it fails louder than the EL.
3. `eth_chainId` — right network at all?
4. `eth_syncing` — `false`?
5. `optimism_syncStatus` — unsafe head recent, **safe head advancing**?
6. Local head and hash against a public endpoint — same chain?
7. Peers. Zero peers ⇒ check egress to `30301` and `9200` before anything else.
8. L1 endpoints reachable from the node host; check for `429` and quota.
9. Disk free, disk latency, clock.
10. Running tag against the latest release, and against any fork deadline.

## Reporting

Report what was checked, what was found, what was done, what remains. For a
Base node the report is incomplete without:

- the running release tag
- unsafe, safe and finalized heads, and the unsafe−safe lag
- agreement with an independent public endpoint, by hash
- which ports are bound off-loopback
- the next known fork deadline and whether the running tag satisfies it

## `scripts/base-healthcheck.sh`

Read-only. Runs no mutating RPC, changes nothing, prints no credential.

```bash
base-healthcheck.sh --local --chain-id 8453
base-healthcheck.sh --host <user>@<host> --chain-id 8453 --compose-dir /opt/base
```

A passing check is evidence, not proof. Confirm the safe head has advanced over
several consecutive samples before declaring a node healthy after an upgrade or
an incident — a single sample cannot distinguish "advancing" from "stopped one
second ago".
