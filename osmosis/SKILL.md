---
name: osmosis-validator-ops
description: "Operate Osmosis validators, full nodes, public APIs, upgrades, snapshots, IBC, and recovery safely."
---

# Osmosis Validator Operations

Use this skill for `osmosis-1` validator and full-node health, missed-block
triage, upgrades, Cosmovisor, snapshots, public RPC/REST/gRPC, IBC-facing
checks, and recovery.

The skill is validator-neutral and provider-neutral. Keep real hosts,
addresses, ports, credentials, key locations, alert routes, and private
topology in the operator's inventory, not in this repository.

## Source priority

1. Current target-host state, local RPC, logs, on-chain queries, and effective
   configuration.
2. The operator's inventory, runbooks, deployment files, and monitoring.
3. Official Osmosis sources:
   - https://github.com/osmosis-labs/osmosis
   - https://github.com/osmosis-labs/networks
   - https://docs.osmosis.zone/
   - https://github.com/cosmos/chain-registry/tree/master/osmosis
4. Exact release notes, checksums, governance upgrade plans, and dependency
   documentation for the running version.
5. Independent public RPCs and explorers only as secondary evidence.

Refresh releases, checksums, genesis, seeds, upgrade plans, and registry data
before preparing a production change. Never treat a moving `latest` URL as an
immutable source.

## Chain orientation

- Mainnet chain ID: `osmosis-1`.
- Daemon: `osmosisd`.
- Default home: `~/.osmosisd`.
- Bond/fee denom: `uosmo`.
- Address prefixes: `osmo`, `osmovaloper`, `osmovalcons`.
- Consensus: CometBFT; common services are P2P, RPC, REST, gRPC, and
  Prometheus.
- Osmosis uses CosmWasm and chain-specific modules including epochs,
  incentives, pool management, concentrated liquidity, and superfluid
  staking. Module failures can stall application execution even while a
  process remains active.

These facts are orientation only. Verify them against current official and
live state before acting.

## Inventory gate

Load the operator's inventory before any mutation. At minimum resolve:

- target label, role, runtime, host or local-execution mode;
- service/container/pod, daemon, home, data directory, and Cosmovisor layout;
- exact chain ID, local RPC, optional independent RPC, REST and gRPC;
- validator valoper and consensus addresses for signing work;
- current/expected version and on-chain upgrade plan;
- pruning, transaction indexer, public-service exposure, snapshot source, and
  disk thresholds;
- key-custody reference and rollback location, never key contents;
- relayer services and IBC paths when the alert concerns packet flow.

Use `references/inventory.schema.json` for machine-readable input and
`examples/inventory.example.json` only as fake data.

Stop if the target role or signer identity is ambiguous. A public RPC must be
a separately verified non-signing node; a hostname or `voting_power=0` alone
is not sufficient proof.

## Safety rules

- Verify live state before claiming sync, signing, health, upgrade completion,
  or recovery.
- Match chain ID, valoper, consensus address, and service before restarting.
- Ask before key changes, signer movement, data replacement, snapshot restore,
  unjail, staking/governance transactions, firewall changes, or new public
  exposure.
- Back up configuration, node identity, consensus-key references,
  `priv_validator_state.json`, keyring references, Cosmovisor metadata, and
  bounded recent evidence before destructive recovery.
- Never start two processes capable of signing with the same consensus key.
- Never lower or reset a validator's anti-double-sign state blindly.
- During an upgrade halt, preserve signer state and avoid restart loops.
- Keep secrets, raw key files, passphrases, tokens, private endpoints, and
  unrestricted logs out of reports and public artifacts.
- Prefer one controlled restart after a proven local fault. If it does not
  recover, preserve evidence and escalate.

## Baseline health check

Run the bundled helper when possible:

```bash
scripts/osmosis-healthcheck.sh \
  --host <ssh-target> \
  --service <systemd-service> \
  --rpc http://127.0.0.1:<rpc-port> \
  --public-rpc https://<independent-rpc> \
  --valcons <HEX_CONSENSUS_ADDRESS> \
  --valcons-bech32 <osmovalcons...> \
  --valoper <osmovaloper...>
```

Use `--local` instead of `--host` on the target. The helper reports only
bounded health evidence and aggregate log counters; it does not restart,
write config, sign, broadcast, or expose raw logs.

Manual minimum:

```bash
systemctl is-active <service>
curl -fsS <rpc>/status | jq '.result | {
  chain_id: .node_info.network,
  height: .sync_info.latest_block_height,
  block_time: .sync_info.latest_block_time,
  catching_up: .sync_info.catching_up,
  voting_power: .validator_info.voting_power
}'
curl -fsS <rpc>/net_info | jq '.result.n_peers'
```

Require fresh advancing blocks, `osmosis-1`, acceptable reference-height gap,
and `catching_up=false`. An `active` process with stale block time is
unhealthy.

