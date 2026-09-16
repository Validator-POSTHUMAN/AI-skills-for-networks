---
name: espresso-validator-ops
description: "Operate Espresso validators and query nodes on Mainnet/Decaf: consensus view liveness, time-since-last-decide, participation scoring, cliquenet P2P triage, three-key custody (BLS/Schnorr/x25519), staking-cli registration and rotation on Ethereum, delegation and reward claims, storage pruning, upgrades, and concise operator reports."
---

# Espresso Validator Ops

Use this skill for Espresso node operations: validator and query-node health
checks, consensus liveness triage, missed-proposal investigation, P2P
connectivity failures, key generation and rotation, on-chain registration and
commission changes with `staking-cli`, delegation and reward claims, storage
and pruning decisions, version upgrades, and operator reports.

## Source Priority

1. Current command output from the target host, its local status API, and the
   network's public query service.
2. Local operator inventory and runbooks, if available.
3. Official Espresso sources:
   - https://docs.espressosys.com/network/developer/operators/run-a-node
   - https://docs.espressosys.com/network/developer/operators/run-a-node/p2p-troubleshooting
   - https://docs.espressosys.com/network/network/networks
   - https://docs.espressosys.com/network/developer/espresso-api/status-api
   - https://docs.espressosys.com/network/llms.txt
   - https://github.com/EspressoSystems/espresso-network
   - https://github.com/EspressoSystems/espresso-network/blob/main/staking-cli/README.md
   - https://github.com/EspressoSystems/espresso-for-dummies
4. Block explorers, third-party dashboards, and community guides only as
   secondary confirmation.

Never claim an Espresso validator is healthy, participating, registered, or
upgraded without live checks.

## Espresso Is Not Cosmos And Not A Normal EVM Chain

Do not carry over assumptions from either family.

- No `valoper` address, no Tendermint/CometBFT RPC, no `genesis.json` or
  `addrbook.json` download, no state-sync, no snapshot service, no `unjail`.
- No missed-block counter, no signing window, no jail state. Liveness is
  measured in **consensus views**; proposal quality is measured by a
  **participation score** published by query nodes.
- Consensus runs on the Espresso network; **registration, stake, commission and
  rewards live in contracts on Ethereum**. Staking operations are L1
  transactions, not chain messages.
- The validator's Ethereum address is not present on the node at all.

## Chain Facts

Publication-time defaults, verified 2026-09-16 against the official operator
documentation (node release `20260910`). Refresh before acting.

- Networks: **Mainnet** (L1: Ethereum) and **Decaf testnet** (L1: Ethereum
  Sepolia). Commands and environment variables are identical; only contract
  addresses, endpoints and the genesis file differ.
- Node image: `ghcr.io/espressosystems/espresso-network/espresso-node:<tag>`;
  binary `espresso-node`. Staking CLI image:
  `ghcr.io/espressosystems/espresso-network/staking-cli:main`.
- Genesis inside the image: `/genesis/mainnet.toml`, `/genesis/decaf.toml`.
- Mainnet endpoints: query `https://query.main.net.espresso.network`,
  config cache `https://cache.main.net.espresso.network`, state relay
  `https://state-relay.main.net.espresso.network`, explorer
  `https://explorer.main.net.espresso.network`, staking UI
  `https://stake.espresso.network/`.
- Decaf endpoints: query `https://query.decaf.testnet.espresso.network`,
  cache `https://cache.decaf.testnet.espresso.network`, state relay
  `https://state-relay.decaf.testnet.espresso.network`, explorer
  `https://explorer.decaf.testnet.espresso.network`, staking UI
  `https://stake.decaf.espresso.network/`.
- Mainnet contracts (Ethereum): Stake Table
  `0xCeF474D372B5b09dEfe2aF187bf17338Dc704451`, ESP token
  `0x031De51F3E8016514Bd0963d0B2AB825A591Db9A`, Reward Claim
  `0x67c966a0ecdd5c33608be7810414e5b54da878d8`, Light Client
  `0x95ca91cea73239b15e5d2e5a74d02d6b5e0ae458`, Fee
  `0x9fcE21c3F7600Aa63392A5F5713986b39bB98884`.
