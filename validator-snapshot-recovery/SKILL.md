---
name: "validator-snapshot-recovery"
description: "Use when recovering validator or full nodes from snapshots with integrity, state, rollback, and sync verification."
---

# Validator snapshot recovery

Use when restoring a validator, sentry, or full node from a state snapshot. Do not use for publishing snapshots.

This public skill contains no provider list or infrastructure inventory. Resolve the authorized `target_ref`, `network_ref`, role, data directory, database backend, service, chain ID, and approved snapshot sources from private knowledge and live state.

## 1. Assess before stopping

1. Confirm whether the workload signs, serves as a sentry, or is non-signing.
2. Read the current network page and canonical recovery guide.
3. Verify the current service, chain ID, version, database backend, data path ownership, sync state, and disk usage.
4. Identify the failure mode and whether snapshot recovery is actually required.
5. Calculate capacity for the archive, extracted data, retained rollback data, temporary files, and safety margin.
6. Download and validate while the current node stays online when possible.

Do not delete or replace data merely because sync is slow. A destructive replacement requires clear operator intent after preflight.

## 2. Protect keys and signer state

Always back up key-bearing configuration before deleting node data. Verify the backup exists, is non-empty, access-restricted, and stored outside the deletion target without printing contents.

Treat consensus keys, remote-signer configuration, and anti-double-sign state as separate safety boundaries:

- never open, echo, diff, or copy key contents into chat or logs;
- never blindly reset validator signing state;
- determine the chain-specific relationship between snapshot height and signer state;
- ensure no second process or host can sign with the same key;
- use a non-signing recovery path when signer-state safety cannot be proven.

Database backups may be large; obtain operator approval unless the canonical procedure already makes one necessary.

## 3. Validate the snapshot

Establish provenance and check:

- correct chain ID and environment;
- snapshot height, age, block time, and trust source;
- compatibility with node version and database backend;
- archive type, compression, layout, and expected contents;
- checksum/signature when published;
- archive integrity with the native test command;
- free space and inode headroom;
- absence of path traversal, unsafe absolute paths, device nodes, or unexpected ownership.

Compare height and freshness against multiple independent healthy RPCs when available. A downloadable archive is not sufficient evidence.

## 4. Stage and inspect

Extract into a separate staging path when space permits. Inspect whether the archive is flat or nested and locate the actual database/state root. Do not extract over the live data directory.

Preserve configuration, keys, address book decisions, and chain-specific state exactly as the canonical guide requires. Keep the old data as a rollback target until recovery is verified, unless the operator explicitly chose deletion because capacity makes rollback impossible.

## 5. Controlled cutover

1. Stop and verify the node process/container is actually stopped.
2. Prevent automation from restarting it during the swap.
3. Reconfirm key backup and signer uniqueness.
4. Move current data to the rollback location or delete only the approved paths.
5. Move staged data atomically when possible.
6. Restore required permissions and chain-specific configuration/state.
7. Start the expected workload.

Do not use broad glob deletion, follow symlinks outside the target, or remove configuration/key directories as a routine data reset.

## 6. Verify recovery

Completion requires:

- service/container active with stable restarts;
- no corruption, panic, schema, or wrong-network errors;
- expected chain ID and snapshot-derived starting height;
- height advancing toward external truth;
- acceptable peer and sync status;
- correct database backend and data ownership;
- for validators: active/not jailed state and recent signatures verified externally;
- monitoring and downstream consumers healthy.

If startup fails, preserve logs and use the defined rollback path rather than repeatedly mutating signer state. Report source/provenance, snapshot height, integrity checks, cutover method, rollback availability, and remaining catch-up.

Update private network knowledge and daily memory, but keep provider choices and environment facts out of this public skill.
