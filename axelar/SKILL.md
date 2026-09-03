---
name: axelar-validator-ops
description: "Set up, monitor, upgrade, and safely recover Axelar classic validators and Amplifier verifiers."
---

# Axelar Validator Operations

Use this skill for Axelar full nodes and classic validators (`axelard`, `vald`,
and `tofnd`) and for the separate Amplifier verifier plane (`ampd`, a dedicated
`tofnd`, and one handler per supported chain).

Keep every procedure validator-neutral and provider-neutral. Load real targets,
service names, addresses, custody references, endpoints, and thresholds only
from the operator's private inventory.

## Source and freshness gate

Use evidence in this order:

1. Current target state, bounded logs, local protocol endpoints, and on-chain
   queries.
2. Operator inventory, runbooks, freezes, topology, and monitoring policy.
3. Pinned official Axelar sources in `references/source-pins.md`.
4. Current signed releases, network metadata, contract deployments, upgrade
   plans, and official security notices.
5. Independent RPCs and explorers only as secondary confirmation.

Refresh moving release, network, contract, genesis, seed, and parameter data
before a production change. The pinned sources document behavior; they do not
freeze current network values or authorize execution.

## Inventory gate

Before mutation, resolve:

- environment, exact chain ID, role, host, runtime, service names, home, data
  path, local RPC/gRPC/metrics, and independent reference endpoint;
- running binary paths, versions, checksums, release provenance, upgrade plan,
  database backend, capacity, backup, and rollback path;
- for classic validators: valoper, consensus address, broadcaster address,
  classic `tofnd`, `vald`, key-custody references, and intended maintainer
  chains;
- for Amplifier: its own Axelar full node, `ampd`, Amplifier-only `tofnd`,
  monitoring endpoint, handler-to-chain map, and one operator-controlled full
  node or light client per supported chain;
- alert thresholds and expected process, listener, firewall, and dependency
  boundaries.

Use `references/inventory.schema.json` and the fake
`examples/inventory.example.json` when a machine-readable inventory is useful.
Stop if identity, role, signer uniqueness, chain support, or rollback evidence
is ambiguous.

## Non-negotiable safety

- Never expose, copy, generate, rotate, or move key material through this
  skill. Key creation/import is a separate operator-controlled custody
  ceremony.
- Never start a second process capable of using the same consensus or threshold
  key. Prove signer uniqueness before start, migration, or recovery.
- Never auto-create a validator, stake, register a broadcaster, change
  maintainer or Amplifier support, bond, register keys, sign, or broadcast.
- Treat every transaction as a separate approval boundary. This skill may only
  produce an unsigned `--generate-only` classic transaction or a non-runnable
  Amplifier review record; it never signs or broadcasts.
- Ask before data replacement, snapshot restore, signer change, unjail,
  staking, registration, funding, firewall/public exposure, or transaction
  broadcast.
- Keep classic `vald` and Amplifier `ampd` on different `tofnd` instances.
  Prefer a separate Axelar full node for Amplifier, as official onboarding
  guidance requires for testnet/mainnet resilience.
- Bind signer, handler, gRPC, and monitoring listeners to loopback or a reviewed
  private network. Do not use passwordless signer containers or wildcard
  signer binds.
- Preserve `priv_validator_state.json`, classic `vald/state.json`, Amplifier
  `state.json`, configs, and protected signer backups. Never print secret
  contents.
- During a network halt, upgrade boundary, AppHash divergence, or deterministic
  panic, preserve evidence and avoid restart loops.

## Route the task

- New classic full node or validator: read `references/classic-setup.md`.
- Broadcaster or external-chain maintainer review: use the transaction and
  coupling gates in `references/classic-setup.md`.
- New Amplifier verifier or chain: read
  `references/amplifier-verifier.md`; onboarding remains review-only.
- Monitoring design, alert handling, or post-install acceptance: read
  `references/monitoring.md`.
- Snapshot recovery: read `references/safe-recovery.md` and run the bundled
  verifier before any approved cutover.
- Upgrade: follow the workflow below and current official release instructions.

## Read-only baseline

