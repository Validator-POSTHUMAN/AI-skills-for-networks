---
name: cosmos-hub-validator-ops
description: "Operate Cosmos Hub Gaia validators and full nodes on cosmoshub-4: monitor gaiad/CometBFT health, signing, provider-security state, IBC/RPC/API/gRPC, upgrades, governance, snapshots, recovery, and safe operator reports."
---

# Cosmos Hub Validator Ops

Use this skill for Cosmos Hub operations: Gaia validator and full-node health,
missed-block triage, upgrades, Cosmovisor, snapshots, state sync, governance,
IBC-facing checks, provider-security checks, public RPC/API/gRPC operation, and
concise operator reports.

This skill is validator-neutral and provider-neutral. It must work for any
operator and must not assume a specific validator, RPC provider, server
provider, cloud, snapshot source, wallet, explorer, custody model, or monitoring
stack.

## Source Priority

1. Current command output from the target host, local RPC/API/gRPC, logs, and
   on-chain queries.
2. Local operator inventory, runbooks, deployment files, and monitoring config.
3. Official Cosmos Hub sources:
   - https://github.com/cosmos/gaia
   - https://docs.cosmos.network/hub/latest
   - https://github.com/cosmos/chain-registry/tree/master/cosmoshub
4. Governance proposals, release notes, security advisories, and upstream
   CometBFT/Cosmos SDK documentation for the exact running Gaia version.
5. Explorers and third-party RPCs only as secondary confirmation.

Always refresh official docs, Gaia tags, checksums, genesis, addrbook, seeds,
upgrade plans, and chain-registry data before preparing upgrades or changing
production configuration.

## Core Chain Facts

- Mainnet chain ID: cosmoshub-4.
- Daemon: gaiad.
- Default home: ~/.gaia.
- Bond and fee denom: uatom.
- Address prefixes: cosmos, cosmosvaloper, cosmosvalcons.
- Consensus: CometBFT/Tendermint RPC, usually on 26657 unless customized.
- Common public services: RPC, REST/API, gRPC, P2P, Prometheus metrics.
- Cosmos Hub is the ATOM staking hub and a provider chain for Interchain
  Security / consumer-chain security. Provider and consumer-chain state must be
  treated as part of validator operations when relevant.
- Gaia includes Cosmos SDK modules such as staking, slashing, distribution,
  governance, bank, upgrade, IBC, feegrant/authz, and provider-security modules.

These are orientation facts, not authorization to act. Verify live state and
current upstream documentation before changing a production node.

## Operator Inventory Guardrails

Before operating infrastructure, load the current operator's Cosmos Hub
inventory from local docs, monitoring config, deployment files, or explicit task
input. Required target fields are:

- Network and chain ID, normally cosmoshub-4.
- Host or SSH target when remote action is needed.
- Runtime: systemd, Docker, Kubernetes, binary, source build, or managed
  service.
- Node role: validator, sentry, full node, archive, public RPC/API/gRPC, IBC
  endpoint, snapshot source, or private infrastructure.
- Service/container/pod name.
- Local RPC endpoint and optional public/reference RPC endpoint.
- Daemon name, home directory, data directory, Cosmovisor layout, binary path,
  genesis path, and config paths.
- Validator moniker or inventory label.
- Valoper address and consensus address when validator-specific action is
  requested.
- Key custody references, never key contents.
- Consumer-chain participation expectations when provider-security checks are
  requested.
- Relayer services and IBC channel expectations when IBC checks are requested.
- Maximum acceptable local/public height gap and alert thresholds.

When a machine-readable inventory format is useful, read
references/inventory.schema.json. Use examples/inventory.example.json only as a
fake-value template; never treat it as production inventory.

If inventory is missing, inconsistent, or ambiguous, ask for the missing target
data before restarting services, changing config, submitting transactions,
restoring snapshots, deleting data, exposing RPC, or touching keys.

## Safety Rules

