# Solana Troubleshooting Reference

Work from evidence in this order: external RPC, local RPC, log, host. Do not restart first — a restart is a snapshot load.

```
solana validators --url <cluster-rpc> | grep <identity-pubkey>
curl -s http://127.0.0.1:8899 -X POST -H 'content-type:application/json' -d '{"jsonrpc":"2.0","id":1,"method":"getHealth"}'
solana catchup --our-localhost
journalctl -u <unit> --since "30 min ago" | grep -Ei 'panic|error|no space|shred version'
```

## Delinquent

Check in this order: process alive; caught up; identity funded; vote account funded; shred version correct; tower file present. A missing tower forces a slow careful restart — never delete it to "fix" a stuck node.

## Healthy service, no peers, no votes

Wrong `--expected-shred-version` after a cluster restart. The node gossips into a void with no error. Take the new value from the official announcement, update the unit, restart, confirm peer count recovers.

## Not admitted at an epoch boundary

The Alpenglow admission ticket could not be paid from the vote account. Nothing crashes; the validator simply stops being one. Fund above rent-exempt minimum plus several tickets and add the alert.

## Falling behind

Usual causes in order: accounts-DB disk latency (check await and utilisation, not free space); CPU contention, especially on the PoH core; memory pressure without swap; NIC loss showing as missed shreds and rising repair traffic; or genuinely behind after a long outage — let it catch up rather than restarting repeatedly, since each restart restarts the snapshot load.

## `No space left on device`

Replay and voting stop at that slot. Delete in this order: superseded snapshot **pairs** (an old full plus every incremental built on it, only after a newer pair exists and has been used), rotated logs, journald, build trees. Never the ledger, accounts, tower or keys. Then fix the cause: move `--snapshots` onto the ledger filesystem, lower retention, or add capacity.

## Snapshot rejected, refetch on every start

Shred version changed, archive corrupt, or the incremental's base full snapshot is gone. Make room before the fetch. Confirm `--known-validator`, `--only-known-rpc` and `--expected-genesis-hash` so the fetch comes from a chosen source and cannot land on another cluster.

## Skipping leader slots

A skip rate above the cluster average is a defect, not luck. Look at PoH core contention and CPU steal, accounts-DB latency during the leader window, NIC drops and upstream bandwidth, then client version and scheduler configuration.

## Will not start

| Symptom | Cause |
|---|---|
| `Unknown argument` | a flag was renamed between releases |
| `Permission denied` on ledger/accounts | ownership, or a too-strict `ProtectSystem` / `ReadWritePaths` |
| `Too many open files` | `LimitNOFILE` missing, or `fs.nr_open` not raised |
| `failed to lock memory` | `LimitMEMLOCK` missing |
| exits immediately, no log | the start script did not use `exec`, or `--log` is unwritable |
| restart loop | stop the unit before debugging |

## Change did not take effect

`systemctl start` on an already-active unit is a no-op. After replacing a key file always `stop` then `start`, or `restart`. Vote-authority changes take effect at the next epoch boundary, once per epoch, and the BLS public key must be re-published after rotating the voter.

## Two hosts, one identity

Stop immediately. Determine which host holds the valid tower, shut the other down completely, then hand over with `--require-tower`. Never run both "just until the window closes".

## Capture before restarting

```
systemctl show <unit> -p NRestarts -p ActiveState -p ExecMainStartTimestamp
journalctl -u <unit> --since "1 hour ago" > /tmp/incident-$(date +%s).log
df -h; free -h; ls -lt <snapshots-dir> | head
```

An incident you cannot reconstruct will repeat.
