---
name: bitcoin-node-and-lightning-ops
description: "Operate Bitcoin infrastructure: Bitcoin Core full nodes, pruning and assumeutxo, RPC and indexer backends, Lightning (LND and Core Lightning), mining setup, monitoring, security hardening, upgrades, backup and recovery, and concise operator reports."
---

# Bitcoin Node and Lightning Ops

Use this skill for Bitcoin Core node operations, RPC and indexer backends,
Lightning node operations, mining setup, monitoring, security hardening,
upgrades, incident triage, and operator-facing reports.

This skill is operator-neutral and provider-neutral. It must work for any
operator and must not assume a specific pool, wallet, hosting provider,
explorer, custody arrangement or cloud.

## Read this first: what Bitcoin is not

Bitcoin has **no validator set, no staking, no delegation, no commission, no
jail and no slashing**. There is nothing to register, nothing to bond, nothing
to unjail and no consensus key to double-sign with. Proof-of-stake reflexes
imported from Cosmos, Ethereum or Solana operations produce wrong answers here.

Two roles exist:

- a **full node** verifies every block and transaction against consensus rules;
- a **miner** produces blocks with proof of work.

Running a node earns no protocol reward. Its value is that you do not have to
trust anyone else's view of the chain.

The one place with double-signing-shaped risk is **Lightning**, and it is
severe: broadcasting an outdated channel commitment lets the counterparty take
the channel balance. Apply validator-grade single-instance discipline there.

## Source Priority

1. Current command output from the target host: `bitcoin-cli`, `lncli`,
   `lightning-cli`, `systemctl`, logs, disk state.
2. Local operator inventory and runbooks, if available.
3. Official sources:
   - https://bitcoincore.org/en/releases/
   - https://bitcoincore.org/en/list/announcements/join/
   - https://github.com/bitcoin/bitcoin/tree/master/doc
   - https://developer.bitcoin.org/reference/rpc/
   - https://github.com/bitcoin/bips
   - https://docs.lightning.engineering/ and
     https://github.com/lightningnetwork/lnd/releases
   - https://docs.corelightning.org/ and
     https://github.com/ElementsProject/lightning/releases
4. Upstream repositories and release notes for electrs, Fulcrum, esplora,
   mempool, and miner firmware.

Never claim a node, indexer, Lightning node or mining setup is healthy without
live checks. Always refresh the official release notes before quoting a
version, a default, or an RPC's behaviour: Bitcoin Core changed several
long-standing defaults in v30.0 and v31.0.

## Core Chain Facts

Verify these against the current release before acting; the version-specific
ones below were true at Bitcoin Core v31.1.

- Block target 10 minutes, retarget every 2016 blocks, subsidy halving every
  **210,000 blocks**. Subsidy is consensus arithmetic — compute it from the
  height, never read it from a third party.
- Mainnet P2P 8333, RPC 8332. testnet4 48333/48332, signet 38333/38332,
  regtest 18444/18443. testnet3 (18333/18332) is deprecated in practice;
  testnet4 enforces BIP94.
- Core's own size assumptions at v31.1: **856 GB** blocks, **14 GB**
  chainstate. `txindex=1` adds roughly 50 GB.
- `prune` and `txindex` are mutually exclusive, and switching either way
  requires `-reindex` — a full revalidation. Decide before the first sync.
- assumeutxo snapshots are verified against a hash hardcoded in the release, so
  a snapshot from any source is either byte-identical or rejected. v31.1
  accepts mainnet heights 840,000 and 880,000.
- **v28.x and older are end of life** and receive no fixes.
- Defaults that changed and break old runbooks:
  - v30.0: `-natpmp` on by default; `-minrelaytxfee`/`-incrementalrelayfee`
    0.1 sat/vB; `-blockmintxfee` 0.001 sat/vB; `-datacarriersize` 100000;
    `-maxorphantx` removed; `coinstatsindex` re-synced into
    `indexes/coinstatsindex/`; new `bitcoin` wrapper command.
  - v31.0: cluster mempool (ancestor/descendant limits gone, clusters capped at
    64 tx / 101 kvB, CPFP carve-out removed, stricter RBF); `-dbcache` default
    1024 MiB when ≥4096 MiB RAM is detected; `-paytxfee` and `settxfee`
    removed; `onlynet=tor` removed in favour of `onion`; embedded asmap;
    `-privatebroadcast` and `-txospenderindex` added.
  - v31.1: fixes a chainstate rewrite causing continuous excessive disk I/O,
    and an IP leak in `-privatebroadcast`. Do not stay on v31.0.

