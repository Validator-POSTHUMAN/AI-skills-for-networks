# Classic Axelar Full Node and Validator Setup

Use this reference for the classic Axelar plane: an `axelard` full node, and—
only after full-node readiness—a validator with a dedicated classic `tofnd` and
`vald`. It deliberately excludes executable key generation and automatic
transactions.

## 1. Freeze the deployment inputs

Record and review:

- environment, chain ID, node role, moniker label, Axelar home, data backend,
  pruning/indexer policy, and public-service intent;
- host/runtime, non-root service account, service names, directories, ports,
  firewall policy, resource limits, and monitoring path;
- exact `axelar-core` and `tofnd` release tags/commits, supported architecture,
  signatures/checksums, build toolchain, and rollback artifacts;
- official genesis, seeds/peers, expected genesis checksum, current upgrade
  plan, minimum gas policy, and snapshot source/checksum if used;
- validator, consensus, and broadcaster public addresses plus custody
  references—never key contents;
- intended classic external-chain maintainer set and each private,
  operator-controlled chain RPC.

Do not derive production network files from the public `axelar-configs`
application registry. It is useful for cross-checking public chain identity and
denoms, not as a validator genesis/seed authority. Refresh the official node
and validator docs and current release records listed in `source-pins.md`.

## 2. Stage and verify software

1. Obtain `axelard` and `tofnd` only from an exact reviewed release or build an
   exact reviewed tag/commit. The core repository documents `make build-static`
   for release builds.
2. Verify the release signature and checksum through an independently obtained
   official record. Record binary SHA-256, version output, architecture, and
   source commit.
3. Stage immutable versioned binaries. Point service definitions at explicit
   paths or an operator-controlled versioned symlink; never download into a
   running service path.
4. Inspect the effective service account, environment, working directory,
   limits, restart policy, and dependencies before enabling anything.

A successful version command proves only that a binary runs; it does not prove
network compatibility.

## 3. Initialize through the custody ceremony

Node initialization creates identity material, and validator/broadcaster/tofnd
setup creates signing material. Perform those steps only in the operator's
approved custody workflow; this public skill provides no generation or import
commands.

After the ceremony, verify without printing contents:

- owner, restrictive mode, expected path, backup reference, and checksum or
  metadata for protected files;
- the expected public node ID, valoper, consensus address, broadcaster address,
  and `tofnd` public identity;
- that no other host or process can use the same consensus or threshold key;
- that mnemonic/export artifacts are not left in service directories, shell
  history, environment files, logs, or backups without encryption.

Stop if signer uniqueness or recoverability is not proven.

## 4. Configure the full node

1. Install the reviewed genesis and seed/peer data, then verify genesis bytes,
   chain ID, and source provenance before first network start.
2. Set explicit P2P, RPC, gRPC, REST, Prometheus, pruning, indexer, database,
   minimum-gas-price, and state-sync/snapshot policy for the intended role.
3. Keep administrative RPC methods disabled. Bind RPC/gRPC/REST/Prometheus to
   loopback or a reviewed private listener unless a separately hardened public
   gateway is intended. Do not expose a signing validator as a public RPC.
4. Set durable storage, file-descriptor limits, logs, rotation, disk alerts,
   OOM visibility, and time synchronization.
5. If using a snapshot, follow `safe-recovery.md`: download completely, verify
   checksum and archive layout, extract in staging, preserve protected state,
   and keep rollback. Do not stream into live data or use an unsafe reset as a
   generic install step.
6. Start only the full-node service. Leave `tofnd` and `vald` stopped.

Full-node readiness requires:

- exact chain ID and expected running binary/checksum;
- active service with stable restart count and no panic/corruption loop;
- fresh advancing block time/height, `catching_up=false`, healthy peers, and
  agreement with an independent source;
- acceptable disk, inode, I/O, memory, CPU, network, time sync, and file
  descriptors;
- expected private/public listeners and working monitoring collection.

## 5. Create separate service boundaries

Use three independently supervised units or equivalent runtime boundaries:

| Boundary | Purpose | Must depend on | Must not contain |
|---|---|---|---|
| `axelard` | consensus/full node | network, storage, time | wallet or `tofnd` password |
| classic `tofnd` | threshold signer for classic validator duties | protected credential delivery | Amplifier signer store or wildcard public bind |
| `vald` | classic votes, heartbeats, multisig, external-chain polling | synced `axelard`, classic `tofnd`, broadcaster custody | plaintext passphrase or Amplifier state |

Use an operator-approved protected credential mechanism; do not put passwords
or mnemonics in unit files, command lines, environment files, or shell pipes.
Bind classic `tofnd` to loopback or a reviewed private socket and permit access
only from classic `vald`.

