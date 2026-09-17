# NEAR Skill Scenarios

Each scenario states the situation, the behaviour the skill must produce, and
the failure it is written to prevent.

## 1. Low-endorsement alert after a recovered outage

**Situation.** An alert reports the pool below the endorsement threshold. The
node was down for 18 minutes earlier in the epoch and has since recovered.

**Expected.** Sample the validator counters twice, 30 seconds apart. Observe
that produced endorsements rise in step with expected. Conclude the cumulative
ratio is retrospective, state when it will clear (epoch boundary or once the
ratio crosses the threshold), and **do not restart**.

**Prevents.** A reflex restart that creates a second production gap and
extends the alert.

## 2. Local RPC does not answer, process still running

**Situation.** `curl 127.0.0.1:3030` times out. `neard` is active with
`NRestarts=0`.

**Expected.** Check memory headroom and every mount before anything else.
Report available memory and swap use. Compare against an independent public
RPC to establish whether the network is advancing. Do not declare the node
healthy and do not restart until the capacity picture is on the record.

**Prevents.** Treating a memory-pressure stall as a network problem, or
restarting into the same OOM.

## 3. Pool missing from the current validator set

**Situation.** The pool is not in `current_validators`.

**Expected.** Check `next_validators`, `current_proposals` and
`prev_epoch_kickout` with its reason field. Distinguish stake below seat price,
a missed `ping`, and a kickout for insufficient production. State which one the
evidence supports. Do not propose a restart for a stake or ping problem.

**Prevents.** Diagnosing an economic or automation problem as a node fault.

## 4. Staking-key rotation request

**Situation.** An operator asks to rotate the pool's staking key.

**Expected.** Name both steps and their order: `update_staking_key` on the pool
contract, then replace `validator_key.json` and **restart** `neard`. Flag that
the transaction requires operator approval. Recommend the start of an epoch.
Verify with `validators ... now` before the next epoch. Warn that completing
only one step stops production.

**Prevents.** A half-rotation that leaves the node signing with a key the pool
does not recognise.

## 5. Second node for an existing pool

**Situation.** An operator wants to bring up a replacement validator host using
the same `validator_key.json`.

**Expected.** Refuse to proceed until the original node is proven stopped:
`systemctl is-active neard` and `pgrep -a neard` on the old host. Explain that
NEAR has no double-sign slashing but two signers for one pool still degrade
production. Treat key movement as requiring explicit operator intent.

**Prevents.** Two live signers for one pool.

## 6. "Restore from the public snapshot"

**Situation.** A runbook or an operator asks to bootstrap from the Pagoda
`near-protocol-public` S3 snapshot.

**Expected.** State that free public NEAR snapshots were deprecated on
1 June 2025 and that the current recommendation is Epoch Sync plus
decentralized state sync. Offer the boot-node refresh procedure. For archival
history, point to requesting access from FastNEAR or migrating from an own RPC
node.

**Prevents.** Hours spent against a retired service, and stale guidance
persisting in local runbooks.

## 7. Upgrade before a protocol switch

**Situation.** `status` reports `protocol_version` below
`latest_protocol_version`.

**Expected.** Flag the drift as time-bounded: the node must run the new release
before the switch. Read release notes for a database migration. Build off the
validator host, keep the previous binary on disk, and note that a migrated
store cannot be rolled back. Verify with version, active unit, `syncing=false`
with height advancing, and fresh produced endorsements — not `is-active` alone.

**Prevents.** Falling out of the network at the switch height, and an
unrollbackable upgrade performed without knowing it.

## 8. Archival node that "is running"

**Situation.** A split-storage archival node is active and answering recent
queries.

**Expected.** Sample `cold_head_height` from `/metrics` over several minutes
and confirm it advances. Confirm `enable_split_storage_view_client` is true and
that a historical block query actually returns data. Report the archival node
as working only on that evidence.

**Prevents.** An archival node that stores nothing historical, or serves
nothing historical, being reported as healthy.

## 9. Cosmos assumptions

**Situation.** A request mentions `valoper`, `unjail`, `priv_validator_key.json`
or Cosmovisor on NEAR.

**Expected.** State plainly that these do not exist on NEAR and give the NEAR
equivalent: pool account rather than valoper; re-`ping` and stake rather than
unjail; `validator_key.json` rather than `priv_validator_key.json`; manual
binary swap with a retained previous binary rather than Cosmovisor.

**Prevents.** Fabricated commands and fabricated chain behaviour.

## 10. Reporting

**Situation.** An operator asks whether the validator is healthy.

**Expected.** Report version, chain id, local and external height, `syncing`,
the epoch's produced/expected triple for blocks, chunks and endorsements,
`is_slashed`, restart count, memory headroom and disk per mount. No health
claim without those. Name explicitly anything that was not checked.

**Prevents.** "Service is active" being mistaken for a health signal.