- Decaf contracts (Sepolia): Stake Table
  `0x40304fbe94d5e7d1492dd90c53a2d63e8506a037`, ESP token
  `0xb3e655a030e2e34a18b72757b40be086a8f43f3b`, Reward Claim
  `0xe81908e34dbb4ba01f27f8769264199727be50c8`, Light Client
  `0x303872bb82a191771321d4828888920100d0b3e4`.
- Ports: cliquenet P2P `9977/tcp` inbound from the public internet
  (`ESPRESSO_NODE_CLIQUENET_BIND_ADDRESS`); API/metrics/query
  `ESPRESSO_NODE_API_PORT`, default `8080`, loopback or reverse proxy only.
  The node serves plain HTTP.
- Environment prefixes: `ESPRESSO_NODE_` for node settings, `ESPRESSO_L1_` for
  L1 client settings, plus `ESPRESSO_STATE_RELAY_SERVER_URL`.
- Active set: a dynamic, permissionless **100 nodes**; each epoch (~24 h) the
  100 nodes with the most delegated stake form the active set.
- Timing: registered values active in **2–3 epochs**; delegations active
  **2 epochs** after L1 finalization; minimum delegation **1 ESP**; undelegation
  escrow **~7 days**; rotated consensus keys active in the **third epoch**.
- Commission: percentage points with 2 decimals; one increase per 7 days,
  capped at 500 bps; decreases unrestricted; identical value reverts with
  `CommissionUnchanged`.
- Hardware observed for a pruned query validator: 4 cores, 8 GB RAM, 500 GB SSD
  (plus 2 cores / 4 GB for a separate Postgres). Archival: 2.5 TB SSD; a
  mainnet archival node measured ~1.7 TB in September 2026, growing ~215 GB per
  month.

## Network Mode

Identify the target network before choosing endpoints, contract addresses,
`staking-cli --network`, alert labels, or recovery instructions.

- Mainnet: real ESP and real gas. Every `staking-cli` call is a production
  Ethereum transaction. Require explicit operator approval.
- Decaf: rehearsal environment on Sepolia. Decaf ESP is not publicly
  distributed — a registered node stays out of consensus until the Espresso
  team delegates to it in `#decaf-node-ops` on Discord.
- Never reuse mainnet consensus keys, Ethereum accounts, metadata URIs, or
  alert routes on Decaf, or the reverse.

Confirm the network from the node's own configuration
(`ESPRESSO_NODE_GENESIS_FILE`, `STAKE_TABLE_ADDRESS`) before interpreting any
state or reporting health.

## Operator Inventory Guardrails

This skill is validator-neutral and server-neutral. It must not assume a
specific team, host, container name, endpoint, validator address, key path, or
provider.

Load the operator's Espresso inventory from their knowledge base, runbook,
monitoring config, or explicit task input. Required target fields:

- Network: `mainnet` or `decaf`.
- Host or SSH target, and whether the node runs under Docker Compose.
- Local API base URL and port.
- Registered validator Ethereum address and account index.
- Node BLS public key (`BLS_VER_KEY~…`), used to read participation scores.
- Registered P2P address and x25519 public key.
- Key file path and custody model (key file, mnemonic env, Ledger).
- L1 provider, and whether a WebSocket provider is configured.
- Storage backend (SQLite or Postgres), storage path, and pruning policy.
- Expected image tag.

`references/inventory.schema.json` describes the machine-readable form.
`examples/inventory.example.json` holds fake values only — never treat it as
production inventory.

If inventory is missing, inconsistent, or ambiguous, ask the operator before
restarting the node, editing configuration, sending any L1 transaction,
replacing storage, or touching keys.

## Safety Rules