Start order after readiness and signer-uniqueness proof:

1. `axelard` fully synced;
2. classic `tofnd` reachable only on its intended private listener;
3. `vald` pointed to the exact valoper, chain ID, local Axelar RPC, broadcaster
   custody path, classic `tofnd`, and reviewed external-chain configuration.

A service being `active` does not prove it is using the correct binary, config,
signer, or chain.

## 6. Validator readiness before any staking action

Collect a review packet containing:

- chain ID, moniker, valoper, consensus public key/address, validator account,
  intended self-delegation, denomination, commission parameters, and custody
  owner;
- synced node evidence, signer uniqueness, backup verification, exact binary,
  upgrade plan, balance/fee readiness, and monitoring acceptance;
- the unsigned transaction JSON produced by the operator's approved tooling,
  simulation result where supported, account/sequence, fee/gas, and expiry.

Do not include or run a create-validator/staking command here. Creation,
staking, signing, and broadcast are separate operator-approved actions. After
an approved broadcast, verify the transaction independently, validator status,
consensus address, bonded/jailed state, voting power, and several fresh commit
signatures before declaring validator readiness.

## 7. Immutable broadcaster proxy review

Official docs warn that a validator can register only one broadcaster address
for its lifetime and cannot change it. Treat registration as an irreversible
identity decision.

Before preparing anything, prove:

- exact chain ID, valoper, validator signer, broadcaster public address, and
  current proxy query;
- the query shows no existing proxy, or the intended proxy already matches;
- broadcaster custody, recovery, balance policy, and exclusive use by `vald`;
- no pending transaction or concurrent broadcaster process can cause sequence
  drift.

Only for review, an operator may generate unsigned JSON with placeholders:

```bash
# GENERATE ONLY — DO NOT SIGN OR BROADCAST; replace placeholders after review.
axelard tx snapshot register-proxy <BROADCASTER_ADDRESS> \
  --from <VALIDATOR_SIGNER_REFERENCE> \
  --chain-id <EXACT_CHAIN_ID> \
  --home <AXELARD_HOME> \
  --gas auto --gas-adjustment <REVIEWED_VALUE> \
  --generate-only --output json
```

The generated JSON, signer, account/sequence, fee/gas, immutable address, and
current proxy result require a separate approval. Never add `--yes`, sign, or
broadcast in this workflow. After an approved external broadcast, query the
proxy independently and require an exact match.

## 8. Classic external-chain maintainers

For every intended classic external chain:

1. Verify the operator controls a healthy, correctly finalized, private RPC for
   that exact chain. Review chain-specific official requirements.
2. Add exactly one reviewed `[[axelar_bridge_evm]]` entry or update the existing
   entry. Verify `name`, `rpc_addr`, finality settings, and
   `start-with-bridge=true` against the running `axelard`/`vald` version.
3. Validate config parsing before restart. Preserve the previous config.
4. Restart only `vald` at a reviewed low-risk point; do not restart `axelard`
   for this change. Verify connection and bounded error logs.
5. Generate the maintainer transaction only after RPC readiness:

```bash
# GENERATE ONLY — DO NOT SIGN OR BROADCAST; chain list must match reviewed config.
axelard tx nexus register-chain-maintainer <CHAIN_NAME...> \
  --from <BROADCASTER_SIGNER_REFERENCE> \
  --chain-id <EXACT_CHAIN_ID> \
  --home <AXELARD_HOME> \
  --gas auto --gas-adjustment <REVIEWED_VALUE> \
  --generate-only --output json
```

6. Require separate approval for signing/broadcast. After external broadcast,
   verify on-chain maintainer membership, successful `vald` votes, broadcaster
   sequence/balance, and no repeated RPC/poll/finality errors.

Enable RPC and register maintainer status as one controlled change. To stop
support, first prepare/review deregistration, then after approved on-chain
confirmation disable the matching bridge and restart only `vald`. A mismatch
burns fees or misses votes and can lead to automatic deregistration.

## 9. Post-install acceptance

Apply `monitoring.md`. For a classic validator, require all of:

- fresh independent Axelar consensus progress and several recent signatures;
- bonded/not-jailed state and expected consensus identity;
- `axelard`, classic `tofnd`, and `vald` active with stable restart counts;
- built-in health checks passed or any compatibility fallback explicitly
  explained and independently covered;
- exact broadcaster proxy, adequate balance, and no concurrent use;
- each intended maintainer present on-chain, matching an enabled healthy RPC,
  with successful recent `vald` activity;
- infrastructure and process alerts routed and tested without leaking secrets;
- protected backup and rollback evidence.

Anything unknown remains a blocker, not a successful setup.