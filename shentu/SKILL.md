---
name: shentu-validator-ops
description: "Operate Shentu Chain validators on shentu-2.2: monitor node health, verify signing, prepare and execute upgrades, triage Tenderduty alerts, recover safely, and write concise operator reports."
---

# Shentu Validator Ops

Use this skill for Shentu Chain validator operations: health checks, upgrade
windows, missed-block alerts, stuck nodes, RPC issues, service restarts,
post-upgrade verification, and concise status reports.

## Source Priority

1. Current command output from the target host and public RPC/API.
2. Local operator inventory and chain-specific runbooks, if available.
3. Official Shentu repositories:
   - https://github.com/shentufoundation/shentu
   - https://github.com/shentufoundation/mainnet
4. Public explorers/RPCs only as secondary confirmation.

Never claim the validator is healthy, upgraded, or signing without live checks.

## Chain Facts

- Chain ID: `shentu-2.2`
- Daemon: `shentud`
- Default home: `~/.shentud`
- Bond denom: `uctk`
- Current official mainnet directory:
  `shentu-2.2` in `shentufoundation/mainnet`
- Official seeds at publication time:
  `867a2986f28575b1fde864136862fde465cac17c@47.253.209.134:26656,3edd4e16b791218b623f883d04f8aa5c3ff2cca6@shentu-seed.panthea.eu:36656`
- Latest verified release at publication time: `v2.18.0`
  (`1e23f5f7c66e90ecc4309f6964b0792d6b1e761b`).

These are publication-time defaults, not authorization to act. Always refresh
official repositories, tags, checksums, seeds, and on-chain upgrade plans before
preparing an upgrade or changing peer configuration.

## Operator Inventory Guardrails

This skill is validator-neutral and server-neutral. It must work for any
Shentu validator operator and must not assume a specific team, host, service
name, RPC port, moniker, valoper, or consensus address.

Before operating infrastructure, load the current operator's Shentu inventory
from their local knowledge base, runbook, monitoring config, or explicit task
input. Required target fields are:

- Host or SSH target.
- Systemd service name.
- Local RPC endpoint.
- Validator moniker or label.
- Valoper address.
- Consensus address.

When a machine-readable inventory format is useful, read
`references/inventory.schema.json`. Use
`examples/inventory.example.json` only as a fake-value template; never treat it
as production inventory.

If the inventory is missing, inconsistent, or ambiguous, ask the operator for
the missing target data before restarting services or deleting data. Do not use
examples from this skill as real inventory.

## Safety Rules

- Before any destructive recovery, back up validator keys. Do not delete data
  until the operator approves.
- Before restarting, prove the target service matches the affected consensus
  address. A missed-block alert for one Shentu validator must not trigger a
  restart of another Shentu validator or another server.
- Do not trust `systemctl is-active` alone. A systemd unit can report inactive
  while the process/RPC are still live and caught up. Verify RPC, process, and
  signing before declaring a node down.
- Prefer waiting over restarting during network-wide halts, upgrade boundaries,
  or when public RPCs show the same stuck height.
- Before any restart, preserve recent logs and define the expected recovery
  signal. Do at most one controlled restart for a clear local fault before
  escalating to deeper recovery.
- For upgrades, prepare binaries in advance and verify the running process
  after the upgrade height.

## Health Check Workflow

Use the bundled script when possible:

```bash
scripts/shentu-healthcheck.sh \
  --host <ssh-target> \
  --service <systemd-service> \
  --rpc http://127.0.0.1:<port> \
  --valcons <HEX_CONSENSUS_ADDRESS> \
  --valoper <shentuvaloper...> \
  --public-rpc https://<public-rpc>
```

Use `--local` instead of `--host` when already running on the target host.
Use `--blocks <n>` to change the recent signing window and `--daemon <name>`
if the binary name differs from `shentud`.

Manual checks:

```bash
systemctl is-active <service>; systemctl is-enabled <service> || true

curl -fsS <rpc>/status | jq -r '
  .result.sync_info.latest_block_height,
  .result.sync_info.latest_block_time,
  .result.sync_info.catching_up,
  .result.validator_info.voting_power'

pgrep -af shentud
readlink -f /proc/$(pgrep -f "shentud.*start" | head -1)/exe
/proc/$(pgrep -f "shentud.*start" | head -1)/exe version

curl -fsS <rpc>/net_info | jq -r '.result.n_peers'
```

