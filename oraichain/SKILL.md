---
name: oraichain-validator-ops
description: "Operate Oraichain validators and nodes: monitor oraid health and signing, prepare upgrades, triage RPC/API/gRPC and CosmWasm/oracle issues, recover safely, and write concise operator reports."
---

# Oraichain Validator Ops

Use this skill for Oraichain validator and full-node operations: health checks,
missed-block alerts, public endpoint issues, upgrades, snapshot recovery,
Cosmovisor work, staking transactions, CosmWasm/oracle workflows, and concise
operator reports.

This skill is validator-neutral and provider-neutral. It must not assume a
specific validator, server provider, RPC provider, moniker, service name, port,
wallet, key custody model, or monitoring stack.

## Source Priority

1. Current command output from the target host and live RPC/API/gRPC endpoints.
2. The operator's own inventory, runbooks, monitoring config, and incident
   notes.
3. Official Oraichain documentation and repositories:
   - https://docs.orai.io/
   - https://github.com/oraichain/orai
   - https://github.com/oraichain
4. Public explorers and third-party RPCs only as secondary confirmation.

Never claim a node is healthy, upgraded, synced, or signing without live
checks. Always refresh official docs, releases, upgrade plans, genesis files,
contract addresses, fees, and bridge/oracle parameters before acting.

## Chain Facts

- Network: Oraichain mainnet.
- Chain ID: Oraichain.
- Daemon: oraid.
- Default home: ~/.oraid.
- Native denom: orai.
- Validator address prefix: oraivaloper.
- Consensus address source: oraid tendermint show-validator.
- Official docs: https://docs.orai.io/.
- Main app repository: https://github.com/oraichain/orai.

Oraichain is an AI-focused Cosmos SDK network with CosmWasm smart contracts,
IBC connectivity, oracle services, OraiDEX/OBridge/OraiBTC ecosystem
components, VRF 2.0, price feed / CW Oracle Hub workflows, and OraichainEVM
compatibility through EVM/CosmWasm integration and precompile paths.

Publication-time reference only: the latest observed orai release was v0.42.4.
Do not treat this as current truth. Refresh official tags, release notes, and
on-chain upgrade plans before building or upgrading.

## Operator Inventory Guardrails

Before operating infrastructure, load the current operator's Oraichain
inventory from local docs, monitoring config, or explicit task input.

Required fields for validator operations:

- Host or SSH target.
- Runtime type: systemd, Docker, Kubernetes, binary, or managed service.
- Service/container name.
- Local CometBFT RPC endpoint.
- API and gRPC endpoints when relevant.
- Daemon name, home directory, and data directory.
- Validator moniker or label.
- Valoper address.
- Consensus address.
- Keyring backend or signer reference, without secrets.
- Cosmovisor layout when used.

Optional fields for extended Oraichain work:

- Public/reference RPC for height comparison.
- Snapshot source and checksum policy.
- Prometheus, Grafana, or Tenderduty targets.
- Oracle, price-feed, VRF, OBridge, OraiBTC, OraiDEX, or EVM component names.
- Contract addresses, only when sourced from official docs or operator
  inventory.
- Reverse proxy and firewall paths for public RPC/API/gRPC endpoints.

When a machine-readable inventory format is useful, read
references/inventory.schema.json. Use examples/inventory.example.json only as a
fake-value template; never treat it as production inventory.

If inventory is missing or inconsistent, ask for the missing target data before
restarts, snapshot restore, unjail, staking transactions, bridge actions,
contract changes, or oracle/VRF provider changes.

## Safety Rules

- Do not perform destructive recovery without explicit operator approval.
- Back up validator keys, signer references, config, priv_validator_state.json,
  and recent logs before replacing or deleting data.
- Never publish mnemonics, private keys, keyring passwords, RPC tokens,
  Ethereum endpoint tokens, signer credentials, or bridge custody secrets.
- Match the affected valoper and consensus address to the target host before
  restart or recovery.
- Do not trust systemctl alone. Verify RPC, process, height progression, peers,
  voting power, and recent signatures.
- Prefer waiting over restarting during network-wide halts, upgrade boundaries,
  or when local and public RPCs are stuck at the same height.
- Use official Oraichain docs and repos for versions, commands, fees,
  contracts, bridge parameters, and oracle/VRF workflows.
- Treat create-validator, edit-validator, delegation, unjail, key changes,
  bridge transfers, OraiDEX/OBridge/OraiBTC transactions, EVM/precompile
  contract changes, and oracle/VRF provider updates as approval-gated.

## Health Check Workflow

Use the bundled script when possible:

~~~bash
scripts/oraichain-healthcheck.sh \
  --host user@host \
  --service oraid \
  --rpc http://127.0.0.1:26657 \
  --expected-chain-id Oraichain \
  --valcons HEX_CONSENSUS_ADDRESS \
  --valoper oraivaloper...
~~~

Use --local instead of --host when already running on the target host. The
valcons and valoper fields are optional for full-node checks, but required for
signing and staking-status verification.

Manual baseline:

~~~bash
systemctl is-active <service>; systemctl is-enabled <service> || true
curl -fsS <rpc>/status | jq -r '.result.node_info.network, .result.sync_info.latest_block_height, .result.sync_info.latest_block_time, .result.sync_info.catching_up, .result.validator_info.voting_power'
curl -fsS <rpc>/net_info | jq -r '.result.n_peers'
oraid query slashing signing-info "$(oraid tendermint show-validator)" --node <rpc> -o json
~~~

Interpretation:

- catching_up=false, recent block time, peers, and local/public height
  progression mean the full node is probably healthy.
- Positive voting power plus recent commit signatures mean the validator is
  signing.
- CometBFT block_id_flag may be numeric. Treat 2 as a commit signature.
- Peer churn such as EOF, connection reset, or timeout is not an incident by
  itself if the node progresses and signs.

## Alert Triage

For missed blocks, endpoint alerts, or Tenderduty warnings:

1. Extract chain ID, moniker, valoper, consensus address, host, and local RPC.
2. Confirm the alert target matches the actual Oraichain service.
3. Compare local and public RPC heights.
4. Check catching_up, peers, process, disk, and recent logs.
5. Check recent signatures when valcons is known.
6. Check validator status:

~~~bash
oraid query staking validator <oraivaloper...> --node <rpc> -o json |
  jq -r '(.validator // .) as $v | $v.status, $v.jailed, $v.tokens'
~~~

7. Restart only for a clear local fault: process dead, RPC unreachable, local
   height stuck while public RPC advances, or logs show a local panic.

Report format:

~~~text
Oraichain status:
- Target: <moniker/valoper/host>
- Height: local <h>, public <h>, gap <n>
- Sync: catching_up=<true|false>, peers=<n>
- Signing: <N>/<M> recent blocks
- Validator: <bonded/unbonded>, jailed=<true|false>
- Action: <none/restart/recovery/escalation>
- Notes: <one concise cause or uncertainty>
~~~

## Upgrade Workflow

Before upgrade:

1. Confirm the on-chain upgrade plan with oraid query upgrade plan --node <rpc>
   -o json.
2. Confirm official tag, release notes, build instructions, and checksum from
   the Oraichain repositories.
3. Confirm Go version and build requirements from the selected release.
4. Build or install the binary on the target host unless the operator's policy
   says otherwise.
5. If using Cosmovisor, verify layout, environment, upgrade-info.json,
   executable permissions, and service user.
6. Preserve current binary path, version, service environment, and disk state.

After upgrade, verify version, RPC status, height progression, peers, logs,
local/public height gap, and signing.

## Snapshot And State Recovery

Snapshot restore is approval-gated.

Minimum safe flow:

1. Confirm network, service, home, data dir, snapshot source, and target height.
2. Stop service cleanly.
3. Preserve config, keys, keyring references, priv_validator_state.json, recent
   logs, binary version, and current metadata.
4. Move the existing data directory aside when disk allows.
5. Verify snapshot source, checksum, size, height, chain ID, and extraction
   command.
6. Restore data with correct owner and permissions.
7. Restore priv_validator_state.json only when the recovery method requires it
   and the operator approves.
8. Start service.
9. Verify RPC, height progression, local/public gap, logs, and signing.
10. Keep rollback data until the operator confirms cleanup.

The skill does not recommend a default snapshot provider. The operator supplies
the source or asks the agent to compare options.

## Oraichain Development And Ecosystem Workflows

For CosmWasm, oracle, VRF, OraiDEX, OBridge, OraiBTC, and OraichainEVM tasks:

- Start from official Oraichain docs and repositories.
- Refresh contract addresses, chain IDs, gas prices, token denoms, bridge
  routes, and precompile details before preparing commands.
- Treat transaction broadcast, key use, contract migration, bridge transfer,
  provider registration, and production endpoint changes as approval-gated.
- Keep wallet and RPC credentials outside chat, docs, and skill files.
- When debugging app integrations, separate node/RPC health, API/gRPC health,
  contract logic, wallet/client behavior, and bridge/oracle dependencies.

## Operator Report Rules

A good report is concise and evidence-based:

- what was checked
- current height and sync state
- signing result when relevant
- validator jailed/status result when relevant
- action taken or intentionally skipped
- remaining risk or missing input

Do not bury uncertainty. If official docs, releases, or inventory are stale or
missing, say what must be refreshed before acting.
