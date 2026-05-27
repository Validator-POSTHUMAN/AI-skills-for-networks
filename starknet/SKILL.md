---
name: starknet-ops-and-apps
description: "Operate and build on Starknet: full nodes, JSON-RPC, Pathfinder/Juno, validator staking and attestation, Starkzap/app integrations, Cairo tooling, upgrades, troubleshooting, and concise operator reports."
---

# Starknet Ops and Apps

Use this skill for Starknet node operations, validator/staking workflows,
attestation checks, JSON-RPC service, Cairo/Starknet app development, Starkzap
integrations, upgrades, incident triage, and concise operator-facing reports.

This skill is validator-neutral and provider-neutral. It must work for any
operator or builder and must not assume a specific validator, RPC vendor,
wallet, bridge, explorer, server provider, cloud, or hosting stack.

## Source Priority

1. Current command output from the target host, local RPC, logs, and project
   repository.
2. Local operator inventory and runbooks, if available.
3. Official Starknet sources:
   - https://docs.starknet.io/
   - https://docs.starknet.io/llms.txt
   - https://docs.starknet.io/learn/cheatsheets/compatibility.md
   - https://docs.starknet.io/learn/cheatsheets/chain-info.md
   - https://docs.starknet.io/secure/quickstart/running-a-node.md
   - https://docs.starknet.io/secure/quickstart/becoming-a-validator.md
   - https://docs.starknet.io/secure/quickstart/attesting-to-blocks.md
   - https://docs.starknet.io/build/quickstart/overview.md
   - https://docs.starknet.io/build/starkzap/overview.md
   - https://github.com/starknet-io/starknet-docs
   - https://github.com/starknet-io/starknet.js
4. Upstream tool repositories and release notes for Pathfinder, Juno, Scarb,
   Starknet Foundry, Starknet Devnet, Starknet.js, Starkzap, and attestation
   services.

Never claim a Starknet node, validator, attestation service, app integration,
or transaction is healthy without live checks. Always refresh official docs
before using versions, contract addresses, staking minimums, RPC paths, or
attestation flags.

## Core Starknet Facts

- Starknet is an L2 validity rollup using STARK proofs and Ethereum settlement.
- Accounts are smart contracts; native account abstraction changes wallet,
  signing, nonce, and transaction UX assumptions.
- Most user actions are invoke transactions; multicall is a standard pattern.
- Full nodes depend on an Ethereum WebSocket endpoint for L1 data.
- Official node docs cover Pathfinder and Juno. Pick the client from the
  operator's existing stack or explicit preference.
- Staking and attestation are phase- and version-sensitive. Re-read official
  Secure docs and chain-info before acting.
- Starkzap is a TypeScript SDK for consumer apps that need wallet, token,
  staking, swap, paymaster/gasless, bridge, and DeFi flows.

These facts are orientation, not authorization to act. Verify current docs and
live state before changing production systems.

## Operator Inventory Guardrails

Before operating infrastructure, load the current operator's Starknet inventory
from local docs, monitoring config, deployment files, or explicit task input.
Required target fields are:

- Network: mainnet, sepolia, appchain, devnet, or local.
- Host or SSH target when remote action is needed.
- Local Starknet JSON-RPC endpoint, including RPC version path.
- Client: Pathfinder, Juno, or other.
- Runtime: Docker Compose, Docker container, systemd binary, source build, or
  managed service.
- Service/container names for node and optional attestation service.
- Ethereum WebSocket dependency source, represented without secrets.
- Data directory and snapshot/backup location.
- Metrics endpoint, if exposed.
- Validator staking, operational, and rewards addresses when validator-specific
  action is requested.

When a machine-readable inventory format is useful, read
`references/inventory.schema.json`. Use
`examples/inventory.example.json` only as a fake-value template; never treat it
as production inventory.

If inventory is missing, inconsistent, or ambiguous, ask the operator for the
missing target data before restarting services, changing config, sending
staking transactions, resetting data, replacing snapshots, exposing RPC, or
touching keys.

## Safety Rules

