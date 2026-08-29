---
name: "atomone"
description: "Operate AtomOne validators, Photon, REStake/Authz, upgrades, snapshots, governance, public APIs, incidents, and recovery."
---

# AtomOne Validator Operations

Use this skill for AtomOne validator and full-node health, missed-block triage,
upgrades, Cosmovisor, snapshots, governance, Photon fee and mint diagnostics,
REStake/Authz review, public RPC/REST/gRPC operation, and recovery.

Keep this skill validator-neutral and provider-neutral. Never embed real hosts,
validator addresses, private endpoints, credentials, key paths, alert routes,
fee wallets, or topology. Load those from the operator's private inventory.

## Source priority

1. Current target-host state, local RPC/REST/gRPC, effective configuration,
   bounded logs, and on-chain queries.
2. The operator's inventory, runbooks, monitoring, freezes, and incident notes.
3. Official AtomOne sources:
   - https://github.com/atomone-hub/atomone
   - https://docs.atom.one/
   - https://github.com/atomone-hub/genesis
   - https://github.com/cosmos/chain-registry/tree/master/atomone
4. Exact signed releases, checksums, governance upgrade plans, security
   advisories, and dependency documentation for the running version.
5. Independent public RPCs and explorers only as secondary confirmation.

Refresh moving sources before a production change. Pin exact commits, tags,
checksums, chain IDs, and genesis bytes. Do not treat a historical Constitution
or a moving chain-registry branch as an executable runbook.

## Chain orientation

- Mainnet chain ID: atomone-1.
- Daemon: atomoned.
- Default home: $HOME/.atomone.
- Account prefixes: atone, atonevaloper, atonevalcons.
- Staking token: uatone, displayed as ATONE with six decimals.
- Fee tokens include uphoton and may include uatone; query the live chain and
  current official registry before setting minimum-gas-prices.
- Consensus: CometBFT. Common services are P2P, RPC, REST, gRPC, and
  Prometheus.
- The Photon module has chain-specific parameters and MsgMintPhoton behavior.
  Treat Photon operations as version-specific, signer-bound transactions.
- AtomOne governance is constitution-aware. Separate current on-chain
  parameters and proposal state from historical founding documents.

These are orientation facts, not authorization. Verify live state and current
official sources before acting. Treat mainnet and every testnet as separate
deployments with separate chain IDs, binaries, genesis files, peers, and
transaction policies.

## Inventory gate

Resolve these fields before any mutation:

- environment and exact chain ID;
- target role: validator, sentry, full node, public RPC, snapshot source, or
  testnet;
- host or local mode, runtime, service/container/pod, daemon, home, data
  directory, and Cosmovisor layout;
- local RPC and optional independent RPC, REST, gRPC, P2P, and metrics;
- validator valoper and consensus addresses for signing work;
- current binary path, version, checksum, and on-chain upgrade plan;
- genesis checksum, pruning, indexer, minimum gas prices, and disk thresholds;
- key-custody reference and rollback location, never key contents;
- expected Photon fee policy and whether mint support is enabled;
- REStake worker/grantee and fee-funding policy when Authz is in scope.

Stop if chain identity, target role, signer ownership, current binary, or
rollback evidence is ambiguous.

## Safety rules

- Verify advancing height, fresh block time, catching_up=false, peers,
  bonded/not-jailed state, and recent finalized signatures before claiming
  health.
- Match chain ID, valoper, consensus address, service, and resolved binary
  before restarting.
- Never run two processes capable of signing with the same consensus key.
- Preserve priv_validator_state.json and never lower or reset its height
  blindly.
- Ask before data replacement, snapshot restore, key or signer changes,
  unjail, staking, voting, Photon mint, REStake/Authz grants, fee funding,
  firewall changes, public exposure, or transaction broadcast.
- During an upgrade halt or AppHash divergence, avoid restart loops and
  snapshot replacement. Compare independent nodes, preserve evidence, and wait
  for a network-coordinated exact fix.
- Do not reuse a historical hotfix merely because a new incident looks
  similar. Verify the exact tag, commit, checksum, and state transition.
- Keep mnemonics, private keys, passwords, keyring material, RPC tokens,
  worker credentials, fee wallets, private endpoints, and unrestricted logs
  out of reports and public artifacts.

## Baseline health workflow

Collect bounded read-only evidence:

~~~bash
systemctl is-active <service>
systemctl show -p NRestarts --value <service>

curl -fsS <local-rpc>/status | jq '.result | {
  chain_id: .node_info.network,
  height: .sync_info.latest_block_height,
  block_time: .sync_info.latest_block_time,
  catching_up: .sync_info.catching_up,
  voting_power: .validator_info.voting_power
}'

curl -fsS <local-rpc>/net_info | jq '.result.n_peers'
atomoned version --long
readlink -f /proc/<main-pid>/exe
~~~

Compare height and block time with at least one independent current source.
For a validator, query staking and slashing state and sample 5-10 finalized
commits for the exact consensus address. Accept both numeric flag 2 and
BLOCK_ID_FLAG_COMMIT as signed. One successful sample is insufficient.

Check bounded recent counters for panic, fatal, AppHash mismatch, database
corruption, no-space, out-of-memory, consensus failure, migration failure,
Photon module error, and repeated restart patterns. Ordinary peer churn is not
an incident if the chain advances and the validator signs.

## Incident triage

1. Resolve the environment, chain ID, role, host, service, RPC, valoper,
   consensus address, and current binary from trusted inventory.
