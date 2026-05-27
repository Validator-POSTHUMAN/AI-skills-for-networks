---
name: axelar-validator-ops
description: "Operate Axelar validators on axelar-dojo-1: monitor axelard, vald, tofnd, broadcaster health, external-chain maintainer status, missed blocks, upgrades, safe recovery, and concise operator reports."
---

# Axelar Validator Ops

Use this skill for Axelar validator operations: consensus node checks, vald and
tofnd triage, broadcaster balance, EVM chain-maintainer health, missed-block
alerts, sequence-drift incidents, upgrade preparation, recovery, and concise
operator-facing reports.

## Source Priority

1. Current command output from the target host, local RPC, and public RPC/API.
2. Local operator inventory and chain-specific runbooks, if available.
3. Official Axelar repositories:
   - https://github.com/axelarnetwork/axelar-core
   - https://github.com/axelarnetwork/axelar-configs
   - https://github.com/axelarnetwork/axelar-docs
4. Explorers, dashboards, and third-party RPCs only as secondary confirmation.

Never claim the validator is healthy, upgraded, signing, or maintaining
external chains without live checks.

## Chain Facts

- Mainnet chain ID: `axelar-dojo-1`
- Testnet chain ID: `axelar-testnet-lisbon-3`
- Daemon: `axelard`
- Default mainnet home: `~/.axelar`
- Default testnet home: `~/.axelar_testnet`
- Bond/fee denom: `uaxl`
- Validator companion processes:
  - `vald`: started through `axelard vald-start`
  - `tofnd`: threshold-signing daemon, commonly listening on `127.0.0.1:50051`
- Official docs say validators should run the Axelar node plus companion
  processes and use `axelard health-check --tofnd-host <host>
  --operator-addr <valoper>`.
- Latest observed `axelar-core` tag at publication time: `v1.4.0`.

These are publication-time defaults, not authorization to act. Always refresh
official tags, release signatures, configs, and on-chain upgrade plans before
building binaries or changing services.

## Operator Inventory Guardrails

This skill is validator-neutral and server-neutral. It must work for any
Axelar validator operator and must not assume a specific team, host, service
name, RPC port, moniker, valoper, consensus address, broadcaster address,
external-chain RPC provider, or server provider.

Before operating infrastructure, load the current operator's Axelar inventory
from their local knowledge base, runbook, monitoring config, or explicit task
input. Required target fields are:

- Host or SSH target.
- Axelar node systemd service name.
- Vald service name, if the validator runs vald.
- Tofnd service name or process supervision method, if the validator runs tofnd.
- Local Axelar RPC endpoint.
- Validator moniker or label.
- Valoper address.
- Consensus address.
- Broadcaster account address.
- Active external chains maintained by the validator, if vald triage is needed.

When a machine-readable inventory format is useful, read
`references/inventory.schema.json`. Use
`examples/inventory.example.json` only as a fake-value template; never treat it
as production inventory.

If inventory is missing, inconsistent, or ambiguous, ask the operator for the
missing target data before restarting services, changing vald config, sending
transactions, or deleting data.

## Safety Rules

- Before any destructive recovery, back up validator keys and tofnd state. Do
  not delete data until the operator approves.
- Do not restart the consensus node to fix vald-only symptoms unless live
  evidence shows an axelard fault. Vald restarts can miss votes; axelard
  restarts can miss blocks.
- Before restarting anything, prove the target service matches the affected
  valoper and consensus address.
- Keep the broadcaster account funded. Official docs require at least 5 AXL;
  operators may set a higher threshold.
- Treat broadcaster registration as effectively permanent for a validator.
  Official docs warn that a validator can register only one broadcaster
  address during its lifetime.
- Do not run maintenance transactions with the broadcaster while vald is
  actively broadcasting unless the operator accepts sequence-mismatch risk.
- Never store keyring passphrases, tofnd mnemonics, RPC secrets, API keys, or
  Telegram tokens in skill files, reports, examples, or runbooks.
- Do not use `localhost` blindly for high-frequency local RPC clients. Check
  whether it resolves to IPv6 first while the node listens on IPv4 only. Prefer
  explicit `127.0.0.1` for local vald-to-axelard RPC when appropriate.
- Enable or disable external-chain RPC config and chain-maintainer
  registration together. A mismatch can burn broadcaster fees or cause missed
  votes.
