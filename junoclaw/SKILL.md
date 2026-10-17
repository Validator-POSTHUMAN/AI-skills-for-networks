---
name: junoclaw-validator-ops
description: "Operate JunoClaw G2 validators: threshold-share onboarding, coordinated starts and upgrades, certified state sync, finality/signing checks, and safe recovery."
---

# JunoClaw validator operations

Use for a JunoClaw G2 seat running `slay3rd` on the Commonware-based chain. JunoClaw is **not** Cosmos Juno: do not use `junod`, CometBFT, Cosmovisor, staking, unjail, or Cosmos snapshot procedures here. G2 is an invited, equal-weight, unpaid testnet without consensus-layer staking or slashing. It still has a double-sign hazard: one seat must never run on two live hosts.

## Source and identity gate

1. Read private inventory and the current coordinator-approved window/config, then compare with the official [validator guide](https://junoclaw.xyz/docs/onboarding/validators/), [run-a-node guide](https://junoclaw.xyz/docs/reference/run-a-node/), and [releases](https://github.com/Dragonmonk111/layer-sdk/releases). Check exact chain ID, release, genesis digest, peer IDs, validator index and anchor against the target host. G2 has used `junoclaw-g1`; do not infer a future chain ID from the devnet example `junoclaw-1`.
2. Check dedicated host/network failure domain, NTP drift under 2 seconds, reachable P2P TCP 7001, sufficient CPU/RAM/disk (official minimum 2 cores, 4 GB, 20 GB SSD), and private gRPC 9090 unless publication was approved. Confirm one signer placement before starting or moving anything.
3. Check the installed binary and release manifest by digest. `v0.6.0-rc11` was published 2026-10-17 with a donor-root quorum gate and diagnostics; publication does not prove the set has coordinated its upgrade or that a particular node runs it. Never mix versions within a set-change window.

## Onboarding and key custody

1. Obtain a coordinator-approved seat and ceremony bundle. Generate the Ed25519/MAYO2 identity on the final signer host with the version-pinned ceremony tool; send only `share-request.json` after checking its public fields and destination. Keep `keys.json`, encrypted dealings and finalized BLS share private on that host.
2. Check DKG round, player set, dealer IDs, previous threshold public key, recipient identity and archive member types before acknowledgement. Verify the public acknowledgement count and coordinator acceptance. Finalize locally only against the reviewed bundle; confirm the threshold group public key is unchanged. Never paste or print private JSON.
3. Obtain exact `node.toml` and genesis from the coordinator. Check validator index against the assigned share, peer Ed25519 keys, release, chain ID, genesis digest, restart anchor and paths. Back up signer material only through an explicitly approved custody path after proving no duplicate signer; never make a casual copy.

## Controlled start and verification

1. At a coordinated window, prove the prior placement is stopped/fenced, the target service is inactive, and existing consensus, WAL and MAYO signature journal are retained. Verify clock, disk, config/release digests and peer reachability, then start the single target service.
2. Check active service, stable restart count, authenticated peers, advancing finalized height, and local digest/app hash at a common height against an independent peer. A running process or connected peers alone are not evidence of signing.
3. Verify the seat's index in a fresh finalized certificate/signature bitmap through an independent peer or coordinator evidence. Record whether evidence is directly observed or relayed. Confirm monitoring alerts on finalized-height stalls and clock/peer loss.

## Recovery boundaries

- If a new seat starts at height 0 or reports unavailable historical payloads, check application state and the official certified state-sync path. An anchor does not supply application state.
- Normal state sync requires a snapshot at H and a matching certified H+1 from enough independent donors. If H+1 is unavailable, stop and escalate. A halted-chain fallback changes the trust model; require a coordinator-approved anchor and explicit operator authorization. On rc10, `min_anchor_agree = 2` did **not** compare snapshot roots in that fallback. rc11 release notes claim a donor-root quorum gate; inspect the exact installed binary/source and donor responses before relying on it.
- Preserve `data/consensus`, `data/wal`, and `data/mayo_sigs.log` across recovery. The MAYO log retains exact prior vote signatures; regenerating them can produce conflicting messages. Never wipe or roll back signer journals to repair a lagging node.
- For a stalled active node, establish whether the network, one peer or only this seat is stalled. Check clock, disk, version, authenticated peers, finalized-height progression and common-height digest before any restart. Coordinate all-version changes; retain a rollback point that does not restore stale signer state.
- No key move, data replacement, second active signer, firewall exposure or coordinated set change without the operator's specific authorization and anti-double-sign proof.

## Report

State exact chain ID and binary release, target and reference finalized heights/digest, peer count, seat participation evidence, clock status, restart count, action taken and unresolved risks. Never include private share contents, private host inventory or credentials in a public report.