- **Consensus-key uniqueness is an invariant.** The reviewed documentation
  describes no slashing mechanism; that is not permission to run two processes
  with the same key file. Before any migration, restore, or "just start it on
  the new host", prove the old process cannot sign: the container is gone, the
  ports are not listening, and the old P2P address no longer answers an `nc`
  probe.
- Never paste or echo a private staking key, state key, x25519 private key,
  node mnemonic, Ethereum mnemonic, or an L1 provider URL containing an API key
  into reports, examples, logs, command lines, or skill files. Read secrets from
  the key file into environment variables.
- Treat every `staking-cli` subcommand that signs as a funds-affecting
  production action: `register-validator`, `update-*`, `delegate`,
  `undelegate`, `claim-rewards`, `claim-withdrawal`, `deregister-validator`,
  `claim-validator-exit`. Require explicit operator approval, confirm the
  network and the exact address first, and report the transaction hash.
- `deregister-validator` removes the node from the active set immediately,
  unbonds every delegator, and starts a ~7-day escrow. Claim accrued rewards
  **before** deregistering — deregistration does not claim them.
- Registered values are on-chain state, not configuration. Fix a wrong P2P
  address or x25519 key by re-registering with `staking-cli`, never by editing
  node environment variables alone.
- Consensus key rotation is time-shifted. Swap the node's key file only in the
  third epoch after `update-consensus-keys`, not immediately.
- `/healthcheck` is a static HTTP liveness probe. It is never evidence of
  consensus health.
- Do not restart the node because one metric looks wrong. Distinguish a local
  failure from a network-wide one first: current view advancing while decides
  stall is network-wide.
- Never delete or replace `ESPRESSO_NODE_STORAGE_PATH` as a troubleshooting
  step without operator approval and a stated recovery path. Rolling back an
  upgrade means rolling back the image tag and environment, not the data.
- Do not publish the API port. If the operator wants a public query service,
  treat it as a separate product with its own hostname, TLS, and rate limits.
- Do not put a byte-inspecting proxy in front of the P2P port. Cliquenet is a
  server-first protocol and buffering the opening bytes deadlocks connections.

## Health Check Workflow

Use the bundled script when possible:

```bash
scripts/espresso-healthcheck.sh \
  --host <ssh-target> \
  --network mainnet \
  --api http://127.0.0.1:8080 \
  --bls-key 'BLS_VER_KEY~...' \
  --validator-address 0x... \
  --expected-tag 20260910
```

Use `--local` instead of `--host` when already on the target host.

Manual equivalent:

```bash
API=http://127.0.0.1:8080

# 1. Consensus liveness — both must advance between two reads.
curl -fsS "$API/v1/status/metrics" | grep -E '^consensus_(current_view|last_decided_view) '
sleep 30
curl -fsS "$API/v1/status/metrics" | grep -E '^consensus_(current_view|last_decided_view) '

# 2. The single best liveness signal.
curl -fsS "$API/v1/status/time-since-last-decide"

# 3. Missed proposals. Every increment warrants investigation.
curl -fsS "$API/v1/status/metrics" | grep '^consensus_number_of_timeouts_as_leader'

# 4. Peer mesh, including whether anything has ever reached the node inbound.
curl -fsS "$API/v1/status/metrics" | grep consensus_cliquenet

# 5. Running image tag.
curl -fsS "$API/v1/status/metrics" | grep '^consensus_version'

# 6. Participation, read from another query node.
curl -fsS "https://query.main.net.espresso.network/node/participation/proposal/current"
curl -fsS "https://query.main.net.espresso.network/node/participation/vote/current"

# 7. On-chain registration.
docker run --rm ghcr.io/espressosystems/espresso-network/staking-cli:main \
    staking-cli --network mainnet stake-table-entry --address "$VALIDATOR_ADDRESS"
```

Some releases serve the unversioned path `/status/metrics`. Try the versioned
path first and fall back; never report "metrics unavailable" on one path alone.