- During network-wide halts or upgrade boundaries, prefer waiting and checking
  the upgrade plan over restart loops.

## Health Check Workflow

Use the bundled script when possible:

```bash
scripts/axelar-healthcheck.sh \
  --host <ssh-target> \
  --node-service <axelard-systemd-service> \
  --vald-service <vald-systemd-service> \
  --tofnd-service <tofnd-systemd-service> \
  --rpc http://127.0.0.1:<port> \
  --valcons <HEX_CONSENSUS_ADDRESS> \
  --valoper <axelarvaloper...> \
  --broadcaster <axelar1...> \
  --public-rpc https://<public-rpc> \
  --maintainer-chain ethereum \
  --maintainer-chain avalanche
```

Use `--local` instead of `--host` when already running on the target host.
Use `--blocks <n>` to change the recent signing window and
`--min-broadcaster-uaxl <amount>` to set the broadcaster balance threshold.

Manual checks:

```bash
systemctl is-active <axelard-service> <vald-service> <tofnd-service>

curl -fsS <rpc>/status | jq -r '
  .result.sync_info.latest_block_height,
  .result.sync_info.latest_block_time,
  .result.sync_info.catching_up,
  .result.validator_info.voting_power'

pgrep -af 'axelard.*start|axelard vald-start|tofnd'
readlink -f /proc/$(pgrep -f "axelard.*start" | head -1)/exe
/proc/$(pgrep -f "axelard.*start" | head -1)/exe version

axelard health-check --tofnd-host 127.0.0.1 --operator-addr <valoper>
```

Verify consensus signing for recent blocks:

```bash
H=$(curl -fsS <rpc>/status | jq -r .result.sync_info.latest_block_height)
for B in $((H-1)) $((H-2)) $((H-3)) $((H-4)) $((H-5)); do
  FLAG=$(curl -fsS "<rpc>/block?height=$B" |
    jq -r --arg v "<HEX_CONSENSUS_ADDRESS>" \
      '[.result.block.last_commit.signatures[]? |
      select(.validator_address==$v) | .block_id_flag][0] // "missing"')
  echo "$B $FLAG"
done
```

Interpretation:
- `catching_up=false`, positive voting power, recent block times, and recent
  commit signatures mean the consensus validator is operational.
- `block_id_flag` values may be numeric in CometBFT JSON. Treat `2` as a
  commit signature.
- Axelar validator health also requires `vald`, `tofnd`, broadcaster funding,
  and expected external-chain maintainer registration.

## Alert Triage

For a missed-block, vald, tofnd, broadcaster, or external-chain alert:

1. Extract chain ID, moniker/label, valoper, consensus address, broadcaster,
   and affected external chain from the alert or monitoring config.
2. Match consensus address and valoper to the actual host before acting.
3. Compare local RPC and public RPC height. If both are stuck at the same
   height, suspect a network-wide halt or upgrade.
4. Check recent consensus signing for the last 5-10 finalized blocks.
5. Run `axelard health-check` and query staking state:

```bash
axelard health-check --tofnd-host 127.0.0.1 --operator-addr <valoper>
axelard query staking validator <valoper> --node <rpc> -o json |
  jq -r '(.validator // .) as $v | $v.status, $v.jailed, $v.tokens'
```

6. Check broadcaster balance and proxy registration:

```bash
axelard q bank balances <broadcaster> --node <rpc> -o json
axelard q snapshot proxy <valoper> --node <rpc> -o json
```

7. For vald issues, inspect recent vald logs before restart:

```bash
journalctl -u <vald-service> --since '30 minutes ago' --no-pager
```

High-signal vald patterns:
- `incorrect account sequence`: sequence drift or concurrent broadcaster use.
- `out of gas`: raise vald `--gas-adjustment` or investigate simulation.
- `poll not found`: often follows missed/late votes.
- `signing session not found`: investigate vald timing and tofnd/session state.
- `rpc client not found`, timeouts, or connection errors: inspect the affected
  external-chain RPC and bridge config.

Report format:

```text
Axelar status:
- Target: <moniker/valoper/host>
- Height: local <h>, public <h>
- Consensus: catching_up=<true|false>, signing <N>/<M>, voting_power=<vp>
- Validator: <bonded/unbonded>, jailed=<true|false>
- Companions: vald=<state>, tofnd=<state>, health-check=<passed/failed/details>
- Broadcaster: <balance>, proxy=<registered/unconfirmed>
- External chains: <ok/problem/unknown>
- Action: <none/restart/recovery/escalation>
- Notes: <one concise cause or uncertainty>
```