These facts are orientation, not authorization to act.

## Operator Inventory Guardrails

Before acting, establish for each target: host, role (archive / pruned / miner
backend / Lightning backend / public API), data directory, service name,
Bitcoin Core version, index set, whether a wallet is present, which services
consume it, and who owns it.

If inventory is missing, inconsistent or ambiguous, ask for the missing target
data before restarting services, changing config, restoring snapshots,
deleting data, exposing RPC, broadcasting a transaction, or touching keys or
Lightning state.

## Safety Rules

- Verify live state before claiming sync, health, upgrade completion or
  recovery success.
- **Never expose RPC (8332) or ZMQ to the internet.** Not behind a password,
  not temporarily. Verify from outside the host after every firewall, Docker or
  proxy change — published container ports bypass `ufw` on most hosts.
- **Never run two `bitcoind` processes against one data directory.**
- **Never run two Lightning instances against one channel state**, and never
  restore a channel database (`channel.db`, `lightningd.sqlite3`), filesystem
  snapshot or VM snapshot of a running Lightning node. The only safe channel
  backup is the Static Channel Backup, which recovers funds by closing
  channels.
- Ask before destructive actions: data deletion, reindex on a production node,
  snapshot or wallet restore, Lightning channel-state restore or force close,
  key movement, transaction broadcast, firewall change, public endpoint
  exposure, or miner firmware changes.
- Stop cleanly, always. `bitcoin-cli stop` or `systemctl stop` with
  `TimeoutStopSec` of at least 1200 s; in containers, `stop_grace_period` of at
  least 20 minutes. A `bitcoind` killed mid-flush corrupts the chainstate and
  costs a multi-hour reindex.
- Never copy `blocks/` or `chainstate/` from an untrusted source.
- Verify every binary: release hash plus GPG signatures from multiple
  independent builders in `bitcoin-core/guix.sigs`. No `curl … | sh`
  installers, no floating container tags, for Core, Lightning, indexers or
  miner firmware.
- Do not publish private keys, seeds, wallet files, descriptors with private
  keys, RPC passwords, macaroons, `hsm_secret`, authentication tokens or
  private infrastructure details in reports, examples, logs or skill files.
- `listdescriptors true` prints private keys. Treat its output as a seed.
- Treat a wallet file or key from a compromised host as permanently
  compromised.

## Health Check Workflow

```bash
bitcoin-cli getblockchaininfo | jq '{chain, blocks, headers, verificationprogress, initialblockdownload, size_on_disk, pruned}'
bitcoin-cli getnetworkinfo    | jq '{version, subversion, connections_in, connections_out, networkactive, warnings}'
bitcoin-cli getmempoolinfo    | jq '{size, bytes, mempoolminfee}'
bitcoin-cli getindexinfo
systemctl show bitcoind -p ActiveState -p NRestarts
df -h | grep -v 'tmpfs\|udev\|loop'
```

Healthy means: `blocks` equals `headers`, `verificationprogress` ≈ 1,
`initialblockdownload` false, `connections_out` ≥ 8, `warnings` empty, every
enabled index synced, and disk with headroom.

**The check that catches real disasters is tip-hash agreement, not height.**

```bash
LOCAL=$(bitcoin-cli getbestblockhash)
A=$(curl -s https://mempool.space/api/blocks/tip/hash)
B=$(curl -s https://blockstream.info/api/blocks/tip/hash)
[ "$LOCAL" = "$A" ] && [ "$LOCAL" = "$B" ] || echo "CHAIN DIVERGENCE: local=$LOCAL a=$A b=$B"
```

A node at the same height on a different chain corrupts everything downstream
— payment credits, explorer data, Lightning decisions. Height lag is an
inconvenience; a persistent hash mismatch is an incident: stop consumers, do
not credit payments, investigate before restarting.

Do not alert on `connections_in == 0` unless the node is meant to serve peers,
and do not alert on one missed block interval — ten-minute blocks are Poisson,
so hour-long gaps occur naturally.

## Alert Triage

