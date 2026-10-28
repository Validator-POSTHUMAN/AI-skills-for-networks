---
name: "solana"
description: "Use for Solana validator and RPC-node install, restart, upgrade, identity cutover, monitoring, SFDP, and incident work."
---

# Solana Validator Operations

Use for Solana consensus-validator and RPC-node work: install, configure, restart, upgrade, identity cutover, monitoring, security review, SFDP eligibility, and incident diagnosis. Covers Agave and its forks (Jito-Solana, Frankendancer, Firedancer).

Governance — `svmgov`, proposal support, formal votes — is outside this skill. Use a separately reviewed governance workflow.

## Do not use when

- The task is Cosmos, EVM or any non-Solana validator work.
- The task is SPL token, program or dApp development with no node involved.
- The request is only "explain Solana" with no operational action.

## Non-negotiable safety gates

**One identity, one voting process. Ever.** Two hosts voting on one identity produce duplicate votes and can cause forks, lost delegation, and removal from delegation programmes; verify the current penalty rules before relying on them. Every identity move goes through the unstaked spare identity and the tower file:

```
agave-validator --ledger <ledger> set-identity <unstaked-identity.json>
# copy tower-1_9-<identity-pubkey>.bin to the receiving host
agave-validator --ledger <ledger> set-identity --require-tower <staked-identity.json>
```

`--require-tower` is mandatory when moving a staked identity to another host. For a sole, fenced host whose prior tower cannot be recovered, an incident recovery may omit it **only** after two external samples show no vote/root advance, all local and fallback units are stopped and disabled, one target identity/process is established, and the operator explicitly directs continuity recovery. Preserve the rejected tower and all ledger data. Record the exception, then verify two advancing external samples before calling the node healthy.

**Never touch the authorized withdrawer.** It controls the vote account, its rewards, the commission and the identity on it. It must never be read, copied, printed or placed on a validator host. Loss is unrecoverable.

**Ask the operator before:** any transaction (vote-account creation, authority rotation, commission change, withdrawal, stake movement), deleting ledger/accounts/snapshot data, moving or generating keys, exposing RPC publicly, or changing the client to a fork.

**Never delete for disk space:** the ledger, the accounts directory, the tower file, or any keypair. Safe order is superseded snapshot *pairs*, rotated logs, journald, build trees.

## First moves

1. Classify: **operate** (restart, upgrade, cutover, incident), **build out** (new validator or RPC node), **assess** (monitoring, security, SFDP standing), or **explain**.
2. Establish live state before any claim. Local health proves nothing about voting — read consensus from an **external** RPC.
3. Check freshness before using any version, flag, threshold, or transaction example in this package. Solana changes fast: flags get renamed between minor versions, feature gates activate at fixed epochs, and SFDP thresholds move. Verify against `docs.anza.xyz`, the Agave feature-gate tracker and `solana.org/delegation-criteria` before acting on a version, flag or threshold.
4. Read the reference for the task rather than all of them.

## The two-sample rule

A single sample cannot distinguish a voting validator from a frozen one. Every health claim needs two external samples about sixty seconds apart, with `lastVote` **and** `rootSlot` advancing in both:

```
solana validators --url <cluster-rpc> | grep <identity-pubkey>
solana vote-account <vote-account> --url <cluster-rpc>
solana catchup --our-localhost
```

Healthy means: appears in gossip, `delinquent=false`, both counters advancing, local and public finalized slots converged, and `NRestarts` unchanged since the start.

## Restart discipline

A restart on Solana is a snapshot load, so its cost is decided before it begins.

1. Confirm a recent full+incremental pair under `--snapshots` and how far behind the tip it is.
2. Confirm free space on the ledger, accounts and snapshots filesystems — budget 2× a full snapshot plus the incremental.
3. Hand the identity to the unstaked spare if a second synced host exists.
4. `agave-validator --ledger <ledger> exit --max-delinquent-stake 5`, then start. Never `kill`.
5. `systemctl start` on an already-active unit is a **no-op**; after replacing a key file or unit use `stop` then `start`, or `restart`.
6. Verify externally before calling it done.

## Silent failures to check first

These produce no crash, no error and no log line, and account for most "the node is fine but earns nothing" reports:

| Symptom | Cause |
|---|---|
| Healthy service, near-zero gossip peers, no votes | wrong `--expected-shred-version` after a cluster restart |
| Not admitted at an epoch boundary | vote account below rent-exempt minimum + the Alpenglow admission ticket |
| Voting stops, nothing else wrong | identity account out of SOL (~1 SOL/day in vote fees) |
| Failing SFDP epochs while healthy | version below the enforced minimum, `SOLANA_METRICS_CONFIG` pointing at the wrong cluster, or credits/skip rate below the cluster grade |

## Upgrades

Resolve the official signed tag to a commit; record tag, commit and binary SHA-256. Stage the release beside the current one and switch `active_release` atomically so rollback is a symlink change. Read release notes for renamed flags and feature-gate activations — run the required version *before* the activation epoch. Verify the running `/proc` binary, not the build log.

## Reference files

- [references/operations.md](references/operations.md): install, system tuning, startup flags per cluster, systemd and logrotate, snapshots and bootstrap, upgrades, identity cutover, RPC node.
- [references/monitoring-security.md](references/monitoring-security.md): what to alert on, watchtower, metrics, key custody, firewall, supply chain, SFDP criteria.
- [references/troubleshooting.md](references/troubleshooting.md): diagnosis paths for delinquency, falling behind, ENOSPC, rejected snapshots, skipped leader slots, start failures.

## Provider-neutral rules

- Do not default to a hosting provider, RPC vendor, snapshot mirror, stake pool or client fork. Present alternatives by requirement and tradeoff.
- Treat a non-baseline client or orderflow stack (Jito-Solana beyond the standard build, Frankendancer, Firedancer, BAM, Raiku, Rakurai, Harmonic, Flowra) as a change requiring commit-pinned source, an upstream diff, reproducible or signed artifacts with digests, exact endpoints and program authorities, a data-retention policy, and testnet failure/fallback evidence. Onboarding forms are not adoption evidence.
- SFDP expects the testnet and mainnet clients to match. A fork pilot needs a separate, non-staked testnet validator with its own identity.
- Third-party dashboards explain a number; they never discover an outage. Your own monitoring and `agave-watchtower` do that.

## Output standards

Operational runbook: prerequisites, exact commands with explicit placeholders, expected healthy signals, verification from an external RPC, rollback, and what to record (tag, commit, binary hash, restart time, snapshot slot).

Incident report: what was checked, what the evidence showed, what was done, what remains, and the captured log and host state from before the restart.

Never claim a command succeeded without its output, never call a validator healthy without the two-sample check, and never call an upgrade complete without post-upgrade external verification.