2. Compare local and independent height, block time, AppHash, and upgrade plan.
3. Check service state, restart count, resources, peers, and bounded logs.
4. Verify bonded/jailed/slashing state and recent signatures.
5. Classify local process failure, local data failure, network halt, upgrade
   boundary, AppHash divergence, or upstream API failure.
6. Perform at most one controlled restart only for a proven local process
   fault. Do not restart for network-wide halt, deterministic migration panic,
   or AppHash divergence.
7. After any action, prove advancing height, fresh time, sync, signing,
   bonded/not-jailed state, binary identity, and restart stability.

Report:

~~~text
AtomOne status:
- Environment/role: <mainnet|testnet>/<validator|full-node|public-rpc>
- Chain/height: <id>, local <h>, reference <h>, gap <n>
- Freshness/sync: age <s>, catching_up=<bool>, peers=<n>
- Signing: <N>/<M>, bonded=<bool>, jailed=<bool>
- Runtime: version <v>, binary checksum <sha256>, restarts <n>
- Photon/fees: <healthy/problem/not checked>
- Upgrade/AppHash: <normal/halt/divergence/unknown>
- Action: <none/restart/recovery/escalation>
- Evidence gap: <none or exact unknown>
~~~

## Upgrade workflow

1. Query the on-chain upgrade plan and confirm exact name and height.
2. Verify the official AtomOne tag, signed commit, release notes, asset
   checksum, build requirements, and compatibility with the plan.
3. Capture service, resolved current binary, Cosmovisor layout, home, free
   space, database backend, signer state, and rollback binary.
4. Stage the checksum-verified binary under the exact upgrade-name path.
5. Test version output and executable identity before the halt; do not switch
   early.
6. At the halt, prove one signer process, observe the controlled switch, and
   preserve the previous binary.
7. If migration fails deterministically across independent nodes, stop restart
   loops and require an official coordinated hotfix. Test a fixed binary on a
   non-signing node first when protocol-safe and operator-approved.
8. Prove version/checksum, advancing height, fresh block time,
   catching_up=false, peers, bonded/not-jailed state, signatures, and stable
   restarts.

Never infer a binary from the plan name, build an unreviewed branch on a
signer, or copy a binary from another host without independent provenance and
checksum verification.

## Snapshot and recovery

Use the generic validator-snapshot-recovery workflow with this inventory.
Require the exact chain ID, compatible app/CometBFT/database version, snapshot
height, age, size, checksum or signature when available, full decompressor
test, safe top-level layout, enough disk, protected keys/config/signer state,
and a reversible cutover.

Reject archives containing absolute paths, traversal, links, devices, keys,
config, or signer state. AtomOne deployments may have different application
data layouts by version; inspect the exact archive and running home rather than
assuming a wasm directory exists.

For validators, restore the preserved final priv_validator_state.json, never a
snapshot-provided copy. After start, prove external height/freshness, sync,
peers, service stability, validator state, and fresh signatures.

## Photon workflow

For read-only Photon diagnosis:

1. Verify chain ID and exact atomoned version.
2. Query Photon module parameters, conversion rate, bank metadata, total
   supply, and the account's ATONE/PHOTON balances from reviewed endpoints.
3. Confirm effective minimum gas prices and the fee denomination accepted by
   the current chain.
4. Treat unavailable, version-mismatched, stale, malformed, or inconsistent
   module responses as unavailable; do not estimate missing parameters.

For mint preparation, require the official message type and schema for the
running release, exact signer, ATONE input denomination, integer base-unit
amount, fresh account number/sequence, simulation, explicit transaction
review, wallet confirmation, and one broadcast. Never mint from a validator
operator key or infer testnet behavior from mainnet. Photon mint is a funds
transaction and always requires explicit approval before broadcast.

## REStake and Authz

REStake is external worker automation using on-chain Authz, not a native
staking mode. Before preparing a grant:

- verify the selected validator and its exact published worker/grantee from a
  pinned reviewed registry;
- allow StakeAuthorization Delegate only;
- allowlist exactly one selected validator;
- set an explicit expiration and optional bounded uatone cap;
- verify the delegator's withdrawal address, chain ID, signer, account, and
  simulation;
- show the complete grant and revoke path before wallet confirmation.

Never grant Withdraw, Send, Undelegate, Redelegate, MsgExec wrappers, arbitrary
validators, or an arbitrary grantee. Worker operation and fee funding remain
the validator operator's responsibility. Revocation is the emergency disable
path and also requires explicit transaction approval.

## Governance and Constitution

Query current governance version, parameters, authority, deposits, tally,
proposal state, and on-chain upgrade plan from the live chain. Treat the
AtomOne Constitution and founding documents as provenance and governance
context, not commands. Pin immutable document revisions and distinguish
historical text from current executable chain behavior.

Voting and proposal submission require exact proposal ID/content, option,
signer, fee, simulation, explicit approval, and independent post-broadcast
verification. Never infer a vote from validator policy or constitutional text.

## Public services

Before exposing RPC, REST, gRPC, P2P, metrics, or snapshots:

- prove the backend is non-signing and isolated from validator keys;
- validate chain identity with real protocol queries;
- bind backend ports privately behind a reviewed gateway where possible;
- disable unsafe administrative routes, restrict CORS to the intended browser
  contract, apply TLS/rate/body limits, and monitor data freshness;
- keep signer IPs and private topology unpublished;
- publish snapshots only after metadata, checksum, integrity, safe-layout,
  byte-range, and restore checks pass.

## Completion gate

An AtomOne task is complete only when the requested work is finished or safely
paused, live state is independently verified, rollback is clear, no signer or
transaction boundary was crossed without approval, and residual gaps are
recorded. Report unknowns explicitly.