Verify signing for the last few blocks:

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
  signatures mean the validator is operational.
- `block_id_flag` values may be numeric in CometBFT JSON. Treat `2` as a
  commit signature.
- Peer churn such as `connection reset`, `EOF`, or `pong timeout` is not
  by itself an incident if blocks progress and the validator signs.

## Alert Triage

For a Tenderduty or missed-block alert:

1. Extract chain ID, moniker/label, valoper, and consensus address from the
   alert or Tenderduty config.
2. Match the consensus address to the actual host before acting.
3. Check local RPC and public RPC height. If both are stuck at the same height,
   suspect a network-wide halt.
4. Check whether the validator signed the last 5-10 finalized blocks.
5. Check jailed status:

```bash
shentud query staking validator <valoper> --node <rpc> -o json |
  jq -r '(.validator // .) as $v | $v.status, $v.jailed, $v.tokens'
```

6. Preserve recent logs before changing process state:

```bash
journalctl -u <service> -n 300 --no-pager
```

7. Restart only if the target node is the affected validator and there is clear
   local failure: RPC down, process dead, stuck local height while public RPC
   advances, or logs show a local panic.

Report format:

```
Shentu status:
- Target: <moniker/valoper/host>
- Height: local <h>, public <h>
- Sync: catching_up=<true|false>
- Signing: <N>/<M> recent blocks
- Validator: <bonded/unbonded>, jailed=<true|false>
- Action: <none/restart/recovery/escalation>
- Notes: <one concise cause or uncertainty>
```

## Upgrade Workflow

Official Shentu upgrade instructions historically use a simple binary swap at
the scheduled height. If the operator uses cosmovisor, still verify the exact
cosmovisor layout and environment on the host.

Before upgrade:

1. Confirm the on-chain upgrade plan:

```bash
shentud query upgrade plan --node <rpc> -o json
```

2. Confirm official release/tag and checksum from
   `shentufoundation/shentu`.
3. Prepare the binary on the target host or install the official release binary.
4. If using cosmovisor, place it at:

```bash
~/.shentud/cosmovisor/upgrades/<upgrade-name>/bin/shentud
```

5. Verify:

```bash
~/.shentud/cosmovisor/upgrades/<upgrade-name>/bin/shentud version
ls -l ~/.shentud/cosmovisor/upgrades/<upgrade-name>/bin/shentud
df -h ~/.shentud
```

During upgrade:

1. Watch logs and height.
2. Do not repeatedly restart during a clean upgrade halt.
3. If the node fails to switch, inspect cosmovisor env, current symlink,
   upgrade-info.json, and binary executable permissions.

After upgrade:

1. Verify running process path and version:

```bash
PID=$(pgrep -f "shentud.*start" | head -1)
readlink -f /proc/$PID/exe
/proc/$PID/exe version
```

2. Verify RPC height advances, `catching_up=false`, recent signing, bonded
   status, and pending upgrade plan is empty or resolved.
3. Update operator docs, upgrade schedule, and daily memory.

## Recovery Playbook

Use the smallest safe fix first.

- RPC down, process alive: inspect logs and port binding before restart.
- Process dead: inspect last logs, disk, OOM/systemd reason; restart once if
  the cause is clear and reversible.
- Local height behind public height: check peers, disk IO, snapshots, and
  consensus logs. If only slightly behind, wait.
- App hash or data corruption: stop, preserve logs, back up keys, then use a
  trusted snapshot only after operator approval.
- Jailed: sync fully first, then unjail with correct wallet/fees only after
  confirming key ownership and operator approval.

Key backup pattern before deleting node data:

```bash
mkdir -p ~/backups
tar -czf ~/backups/shentu-keys-$(date +%Y%m%d).tar.gz \
  ~/.shentud/config/*key*.json ~/.shentud/keyring-file/
```

## External References

- Shentu app repository: https://github.com/shentufoundation/shentu
- Shentu mainnet repository: https://github.com/shentufoundation/mainnet
- Current mainnet directory:
  https://github.com/shentufoundation/mainnet/tree/main/shentu-2.2
- Official releases:
  https://github.com/shentufoundation/shentu/releases

## Skill Evaluation

Use `evals/shentu-skill-scenarios.md` when validating whether an agent applies
this skill safely across ambiguous alerts, RPC failures, network halts, local
stalls, and jailed-validator workflows.