| Symptom | First checks |
|---|---|
| Will not start | `journalctl -u bitcoind -n 50`; datadir lock; corruption; removed options such as `-maxorphantx` |
| Corrupt chainstate | `-reindex-chainstate` first; `-reindex` only if block files are suspect or `txindex`/`prune` changed |
| Stuck sync | `getchaintips` for a `headers-only` tip with more work; peer count; disk saturation |
| No peers | `networkactive`; DNS seeds; `onlynet=onion` with Tor down; firewall |
| Tip disagreement | stale binary missing a soft fork; manual `assumevalid`; untrusted datadir |
| `Work queue depth exceeded` | raise `rpcworkqueue`/`rpcthreads`; throttle the indexer |
| Container OOM at start | `-dbcache` sized from host RAM, not the cgroup — set it explicitly |
| Constant disk I/O on v31.0 | the chainstate rewrite bug; upgrade to v31.1 |
| Indexer or Lightning sees no new blocks | ZMQ — `bitcoind` reports nothing when a subscriber stops receiving |

ZMQ failure deserves its own monitor: the daemon stays perfectly healthy while
everything downstream silently stops learning about blocks.

## Upgrade Workflow

1. Read the release notes for **every** version being skipped, not only the
   target. Check the "defaults that changed" list above against the config.
2. Record current state: version, tip height, tip hash, `size_on_disk`,
   `NRestarts`, index set.
3. Back up `bitcoin.conf`, the unit file, any wallet. **Keep the old binary** —
   that is the rollback, together with a datadir snapshot.
4. Verify the new release: `sha256sum --check SHA256SUMS`, then
   `gpg --verify SHA256SUMS.asc SHA256SUMS` against guix.sigs builder keys.
5. Stop cleanly and confirm the shutdown completed before replacing binaries.
6. Start, then verify version, sync, tip hash against two independent sources,
   `getindexinfo`, `NRestarts`, and the log.
7. Verify the dependent layers — ZMQ subscribers, electrs/Fulcrum, mempool,
   Lightning — before calling the upgrade done.

Downgrades are not generally supported: wallet migrations, index format changes
and chainstate writes are one-way. Plan rollback as "old binary plus a pre-
upgrade datadir snapshot".

Upgrade the node first, verify, then each layer above it one at a time.

## Sync, Pruning and Recovery

- IBD levers, in order of effect: `dbcache` (8–16 GB during IBD if RAM allows),
  NVMe over SATA, `par`, assumeutxo.
- assumeutxo: `loadtxoutset <file>` on a started node, then watch
  `getchainstates` until one chainstate reports `validated: true`. Until then
  the node has snapshot-plus-forward security, not full verification. Disk use
  for the chainstate is roughly doubled meanwhile.
- Produce a snapshot from a node you control:
  `bitcoin-cli -rpcclienttimeout=0 dumptxoutset <file> rollback=<height>` —
  the node is unusable while it runs.
- Moving a datadir: stop cleanly, `rsync -aH`, then a second pass with
  `--checksum`. Size and mtime are not sufficient for LevelDB data.
- Corruption recovery: `-reindex-chainstate` before `-reindex`.

## RPC, Indexes and Public Endpoints

- One `rpcauth` identity per consumer, each with its own `rpcwhitelist` method
  allowlist. `disablewallet=1` wherever a wallet is not needed.
- Remote access is an SSH tunnel or a private network link, never a wider bind.
- ZMQ is unauthenticated: loopback or a firewalled private interface only.
- Raise `rpcthreads`/`rpcworkqueue` before an Electrum server or explorer
  starts; the defaults will not survive the fan-out.
- Electrum servers (electrs, Fulcrum) and explorer backends (esplora, mempool)
  require an **archive** node.
- Publishing to untrusted callers: prefer an Esplora-compatible REST API from
  your own instance over raw RPC — proxy with a method allowlist, per-IP and
  global rate limits, no wallet, separate from anything holding keys.

## Lightning Workflow

Prerequisites: Core with ZMQ, ideally archival. A pruned backend fails exactly
when a force close needs a block below the prune horizon.

Checks:

```bash
lncli getinfo | jq '{version, synced_to_chain, synced_to_graph, num_active_channels, block_height}'
lncli listchannels | jq '.channels[] | {remote_pubkey, capacity, local_balance, active}'
lncli wtclient towers
# or
lightning-cli getinfo && lightning-cli listpeerchannels
```

`synced_to_chain: false` beyond a few minutes means the backing node or ZMQ is
broken. `synced_to_graph: false` means the node routes nothing while looking
healthy — alert on it.

Backup rules:

- Ship `channel.backup` off-host **on every channel open and close**; it is
  rewritten each time.
- The aezeed or `hsm_secret` goes offline, once, on paper or encrypted media.
- SCB recovery (`lncli restorechanbackup`, or CLN `emergencyrecover`) asks
  counterparties to force-close; funds return on-chain after timelocks, with
  fees and delay. That is the intended, safe behaviour.
- CLN's supported continuous backup is the `backup` plugin, which maintains a
  consistent replica rather than copying a live database.

Before restarting or restoring anything Lightning: prove no second instance
exists against the same channel state. Fence the old host — stop, disable,
mask, confirm no process holds the directory — before starting a replacement.

Keep the on-chain wallet funded above the fee reserve needed to force-close
every channel, and register at least one independent watchtower for nodes
holding real balances.

## Mining Workflow

- Solo odds are `difficulty × 2³² ÷ hash rate`. Compute them for the operator's
  actual hardware and say the number plainly; at ~1.27 × 10¹⁴ difficulty a
  1 TH/s device expects a block roughly every 17,000 years.
- Profitability is decided by electricity price and J/TH, not hardware price.
  Model with current difficulty and assume it rises.
- Pool mining needs no node. Solo mining needs an unpruned, synced node with a
  healthy mempool and a Stratum server (public-pool, ckpool) between the ASIC
  and `getblocktemplate`.
- Choosing a pool is choosing who builds the block template. Miner-built
  templates (Ocean DATUM, Stratum v2 job declaration) return that decision to
  the operator.
- The IPC mining interface (`bitcoin -m node -ipcbind=unix`) is experimental
  and has changed in every release since v30.0; re-read the notes for the exact
  version before wiring anything to it.
- `blocksonly=1` is incompatible with mining.
- Verify the payout address after **every** firmware update; replacing it is
  the standard ASIC malware payload. Miners get their own VLAN, changed
  credentials, and no internet-facing web interface.

## Security Hardening

- Prefer no keys on the node: `disablewallet=1`. Where a wallet is required,
  encrypt it, unlock only for the operation, and prefer watch-only descriptors
  with signing elsewhere.
- Firewall: deny inbound by default; allow SSH and, only if the node should
  serve peers, 8333. Everything else stays on loopback or behind a reviewed
  proxy.
- Privacy tiers: `proxy=127.0.0.1:9050` for outbound Tor; add `listenonion=1`
  and `torcontrol` for a hidden service; `onlynet=onion` for Tor-only, which
  makes a Tor outage a node outage. `privatebroadcast=1` needs v31.1.
- Host: SSH keys only, no root login, unattended security upgrades, dedicated
  unprivileged service user, systemd sandboxing, datadir `0700`, config
  `0600`, full-disk encryption anywhere a wallet lives.
- Version currency is a security control: end-of-life releases receive no
  fixes.

## Backup and Recovery

Back up what cannot be recomputed; never back up consensus or channel state as
a file you might restore.

| Back up | Never back up |
|---|---|
| wallet descriptors and `wallet.dat` | `blocks/`, `chainstate/`, `indexes/` |
| LND `channel.backup`, aezeed | LND `channel.db` |
| CLN `hsm_secret` | CLN `lightningd.sqlite3` as a file copy |
| `bitcoin.conf`, units, `lnd.conf` | |

Rules: at least one copy outside the machine's failure domain and outside its
RAID set; checksum verified on the destination; encrypted at rest for key
material; restore-tested on a schedule — on signet or regtest, not in
production.

Recovering the chain is always possible and never urgent. Recovering keys is
impossible and always urgent. Budget effort accordingly.

## Testing Before Production

Rehearse on **regtest** (instant, deterministic, `invalidateblock` for reorgs),
**signet** (realistic, small, predictable blocks) or **testnet4** (real proof
of work). Nigiri brings up regtest plus Electrs and Esplora in one command.

Rehearse specifically: upgrade and rollback including index migrations; reorg
handling; RBF and cluster-mempool limits; wallet restore and rescan; Lightning
force close, SCB recovery and watchtower justice; and the full mining pipeline.

## Reports

Report: what was checked, what was found, what was done, what remains, and
what changed. Include exact versions, heights, tip hashes, service states and
command output. Never include keys, seeds, descriptors with private keys, RPC
passwords, macaroons or private infrastructure details.

State plainly when something was not verified. "The service is running" is not
"the node is synced", and neither is "the chain is correct".
