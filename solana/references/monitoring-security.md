# Solana Monitoring and Security Reference

## Alert policy

Page on: delinquency over ~2 minutes; slot distance growing for over 5 minutes; gossip peer count collapsing; vote-account or identity balance below threshold; disk free below one snapshot's worth; service restart; `No space left on device`; panic.

Ticket on: skip rate above the cluster average; vote credits below the cluster grade; NIC errors; memory trend; a new client version.

Ignore: transient gossip-table warnings, single-sample slot jitter, third-party dashboards disagreeing by a slot.

## What to measure

| Signal | Source | Healthy |
|---|---|---|
| `delinquent` | external RPC `solana validators` | `false` |
| `lastVote`, `rootSlot` | external RPC `solana vote-account` | both advance across two samples 60 s apart |
| slot distance | local `getSlot` finalized minus public | 0–1 |
| gossip peers | `solana gossip \| wc -l` | stable; a collapse means the wrong shred version |
| skip rate | `solana block-production` | at or below cluster average |
| vote credits | `solana validators` | within 3% of cluster average (SFDP) |
| vote-account balance | `solana balance <vote>` | rent-exempt minimum + several admission tickets |
| identity balance | `solana balance <identity>` | weeks of vote fees (~1 SOL/day) |
| disk free | ledger, accounts, snapshots | 2× full snapshot + incremental |
| `NRestarts` | `systemctl show` | unchanged |

## Watchtower

```
agave-watchtower --url <cluster-rpc> --monitor-active-stake --validator-identity <pubkey>
```

Run it on a **different host** from the validator — on the same host it goes silent in exactly the failures it exists to report. Run it as a systemd unit with notification credentials in a mode-0600 `EnvironmentFile`, never on a command line or in shell history. Run one instance per cluster with the cluster named in the message.

## Metrics

`SOLANA_METRICS_CONFIG` publishes node metrics to the public cluster dashboard and is **required** for SFDP. The value is per-cluster; setting the mainnet value on a testnet node fails the criterion with no local symptom.

There is no first-party Prometheus exporter. Normal stack: `node_exporter` for host counters, plus RPC-derived gauges for the table above. Community `solana-exporter` projects do most of it — pin the version and check what they query, because some rate-limit themselves against a public RPC and the outage then appears in your own dashboard.

## Log patterns worth alerting on

| Pattern | Meaning |
|---|---|
| `No space left on device` | snapshot packaging or ledger write failed; replay stops |
| `panicked at` | process fault — capture the log before restarting |
| snapshot download outside a planned restart | local snapshot was rejected |
| `shred version` mismatch at startup | wrong cluster state after a restart |
| duplicate / dead slot bursts | fork or hardware trouble |

## Key custody

| Key | Rule |
|---|---|
| Authorized withdrawer | never on the validator, never read or copied by an agent; hardware wallet, paper or multisig; loss is unrecoverable |
| Identity | hot by necessity; mode 600, service-user owned, backup restore-tested against its pubkey |
| Vote account keypair | not secret after creation; keep it 600 anyway |
| Unstaked spare identity | on the host; the mechanism for every safe cutover |

`solana-keygen verify <pubkey> <file>` exits non-zero on mismatch and belongs in a check script. Keep the identity balance small and top it up from cold storage.

## Host and network

- Validator runs as a dedicated non-root user.
- SSH: keys only, root disabled, source-restricted to a static management address, `fail2ban` installed. Separate SSH keys per host; never share keys between testnet and mainnet validators.
- UFW default-deny inbound; allow SSH from the management address and the pinned `--dynamic-port-range` only.
- RPC 8899/8900 unreachable from the internet on a staked validator.
- **Outbound traffic must not be filtered.** Gossip, turbine and repair talk to the whole cluster; egress ACLs break consensus participation in ways that are hard to diagnose.
- Systemd hardening (`NoNewPrivileges`, `ProtectSystem=full`, `ProtectHome=read-only`, `PrivateTmp`, explicit `ReadWritePaths`) added incrementally and verified with `systemd-analyze verify` plus a real restart.

## Supply chain

Install from the official release channel or build from a signed tag. Record the tag, resolved commit and binary SHA-256, verify the archive against the published digest, and verify the running binary afterwards. Keep the previous release directory so rollback is a symlink change. Never install a client build from an unattributed link or a chat message.

## SFDP criteria

The thresholds below are a dated operating reference, not a live eligibility decision. Verify current criteria at `https://solana.org/delegation-criteria` and the validator's current standing before acting.

| Criterion | Requirement | Cluster |
|---|---|---|
| Testnet participation | baseline met in 5 of the last 10 testnet epochs | gate for mainnet delegation |
| Vote credits | no more than 3% below cluster average | both |
| Skip rate | at most network average + 5 percentage points | both |
| Commission | 5% or less | mainnet only |
| Total stake | under 1,000,000 SOL | mainnet only |
| Software version | at or above the enforced minimum, which moves 48 h after supermajority adoption | both, different values |
| Metric reporting | continuous, per cluster; recognised Firedancer versions exempt, unreported version is not | both |
| Data-centre concentration | provider at or below 15% of network stake | mainnet, since 2026-05-01 |
| ASN / company concentration | under 25% of network stake | mainnet, since 2026-05-01 |
| Earned stake | not 10+ epochs without Foundation stake | mainnet: rejection; testnet: lose the onboarding number |

Concentration is tracked from `validators.app`. When a provider crosses the threshold the Foundation removes delegations by seniority, lowest first — check a provider's existing concentration before signing a hosting contract, because it is the one criterion that cannot be fixed without moving the node.
