---
name: "limonata-validator-ops"
description: "Operate Limonata validators/full nodes with encrypted-mempool and DKG safety gates."
---

# Limonata validator operations

Use for Limonata testnet full-node or validator health checks, installation
planning, state sync, recovery, DKG observation, controlled restarts,
encrypted-mempool testing, and upgrade planning.

## Source priority

1. Current target state and local RPC.
2. The operator's own inventory and runbooks.
3. Official Limonata documentation, releases, and repository.
4. Official CometBFT RPC, REST, EVM RPC, explorer, and Proving Grounds.
5. Third-party sources only as secondary evidence.

Refresh release, checksum, genesis, chain parameters, upgrade plan, and DKG
behavior before production changes.

## Core facts to verify

- Cosmos chain ID: `limonata_10777-1`.
- EVM chain ID: `10777`.
- Publication-time release baseline: `limonata-v0.3.4` / `77fc357f`; revalidate
  before installing or upgrading.
- Use CometBFT RPC for state-sync trust data; do not use EVM JSON-RPC for
  `/block` or `/commit`.
- Keep RPC, REST, gRPC, EVM RPC, metrics, and pprof loopback-only unless a
  separately approved public-service design exists.

## Validator and DKG safety

- Never copy a consensus key to a second active signer.
- Preserve the consensus key, monotonic signer state, and mode-0600 DKG ECIES
  key before destructive recovery.
- DKG shares, threshold key, QUAL, and committee reconstruct from committed
  state; do not invent local-share backup procedures.
- Routine public-testnet restart belongs in an ACTIVE epoch with no open DKG
  round.
- Confirm signing, DKG key persistence, and QUAL membership after restart.
- Use isolated devnet only for phase-precise member-drop, malformed, Byzantine,
  or poisoned-material testing.
- Encrypted transaction tests require an operator-approved low-rate payload and
  independent result verification.

## Health workflow

1. Prove chain ID, local and official height, advancing blocks, sync state,
   peer count, version, and service identity.
2. For validators, query bonded/jailed state and confirm recent commit
   signatures through independent RPC.
3. For DKG participation, inspect `encmempool_dkg_round_opened` for
   member/index/key/evaluation points and `encmempool_dkg_finalized` for QUAL.
4. Compare the epoch threshold as weighted evaluation points, not validator
   count.
5. Do not restart on a network-wide halt or uncertain DKG transition.

## Recovery and restart

1. Prove one active signer and capture rollback evidence.
2. Preserve the required key and state files without exposing their contents.
3. Rebuild only disposable node data from a verified source.
4. After restart or restore, verify external height, sync, bonded/not-jailed
   state, fresh signatures, DKG permissions, and monitoring.
5. Escalate before key movement, duplicate signer uncertainty, public endpoint
   exposure, or any transaction.

## Evidence and documentation

Record commands, version, heights, event IDs, signatures, QUAL result,
resource observations, and rollback state. Keep secrets, private topology, and
unapproved endpoints out of logs and public material.

Official sources:

- https://limonata.xyz/
- https://limonata.xyz/VALIDATOR.md
- https://github.com/Limonata-Blockchain/limonata
