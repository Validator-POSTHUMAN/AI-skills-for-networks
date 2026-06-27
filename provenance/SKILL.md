---
name: provenance-validator-ops
description: "Operate Provenance Blockchain validators and full nodes on pio-mainnet-1: monitor provenanced/CometBFT health, signing, upgrades, governance, snapshots, public RPC/API/gRPC, and safe recovery."
---

# Provenance Validator Ops

Use this skill for Provenance Blockchain operations: `provenanced` validator
and full-node health, missed-block triage, upgrades, Cosmovisor, snapshots,
state sync, governance, public RPC/API/gRPC operation, application-module
checks, safe recovery, and concise operator reports.

This skill is validator-neutral and provider-neutral. It must work for any
operator and must not assume a specific validator, RPC provider, server
provider, snapshot source, wallet, explorer, custody model, or monitoring
stack.

## Source Priority

1. Current command output from the target host, local RPC/API/gRPC, logs, and
   on-chain queries.
2. Local operator inventory, runbooks, deployment files, and monitoring config.
3. Official Provenance sources:
   - https://github.com/provenance-io/provenance
   - https://github.com/provenance-io/mainnet
   - https://docs.provenance.io/
   - https://github.com/cosmos/chain-registry/tree/master/provenance
4. Governance proposals, release notes, security advisories, and upstream
   Cosmos SDK / CometBFT documentation for the exact running version.
5. Explorers and third-party RPCs only as secondary confirmation.

Always refresh official docs, release tags, checksums, genesis, mainnet config,
seeds, upgrade plans, and chain-registry data before preparing upgrades or
changing production configuration.

## Core Chain Facts

- Mainnet chain ID: `pio-mainnet-1`.
- Daemon: `provenanced`.
- Default home: `~/.provenanced`.
- Bond and fee denom: `nhash`; 1 HASH = 1,000,000,000 nhash.
- Address prefixes: `pb`, `pbvaloper`, `pbvalcons`.
- Official mainnet config directory: `pio-mainnet-1` in
  `provenance-io/mainnet`.
- Official mainnet seed nodes at publication time:
  `4bd2fb0ae5a123f1db325960836004f980ee09b4@seed-0.provenance.io:26656,048b991204d7aac7209229cbe457f622eed96e5d@seed-1.provenance.io:26656`.
- Provenance is a Cosmos SDK / CometBFT chain for financial applications. It
  includes standard Cosmos modules plus Provenance modules such as marker,
  metadata, name, attribute, exchange, smart contract, and related application
  functionality.
- Latest official Provenance release observed at publication time: `v1.29.0`.

These are orientation facts, not authorization to act. Verify live state and
current upstream documentation before changing a production node.

## Operator Inventory Guardrails

Before operating infrastructure, load the current operator's Provenance
inventory from local docs, monitoring config, deployment files, or explicit task
input. Required target fields are:

- Network and chain ID, normally `pio-mainnet-1`.
- Host or SSH target when remote action is needed.
- Runtime: systemd, Docker, Kubernetes, binary, source build, or managed
  service.
- Node role: validator, sentry, full node, archive, public RPC/API/gRPC,
  snapshot source, or private infrastructure.
- Service/container/pod name.
- Local RPC endpoint and optional public/reference RPC endpoint.
- Daemon name, home directory, data directory, Cosmovisor layout, binary path,
  genesis path, and config paths.
- Validator moniker or inventory label.
- Valoper address and consensus address when validator-specific action is
  requested.
- Key custody references, never key contents.
- Public endpoint, reverse proxy, TLS, and metrics expectations when operating
  public services.
- Maximum acceptable local/public height gap and alert thresholds.

When a machine-readable inventory format is useful, read
`references/inventory.schema.json`. Use `examples/inventory.example.json`
only as a fake-value template; never treat it as production inventory.

If inventory is missing, inconsistent, or ambiguous, ask for the missing target
data before restarting services, changing config, submitting transactions,
restoring snapshots, deleting data, exposing RPC, or touching keys.

## Safety Rules

- Verify live state before claiming health, sync, signing, upgrade completion,
  or validator safety.
- Before restarting, prove the target service maps to the affected
  `pio-mainnet-1` node, valoper, and consensus address.
- Ask before destructive actions: data deletion, snapshot restore, validator
  key changes, signer changes, unjail, governance voting, staking edits,
  commission changes, marker/metadata/name/attribute/exchange transactions,
  public endpoint exposure, firewall changes, or transaction broadcast.