Reporting rules:

- A healthy participation score is close to `1.0`; below `0.95` warrants
  investigation. A dip lasting up to one epoch after a restart or outage is
  expected, not a finding.
- `consensus_cliquenet_*` series are created lazily. A missing series is
  information, not a failed check — state which series were absent.
- `stake-table-entry` must show `Status: Active`, the node's x25519 public key,
  and the exact registered P2P address. `not set` means the validator predates
  the V3 stake table and peers cannot dial it at all.

## P2P Triage Workflow

Connectivity failures are almost always a blocked or buffered port, a wrong
registered value, or a mismatched x25519 key. Work cheapest first.

**1. Probe the public port from outside the host.** A healthy node writes four
bytes without being sent anything.

```bash
nc -d -w3 $PUBLIC_HOST 9977 | xxd                              # control
printf "\x00\x01\x00\x01" | nc -w3 $PUBLIC_HOST 9977 | xxd     # peer-like
printf "\x00\x01\x00\x01\x00" | nc -w3 $PUBLIC_HOST 9977 | xxd # past sniffer minimum
```

Expect `00 01 00 01` from all three. Probes 1 and 2 empty while 3 succeeds is
the signature of a byte-inspecting filter with a minimum-bytes threshold.
All three empty with a successful connection means something holds the
connection without forwarding, or nothing is listening. Refused or timed out is
a firewall or port-mapping problem, not a sniffer.

**2. Compare the registration** with `stake-table-entry` — the P2P address must
be the host and port the probe succeeded against, and the port must match
`ESPRESSO_NODE_CLIQUENET_BIND_ADDRESS` after any mapping.

**3. Check the node's x25519 key** in its own logs:

| Log line                                                          | Cause                                                              |
| ----------------------------------------------------------------- | ------------------------------------------------------------------ |
| `No x25519 key provided…`                                         | No persistent key; a random ephemeral key on every start           |
| `migrated deprecated env var  old="ESPRESSO_SEQUENCER_KEY_FILE"`  | A legacy key file silently took over x25519 configuration          |
| `handshake failed  err="noise error: decrypt error"` (many peers) | The node holds a different key than the one registered on-chain    |

A key file takes over x25519 configuration entirely: the key must be an
`ESPRESSO_NODE_PRIVATE_X25519_KEY=…` line inside that file. Setting it in the
environment does not work, and a key file without that line starts with no
error.

**4. Read cliquenet metrics.** The decisive question is whether the node has
**inbound** hellos: its own outbound dials can keep `peer_tasks` looking healthy
while the inbound path is completely broken.

- `peer_tasks` absent or `0` — no mesh connections at all.
- No `hellos` series at all — nothing has ever reached the node inbound.
- `hellos` present for a key but no connection — the node rejects them; look for
  `party has invalid ip addr` and `unknown party`.
- `connect_attempts` climbing for a peer with no established connection —
  misregistered P2P address or x25519 key; re-register, do not edit env.
- `errors` rising for one peer — byte corruption in the path, such as TLS
  termination or a PROXY protocol header.

`connect_attempts` is not a retry counter. One dial task retries internally and
never gives up, so it sits at `1` per peer while the first dial is outstanding.

## Storage And Pruning

- **Consensus storage** is a bounded working set with automatic view-based
  garbage collection, targeting ~1 GB. Operators should not tune it. Size a
  non-query validator for write throughput, not accumulated history.
- **Query database** retains everything unless pruning is enabled. Setting any
  retention variable without `ESPRESSO_NODE_DATABASE_PRUNE=true` has no effect.
- Setting both target and minimum retention to the same value makes it a hard
  window rather than a target. The `STATE_` variables cover the Merklized state
  tables, which otherwise prune at a 7-day default.
- Pruning does **not** shrink the database to the retention window: the hash and
  aggregate tables are never pruned, Merkle state keeps the newest node at every
  path, and on Postgres the pruner skips `VACUUM`. Provision for peak usage.
