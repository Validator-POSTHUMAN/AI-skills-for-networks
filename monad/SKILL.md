---
name: monad-validator-ops
description: "Operate Monad validators and full nodes on mainnet/testnet: monitor monad-bft, monad-execution, monad-rpc, TrieDB, OTel, JSON-RPC health, execution events/WebSockets, staking state, FastLane/shMonad sidecar integration, upgrades, safe recovery, and concise operator reports."
---

# Monad Validator Ops

Use this skill for Monad node operations: validator and full-node health
checks, JSON-RPC issues, missed participation symptoms, BFT/execution/RPC
service triage, TrieDB disk checks, OTel metrics, execution events and
WebSocket enablement, FastLane/shMonad sidecar integration, upgrade
preparation, staking operations, safe recovery, Solonet rehearsals, and
concise operator reports.

## Source Priority

1. Current command output from the target host, local JSON-RPC, and public RPC.
2. Local operator inventory and chain-specific runbooks, if available.
3. Official Monad sources:
   - https://docs.monad.xyz/#mainnet
   - https://docs.monad.xyz/llms.txt
   - https://github.com/monad-crypto/monad-solonet
   - https://github.com/monad-developers/staking-sdk-cli
   - https://docs.shmonad.xyz/validators/onboarding
   - https://docs.shmonad.xyz/validators/onboarding/install-sidecar-rootless-docker
4. Explorers, dashboards, and third-party RPCs only as secondary confirmation.

Never claim a Monad validator is healthy, synced, upgraded, or active without
live checks. Monad is not Cosmos: do not use Cosmos SDK assumptions such as
`unjail`, `valoper`, Tendermint RPC paths, or CometBFT block-signature
queries unless an operator's local tooling explicitly provides them.

## Chain Facts

- Mainnet chain ID: `143`
- Testnet chain ID: `10143`
- Token symbol: `MON`
- Mainnet public RPC examples: `https://rpc.monad.xyz` and
  `https://rpc-mainnet.monadinfra.com`.
- Testnet public RPC examples: `https://testnet-rpc.monad.xyz` and
  `https://rpc-testnet.monadinfra.com`.
- Main services from the official package:
  - `monad-bft`: consensus client
  - `monad-execution`: execution client
  - `monad-rpc`: Ethereum-compatible JSON-RPC server
  - `monad-mpt`: one-time TrieDB initialization helper
  - `monad-cruft`: cleanup timer
  - `otelcol`: OTel collector for metrics
- Default RPC port in official node-ops docs: `8080`.
- Default WebSocket port when `monad-rpc --ws-enabled` is used: `8081`.
- Execution events are required for WebSocket subscriptions and for
  `eth_sendRawTransactionSync` support in releases that route that method
  through execution events, such as testnet `v0.14.5`.
- Execution events require a `hugetlbfs` user mount and an event-rings
  directory, usually
  `/var/lib/hugetlbfs/user/monad/pagesize-2MB/event-rings`.
- P2P firewall baseline from official docs: allow TCP/UDP `8000` and
  authenticated UDP `8001` where required.
- Default node user and paths in official docs:
  - user: `monad`
  - env: `/home/monad/.env`
  - BFT config: `/home/monad/monad-bft/config/node.toml`
  - validators file: `/home/monad/monad-bft/config/validators/validators.toml`
  - forkpoint dir: `/home/monad/monad-bft/config/forkpoint/`
  - BFT ledger: `/home/monad/monad-bft/ledger/`
  - TrieDB device: `/dev/triedb`
- Staking precompile: `0x0000000000000000000000000000000000001000`.
- Official validator onboarding uses `staking-sdk-cli` for staking precompile
  workflows.
- Solonet is a local Docker network for rehearsal and development; do not use
  it as production guidance for joining mainnet or testnet.

These are publication-time defaults, not authorization to act. Always refresh
official docs, package versions, upgrade instructions, snapshots, and current
network information before changing a production node.

## Network Mode

This skill supports Monad mainnet and testnet. Always identify the target
network before choosing RPC endpoints, expected chain ID, staking CLI
parameters, alert labels, or recovery instructions.

- Mainnet: use EVM chain ID `143`; default public RPC fallback
  `https://rpc.monad.xyz`; production validator actions require the
  operator's real inventory and explicit approval for transactions or recovery.