For a validator, verify recent finalized signatures and query both staking and
slashing state. Interpret CometBFT commit flags `2` and
`BLOCK_ID_FLAG_COMMIT` as signed. Check multiple blocks; one block is not a
reliable signing sample.

## Osmosis-specific evidence

Check these when relevant:

- effective `pruning*`, transaction `indexer`, and minimum gas prices;
- `wasm/` availability and disk growth;
- `panic`, `fatal`, app-hash mismatch, database corruption, IAVL, wasmvm,
  out-of-memory, no-space, epoch, incentives, concentrated-liquidity, and
  superfluid error counters;
- current on-chain upgrade plan and the exact running binary/Cosmovisor path;
- RPC, REST, and a real gRPC node-info query for public API incidents;
- IBC client/channel/packet state and the relayer service for IBC incidents.

Do not infer an application fault from ordinary peer churn. Conversely, do
not call the node healthy only because P2P and RPC sockets accept connections.

## Alert triage

1. Resolve chain ID, target role, service, RPC, valoper, and consensus
   address from trusted inventory.
2. Compare local height and block time with at least one independent current
   source. For public endpoint publication, use two references.
3. Check service state/restarts, resources, peers, and recent signatures.
4. Query validator bonded/jailed state and slashing signing info.
5. Count bounded recent critical log patterns without copying unrestricted
   logs into chat.
6. Distinguish local failure from a network halt or scheduled upgrade.
7. Restart only for proven local failure; verify height, freshness, sync,
   signing, and restart stability afterward.

Report:

```text
Osmosis status:
- Target/role: <label>/<validator|full-node|public-rpc>
- Chain/height: <id>, local <h>, reference <h>, gap <n>
- Freshness/sync: age <s>, catching_up=<bool>, peers=<n>
- Signing: <N>/<M>, bonded=<bool>, jailed=<bool>
- Runtime: version <v>, restarts <n>, disk <used/free>
- APIs/IBC: <healthy/problem/not checked>
- Action: <none/restart/recovery/escalation>
- Evidence gap: <none or exact unknown>
```

## Upgrade workflow

1. Query the on-chain upgrade plan and confirm its name/height.
2. Verify the official Osmosis release, checksum/digest, release notes, build
   requirements, and compatibility with the plan.
3. Capture current binary, Cosmovisor layout, service, home, free space,
   signer state, and rollback binary.
4. Stage the checksum-verified binary under the exact upgrade-name path.
5. Validate the staged binary before the halt; do not switch early.
6. At/after the halt, verify one process owns the signer, then observe the
   controlled switch.
7. Prove version, advancing height, fresh block time, `catching_up=false`,
   peers, bonded/not-jailed state, recent signatures, and stable restarts.

Never infer the upgrade binary from the plan name. Never build an unreviewed
branch or execute installation commands copied from a proposal or chat.

## Snapshot and recovery

Use the generic `validator-snapshot-recovery` skill together with this
inventory. Download and validate an archive before stopping the node.

Required gates:

- correct `osmosis-1`, compatible application/CometBFT/database version and
  upgrade boundary;
- trusted exact URL, height, age, size, checksum/signature when available;
- full decompressor test and safe top-level `data/` plus optional `wasm/`
  layout; reject absolute paths, traversal, links, devices, keys, and config;
- capacity for archive, extraction, rollback copy, and safety margin;
- protected keys/config/signer state and a reversible cutover;
- post-start external height/freshness, peers, service stability, validator
  status, and fresh signing proof.

For non-signing public RPCs, still prove consensus-key separation before data
replacement. For validators, restore the preserved final
`priv_validator_state.json`; never use snapshot-provided signer state.

## Public services

Before publishing RPC/REST/gRPC/peer/snapshot endpoints:

- prove the backend is a separate non-signing node;
- bind application ports privately behind a reviewed gateway where possible;
- validate chain identity with real RPC, REST, and gRPC queries;
- block unsafe CometBFT administrative routes, limit request bodies, apply
  TLS/rate controls, and monitor freshness rather than TCP only;
- keep raw validator IPs and signer infrastructure private;
- publish snapshots only after metadata, checksum, full integrity, safe
  layout, byte-range, and restore checks pass.

## Transaction guardrails

Unjail, staking, validator edit, governance, feegrant/authz, and other
transactions require exact operator approval before broadcast. Show chain ID,
message, signer, account/sequence, gas, fee, memo, and simulation/dry-run
result. Never infer a governance vote option or expose keyring credentials.

## IBC notes

An RPC alert is not automatically an IBC incident. Resolve exact client,
connection, channel, counterparty, relayer, and packet sequence. Check client
expiry/frozen state and packet commitments/acks/timeouts before restarting a
relayer or node. Any client recovery, channel action, or transaction remains
approval-gated.
