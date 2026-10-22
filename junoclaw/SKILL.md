---
name: junoclaw-validator-ops
description: "Operate JunoClaw G2 validators: threshold reshares, single-signer cutovers, state sync, finality/signing checks, and recovery."
---

# JunoClaw validator operations

Use for a JunoClaw G2 seat running `slay3rd` on the Commonware-based chain. JunoClaw is **not** Cosmos Juno: do not use `junod`, CometBFT, Cosmovisor, staking, unjail, or Cosmos snapshot procedures. G2 is an invited, equal-weight testnet without consensus-layer staking or slashing, but a second live signer for one seat is unsafe.

## Source and identity gate

1. Read private inventory and the current coordinator-approved roster, window and config. Compare the [validator guide](https://junoclaw.xyz/docs/onboarding/validators/), [run-a-node guide](https://junoclaw.xyz/docs/reference/run-a-node/), and [releases](https://github.com/Dragonmonk111/layer-sdk/releases). Check exact chain ID, binary provenance/digest, genesis, peer IDs, index, quorum and anchor. G2 has used `junoclaw-g1`; the reference devnet's `junoclaw-1` is not interchangeable.
2. Check dedicated host/network failure domain, NTP drift under two seconds, reachable P2P TCP 7001, adequate resources (official minimum two cores, 4 GB RAM, 20 GB SSD), and private gRPC TCP 9090 unless publication was approved. Prove one signer placement before start or key movement.
3. Pin ceremony tool and node binary to an authenticated release or coordinator package and checksum. A digest supplied with an unauthenticated download proves byte agreement, **not publisher authenticity**. The 2026-10-22 fleet used a coordinator-distributed rc14v3 build, but its full build commit and independent publisher authenticity were not established locally. Do not install an unverified URL from forwarded text; coordinate version/config changes across the set.

## Threshold reshare and key custody

The 2026-10-22 round-2 ceremony expanded G2 to eight seats, a 6-of-8 threshold and five dealers while preserving the prior full BLS group public key. These are historical facts, **not** defaults for future rounds. Reconfirm roster, quorum, dealers, tool and previous key each time.

1. Generate or retain the identity on the final signer. Share only the public identity request. Never print, paste or transmit `keys.json`, a decrypted share, `bls-share.json` or `dealer.seed`. Recipient-sealed `dealing-priv-*-for-*.json` files may be relayed only to the named recipients through the approved ceremony route; do not publish them as general downloads.
2. Check exact round, player/dealer IDs, previous full group public key, recipient and safe archive member types before extraction. Dealers retain `dealer.seed` locally until their log is verified. Players acknowledge every expected dealer with the pinned tool; verify counts, zero complaints and coordinator acceptance.
3. **Do not run dealer logging with a missing or disputed acknowledgement.** A missing ack can reveal that player's share in dealer logs. After all expected acks are accepted, generate and relay only the intended public log. Remove the used seed only after log verification and the approved retention decision.
4. Independently observe complete logs: require exact equality with the previous full BLS group public key and approved new threshold. On the **same signer**, finalize against a protected copy of the live key, verify validator/share index and stage the new key without replacing the live key before the window. Check the issued `node.toml`, genesis, peer keys, chain ID, anchor and host paths. No ad-hoc off-host key copy.

## Controlled cutover and verification

1. At the coordinated window, check exact target, freeze, single-signer placement, clock, disk, digests and rollback capacity. Stop the old service and prove its signer process and listeners absent before swapping. Preserve old binary/config/key as protected artifacts, and retain consensus, WAL and application state unless a separately approved recovery plan requires otherwise.
2. Switch only the reviewed binary, finalized same-host key and host-specific config; start one service. Check running image digest, loaded share index/quorum, accepted anchor, active service, stable restart count, authenticated peers and advancing **local** finality. Compare digest/app hash at a common height with an independent peer.
3. A running process, peers or coordinator announcement do not prove this seat signed. Independently decode a fresh certificate/signature bitmap for its index, or label peer/coordinator evidence as relayed. Alert on finality stalls and clock/peer loss. Never blindly restore an old key or journal after the new share may have signed.

## Recovery boundaries

- A restart anchor alone does not import application state. A joining seat may need certified state sync: a snapshot at H normally needs an agreed certified H+1 from independent donors. If the chain is halted and H+1 is unavailable, require an explicit coordinator-approved halted-chain anchor path and donor trust decision. A single-donor `min_anchor_agree = 1` path is weaker than multi-donor agreement. Check the exact installed binary before relying on flags or release-note quorum claims.
- Preserve `data/consensus`, `data/wal` and `data/mayo_sigs.log`. Never wipe or roll back signer journals to repair lag. Divergent application state requires a target-specific backup and approved sync plan; do not apply another seat's wipe instruction.
- For a stalled active node, determine whether the network, a peer or this seat is stalled. Check clock, disk, version, peers, finalized-height progression and common-height digest before intervention. No key move, state replacement, second active signer, firewall exposure or set change without specific authorization and anti-double-sign proof.

## Report

State chain ID, binary identity/provenance, target/reference heights and digest, peer count, seat participation evidence, clock, restart count, action and residual risk. Never include private share contents, private inventory or credentials in a public report.
