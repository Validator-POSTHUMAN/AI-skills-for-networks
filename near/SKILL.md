---
name: near-validator-ops
description: "Operate NEAR validators, RPC and archival nodes: neard health and sync, staking-pool creation and ping, epoch proposals, endorsement and chunk production, key custody, split-storage archival, epoch/state sync, monitoring, upgrades, safe recovery, and concise operator reports."
---

# NEAR Validator Ops

Use this skill for NEAR node operations: validator and full-node health checks,
sync and RPC issues, missed endorsement or chunk symptoms, staking-pool
creation and maintenance, `ping` and proposal handling, key custody and
rotation, archival split-storage setup, `neard` upgrades, recovery, and
operator reports.

This skill is validator-neutral and server-neutral. It contains no production
pool names, hosts, keys or credentials.

## Source Priority

1. Current command output from the target host, local RPC (`127.0.0.1:3030`)
   and an independent public RPC.
2. Local operator inventory and runbooks, if available.
3. Official NEAR sources:
   - https://near-nodes.io/
   - https://docs.near.org/protocol/network/validators
   - https://docs.near.org/protocol/network/staking
   - https://docs.near.org/tools/cli
   - https://github.com/near/nearcore
   - https://github.com/near/core-contracts/tree/master/staking-pool
4. Explorers and third-party dashboards
   ([nearblocks.io](https://nearblocks.io/node-explorer),
   [near-staking.com](https://near-staking.com/stats),
   [pikespeak.ai](https://pikespeak.ai/validators/overview)) as secondary
   confirmation only.

Never claim a NEAR validator is healthy, synced, upgraded or producing without
live checks.

**NEAR is not Cosmos.** Do not apply Cosmos SDK assumptions. There is no
`valoper` address, no `priv_validator_key.json`, no Tendermint RPC, no
`unjail` transaction, no Cosmovisor, no governance module, no IBC, and no
genesis/addrbook bootstrap pair. Staking lives in a smart contract, not in a
staking module.

## Chain Facts

- Mainnet chain ID: `mainnet`; testnet chain ID: `testnet`.
- Binary: `neard` from `near/nearcore`. Mainnet runs the latest **stable** tag;
  testnet runs the latest **release candidate**.
- Reference point: stable `2.13.4`, mainnet protocol version `86`. Always
  re-verify against the releases page and live `status`.
- Ports: `24567/tcp` P2P; `3030/tcp` serves **both** JSON-RPC and Prometheus
  `/metrics`. There is no separate metrics port.
- Block time ~1.1 s. Epoch = 43,200 blocks (~12 h). Unbonding = 4 epochs.
- Staking-pool factory: `poolv1.near` (mainnet), `pool.f863973.m0` (testnet).
  Pool accounts are `<name>.poolv1.near` / `<name>.pool.f863973.m0`.
- Pool creation costs a 30 NEAR attached deposit for contract storage.
- Seat price: set by the 300th largest staking proposal, floor 25,500 NEAR.
- Validator roles: top 100 by stake are block/chunk producers; the rest are
  chunk validators, which do not track shards and endorse chunks only.
- Reward target: 2.5% of total supply per year, paid regardless of fees.
- Config profiles for `--download-config`: `validator`, `rpc`, `archival`.
- Key files in NEAR home (default `~/.near`): `config.json`, `genesis.json`,
  `node_key.json`, `validator_key.json`, `data/`.

## Key Model

Four distinct secrets. Never conflate them:

| Secret | Location | Controls | Leak impact |
|--------|----------|----------|-------------|
| Node key | `node_key.json` | P2P identity | peer impersonation only |
| Staking key | `validator_key.json` | signs as the pool | another host can sign for the pool |
| Pool owner full-access key | operator keychain / hardware wallet | the owner account and the pool | total loss |
| Automation key | function-call access key | only allowlisted pool methods | limited to those methods |

Rules:

- `validator_key.json` carries the **pool** account in `account_id` and the
  field name is `secret_key`, not `private_key`.
- `neard` reads `validator_key.json` only at startup. After changing it,
  `systemctl restart neard`. `systemctl start` on an active unit is a no-op.
- The owner full-access key must not live on the validator host.
- The unattended `ping` signer should be a function-call access key scoped to
  the pool contract and the `ping` method.
- NEAR has no Cosmos-style double-sign slashing, but two hosts signing for one
  pool still degrade production and make diagnosis impossible. Before starting
  a replacement host, prove the old one is stopped: `systemctl is-active neard`
  and `pgrep -a neard`.

## Health Check Sequence

Run in this order and record the output. Use `127.0.0.1`, never `localhost` —
IPv6-first resolution against a service bound to `0.0.0.0` adds hundreds of
milliseconds per request.

1. Service state:
   ```bash
   systemctl status neard --no-pager
   systemctl show neard -p NRestarts --value
   ```
2. Local status and sync:
   ```bash
   curl -s -X POST http://127.0.0.1:3030 -H 'Content-Type: application/json' \
     -d '{"jsonrpc":"2.0","id":1,"method":"status","params":[]}' \
     | jq '{version: .result.version.version, chain: .result.chain_id,
            protocol: .result.protocol_version,
            latest: .result.latest_protocol_version,
            height: .result.sync_info.latest_block_height,
            syncing: .result.sync_info.syncing}'
   ```
3. Independent height for comparison (`https://free.rpc.fastnear.com` or
   `https://rpc.mainnet.near.org`; the latter is severely rate limited).
4. Validator production in the current epoch:
   ```bash
   curl -s -X POST http://127.0.0.1:3030 -H 'Content-Type: application/json' \
     -d '{"jsonrpc":"2.0","id":1,"method":"validators","params":[null]}' \
     | jq --arg p "<pool>" '.result.current_validators[] | select(.account_id==$p) |
         {stake, is_slashed,
          blocks: "\(.num_produced_blocks)/\(.num_expected_blocks)",
          chunks: "\(.num_produced_chunks)/\(.num_expected_chunks)",
          endorsements: "\(.num_produced_endorsements)/\(.num_expected_endorsements)"}'
   ```
5. Next-epoch membership and proposals:
   `near-validator validators network-config mainnet next`,
   `near-validator proposals network-config mainnet`.
6. Capacity — memory headroom and **every** mount:
   ```bash
   free -h
   df -h | grep -v 'tmpfs\|udev\|loop'
   ```
7. Logs for real failure signatures:
   ```bash
   journalctl -u neard -n 500 --no-pager | grep -iE 'panic|fatal|corrupt|OOM|error'
   ```

`scripts/near-healthcheck.sh` automates steps 1–7.

## Endorsements Are Cumulative — Read This Before Restarting

A low-endorsement alert is usually **retrospective**. The kickout threshold is
computed on the cumulative ratio over the whole epoch, so a short outage keeps
the alert firing for hours after full recovery.

Before restarting on a low-endorsement alert, sample the counters twice, 30
seconds apart:

- If `num_produced_endorsements` is rising in step with
  `num_expected_endorsements`, the node is healthy. The alert clears at the
  epoch boundary or when the cumulative ratio crosses the threshold. **Do not
  restart** — a restart only creates a second gap.
- If fresh expected endorsements are not being produced, treat it as a live
  incident and continue triage.

Apply the same logic to `blocks` and `chunks`.

## Triage Map

| Symptom | First checks | Common causes |
|---------|--------------|---------------|
| Local RPC does not answer | process alive? memory? disk? | OOM kill, stalled RPC thread, disk full |
| `syncing=true`, height stalled | peers, boot nodes, disk | stale `network.boot_nodes`, no peers, storage exhaustion |
| In set, low production | fresh counters, host load, logs | host saturation, slow disk, recent restart gap |
| Not in `current_validators` | proposals, seat price, stake | stake below seat price, missed `ping`, kicked out last epoch |
| `prev_epoch_kickout` entry | reason field | `NotEnoughBlocks`, `NotEnoughChunks`, `NotEnoughStake`, `Unstaked` |
| Pool rewards stale for delegators | `ping` timer | ping not running; check the timer, not the node |
| Archival node not serving history | `cold_head_height`, split-storage config | cold head not advancing, `enable_split_storage_view_client` false |
| Version/protocol drift | `protocol_version` vs `latest_protocol_version` | upgrade needed before the protocol switch |

## Staking Pool Operations

All transactions sign with the owner key. Confirm the network name in every
command; `network-config mainnet` and `network-config testnet` differ by one
word and by a real pool.

- Create: `create_staking_pool` on the factory, 30 NEAR attached, 300 Tgas.
- Self-bond: `deposit_and_stake` with an attached deposit.
- Epoch signal: `ping` — re-submits the proposal and refreshes delegator
  reward accounting. Automate on a timer more frequent than one epoch
  (6 h is a safe cadence); a duplicate ping is harmless.
- Commission: `update_reward_fee_fraction`. Announce before sending.
- Staking-key rotation is two steps and both must land, in order:
  `update_staking_key` on the pool, then replace `validator_key.json` and
  restart `neard`. Do it at the start of an epoch and verify with
  `validators ... now` before the next one.
- Exit: `unstake_all`, wait 4 epochs, `withdraw_all`. Commission accrues as
  owner stake inside the pool and compounds until explicitly withdrawn.

Proposals apply two epochs out: signal now, seat in roughly three epochs.

## Bootstrap and Recovery

- **Free public snapshots are gone.** Pagoda's `near-protocol-public` S3
  backups and FastNEAR free snapshot downloads were deprecated on 1 June 2025.
  Treat any guide that recommends them as stale.
- Default bootstrap is **Epoch Sync**: refresh `network.boot_nodes` from a
  public endpoint's `network_info`, then start. A stale boot-node list is the
  most common cause of a node stuck at height 0.
- **State Sync from external storage** handles shard catchup. A validator
  should leave `tracked_shards`, `tracked_accounts` and
  `tracked_shard_schedule` empty; consensus assigns the shard.
- Inspect the *effective* config, not the file you think is loaded:
  `curl -s http://127.0.0.1:3030/debug/client_config | jq`.
- `data/` is disposable; re-sync rather than restoring stale copies. If
  copying a chain database between hosts, the final `rsync` pass must use
  `--checksum` — `neard` uses an LSM-tree store and size+mtime misses changed
  SST files.
- Archival nodes use split storage: `archive: true`, `save_trie_changes: true`,
  `store.path=hot-data`, `cold_store.path=cold-data`,
  `split_storage.enable_split_storage_view_client=true`. Verify with
  `curl -s http://127.0.0.1:3030/metrics | grep cold_head_height` sampled over
  several minutes; a static cold head means the migration did not complete.

## Upgrades

- No Cosmovisor, no on-chain upgrade plan that halts the node. A release with a
  protocol bump must be running before the switch.
- `latest_protocol_version` above `protocol_version` in `status` means the
  network is moving to a version the node may not support.
- Build on a non-validator host; keep the previous binary on disk so rollback
  is a file move.
- Read release notes for database migrations. Some releases migrate the store
  on first start (for example 2.13.0's 48 → 49 migration). Never interrupt one,
  and note that a migrated store cannot be rolled back to the old binary.
- Verify: new version on disk, unit active, `syncing=false` with height
  advancing, and **fresh** produced endorsements sampled twice.

## Safety Gates

Stop and ask an operator before:

- moving, copying or exposing `validator_key.json`, or any owner key;
- starting a second node for an existing pool without proving the first is
  stopped;
- any staking-pool transaction that moves funds — `deposit_and_stake`,
  `unstake*`, `withdraw*` — or changes commission or the staking key;
- deleting `data/` or any storage path without a verified recovery path;
- exposing port `3030` from a validator host;
- restarting on a retrospective low-endorsement alert while fresh production is
  healthy.

Controlled `restart` of `neard` to recover a stuck process, complete an upgrade
or prevent missed production is normal operational work, once live state has
been checked.

## Reporting

Report: what was checked, what the evidence showed, what was done, what remains.
Include version, chain ID, local and external height, `syncing`, the current
epoch's produced/expected triple, `is_slashed`, restart count, memory headroom
and disk per mount. Never call a node healthy on the strength of
`systemctl is-active` alone.

## Files in This Skill

- `scripts/near-healthcheck.sh` — one-shot node and validator health check.
- `references/inventory.schema.json` — operator inventory schema.
- `examples/inventory.example.json` — worked example.
- `evals/near-skill-scenarios.md` — scenarios this skill must handle.