## Vald and External-Chain Workflow

Vald is not just a sidecar. It posts Axelar vote transactions for external
chains through the broadcaster account and depends on:

- local Axelar RPC latency and reliability;
- tofnd availability;
- broadcaster account sequence and balance;
- configured external-chain RPCs;
- on-chain chain-maintainer registration.

For persistent sequence drift:

1. Confirm no other process is using the broadcaster account.
2. Compare `localhost` and `127.0.0.1` latency if vald uses localhost.
3. Check local mempool, tx inclusion, and recent failed vote transaction codes.
4. Look for out-of-gas before blaming external-chain RPCs.
5. Restart vald at most once when there is a clear stuck local state; preserve
   logs first.
6. Do not schedule blind periodic consensus-node restarts to mask vald issues.

For external-chain RPC changes:

1. Confirm the affected chain from vald logs.
2. Benchmark current and candidate RPC endpoints with chain-appropriate calls.
3. Back up vald config before editing.
4. Enable/disable `start-with-bridge` and register/deregister maintainer status
   as a coordinated change.
5. Restart vald and verify `successfully connected to EVM bridge for chain
   <chain>` or the current equivalent log line.

## Upgrade Workflow

Before upgrade:

1. Confirm the on-chain upgrade plan:

```bash
axelard query upgrade plan --node <rpc> -o json
```

2. Confirm official release tag, release notes, binary signatures, and
   checksums from `axelarnetwork/axelar-core`.
3. Prefer a verified official binary or a reproducible/static build from the
   release tag. The official `axelar-core` README recommends `make
   build-static` for portable release builds.
4. Check whether the operator uses cosmovisor, manual systemd binaries, or the
   Axelar `${AXELARD_HOME}/bin` symlink layout.
5. Verify disk space, recent backups, and the exact service environment.

During upgrade:

1. Watch consensus logs, height, and upgrade halt behavior.
2. Avoid restart loops during a clean halt.
3. If vald/tofnd are restarted, do it deliberately and verify reconnection.

After upgrade:

1. Verify running process path and version:

```bash
PID=$(pgrep -f "axelard.*start" | head -1)
readlink -f /proc/$PID/exe
/proc/$PID/exe version
```

2. Verify RPC height advances, `catching_up=false`, recent consensus signing,
   staking state, `axelard health-check`, broadcaster balance, and vald
   external-chain connections.
3. Update operator docs, upgrade schedule, and daily memory.

## Recovery Playbook

Use the smallest safe fix first.

- Consensus RPC down, process alive: inspect logs, port binding, disk, and OOM
  before restart.
- Process dead: inspect last logs and systemd reason; restart once only if the
  cause is clear and reversible.
- Local height behind public height: check peers, disk IO, snapshots, and
  consensus logs. If only slightly behind, wait.
- Vald down while axelard is healthy: inspect vald logs, broadcaster balance,
  tofnd state, local RPC latency, and external-chain RPCs before restart.
- Tofnd down: inspect service, listener, key-store state, and recent signing
  logs; do not expose or rewrite tofnd secrets casually.
- App hash or data corruption: stop, preserve logs, back up keys and tofnd
  state, then use a trusted snapshot only after operator approval.
- Jailed validator: sync fully first, wait through the minimum jail period if
  needed, then unjail with correct wallet/fees only after confirming key
  ownership and operator approval.

Key backup pattern before deleting node data:

```bash
mkdir -p ~/backups
tar -czf ~/backups/axelar-keys-$(date +%Y%m%d).tar.gz \
  ~/.axelar/config/*key*.json ~/.axelar/keyring-file/ ~/.tofnd/
```

Use the operator's actual home paths when they differ from these defaults.

## External References

- Axelar app repository: https://github.com/axelarnetwork/axelar-core
- Axelar public configs: https://github.com/axelarnetwork/axelar-configs
- Axelar documentation: https://github.com/axelarnetwork/axelar-docs
- Validator setup docs:
  https://docs.axelar.dev/validator/setup/overview/
- Validator health check docs:
  https://docs.axelar.dev/validator/status/health-check/
- External-chain maintainer docs:
  https://docs.axelar.dev/validator/external-chains/overview/
