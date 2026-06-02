---
name: fuel-network-ops
description: "Operate and build on Fuel Network: Fuel Ignition fuel-core full nodes, GraphQL API, Fuel Sequencer Cosmos nodes and validators, sidecar/Ethereum dependencies, upgrades, snapshots, bridge workflows, Sway/forc tooling, monitoring, and safe incident triage."
---

# Fuel Network Ops

Use this skill for Fuel Network operations and development: Fuel Ignition
fuel-core full nodes, GraphQL API service, Fuel Sequencer fuelsequencerd nodes
and validators, sidecar/Ethereum dependencies, bridge workflows, snapshots,
upgrades, Sway/forc tooling, and concise operator reports.

This skill is validator-neutral and provider-neutral. It must work for any
operator or builder and must not assume a specific validator, RPC provider,
server provider, wallet, explorer, cloud, snapshot source, relayer stack, or
custody model.

## Source Priority

1. Current command output from the target host, local RPC/GraphQL, logs, and
   project repositories.
2. Local operator inventory and runbooks, if available.
3. Official Fuel sources:
   - https://docs.fuel.network/
   - https://docs.fuel.network/docs/node-operator/
   - https://docs.fuel.network/docs/node-operator/fuel-ignition/
   - https://docs.fuel.network/docs/node-operator/fuel-ignition/mainnet-node/
   - https://docs.fuel.network/docs/node-operator/fuel-sequencer/
   - https://docs.fuel.network/docs/node-operator/fuel-sequencer/mainnet-node/
   - https://docs.fuel.network/docs/node-operator/fuel-sequencer/mainnet-validator/
   - https://docs.fuel.network/docs/graphql/overview/
   - https://github.com/FuelLabs/fuel-core
   - https://github.com/FuelLabs/chain-configuration
   - https://github.com/FuelLabs/fuel-sequencer-deployments
4. Upstream release notes, security notices, and issue trackers for
   fuel-core, fuelup, forc, fuelsequencerd, CometBFT/Cosmos SDK, and any
   operator-selected Ethereum client.

Always refresh official docs and releases before using versions, network
parameters, contract addresses, bridge commands, sequencer release tags,
genesis files, bootstrap nodes, or validator commands.

## Core Fuel Facts

- Fuel is an execution layer for Ethereum rollups with FuelVM, Sway, the UTXO
  model, native assets, and parallel transaction execution.
- Fuel Ignition is the main Fuel L2 network operated by fuel-core. fuel-core
  exposes GraphQL at /v1/graphql.
- Fuel Ignition mainnet GraphQL chain ID is documented as 9889; testnet is
  documented as 0. Verify against current chain configuration before signing or
  submitting transactions.
- fuelup installs the Fuel toolchain, including forc and fuel-core. forc node
  can abstract many fuel-core run flags; use dry-run mode when the operator
  wants to inspect the generated command.
- Fuel Ignition mainnet nodes require a reliable Ethereum Mainnet RPC endpoint
  for the relayer. Treat this L1 endpoint as a critical dependency and keep
  credentials out of reports and examples.
- Fuel Sequencer is a Cosmos SDK/CometBFT based shared sequencer network using
  fuelsequencerd, Cosmovisor, ~/.fuelsequencer, and chain IDs such as
  seq-mainnet-1 and seq-testnet-2.
- Sequencer validator setups may include a fuelsequencerd node, sidecar, and
  an Ethereum Mainnet full node or operator-selected Ethereum endpoint,
  depending on the official guide and operator requirements.

These facts are orientation, not authorization to act. Verify live state and
current upstream docs before changing production systems.

## Operator Inventory Guardrails

Before operating infrastructure, load the current operator's Fuel inventory
from local docs, monitoring config, deployment files, or explicit task input.
Required target fields depend on the mode.

Fuel Ignition / fuel-core:

- Network: mainnet, testnet, local, or devnet.
- Host or SSH target when remote action is needed.
- Runtime: systemd, Docker, Docker Compose, binary, source, Kubernetes, or
  managed service.
- Local GraphQL URL, usually http://127.0.0.1:PORT/v1/graphql.
- Service/container/pod name.
- Data directory and snapshot/chain-configuration path.
- Ethereum RPC dependency source, represented without secrets.
- P2P key custody reference, if P2P is enabled.
- Public GraphQL URL and maximum acceptable local/public height lag, if exposed.

Fuel Sequencer / fuelsequencerd:

- Network and chain ID, for example seq-mainnet-1 or seq-testnet-2.
- Host or SSH target when remote action is needed.
- Systemd service or container name.
- Local CometBFT RPC endpoint.
- Daemon binary name, normally fuelsequencerd.
- Home directory, normally ~/.fuelsequencer.
- Data directory, Cosmovisor layout, binary path, and genesis path.
- Node role: full node, public RPC, validator, sidecar host, or bridge helper.
- P2P peers/seeds, validator consensus address, valoper/operator address, and
  signer/key custody references when validator-specific action is requested.
- Sidecar URL/port and Ethereum dependency source when sidecar is enabled.

When a machine-readable inventory format is useful, read
references/inventory.schema.json. Use examples/inventory.example.json only as a
fake-value template; never treat it as production inventory.

If inventory is missing, inconsistent, or ambiguous, ask the operator for the
missing target data before restarting services, changing config, submitting
transactions, restoring snapshots, deleting data, exposing RPC, or touching
keys.

## Safety Rules

- Ask before fund-moving actions, bridge withdrawals/deposits, staking,
  validator creation/editing, signer changes, key changes, public RPC exposure,
  snapshot replacement, data deletion, or transaction submission.
- Back up key material and config before destructive recovery. For Sequencer,
  preserve priv_validator_key.json, node_key.json, keyring material,
  priv_validator_state.json, app.toml, config.toml, and genesis.
- Never paste private keys, mnemonics, P2P private keys, Ethereum RPC tokens,
  wallet secrets, keyring passwords, or bridge/signing secrets into chat,
  reports, examples, or skill files.
- Do not recommend a server provider, RPC provider, wallet, explorer, bridge
  interface, or snapshot provider as default. Present requirements and
  tradeoffs, then use the operator's choice.
- Treat the Ethereum dependency as critical. A node can look locally healthy
  while the relayer or sidecar is stalled because L1 is broken, rate-limited,
  misconfigured, or behind.
- Do not delete or rebuild node data first. Preserve logs, check live state,
  verify disk, and confirm snapshot/chain-configuration compatibility.
- During upgrades or network-wide halts, prefer observation, official release
  notes, and compatibility checks over restart loops.
- For Sequencer validators, prove the affected consensus address maps to the
  target host before restarting or changing signer state.

## Health Check Workflow

Use the bundled script when possible.

Fuel Ignition:

~~~bash
scripts/fuel-healthcheck.sh \
  --mode ignition \
  --host <ssh-target> \
  --service <systemd-service> \
  --graphql http://127.0.0.1:4000/v1/graphql \
  --public-graphql https://mainnet.fuel.network/v1/graphql \
  --expected-chain-name Ignition \
  --max-block-lag 100
~~~

Fuel Sequencer:

~~~bash
scripts/fuel-healthcheck.sh \
  --mode sequencer \
  --host <ssh-target> \
  --service <systemd-service> \
  --rpc http://127.0.0.1:26657 \
  --public-rpc https://<reference-rpc> \
  --expected-chain-id seq-mainnet-1 \
  --valcons <HEX_CONSENSUS_ADDRESS> \
  --valoper <fuelsequencervaloper...>
~~~

Use --local instead of --host when already running on the target host. Use
--container for Docker deployments and --data-dir to include disk usage.

Manual Fuel Ignition baseline:

~~~bash
curl -fsS http://127.0.0.1:<port>/v1/graphql \
  -H 'Content-Type: application/json' \
  --data '{"query":"query { chain { name daHeight latestBlock { header { height id } } } nodeInfo { nodeVersion } }"}'

curl -fsS https://mainnet.fuel.network/v1/graphql \
  -H 'Content-Type: application/json' \
  --data '{"query":"query { chain { latestBlock { header { height } } } }"}'
~~~

Manual Sequencer baseline:

~~~bash
curl -fsS http://127.0.0.1:<rpc-port>/status | jq -r '
  .result.node_info.network,
  .result.sync_info.latest_block_height,
  .result.sync_info.latest_block_time,
  .result.sync_info.catching_up'

curl -fsS http://127.0.0.1:<rpc-port>/net_info | jq -r '.result.n_peers'

fuelsequencerd status --node http://127.0.0.1:<rpc-port>
fuelsequencerd version
~~~

Healthy baseline:

- service/container is running and not flapping
- local height increases over time
- local/public height gap is inside the operator's SLO
- expected network/chain name or chain ID matches the inventory
- recent logs do not show repeated database, GraphQL/RPC, P2P, relayer,
  Ethereum, sidecar, consensus, or keyring errors