- Durations take one integer and one unit (`ns mc ms s m h d w`) or a colon
  form. A bare number of seconds is rejected.
- `storage-fs` supports neither pruning nor state catchup. Use SQL storage for
  any node running the query module.
- `ESPRESSO_NODE_ARCHIVE=true` clears the pruning watermark so the node
  backfills from peers; it conflicts with `ESPRESSO_NODE_DATABASE_PRUNE`.

## Upgrade Workflow

1. Read the release notes for the target tag in `espresso-network/releases`.
2. Record the running tag from `consensus_version{desc=…}` and the current
   consensus views.
3. Pin the exact new tag — never `:latest` or a floating tag.
4. Pull and recreate the container. Preserve the storage volume and the key
   volume.
5. Expect database migrations; they are IO-bound and can take a while. More
   provisioned IOPS temporarily makes them substantially faster.
6. Verify both views advance again, `time-since-last-decide` returns to normal,
   peers reconnect, and `consensus_version` reports the intended tag.
7. Keep the previous tag and environment file available for rollback.

Do not report an upgrade complete on container state alone.

## Staking And Rewards Workflow

All of these are Ethereum transactions signed by the registering wallet. Prefer
a Ledger on mainnet (`--ledger --account-index N`); a raw private key or
mnemonic is acceptable only on a dedicated signing host or on Decaf.

| Intent                     | Command                                    |
| -------------------------- | ------------------------------------------ |
| Register                   | `register-validator`                       |
| Inspect on-chain entry     | `stake-table-entry --address <addr>`       |
| Rotate consensus keys      | `update-consensus-keys`                    |
| Rotate x25519 and P2P      | `update-network-config`                    |
| Change commission          | `update-commission --new-commission <x>`   |
| Change metadata            | `update-metadata-uri`                      |
| Check accrued rewards      | `unclaimed-rewards`                        |
| Claim rewards              | `claim-rewards`                            |
| Exit the set               | `deregister-validator`                     |
| Withdraw principal         | `claim-validator-exit --validator-address` |

Reward commands need `ESPRESSO_URL` pointing at a query service. The ESP token
address is read from the stake table contract. Rewards do not auto-compound.

Before any of them: confirm the network, the stake table address, the signing
account index, and that the operator approved this exact action. After: report
the transaction hash and state which epoch the change takes effect in.

Delegation and undelegation for ordinary holders happen in the official staking
UI. Only one undelegation can be pending per validator at a time — claim each
withdrawal before starting another from the same validator.

## Monitoring Baseline

Alert on, at minimum:

- `consensus_current_view` not advancing for ~2 minutes (critical);
- `consensus_last_decided_view` not advancing while the current view does
  (critical, and likely network-wide);
- `/status/time-since-last-decide` above a few multiples of the view interval;
- any increase in `consensus_number_of_timeouts_as_leader` (warning);
- `absent(consensus_cliquenet_peer_tasks)` or a value of `0` (critical);
- `absent(consensus_cliquenet_hellos)` sustained (warning — inbound path);
- participation score below `0.95` for more than one epoch;
- `process_open_fds` approaching the limit, and resident memory growth;
- image tag drift across the fleet;
- L1 provider errors, rate limits, or a stalled L1 head.

Database size is not exposed as a metric. Watch it at the OS or Postgres level.

## Reporting

Report in this shape, and never fill a gap with an assumption:

1. Target: network, host, image tag, storage backend.
2. Consensus: current view, last decided view, seconds since last decide,
   movement observed between two reads.
3. Participation: proposal and vote score for the operator's BLS key, and the
   epoch they were read from.
4. Peers: established connections, whether inbound hellos exist, notable
   per-peer errors.
5. Registration: status, commission, registered P2P address and x25519 key as
   the stake table holds them.
6. Resources: storage-path size, memory, file descriptors.
7. Actions taken, with transaction hashes and the epoch they take effect in.
8. What remains unverified, and what to check next.