- Testnet: use EVM chain ID `10143`; default public RPC fallback
  `https://testnet-rpc.monad.xyz`; do not reuse mainnet keys, beneficiary
  addresses, alert routes, or snapshot assumptions unless the operator's
  inventory explicitly says they are intended for testnet.
- Tempnet and Solonet: require operator-provided chain ID, RPC, service names,
  and local docs because these environments can be reset or customized.

For every health check, confirm `eth_chainId` against the intended network
before interpreting validator state or reporting that the node is healthy.

## Operator Inventory Guardrails

This skill is validator-neutral and server-neutral. It must work for any
Monad operator and must not assume a specific team, host, service name, RPC
endpoint, validator ID, beneficiary address, key path, RPC provider, or server
provider.

Before operating infrastructure, load the current operator's Monad inventory
from their local knowledge base, runbook, monitoring config, or explicit task
input. Required target fields are:

- Network: mainnet, testnet, tempnet, or solonet.
- Host or SSH target.
- Local JSON-RPC endpoint.
- Service names for BFT, execution, RPC, and optional OTel.
- Validator ID, node name, secp public key, BLS public key, and beneficiary
  address when validator-specific action is needed.
- Staking CLI location and auth method when staking transactions are requested.
- Expected package/runtime version when checking upgrades.

When a machine-readable inventory format is useful, read
`references/inventory.schema.json`. Use
`examples/inventory.example.json` only as a fake-value template; never treat it
as production inventory.

If inventory is missing, inconsistent, or ambiguous, ask the operator for the
missing target data before restarting services, changing config, sending
staking transactions, resetting state, formatting disks, or touching keys.

## Safety Rules

- Before any destructive recovery, back up Monad BFT keys, keystore password,
  staking CLI config, and any operator-specific secrets. Do not delete or reset
  data until the operator approves.
- Never paste key backups, keystore passwords, auth private keys, RPC secrets,
  or OTel credentials into reports, examples, or skill files.
- Treat `/dev/triedb`, NVMe formatting, `reset-workspace.sh`, hard reset,
  and snapshot import as destructive. Verify the target host and disk first.
- Do not restart services just because one public RPC is slow. Compare local
  RPC, another public RPC, service state, logs, and block progress.
- Restart order matters operationally. Prefer official instructions and local
  runbooks; when no runbook exists, restart `monad-execution`,
  `monad-bft`, then `monad-rpc` only after preserving logs and defining the
  expected recovery signal.
- Do not change `node.toml`, remote config URLs, beneficiary address,
  staking parameters, or firewall rules without backup and explicit target
  confirmation.
- Do not enable WebSockets by opening a validator directly to the internet
  unless the operator explicitly asks for public exposure. Prefer
  `--rpc-addr 127.0.0.1`, local-only `ws://127.0.0.1:8081`, and a firewall
  deny/default-deny rule for `8081/tcp`; publish through a separate gateway
  when public WSS is required.
- Do not assume a cloud VM is production-suitable. Official hardware guidance
  prefers bare metal, high-frequency CPU, NVMe storage, and disabled SMT/HT.
- During network-wide stalls, upgrade boundaries, or public RPC disagreement,
  prefer observation and official upgrade/recovery instructions over restart
  loops.
- Staking actions can have epoch-delay effects. Check current validator state,
  epoch timing, auth address permissions, and transaction success before
  reporting completion.

## FastLane / shMonad Sidecar

For detailed FastLane MEV sidecar installation, verification, upgrade,
rollback, and monitoring workflows, use the separate fastlane-sidecar-ops
skill when available:

- Skill: https://github.com/Validator-POSTHUMAN/AI-skills-for-networks/blob/main/fastlane-sidecar/SKILL.md
- Official install docs: https://docs.shmonad.xyz/validators/onboarding/install-sidecar-rootless-docker

Monad-specific sidecar guardrails:

- Treat sidecar work as production validator work. Confirm the target network,
  host, local RPC, service names, BFT version, and shMonad onboarding status
  before changing anything.
- Official shMonad onboarding order matters: coinbase contract / onboarding,
  beneficiary update, FastLane dedicated fullnodes, then sidecar.
- Do not change node.toml beneficiary / coinbase routing without explicit
  operator confirmation and config backup.
