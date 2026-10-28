# Solana Operations Reference

## Hardware

| Component | Validator | RPC node |
|---|---|---|
| CPU | 12 cores / 24 threads minimum, high single-core clock, SHA extensions, AVX2 | 16 cores / 32 threads or more |
| RAM | 256 GB, ECC suggested | 512 GB with all account indexes |
| Disk | accounts 1 TB+ NVMe, ledger 1 TB+ NVMe, snapshots 500 GB+, each separate | accounts and ledger must not share a disk |
| Network | 2 Gbit/s symmetric minimum for a staked node, 10 Gbit/s recommended | same |
| OS | Ubuntu 24.04 | same |

Community hardware list: <https://www.solanahcl.org/>. No NAT — upstream Agave does not support it. Docker is not supported for live clusters.

## System tuning

```
# /etc/sysctl.d/21-agave-validator.conf
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
vm.max_map_count = 1000000
fs.nr_open = 1000000
```

```
# /etc/security/limits.d/90-solana-nofiles.conf
* - nofile 1000000
* - memlock 2000000
```

Unit must carry `LimitNOFILE=1000000` and `LimitMEMLOCK=2000000000`. Add swap even on a large-memory host: without it a validator under memory pressure dies, with it the node slows and survives. Keep the system clock accurate — drift breaks gossip.

## Cluster parameters

| | mainnet-beta | testnet |
|---|---|---|
| Genesis hash | `5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d` | `4uhcVJyU9pJkvQyS88uRDiswHXSCkY3zQawwpjk2NsNY` |
| RPC | `https://api.mainnet-beta.solana.com` | `https://api.testnet.solana.com` |
| Entrypoints | `entrypoint[2-5].mainnet-beta.solana.com:8001` | `entrypoint[2-3].testnet.solana.com:8001` |
| Faucet | none | `solana airdrop 1` |

Always set `--expected-genesis-hash` so a wrong entrypoint cannot put the node on another cluster. Always pair `--known-validator` with `--only-known-rpc`: without it the node accepts a snapshot from an arbitrary gossip peer.

## Startup shape

```
exec agave-validator \
  --identity <identity.json> \
  --vote-account <vote-account.json> \
  --ledger /mnt/ledger \
  --accounts /mnt/accounts \
  --snapshots /mnt/ledger/snapshots \
  --log /home/sol/agave-validator.log \
  --rpc-port 8899 --private-rpc \
  --dynamic-port-range 8000-8050 \
  --entrypoint <entrypoint> \
  --known-validator <pubkey> --only-known-rpc \
  --expected-genesis-hash <hash> \
  --wal-recovery-mode skip_any_corrupted_record \
  --limit-ledger-size
```

`exec` is mandatory — without it logrotate's `SIGUSR1` kills the wrapper and the validator with it. Pin `--dynamic-port-range` so the firewall rule and the process agree.

Logrotate reopens the log on `SIGUSR1`:

```
/home/sol/agave-validator.log {
  rotate 7
  daily
  missingok
  postrotate
    systemctl kill -s USR1 sol.service
  endscript
}
```

## Snapshots

Snapshots belong on the ledger filesystem, never on root. Packaging needs headroom for a temporary copy; a root filesystem that fills during packaging stops replay and voting with `No space left on device`, and recovery is a full network fetch.

```
--full-snapshot-interval-slots 25000
--incremental-snapshot-interval-slots 4000
--maximum-full-snapshots-to-retain 2
--maximum-incremental-snapshots-to-retain 4
```

An incremental is only usable with the full snapshot whose base slot it names. Keep two full snapshots so a known-good one exists while the next is written.

## Vote account

Creation, authority rotation and commission changes are signed transactions and need operator approval.

- `solana create-vote-account <vote> <identity> <withdrawer>` — the withdrawer may not equal the identity or vote authority.
- **SIMD-0387**: publish the BLS public key before the validator can vote. `solana vote-authorize-voter-checked <vote> <voter-keypair> <voter-keypair>` fills it in without rotating the voter; requires CLI 4.1.0+. Confirm with `solana vote-account <vote> | grep "BLS Public Key"`.
- **Alpenglow VAT**: an admission ticket is burned from the vote account each epoch, buying admission for the next one. Keep rent-exempt minimum plus several tickets. Per-epoch cost scales with target slot time (1.6 SOL at 400 ms down to 0.8 SOL at 200 ms; 1.2 SOL at the 300 ms stage).
- **SIMD-0232**: `solana vote-update-commission-collector <vote> block-revenue <vote> <withdrawer>` routes block revenue to the vote account and can make the ticket self-funding. Block-revenue changes take effect in E+2, inflation-rewards in E+1.
- Vote authority changes at most once per epoch, effective at the next boundary. Pass `--authorized-voter` twice — old and new — to keep voting across the switch.
- Use only the `-checked` authority commands on mainnet.

## Upgrades

1. Resolve the official signed tag to a commit. Record tag, commit, archive digest and binary SHA-256.
2. Read release notes for renamed flags and feature gates. Run the required version before the activation epoch.
3. Stage beside the current release; switch `active_release` atomically. Keep the previous directory for rollback.
4. Confirm snapshot freshness and disk headroom.
5. `exit --max-delinquent-stake 5`, start, verify the running `/proc` binary and version, then the two-sample external check.
6. After a cluster restart the shred version changes — update `--expected-shred-version` from the announcement.

## Identity cutover

Requires a second synced host running the unstaked identity.

1. Active node: `set-identity <unstaked-identity.json>` — it stops voting.
2. Copy `tower-1_9-<identity-pubkey>.bin` to the receiving host.
3. Receiving node: `set-identity --require-tower <staked-identity.json>`.

If `--require-tower` refuses, fix the tower copy. Never drop the flag.

## RPC node

Same software with `--no-voting`. No vote account, unfunded identity, more CPU and RAM, and accounts and ledger on separate disks.

- `--rpc-bind-address 127.0.0.1` plus a reverse proxy for TLS, rate limiting and method policy. Never expose `agave-validator` RPC directly.
- `--enable-rpc-transaction-history` and `--enable-extended-tx-metadata-storage` blow past the `--limit-ledger-size` target; size the disk for the history depth actually needed.
- `--account-index program-id|spl-token-mint|spl-token-owner` are held in memory and are why the RAM figure doubles. Enable only what callers use; `--account-index-exclude-key` trims the worst offenders.
- Geyser plugins run inside the validator process — pin and attribute them like the client itself.