- Ask before fund-moving actions, staking, unstaking, delegation-pool changes,
  commission changes, validator key changes, data deletion, snapshot
  replacement, public RPC exposure, or transaction submission.
- Back up validator/operator key material and config before destructive
  recovery or signer changes.
- Never paste private keys, mnemonics, Ethereum WS credentials, RPC tokens,
  wallet secrets, or paymaster secrets into reports, examples, or skill files.
- Treat Ethereum WS as a critical dependency. A node can look locally healthy
  while it is stalled because L1 input is broken or rate-limited.
- Do not recommend a cloud, bare-metal provider, RPC provider, wallet, bridge,
  explorer, or paymaster as default. Present tradeoffs and let the operator
  choose.
- Do not delete or rebuild node data first. Preserve logs, check live state,
  verify disk, and confirm snapshot integrity.
- During network upgrades or public RPC disagreement, prefer observation,
  official release notes, and compatibility checks over restart loops.

## Health Check Workflow

Use the bundled script when possible:

```bash
scripts/starknet-healthcheck.sh \
  --host <ssh-target> \
  --rpc http://127.0.0.1:9545/rpc/v0_9 \
  --client pathfinder \
  --container <node-container> \
  --attestation-container <attestation-container> \
  --public-rpc https://<public-rpc>/rpc/v0_9 \
  --expected-chain-id SN_MAIN
```

Use `--local` instead of `--host` when already running on the target host. Use
`--service` or `--attestation-service` for systemd-based deployments.

Manual baseline:

```bash
curl -fsS http://127.0.0.1:<port>/rpc/<version> \
  -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","method":"starknet_blockNumber","params":[],"id":1}'

curl -fsS http://127.0.0.1:<port>/rpc/<version> \
  -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","method":"starknet_syncing","params":[],"id":1}'

curl -fsS http://127.0.0.1:<port>/rpc/<version> \
  -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","method":"starknet_chainId","params":[],"id":1}'
```

Healthy baseline:
- node service/container is running
- block number increases over time
- local/public height gap is acceptable for the operator's SLO
- `starknet_syncing` is `false` or converging
- chain ID matches the intended network
- RPC version path matches client and app expectations
- recent logs do not show repeated L1, Ethereum WS, database, or RPC errors
- attestation logs show current attestation info, epoch updates, and
  transaction confirmation when the validator is assigned

## Monitoring Baseline

Monitor Starknet nodes at three layers:

- **Process/runtime**: systemd unit or container state, restart count, recent
  logs, CPU, memory, disk, inode usage, and file descriptor pressure.
- **Starknet sync/RPC**: local block number, `starknet_syncing`, chain ID, RPC
  version path, local/public height gap, RPC latency, and error rate.
- **Dependencies**: Ethereum WebSocket reachability, reconnect loops, L1
  provider rate limits, disk latency, network/firewall reachability, and
  reverse-proxy health if RPC is exposed.

Validator and attestation monitoring should additionally track attestation
service state, current epoch, assignment detection, sent transaction hashes,
transaction confirmation, and repeated signer/RPC/contract-address errors.

Prefer alerts on sustained conditions:
- node process stopped or restart loop
- local height not increasing while public height advances
- sync gap exceeds the operator's SLO
- disk usage above the operator's threshold
- repeated Ethereum WS, database, trie, or RPC errors
- attestation service cannot detect epochs or confirm transactions when
  assigned

## Snapshot Recovery

Snapshot recovery is destructive to node database state. Ask before replacing
or deleting data. Back up config, key material, and current metadata first.

Preflight:
1. Confirm network, client, runtime, data directory, RPC path, and snapshot
   source.
2. Read current official node docs and client release notes for snapshot and
   database compatibility.
3. Stop the node cleanly.
4. Save recent logs and current config.
5. Back up validator/operator keys and signer config according to the
   operator's secret policy.
6. Check disk space for both the downloaded archive and extracted database.
7. Verify snapshot checksum, size, network, client, and block height when
   provided.

Generic restore shape:

~~~bash
sudo systemctl stop <starknet-service>
# or: docker compose stop <node-service>