- Sidecar wiring changes monad-bft and monad-rpc mempool IPC paths. Preserve
  the full original ExecStart in systemd drop-ins; do not edit installed unit
  files directly.
- Keep sidecar metrics loopback-only by default, for example
  http://127.0.0.1:8765/health and /metrics.
- Verify container digest and release provenance before running or upgrading.
- If installed, monitoring should include sidecar container state, health
  timestamp, tx_received behavior, metrics reachability, socket permissions,
  and recent logs.

## Health Check Workflow

Use the bundled script when possible:

```bash
scripts/monad-healthcheck.sh \
  --host <ssh-target> \
  --network mainnet \
  --rpc http://127.0.0.1:8080 \
  --public-rpc https://rpc.monad.xyz \
  --validator-id <id> \
  --expected-version <version> \
  --check-exec-events
```

Use `--local` instead of `--host` when already running on the target host.
Use `--service <name>` repeatedly if the operator uses custom service names.
Use `--staking-cli <path>` when validator state should be queried through an
installed staking CLI.
`--network mainnet` and `--network testnet` set the expected chain ID and
default public RPC unless explicitly overridden.

Manual checks:

```bash
systemctl is-active monad-bft monad-execution monad-rpc otelcol.service || true
systemctl list-units --type=service monad-bft.service monad-execution.service monad-rpc.service

monad-node --version || true
monad-rpc --version || true

curl -fsS http://127.0.0.1:8080/ \
  -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}'

curl -fsS http://127.0.0.1:8080/ \
  -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}'

curl -fsS http://127.0.0.1:8080/ \
  -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"eth_syncing","params":[]}'

curl -fsS http://127.0.0.1:8889/metrics | head || true
monad-mpt --storage /dev/triedb || true
journalctl -u monad-bft -n 200 --no-pager
```

Interpretation:

- Healthy baseline: core services active, `eth_chainId` matches the intended
  network, local block height advances, `eth_syncing=false`, BFT/execution/RPC
  logs have no recent fatal loop, disk/TrieDB usage is safe, and OTel is active
  if required by the operator.
- `monad-rpc` may not listen on `8080` until statesync has completed.
- JSON-RPC block values are hex. Convert before comparing heights.
- Compare `latest` and `finalized` block tags when finality matters. Monad's
  `latest` data is low-latency and can be provisional.
- Public RPCs are rate-limited and provider-specific. Do not diagnose a local
  node solely from one public endpoint.

## Execution Events and WebSocket Setup

Use this workflow when the operator asks to enable execution events,
WebSockets, or release-note functionality that depends on them. In testnet
`v0.14.5`, `eth_sendRawTransactionSync` requires execution events; without
them, `monad-rpc` returns `Method not supported`.

Before changing anything:

1. Read the current official page:
   `https://docs.monad.xyz/node-ops/events-and-websockets`.
2. Confirm target network, host, node user, and RPC/WS exposure policy.
3. Capture pre-state: `systemctl cat monad-execution monad-rpc`, process
   flags, service state, `eth_chainId`, `eth_syncing`,
   `eth_sendRawTransactionSync`, listeners, and firewall state.
4. Back up current systemd state and drop-ins under
   `~/backups/monad-exec-events-<timestamp>/`.

Required persistent setup:

- Install `libhugetlbfs-bin` if `hugeadm` is missing.
- Add and enable `events-hugepages-mounts.service` with
  `ExecStart=/usr/bin/hugeadm --create-user-mounts monad`.
- Create `/var/lib/hugetlbfs/user/monad/pagesize-2MB/event-rings` and chown
  it to the Monad node user.
- Add a `monad-execution` drop-in that preserves existing execution flags and
  adds `--exec-event-ring` pointing to
  `/var/lib/hugetlbfs/user/monad/pagesize-2MB/event-rings/monad-exec-events`.
- Add a `monad-rpc` drop-in that preserves existing RPC flags, keeps
  `--rpc-addr 127.0.0.1` unless public exposure is explicitly requested, and
  adds `--exec-event-path` pointing to the same event-rings file plus
  `--ws-enabled`.
- Run `systemctl daemon-reload`, restart `monad-execution`, then restart
  `monad-rpc`. Do not restart BFT unless evidence requires it.
- If WebSocket must stay private, deny external `8081/tcp` in the firewall.

Verification:

- `events-hugepages-mounts.service`, `monad-execution`, `monad-rpc`,
  `monad-bft`, and `otelcol.service` are active.