- disk and inode pressure are below the operator's thresholds
- Fuel Ignition relayer can reach Ethereum Mainnet
- Sequencer node has peers, is not catching up indefinitely, and validator
  targets are signing recent blocks when validator checks are requested

## Monitoring Baseline

Monitor Fuel at four layers:

- Runtime: systemd/container/pod state, restart count, recent logs, CPU,
  memory, disk, inode usage, file descriptors, and open port bindings.
- Fuel Ignition GraphQL: latest block height, block height progression, chain
  name, node version, DA height, GraphQL latency, error rate, public/local
  height gap, and wallet/app compatibility with the GraphQL URL.
- Sequencer CometBFT: latest block height/time, catching-up state, peer count,
  validator voting power, recent signatures, jailed/bonded status,
  mempool/RPC limits, and Cosmovisor upgrade state.
- Dependencies: Ethereum Mainnet RPC/L1 node health, sidecar health, reverse
  proxy health, TLS certificate expiry, firewall exposure, and snapshot source
  availability if snapshots are part of the recovery plan.

Prefer alerts on sustained conditions:

- process stopped or restart loop
- local height not increasing while public/reference height advances
- local/public lag exceeds the operator's SLO
- GraphQL/RPC endpoint unavailable or returning schema/server errors
- repeated relayer, Ethereum RPC, sidecar, database, P2P, or consensus errors
- disk/inode usage above threshold
- Sequencer validator missing signatures in recent finalized blocks
- bridge or sidecar transactions failing repeatedly

## Fuel Ignition Operations

Before running or changing a Fuel Ignition node:

1. Confirm network: mainnet, testnet, local, or devnet.
2. Confirm fuel-core version from official releases and the operator's
   compatibility target.
3. Confirm chain configuration source, snapshot path, data directory, and
   database compatibility.
4. Confirm Ethereum RPC endpoint source without exposing secrets.
5. Confirm P2P key custody if P2P is enabled.
6. Check fuel-core run --help or forc node <network> --help on the target
   version before changing flags.

Key operational checks:

~~~bash
fuel-core --version
fuel-core run --help
forc --version
fuelup show
ulimit -n
~~~

Use forc-node --dry-run ignition or the current equivalent when the operator
wants to inspect generated flags before starting a node. If the operator uses
raw fuel-core run, preserve all current flags before changing them.

## Fuel Sequencer Operations

Before running or changing a Sequencer node:

1. Confirm chain ID and release tag from fuel-sequencer-deployments.
2. Verify binary architecture, version, checksum when available, and genesis
   file.
3. Confirm ~/.fuelsequencer/config/app.toml and config.toml against current
   official docs.
4. Confirm Cosmovisor uses cosmovisor run start and the correct
   DAEMON_NAME=fuelsequencerd, DAEMON_HOME, and upgrade directories.
5. Confirm sidecar settings only when the node role requires sidecar.
6. Confirm CometBFT RPC, P2P, REST, gRPC, and sidecar port exposure.

Important config areas:

- minimum-gas-prices in app.toml: use the operator's intended policy and
  current official guidance. Do not assume validator and public entry-point
  policies are identical.
- sidecar config in app.toml: disabled for non-sidecar nodes, enabled and
  pointed at the sidecar only when the role requires it.
- mempool config in config.toml: keep max transaction size parameters aligned
  with current network guidance.
- RPC/API max body and timeout values: tune for public endpoints only with
  explicit exposure policy and reverse-proxy controls.
- state-sync: enable only when the operator intends to provide or use state
  sync and has verified trust height/hash sources.

## Snapshot Recovery

Snapshot recovery is destructive to database state. Ask before replacing or
deleting data. Preserve rollback state whenever disk allows.

Preflight:

1. Confirm network, node mode, runtime, service/container name, data directory,
   home directory, and snapshot source.
2. Read current official docs and release notes for snapshot/database
   compatibility.
3. Stop the service cleanly.
4. Save recent logs and current config.
5. Back up keys and state files according to the operator's secret policy.
6. Check disk space for archive and extracted data.
7. Verify snapshot checksum, size, network, client, and height when provided.

Sequencer restore shape:

~~~bash
sudo systemctl stop <fuelsequencerd-service>

mkdir -p <backup-dir>
cp -a ~/.fuelsequencer/config <backup-dir>/config-$(date +%Y%m%d-%H%M%S)
cp -a ~/.fuelsequencer/data/priv_validator_state.json <backup-dir>/priv_validator_state.json

