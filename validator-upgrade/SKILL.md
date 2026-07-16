---
name: "validator-upgrade"
description: "Use when planning or executing validator upgrades with source, migration, restart, and signing verification gates."
---

# Validator upgrade

Use for planned validator binary, image, package, runtime, hard-fork, or protocol upgrades.

This public skill is environment-neutral. Resolve the authorized `target_ref`, `network_ref`, service, expected chain, current version, signing role, and maintenance constraints from private knowledge and live state. Never embed or guess inventory.

## 1. Establish authority and source

1. Confirm the exact requested network and environment.
2. Read the current network page, upgrade schedule, freeze/cutover notes, and canonical upgrade guide.
3. Verify the release from official project documentation, repository, or signed distribution.
4. Match tag, commit, architecture, package/image, chain, upgrade height or time, and checksum/signature when provided.
5. Treat release notes, migrations, database requirements, config changes, and breaking flags as part of the upgrade.
6. Stop on source ambiguity, checksum mismatch, wrong network, or conflicting instructions.

Do not expose credentials, key material, environment files, or full private inventory.

## 2. Classify the upgrade

Determine whether execution is:

- automatic upgrade manager;
- pre-staged binary switch;
- manual service replacement;
- container image rollout;
- package or runtime update;
- hard-fork with a height/time gate;
- state, database, genesis, or configuration migration.

Identify what must not happen early. Respect project cohorts, embargoes, staged rollout windows, and operator freezes.

## 3. Preflight

Before mutation, record:

- current binary/image and immutable version evidence;
- service/container state, restart count, recent logs, height advance, peers, and sync status;
- validator bonded/active, not jailed, recent signing, and external network truth;
- disk, memory, archive space, ownership, and executable architecture;
- active upgrade manager and its plan;
- database backend and schema when relevant;
- rollback artifact, prior config, and safe rollback boundary;
- downstream monitors, RPC consumers, relayers, sentries, and automation that may restart the workload.

An upgrade request authorizes normal reversible upgrade work. Ask separately before key movement, destructive data replacement, undocumented database migration, or a change with materially broader scope.

## 4. Stage safely

Download or pull while the node remains online when possible. Verify artifact integrity before stopping. Keep the previous binary/image and configuration. Validate generated configuration without printing secrets. Do not overwrite the only rollback copy.

For automatic managers, verify the plan name/height and staged binary, but do not perform a manual competing switch.

## 5. Execute

1. Upgrade one signing instance at a time.
2. Never allow two processes or hosts to sign with the same consensus key.
3. Stop only at the defined gate or during the approved maintenance window.
4. Apply only documented migrations and scoped config changes.
5. Start the intended artifact and confirm the running process/image—not merely the file on disk.
6. Preserve evidence and roll back if the new workload cannot reach a safe operating state and rollback remains protocol-safe.

## 6. Verify completion

Completion requires all applicable checks:

- expected running version/digest;
- active service with stable restart count;
- no fatal/panic loop in recent logs;
- correct chain ID and advancing height/block time;
- healthy peer count and sync state;
- validator active/bonded, not jailed, and signing recent blocks;
- confirmation from an independent external source;
- monitoring and downstream consumers healthy;
- upgrade manager plan consumed or cleared as documented.

Report the source, old/new versions, execution mode, checks performed, rollback state, and remaining watch items. Update private network knowledge, schedule/todo, and daily memory without copying private facts into this skill.