- `monad-execution` process includes `--exec-event-ring`.
- `monad-rpc` process includes `--exec-event-path` and `--ws-enabled`.
- HTTP RPC returns the expected `eth_chainId`, advancing `eth_blockNumber`,
  and `eth_syncing=false`.
- Local WebSocket on `ws://127.0.0.1:8081` returns the expected `eth_chainId`
  if WebSockets were enabled.
- `eth_sendRawTransactionSync` no longer returns `Method not supported`; an
  invalid test transaction may return a validation/readiness error instead.
- Recent RPC/execution logs show no fatal loop, no failed units exist, and
  external direct connects to `8081` fail or time out when WS is private.

## Monitoring Setup

The skill covers monitoring design and verification, but it does not assume a
single operator's alerting stack. Prefer the operator's existing monitoring
system; otherwise build a minimal state-change monitor first and expand into
Prometheus/Grafana after the node is stable.

Minimum checks for both mainnet and testnet:

- systemd state for `monad-bft`, `monad-execution`, `monad-rpc`, and
  `otelcol.service` when OTel is enabled
- local JSON-RPC `eth_chainId`, `eth_blockNumber`, and `eth_syncing`
- local vs public RPC height gap, using a public RPC for the same network
- recent fatal/error patterns in BFT, execution, and RPC logs
- root, home, ledger, and TrieDB storage pressure
- `/metrics` availability from the OTel collector when the operator expects
  Prometheus scraping
- FastLane sidecar container state, /health, /metrics, socket permissions,
  and tx_received behavior when the sidecar is installed
- optional staking CLI validator query when a validator ID and CLI inventory
  are available

Alerting guardrails:

- Use network-specific labels such as `monad-mainnet` and `monad-testnet`;
  never send both networks to the same unlabeled alert route.
- Alert on state changes, not every failed poll. Avoid restart loops triggered
  by public RPC provider noise.
- Include network, host, service, local chain ID, local height, public height,
  lag, and the action taken in every alert.
- Keep Telegram, Slack, webhook, and OTel credentials outside the skill and
  outside repository files. Use environment files or the operator's secret
  manager.
- Before declaring monitoring complete, force or simulate one safe failure
  such as a wrong RPC URL or a stopped disposable test service, then verify the
  alert and recovery path.

For a portable baseline, run `scripts/monad-healthcheck.sh` from cron,
systemd timer, or the operator's monitoring agent with the correct
`--network`, `--rpc`, service names, and alert wrapper. For production
Prometheus/Grafana, scrape the local OTel collector and add rules for service
down, height not advancing, chain ID mismatch, high height lag, disk pressure,
and missing metrics.

## Alert Triage

For a missed-participation, RPC, service, OTel, disk, or staking alert:

1. Extract network, node label, host, local RPC, validator ID, node name, and
   affected service from the alert or monitoring config.
2. Match the alert to inventory before acting.
3. Check local service state, local RPC height, public RPC height, chain ID,
   `eth_syncing`, disk, and recent logs.
4. If local and public heights are both stalled, check official announcements
   and upgrade instructions before restarting.
5. If only `monad-rpc` fails but BFT/execution progress, triage RPC config,
   port binding, and logs before restarting consensus.
6. If BFT logs show statesync/blocksync/forkpoint/validators issues, inspect
   `/home/monad/.env`, `forkpoint`, and `validators.toml` freshness.
7. If execution or TrieDB errors appear, inspect `/dev/triedb`, NVMe health,
   `monad-mpt --storage /dev/triedb`, and disk/IO before recovery.
8. Preserve recent logs before any restart:

```bash
journalctl -u monad-bft -n 300 --no-pager
journalctl -u monad-execution -n 300 --no-pager
journalctl -u monad-rpc -n 300 --no-pager
```

Report format:

```text
Monad status:
- Target: <network/node/host/validator-id>
- Services: bft=<state>, execution=<state>, rpc=<state>, otel=<state|n/a>
- RPC: chain_id=<id>, local_height=<h>, public_height=<h>, syncing=<value>
- Version: running=<version>, expected=<version|unknown>
- Validator: id=<id|unknown>, active=<yes/no/unknown>, staking=<summary>
- Storage: triedb=<ok/problem/unknown>, root=<usage>, data=<usage>
- Action: <none/restart/recovery/escalation>
- Notes: <one concise cause or uncertainty>
```