mv ~/.fuelsequencer/data ~/.fuelsequencer/data.pre-snapshot-$(date +%Y%m%d-%H%M%S)
mkdir -p ~/.fuelsequencer

# Download, verify, and extract the operator-selected snapshot here.
# Restore priv_validator_state.json before starting if this is a validator.

sudo chown -R <node-user>:<node-group> ~/.fuelsequencer
sudo systemctl start <fuelsequencerd-service>
~~~

Fuel Ignition restore shape:

~~~bash
sudo systemctl stop <fuel-core-service>
cp -a <fuel-core-config-or-env> <backup-dir>/
mv <db-path> <db-path>.pre-snapshot-$(date +%Y%m%d-%H%M%S)

# Download and verify the operator-selected snapshot or chain configuration.
# Restore ownership and start the service.

sudo systemctl start <fuel-core-service>
~~~

Post-restore verification:

- service/container starts without database format errors
- chain/network matches expected target
- local height is at or above snapshot height
- local height increases over time
- local/public gap is closing
- recent logs are free of repeated database, relayer, sidecar, P2P, or RPC
  errors
- validator signing resumes for Sequencer validator targets

Rollback:

- stop the service
- move the restored data directory aside
- restore the preserved pre-snapshot data directory and config
- start the previous binary only when upstream notes say database
  compatibility allows it

## Upgrade Workflow

Before upgrades:

1. Confirm whether the target is Fuel Ignition fuel-core or Fuel Sequencer
   fuelsequencerd.
2. Read official release notes and security notes.
3. Check current binary version, runtime flags, data directory, and disk space.
4. Confirm whether database migration, re-sync, or snapshot restore is
   recommended.
5. Back up config, key material references, and current service files.
6. Stage the new binary/image without replacing the running one until the
   operator-approved window.

Fuel Ignition:

- Prefer official release artifacts or reproducible source builds from the
  requested tag.
- Verify fuel-core --version, fuel-core run --help, and current service flags.
- After upgrade, verify GraphQL latest height, node version, local/public gap,
  relayer logs, and app/wallet compatibility.

Fuel Sequencer:

- Use the correct fuel-sequencer-deployments release for the chain ID.
- If using Cosmovisor, place the binary in the expected upgrade directory and
  verify executable permissions and version.
- At upgrade height, watch logs and avoid repeated restarts during a clean
  network-wide halt.
- After upgrade, verify CometBFT height, catching-up state, peers, validator
  signatures, sidecar logs, and bridge-related errors.

## Bridge and Validator Transactions

Fuel bridge, staking, validator creation, validator edit, delegation, and
withdrawal commands can move funds or affect validator state. Treat them as
approval-gated.

Before preparing a transaction:

1. Refresh current official docs.
2. Confirm network and chain ID.
3. Confirm key name, address, keyring backend, and fee denom without exposing
   secrets.
4. Confirm RPC endpoint chosen by the operator.
5. Use dry-run, simulation, or unsigned transaction generation when available.
6. Present exact action, amount, destination, fee, and expected verification
   path before asking for approval to broadcast.

Never fill contract addresses, bridge addresses, validator JSON, or fee values
from memory when current docs or chain state can be checked.

## Development Workflow

For Sway, forc, SDK, or app work:

- Install and update through official fuelup unless the repository requires a
  pinned toolchain.
- Check fuelup show, forc --version, and project Forc.toml.
- Use local nodes for tests when possible; use testnet/mainnet only when the
  task requires live network behavior.
- Keep wallet private keys, provider tokens, and indexer credentials outside
  repositories and examples.
- Verify GraphQL endpoint shape, chain ID, base asset ID, gas policies, pending
  states, failed transaction states, and retry behavior.

## Reporting Format

Keep reports concise and evidence-based:

~~~text
Fuel status:
- Target: <Ignition|Sequencer> <network> <host/service>
- Version: <fuel-core|fuelsequencerd version>
- Height: local <h>, reference <h>, gap <n>
- Sync: <catching_up / progressing / stalled>
- Dependencies: Ethereum <ok|issue|unknown>, sidecar <ok|issue|n/a>
- Validator: <signing N/M | not checked | n/a>
- Action: <none/restart/recovery/upgrade/escalation>
- Notes: <verified cause, risk, or missing input>
~~~

Do not claim success without verification from live checks.
