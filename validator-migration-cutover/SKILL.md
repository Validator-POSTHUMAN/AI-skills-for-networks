---
name: "validator-migration-cutover"
description: "Use when migrating validator workloads with freeze, key uniqueness, cutover, rollback, and downstream verification."
---

# Validator migration and cutover

Use for moving a validator, sentry, or full-node workload between authorized environments.

This public skill is environment-neutral. Resolve opaque `source_ref`, `target_ref`, `network_ref`, signing role, service, paths, dependencies, and access policy through private knowledge and live state. Never embed or infer private infrastructure.

## 1. Define the migration

Confirm:

- exact source and target;
- validator signer, remote signer, sentry, or non-signing role;
- chain ID/environment and current version;
- what moves: binary/image, config, database, identity, consensus key, signer state, monitoring, network policy;
- cutover window, freeze, success criteria, rollback boundary, and decommission boundary.

A migration request authorizes the scoped workload move. Key movement, data deletion, public endpoint changes, and source decommission require the authority applicable to those actions.

## 2. Anti-double-sign invariant

For a signing validator, the same consensus key must never be usable by two active signers.

Before any key transfer:

1. Identify the active signer from live process/container, service automation, and external recent signatures.
2. Pre-sync and validate the target without the consensus key or with signing disabled.
3. Record only safe key metadata or fingerprint; never open, echo, diff, or log secret key contents.
4. Find all mechanisms that could restart the source: systemd, containers, supervisors, upgrade managers, cron, monitoring remediation, and remote signers.
5. Define evidence that the source is stopped and fenced before the target starts.
6. Preserve chain-specific signer state and prove its monotonic relationship to the target state.

If key uniqueness or signer-state safety is uncertain, stop. Availability loss is preferable to double signing.

## 3. Prepare target and rollback

Validate the target's capacity, time synchronization, kernel/runtime, binary/image, chain ID, database backend, data ownership, firewall, P2P/RPC policy, and monitoring.

Pre-sync data while non-signing when possible. Capture source and target service definitions, immutable versions, config hashes excluding secret contents, and rollback artifacts.

Rollback is allowed only before the new signer produces blocks, unless the chain-specific procedure explicitly proves a safe reverse cutover. After target signing begins, returning to the source is a new controlled cutover.

## 4. Freeze dependent automation

Pause or account for automation that can race the cutover:

- automatic upgrade managers;
- health remediators and watchdogs;
- orchestrator restart policies;
- deployment jobs;
- monitoring actions;
- remote signer failover;
- DNS, proxy, firewall, or service-discovery automation.

Record what was frozen and how it will be restored.

## 5. Execute cutover

1. Take final source health, height, version, and signing evidence.
2. Stop the source workload.
3. Disable/fence every source autostart path and prove no signer process/container remains.
4. Transfer only the authorized artifacts through a protected channel without printing contents.
5. Verify safe metadata, ownership, permissions, and signer state on the target.
6. Start the target once.
7. Do not restart repeatedly if signing or state errors appear; preserve evidence and reassess.
8. Keep the source fenced throughout verification.

For non-signing workloads, omit key transfer but retain target, data, network, dependency, and rollback checks.

## 6. Verify

Completion requires:

- expected service/image/version on target;
- correct chain ID and advancing height;
- healthy peers and sync state;
- for validators: active/not jailed and recent signatures verified from independent external truth;
- proof source remains stopped and fenced;
- no duplicate node identity or unexpected public RPC/admin exposure;
- monitoring, sentries, relayers, RPC consumers, backups, firewall rules, DNS/proxies, and inventories point to the intended target;
- automation restored deliberately.

Report the cutover timeline, anti-double-sign evidence, target health, source fence, downstream changes, rollback status, and watch period. Keep the source intact until the separately approved decommission step. Update private infrastructure/network knowledge and daily memory without copying private facts into this package.