- Verify live state before claiming health, sync, signing, upgrade completion,
  or validator safety.
- Before restarting, prove the target service maps to the affected chain ID,
  valoper, and consensus address.
- Ask before destructive actions: data deletion, snapshot restore, validator
  key changes, signer changes, unjail, governance voting, staking edits,
  commission changes, public endpoint exposure, firewall changes, or transaction
  broadcast.
- Back up priv_validator_key.json, node_key.json, keyring references,
  priv_validator_state.json, app.toml, config.toml, client.toml, genesis,
  Cosmovisor metadata, and recent logs before destructive recovery.
- Preserve priv_validator_state.json and understand double-sign risk before
  moving validator data between hosts.
- Do not restart-loop during network-wide halts, upgrade boundaries, or public
  RPC stalls. Compare local and public/reference RPC first.
- Do not recommend a default server provider, RPC provider, wallet, explorer,
  relayer, snapshot provider, or custody model. Present requirements and
  tradeoffs, then use the operator's choice.
- Keep private keys, mnemonics, keyring passwords, RPC tokens, monitoring
  webhooks, wallet secrets, and private infrastructure details out of reports,
  examples, logs, and skill files.

## Health Check Workflow

Use the bundled helper when possible:

~~~bash
scripts/cosmoshub-healthcheck.sh \
  --host <ssh-target> \
  --service <systemd-service> \
  --rpc http://127.0.0.1:<rpc-port> \
  --public-rpc https://<reference-rpc> \
  --valcons <HEX_CONSENSUS_ADDRESS> \
  --valcons-bech32 <cosmosvalcons...> \
  --valoper <cosmosvaloper...> \
  --expected-chain-id cosmoshub-4
~~~

Use --local instead of --host when already running on the target host. Use
--blocks <n> to change the recent signing window and --daemon <name> if the
binary name differs from gaiad.

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

pgrep -af 'gaiad.*start|cosmovisor.*run start'
readlink -f /proc/$(pgrep -f "gaiad.*start" | head -1)/exe
gaiad version --long
~~~

Verify recent signatures:

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

- network=cosmoshub-4, catching_up=false, recent block times, positive voting
  power, enough peers, and recent commit signatures mean the validator is
  operational.
- block_id_flag may be numeric or string depending on CometBFT JSON. Treat 2
  and BLOCK_ID_FLAG_COMMIT as commit signatures.
- Peer churn such as EOF, connection reset, or pong timeout is not by itself an
  incident if blocks progress and the validator signs.

## Alert Triage

For a missed-block, RPC, sync, jail, public endpoint, or provider-security
alert:

1. Extract chain ID, moniker/label, valoper, consensus address, host, service,
   and RPC endpoint from the alert or inventory.
2. Match the consensus address and valoper to the actual target before acting.
3. Compare local and public/reference RPC height. If both are stuck at the same
   height, suspect a network-wide halt or upgrade.
4. Check recent signing for the last 5-10 finalized blocks.
5. Query validator and slashing state:

~~~bash
gaiad query staking validator <cosmosvaloper...> --node <rpc> -o json |
  jq -r '(.validator // .) as $v | $v.status, $v.jailed, $v.tokens'

gaiad query slashing signing-info <cosmosvalcons...> --node <rpc> -o json
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
Cosmos Hub status:
- Target: <moniker/valoper/host>
- Height: local <h>, public <h>, gap <n>
- Sync: chain_id=<id>, catching_up=<true|false>, peers=<n>
- Signing: <N>/<M> recent blocks, voting_power=<vp>
- Validator: <bonded/unbonded>, jailed=<true|false>
- Provider/IBC: <ok/problem/unknown/not checked>
- Action: <none/restart/recovery/escalation>
- Notes: <one concise cause or uncertainty>
~~~

## Upgrade Workflow

Before upgrade:

1. Confirm the on-chain upgrade plan:

~~~bash
gaiad query upgrade plan --node <rpc> -o json
~~~

2. Confirm the official Gaia release/tag, release notes, checksums, and build
   requirements from cosmos/gaia.
3. Confirm current binary, Cosmovisor environment, home, data directory, disk,
   backup location, and rollback path.
4. Build or install the target binary on the target host unless the operator's
   runbook says otherwise.
5. If using Cosmovisor, place the binary at:

~~~bash
~/.gaia/cosmovisor/upgrades/<upgrade-name>/bin/gaiad
~~~

6. Verify:

~~~bash
~/.gaia/cosmovisor/upgrades/<upgrade-name>/bin/gaiad version --long
ls -l ~/.gaia/cosmovisor/upgrades/<upgrade-name>/bin/gaiad
df -h ~/.gaia
~~~

During upgrade:

1. Watch height and logs.
2. Avoid repeated restarts during a clean upgrade halt.
3. If the binary switch fails, inspect Cosmovisor env, upgrade-info.json,
   current symlink, permissions, and process logs.

After upgrade:

1. Verify version, chain ID, height progression, catching_up=false, peers,
   recent signatures, staking status, and logs.
2. Check provider-security and IBC-related logs if the node serves those roles.
3. Record the final version, upgrade height, verification, and any follow-up in
   the operator's local documentation.

## Snapshot and State Sync Recovery

Snapshot or state-sync recovery is approval-gated because it replaces local
state.

Required preflight:

- Confirm node role, target host, service, chain ID, home/data directory, RPC,
  binary version, snapshot/state-sync source, and disk space.
- Back up keys, validator state, configs, genesis, addrbook, Cosmovisor
  metadata, and recent logs.
- Preserve existing data by moving it aside when disk allows.
- Verify snapshot network, height, checksum when available, compression format,
  ownership, and Gaia/CometBFT compatibility.
- Restore priv_validator_state.json for validators before start.

Post-restore verification:

- Service/container active.
- Chain ID is cosmoshub-4.
- Height progresses and local/public gap shrinks.
- No database, app-hash, consensus, p2p, or keyring errors in logs.
- Validator signs recent blocks when expected.

## Governance and Transaction Guardrails

Governance, staking, unjail, redelegation, commission, validator edit,
provider-security, and IBC transactions require explicit operator approval
before broadcast.

Use dry-run/simulation and show the exact message, signer, chain ID, account,
sequence, gas, fee, memo, and target contract/module before asking for approval.
Never infer a vote option from personal preference or from another validator's
vote. If the operator requests analysis, distinguish facts, risks, tradeoffs,
and recommendation clearly.

## Provider Security and IBC Notes

When the task involves consumer chains, Replicated Security, Partial Set
Security, or provider module state:

- Refresh current Cosmos Hub docs and Gaia version-specific CLI help.
- Query on-chain provider module state before acting.
- Check whether the validator is expected to participate in the affected
  consumer chain.
- Treat consumer-chain opt-in/opt-out, key assignment, validator set changes,
  and reward/slashing effects as approval-gated.

When the task involves IBC:

- Identify exact clients, connections, channels, counterparty chains, relayer
  service, and packet flow before restarting or changing relayer config.
- Do not treat an RPC issue as an IBC incident until client/channel and packet
  state are checked.

## How to Use

For an AI-agent session, reference the skill and provide your own inventory:

~~~text
Use the Cosmos Hub skill.
Network: cosmoshub-4.
Runtime: <systemd|docker|kubernetes|binary>.
Local RPC: <http://127.0.0.1:26657 or custom>.
Service/container: <name>.
Valoper: <cosmosvaloper...>.
Consensus address: <hex and/or cosmosvalcons...>.
Task: run a health check / triage missed blocks / prepare upgrade / plan snapshot recovery / review governance transaction.
~~~

Keep production inventory, secrets, and real validator-specific details in your
private operational docs, not in the public skill repository.