Use `scripts/axelar-healthcheck.sh` for a classic validator when its required
inventory is complete. It checks service state, block freshness, sync, peers,
recent signatures, staking status, classic `tofnd`, broadcaster balance/proxy,
maintainer membership, and bounded `vald` errors.

```bash
scripts/axelar-healthcheck.sh \
  --host <ssh-target> \
  --node-service <axelard-service> \
  --vald-service <vald-service> \
  --tofnd-service <classic-tofnd-service> \
  --rpc http://127.0.0.1:<rpc-port> \
  --expected-chain-id <EXACT_AXELAR_CHAIN_ID> \
  --valcons <HEX_CONSENSUS_ADDRESS> \
  --valoper <axelarvaloper...> \
  --broadcaster <axelar1...> \
  --public-rpc https://<independent-rpc> \
  --maintainer-chain <chain-name>
```

Use `--local` only when already on the intended target. Set operator-approved
freshness, signing-window, and broadcaster thresholds. A passing built-in
`health-check` does not replace fresh consensus, signature, maintainer, process,
and independent-height evidence.

For Amplifier, run `scripts/axelar-amplifier-healthcheck.sh` on the separate
Amplifier target, then complete the chain-native and on-chain checks in
`references/monitoring.md`. The helper verifies process boundaries, private
`tofnd`/handler gRPC reachability, Axelar freshness, handler/client service-set
parity, `/status`, `/metrics`, and bounded error counts; it deliberately cannot
prove source-chain finality, vote correctness, or on-chain authorization.

## Incident workflow

1. Resolve the exact plane, chain ID, role, target, service, signer identity,
   and affected external chain from trusted inventory.
2. Compare local and independent height/block time. Verify classic signatures
   or Amplifier input/vote progress as applicable.
3. Capture service states, restart counts, listeners, resources, dependencies,
   and bounded logs before mutation.
4. Classify consensus failure, classic `vald`/broadcaster/maintainer failure,
   classic or Amplifier `tofnd` failure, `ampd` failure, one handler/client
   failure, network halt, upgrade boundary, or data corruption.
5. Restart at most the smallest proven failed boundary. Do not restart
   `axelard` for a `vald`-only or handler-only fault.
6. After action, repeat the complete plane-specific acceptance gate.

For classic sequence drift, first exclude concurrent broadcaster use, local RPC
latency, mempool/confirmation failure, and out-of-gas. For an Amplifier chain
fault, keep unaffected handlers running; verify the handler, its exact chain
client, `ampd` gRPC path, and chain-specific finality configuration.

## Upgrade workflow

1. Confirm the on-chain plan and exact affected plane/components.
2. Pin the official release tag/commit, release notes, signatures/checksums,
   build requirements, compatibility, and any config migration.
3. Capture resolved binaries, services, configs, state files, signer uniqueness,
   capacity, backup, and rollback evidence.
4. Stage and verify artifacts without switching live processes early.
5. Change one dependency boundary at a time. Keep classic and Amplifier signer
   stores separate.
6. Verify exact running binaries, advancing/fresh Axelar state, stable restart
   counts, classic signing and maintainer duties, or Amplifier `ampd`/handler
   progress and per-chain client health.

Do not infer versions from a moving docs page, use an unreviewed branch, or roll
back across an undocumented state/schema migration.

## Recovery

Use the smallest reversible fix. For snapshots, fully download and verify an
operator-trusted checksum and safe archive layout with
`scripts/axelar-snapshot-verify.sh`; never stream into live data. Preserve
signer state and rollback data, then prove external signing after an approved
validator cutover. `references/recovery-validation.md` is bounded historical
evidence, not authorization for a new target.

Do not replace Amplifier `state.json`, handler configuration, or either `tofnd`
store with classic validator data. Restore each plane from its own protected,
verified backup and re-establish one signer instance before start.

## Completion gate

Complete only when the requested plane is installed or restored, all intended
services and listeners match inventory, chain data is fresh and independently
confirmed, classic signing/maintainer duties or Amplifier vote/handler duties
are proven, monitoring is active, restart counts are stable, no transaction or
key boundary was crossed without approval, rollback is clear, and residual
limitations are reported.