## Upgrade Workflow

Before upgrade:

1. Read the current official upgrade page from
   `https://docs.monad.xyz/node-ops/upgrade-instructions` and any operator
   announcement channels.
2. Confirm target network, version, revision, package name, and whether the
   node is mainnet, testnet, tempnet, or solonet.
3. Capture current state: services, binary versions, JSON-RPC height,
   `eth_syncing`, disk, TrieDB, and recent logs.
4. Back up keys and configs before package changes:

```bash
mkdir -p ~/backups
tar -czf ~/backups/monad-keys-config-$(date +%Y%m%dT%H%M%SZ).tar.gz \
  /home/monad/.env \
  /home/monad/monad-bft/config/id-secp \
  /home/monad/monad-bft/config/id-bls \
  /home/monad/monad-bft/config/node.toml \
  /home/monad/monad-bft/config/validators/validators.toml \
  /home/monad/monad-bft/config/forkpoint 2>/dev/null
```

During upgrade:

1. Follow the exact official version-specific instructions.
2. Avoid arbitrary CLI flag changes; Monad docs warn that some options can
   cause unexpected behavior or crashes.
3. Watch service logs and JSON-RPC block progress.

After upgrade:

1. Verify package/runtime version, service state, local RPC, public height
   comparison, `eth_syncing=false`, OTel metrics if required, and no recent
   fatal log loop.
2. If the node is too far behind for normal sync, use the official recovery
   decision tree rather than repeated restarts.
3. Update the operator's inventory, upgrade schedule, and daily memory.

## Recovery Playbook

Use the smallest safe fix first.

- RPC down, BFT/execution healthy: inspect `monad-rpc` logs, port binding,
  `eth_chainId`, and RPC flags; restart RPC only if there is a clear local
  fault.
- BFT stalled close to network tip: use soft reset/statesync guidance if
  current official docs and local evidence match.
- Far behind or corrupted state: hard reset from a trusted Monad Foundation or
  Category Labs snapshot only after key/config backup and operator approval.
- TrieDB or NVMe issues: check `/dev/triedb`, `nvme list`, `lsblk`,
  `monad-mpt --storage /dev/triedb`, kernel logs, and disk health before
  attempting reset.
- Validator migration: follow official node migration docs; do not improvise
  by copying keys to a new host without a full migration plan.
- Staking problem: query staking state through the official staking CLI or
  precompile tooling. Verify validator ID, auth address, epoch timing, and tx
  status before claiming success.

Hard reset is destructive because it wipes local runtime state and imports a
snapshot. Before running it, explicitly confirm:

- Correct host and network.
- Key/config backups exist off-node or in an approved secure location.
- Snapshot provider and script source are official/current.
- `forkpoint.toml` and `validators.toml` will be refreshed or auto-fetched.
- The operator accepts archive gaps from snapshot-based recovery.

## Solonet Workflow

Use Solonet for rehearsal, local development, and issue reproduction when the
operator needs full Monad behavior instead of a simple EVM dev node.

Good Solonet uses:

- Practice upgrades, resets, and validator workflows on a disposable network.
- Test staking CLI commands without mainnet/testnet funds.
- Reproduce consensus or block-delivery behavior in single-validator or
  multi-validator topologies.

Guardrails:

- Solonet is local Docker/devnet infrastructure. Do not use Solonet state,
  keys, chain IDs, or configs as production inventory.
- Solonet performance is not production-realistic; validate production
  performance on real node hardware.
- The upstream repository is the source of truth:
  https://github.com/monad-crypto/monad-solonet

## External References

- Monad docs index: https://docs.monad.xyz/llms.txt
- Mainnet docs: https://docs.monad.xyz/#mainnet
- Node operations: https://docs.monad.xyz/node-ops
- Full-node installation: https://docs.monad.xyz/node-ops/full-node-installation
- Validator installation: https://docs.monad.xyz/node-ops/validator-installation
- Recovery: https://docs.monad.xyz/node-ops/node-recovery
- JSON-RPC overview: https://docs.monad.xyz/reference/json-rpc/overview
- Staking overview: https://docs.monad.xyz/reference/staking/overview
- Solonet: https://github.com/monad-crypto/monad-solonet