cp -a <config-dir> <backup-dir>/config-$(date +%Y%m%d-%H%M%S)
# Back up keys/signer config separately according to the operator's policy.

mv <data-dir> <data-dir>.pre-snapshot-$(date +%Y%m%d-%H%M%S)
mkdir -p <data-dir>

# Download and verify the snapshot using the snapshot source's documented
# command. Extract as the node user when possible, then restore ownership:
sudo chown -R <node-user>:<node-group> <data-dir>

sudo systemctl start <starknet-service>
# or: docker compose up -d <node-service>
~~~

Post-restore verification:
- service/container starts without database format errors
- chain ID matches the intended network
- RPC block number is at or above the snapshot height
- `starknet_syncing` is `false` or converging
- block number increases over time
- local/public height gap is closing
- logs do not show repeated Ethereum WS, database, trie, or RPC errors
- public RPC, indexers, and attestation services still match the restored RPC
  path and client version

Rollback:
- stop the node
- move the restored data directory aside
- restore `<data-dir>.pre-snapshot-*` if it was preserved
- restore previous config if changed
- start the previous service/image/binary only when upstream notes say database
  compatibility allows it

## Validator, Staking, and Attestation

Before validator work:
1. Read current Secure docs and chain-info.
2. Verify staking and attestation contract addresses from official docs.
3. Verify minimum stake, token decimals, and current validator phase.
4. Confirm the staking, operational, and rewards addresses.
5. Confirm signer custody and account deployment.
6. Confirm the node is synced and RPC path is compatible with the attestation
   service.

Generic sequence:
1. Run and verify a full node.
2. Prepare addresses and signer custody according to current docs.
3. Approve STRK transfer to the staking contract.
4. Stake through the staking contract.
5. Set commission and open delegation only if the operator explicitly wants it.
6. Verify staker info from the staking contract.
7. Configure attestation with the current upstream command and safe secret
   handling.
8. Monitor logs for current attestation info, epoch changes, sent transaction
   hashes, and confirmations.

Never fill in contract addresses from memory.

## Development and Starkzap Workflow

For Cairo/contracts:
- read `Scarb.toml`, Starknet Foundry config, tests, deployment scripts, and
  CI before editing
- verify Cairo/Sierra/RPC/tool compatibility
- prefer local Devnet/Katana for fast tests and Sepolia for public verification
- run project-native checks: `scarb test`, `snforge test`, typecheck, app
  build, or integration tests

For Starkzap/app work:
- use official Starkzap docs for API syntax
- use official Starknet docs, `starknet-io/starknet-docs`, and
  `starknet-io/starknet.js` for source/API context
- keep wallet, RPC, paymaster, token, and network config outside source code
- verify token decimals, fee flow, sponsored-call policy, session expiry,
  user rejection, pending transaction, failed transaction, and retry states
- be explicit about custody and embedded-wallet assumptions

## Troubleshooting

Triage in this order:
1. Symptom and scope: node, RPC, app, contract, transaction, staking, or
   attestation.
2. Recent changes: version, config, snapshot, Ethereum WS, firewall, dependency,
   deployment, wallet, paymaster, or contract address.
3. Live state: services/containers, logs, RPC block number, sync, disk, memory,
   Ethereum WS reachability, and RPC version path.
4. Compatibility table: Starknet version, RPC version, node client, SDK, Cairo,
   Starknet Foundry, Devnet.
5. One change at a time, then verification.

Common causes:
- Ethereum WS URL, credentials, rate limit, or provider outage.
- RPC version path mismatch.
- node not synced, stalled, or out of disk.
- incompatible SDK or transaction format.
- wrong chain ID or network.
- undeployed/underfunded account.
- wrong operational key or staking address.
- attestation service using stale contract addresses or RPC path.
- paymaster/session policy does not sponsor the call.

## Reporting Format

For operator reports, include:

```text
Status:
Checked:
Found:
Changed:
Verified:
Risk:
Next:
```

Keep reports concise. Distinguish verified facts from assumptions and state what
must be checked next if the task is not complete.