- Back up `priv_validator_key.json`, `node_key.json`, keyring references,
  `priv_validator_state.json`, `app.toml`, `config.toml`, `client.toml`,
  genesis, Cosmovisor metadata, and recent logs before destructive recovery.
- Preserve `priv_validator_state.json` and understand double-sign risk before
  moving validator data between hosts.
- Do not restart-loop during network-wide halts, upgrade boundaries, or public
  RPC stalls. Compare local and public/reference RPC first.
- Treat inactive, unbonded, or temporarily out-of-active-set status as a
  validator state signal, not automatically a service failure. Query staking
  and slashing state before unjail or restart decisions.
- Do not recommend a default server provider, RPC provider, wallet, explorer,
  snapshot provider, or custody model. Present requirements and tradeoffs, then
  use the operator's choice.
- Keep private keys, mnemonics, keyring passwords, RPC tokens, monitoring
  webhooks, wallet secrets, and private infrastructure details out of reports,
  examples, logs, and skill files.

## Health Check Workflow

Use the bundled helper when possible:

~~~bash
scripts/provenance-healthcheck.sh \
  --host <ssh-target> \
  --service <systemd-service> \
  --rpc http://127.0.0.1:<rpc-port> \
  --public-rpc https://<reference-rpc> \
  --valcons <HEX_CONSENSUS_ADDRESS> \
  --valoper <pbvaloper...> \
  --expected-chain-id pio-mainnet-1
~~~

Use `--local` instead of `--host` when already running on the target host.
Use `--blocks <n>` to change the recent signing window and `--daemon <name>`
if the binary name differs from `provenanced`.

Manual baseline:

~~~bash
systemctl is-active <service>; systemctl is-enabled <service> || true

curl -fsS <rpc>/status | jq -r '
  .result.node_info.network,
  .result.sync_info.latest_block_height,
  .result.sync_info.latest_block_time,
  .result.sync_info.catching_up,
  .result.validator_info.voting_power'

curl -fsS <rpc>/net_info | jq -r '.result.n_peers'
pgrep -af 'provenanced.*start|cosmovisor.*run start'
readlink -f /proc/$(pgrep -f "provenanced.*start" | head -1)/exe
provenanced version --long
~~~

Verify recent signatures for validators:

~~~bash
H=$(curl -fsS <rpc>/status | jq -r .result.sync_info.latest_block_height)
for B in $((H-1)) $((H-2)) $((H-3)) $((H-4)) $((H-5)); do
  curl -fsS "<rpc>/block?height=$B" |
    jq -r --arg v "<HEX_CONSENSUS_ADDRESS>" \
      '"flag=" +
      ([.result.block.last_commit.signatures[]? |
        select(.validator_address==$v) | .block_id_flag][0] // "missing")'
done
~~~

Interpretation:

- `network=pio-mainnet-1`, `catching_up=false`, recent block times,
  enough peers, and local/public height agreement mean the node is operational.
- Positive voting power and recent commit signatures are required before
  claiming an active validator is signing.
- `block_id_flag` may be numeric or string depending on CometBFT JSON. Treat
  `2` and `BLOCK_ID_FLAG_COMMIT` as commit signatures.
- Peer churn such as EOF, connection reset, or pong timeout is not by itself an
  incident if blocks progress and the validator signs.

## Alert Triage

For a missed-block, RPC, sync, jail, public endpoint, or application-module
alert:

1. Extract chain ID, moniker/label, valoper, consensus address, host, service,
   and RPC endpoint from the alert or inventory.
2. Match the consensus address and valoper to the actual target before acting.
3. Compare local and public/reference RPC height. If both are stuck at the same
   height, suspect a network-wide halt or upgrade.
4. Check recent signing for the last 5-10 finalized blocks when a consensus
   address is provided.
5. Query validator and slashing state:

~~~bash
provenanced query staking validator <pbvaloper...> --node <rpc> -o json |
  jq -r '(.validator // .) as $v | $v.status, $v.jailed, $v.tokens'

provenanced query slashing signing-info <pbvalcons...> --node <rpc> -o json
~~~

6. Preserve recent logs before changing process state:

~~~bash
journalctl -u <service> --since '30 minutes ago' --no-pager
~~~

7. Restart only for clear local failure: process dead, RPC down, local height
   stuck while public height advances, unrecoverable panic, or exhausted local
   resources. Do at most one controlled restart before escalating.

Report format:

~~~text
Provenance status:
- Target: <moniker/valoper/host>
- Height: local <h>, public <h>, gap <n>
- Sync: chain_id=<id>, catching_up=<true|false>, peers=<n>
- Signing: <N>/<M> recent blocks, voting_power=<vp>
- Validator: <bonded/unbonded/unbonding>, jailed=<true|false>
- Endpoints: RPC/API/gRPC <ok/problem/unknown/not checked>
- Action: <none/restart/recovery/escalation>
- Notes: <one concise cause or uncertainty>
~~~

## Upgrade Workflow

Before upgrade:

1. Confirm the on-chain upgrade plan:

~~~bash
provenanced query upgrade plan --node <rpc> -o json
~~~

2. Confirm the official Provenance release/tag, release notes, plan JSON,
   checksums, and build requirements from `provenance-io/provenance`.
3. Confirm current binary, Cosmovisor environment, home, data directory, disk,
   backup location, and rollback path.
4. Build or install the target binary on the target host unless the operator's
   runbook says otherwise.
5. If using Cosmovisor, place the binary at:

~~~bash
~/.provenanced/cosmovisor/upgrades/<upgrade-name>/bin/provenanced
~~~

6. Verify:

~~~bash
~/.provenanced/cosmovisor/upgrades/<upgrade-name>/bin/provenanced version --long
ls -l ~/.provenanced/cosmovisor/upgrades/<upgrade-name>/bin/provenanced
df -h ~/.provenanced
~~~

During upgrade:

1. Watch height and logs.
2. Avoid repeated restarts during a clean upgrade halt.
3. If the binary switch fails, inspect Cosmovisor env, `upgrade-info.json`,
   current symlink, permissions, and process logs.

After upgrade:

1. Verify version, chain ID, height progression, `catching_up=false`, peers,
   recent signatures when applicable, staking status, and logs.
2. Check public RPC/API/gRPC and reverse proxy health if the node serves public
   endpoints.
3. Record the final version, upgrade height, verification, and any follow-up in
   the operator's local documentation.

## Snapshot and State Recovery

Use the smallest safe fix first.

- RPC down, process alive: inspect logs, port binding, and reverse proxy before
  restart.
- Process dead: inspect last logs, disk, OOM/systemd reason; restart once if
  the cause is clear and reversible.
- Local height behind public height: check peers, disk IO, snapshot state, and
  consensus logs. If only slightly behind, wait.
- App hash, database, or state corruption: stop, preserve logs, back up keys and
  state, then use an operator-selected snapshot only after approval.
- Jailed: sync fully first, verify key ownership and wallet authorization, then
  unjail only after explicit approval.

Key backup pattern before deleting node data:

~~~bash
mkdir -p ~/backups
tar -czf ~/backups/provenance-keys-$(date +%Y%m%d).tar.gz \
  ~/.provenanced/config/*key*.json ~/.provenanced/keyring-file/
~~~

For snapshot restore, verify source, network, client compatibility, checksum,
size, height, disk space, and ownership. Move existing data aside instead of
deleting it when disk allows, preserve `priv_validator_state.json`, and verify
post-restore chain ID, height progression, local/public gap, logs, and recent
validator signatures.

## Public Endpoint Checks

For public RPC/API/gRPC services:

- Confirm local service health first, then reverse proxy/TLS.
- Compare public height and chain ID to local RPC.
- Check API and gRPC only through the operator's documented endpoints.
- Do not expose new ports, change firewall rules, or alter TLS/proxy config
  without operator approval.
- Keep rate-limit, WAF, Prometheus, and alert credentials outside this skill.

## Governance and Application Transactions

For governance, staking, marker, metadata, name, attribute, exchange, wasm, or
other application transactions:

- Use read-only queries first.
- Prepare unsigned or dry-run transactions when possible.
- Show chain ID, account, sequence, fees, gas, messages, signer, and target
  module before requesting approval.
- Do not broadcast without explicit operator approval.
- Avoid `--gas auto` if the operator's runbook has fixed gas/fee rules for
  Provenance.

## External References

- Provenance app repository: https://github.com/provenance-io/provenance
- Provenance mainnet repository: https://github.com/provenance-io/mainnet
- Provenance docs: https://docs.provenance.io/
- Mainnet directory:
  https://github.com/provenance-io/mainnet/tree/main/pio-mainnet-1
- Explorer: https://explorer.provenance.io/
- Chain registry:
  https://github.com/cosmos/chain-registry/tree/master/provenance
