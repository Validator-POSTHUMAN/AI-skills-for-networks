---
name: xrplevm-node-ops
description: "Operate XRPL EVM nodes and validators: exrpd installation, snapshot and state-sync bootstrap, Proof of Authority admission, consensus-breaking versus patch upgrades, app-hash agreement checks, anti-double-sign discipline, EVM JSON-RPC and indexing, monitoring, hardening, incident triage, and concise operator reports."
---

# XRPL EVM Node Ops

Use this skill for XRPL EVM node and validator operations: installing `exrpd`,
bootstrapping from a snapshot or state sync, joining the Proof of Authority
set, running upgrades, serving the Cosmos and EVM APIs, monitoring, hardening,
and triaging incidents.

Operator-neutral. It names no production host, no credential and no private
endpoint.

## Read this first: what XRPL EVM is

A Cosmos SDK chain with an EVM execution layer, served by one binary, `exrpd`,
under CometBFT consensus. Consensus is **Proof of Authority**: the validator
set is admitted by a vote of the existing validators, over seven days, not by
stake weight.

A validator here holds a consensus key, signs blocks, can be jailed, and can be
**tombstoned** — permanently, with no vote that reverses it.

So none of the "restart it, wipe it, restore it" reflexes from follower chains
apply. On this network:

| Action | Cost |
|---|---|
| Two processes with one `priv_validator_key.json` | double-sign → tombstoned → permanent |
| Rolling `priv_validator_state.json` backwards | the same |
| `unsafe-reset-all` on a signer home | key and state loss |
| Restarting a signer without cause | missed blocks, possibly jail |

**Uptime never justifies double-sign risk.** If the two are in tension, stop
and ask the operator.

## The failures this skill exists for

### Six digits instead of seven

```
chain-id = "xrplevm_144000-1"   # wrong — 6 digits
chain-id = "xrplevm_1440000-1"  # correct — 7 digits
```

A stale six-digit value in `client.toml` produces deterministic app-hash
divergence during bootstrap while the genesis file and the binary are both
correct. It does not present as a configuration error. Leaving the field unset
also works. Check this first on any fresh node that diverges.

### The documentation table lags the fleet

The official Networks page lists the last **consensus-breaking** version and
its upgrade height. Patch releases never appear there, never produce an
on-chain plan, and `exrpd query upgrade plan` returning `{}` is therefore not
evidence that there is nothing to do.

Verified 2026-09-18: the table said `v10.1.0` while `cosmos-rpc.xrplevm.org`
answered `abci_info` with `10.2.1` and an independent ITRocket node answered
`10.2.0` — same height, same app hash. `v10.2.0` and `v10.2.1` are `cosmos/evm`
dependency bumps (`v0.6.2-august-2026-hotfix-xrplevm.1` and `.2`).

**Read the fleet, not only the table.**

### `systemctl start` on a live unit is a no-op

After replacing a binary or a `priv_validator_key.json`, `start` against an
already-active unit returns success and changes nothing. Use `restart`, or
`stop` then `start`. Symptoms of getting it wrong: `voting_power=0`, height
stuck, the node's `valcons` absent from `last_commit`.

### A healthy-looking node on the wrong chain

`active (running)` plus `catching_up=false` is fully compatible with following
a different chain. The only check that settles it is an app-hash comparison at
a common height against an independent RPC — preferably two.

### The `v11` line is not mainnet

`v11.x` tags exist and run on devnet and testnet. Installing one on mainnet
before the mainnet proposal passes is a self-inflicted fork.

## Source priority

1. Live command output from the target host: `/status`, `/abci_info`,
   `/net_info`, unit state, `ss`, disk, clock, logs.
2. Independent public RPCs, for agreement — one is not enough.
3. Local operator inventory and runbooks.
4. Official sources:
   - https://docs.xrplevm.org/pages/operators — operator documentation
   - https://docs.xrplevm.org/pages/operators/resources/networks — chain IDs,
     genesis, peers, **consensus-breaking** upgrade history
   - https://github.com/xrplevm/node/releases — the release source of truth,
     including patches the docs table does not show
   - https://github.com/xrplevm/networks — genesis and peer lists
   - https://governance.xrplevm.org/validators — the set's view of your
     validator
5. Community: the XRPL EVM Discord, `#become-a-validator`.

Never call a node healthy without live checks. Refresh the releases page before
quoting a version.

## Architecture

One process, four APIs.

| API | Default port | Serves |
|---|---|---|
| CometBFT P2P | `26656` | consensus gossip — **public** |
| CometBFT RPC | `26657` | `/status`, `/block`, `/commit`, `/net_info` |
| Cosmos REST | `1317` | staking, gov, bank, slashing |
| Cosmos gRPC | `9090` | the same, typed |
| EVM JSON-RPC | `8545` / `8546` | `eth_*`, wallets, contracts |
| Prometheus | `26660` | CometBFT metrics |

Only `26656` belongs on the public internet. Everything else is loopback or
behind a reviewed reverse proxy with TLS and rate limiting — `exrpd` enforces
no per-client limit.

## Operational facts worth not re-deriving

| Fact | Value |
|---|---|
| Mainnet Cosmos chain ID | `xrplevm_1440000-1` |
| Mainnet EVM chain ID | `1440000` / `0x15f900` |
| Testnet | `xrplevm_1449000-1` / `1449000` / `0x161c28` |
| Devnet | `xrplevm_1449900-1` / `1449900` |
| Binary | `exrpd` |
| CometBFT | `0.38.19` |
| Cosmos SDK | `v0.53.x-xrplevm` |
| Denom | `axrp`, 18 decimals, displayed as XRP |
| Bech32 | `ethm1…`, `ethmvaloper1…`, `ethmvalcons1…` |
| Operator key type | `eth_secp256k1` — **not** the Cosmos default |
| `evm-chain-id` in `app.toml` | mandatory since v10 |
| Mainnet upgrade heights | v8 `497000`, v9 `4688681`, v10 `4749000`, v10.1 `6856000` |
| Docker image | `peersyst/exrp:<tag>` |
| Admission | 7-day Proof of Authority vote |

Two things that trip people:

- **One account, two representations.** `ethm1…` and `0x…` are the same key and
  the same balance. Never display them as two assets; never add them together.
- **`indexer = "null"` is correct on a signer and wrong on an RPC node.** It is
  why `eth_getTransactionByHash` returns null for transactions that plainly
  exist. Changing it does not backfill.

## What this skill helps agents do

- Verify a node in the right order: `/status`, `/abci_info`, then app-hash
  agreement against two independent RPCs — by hash, not by height.
- Separate a consensus-breaking upgrade at a block height from a patch release
  with no gate, and drive each to its own verification.
- Restore a snapshot in the order that works — download, verify the archive,
  **then** stop the node — while preserving `priv_validator_state.json`.
- Run the anti-double-sign check across every host that has ever held the key,
  and treat an inactive unit with a live listener as a running node.
- Read `voting_power: 0` through its real causes: a `start` on a live unit,
  still syncing, jailed, or the wrong key in place.
- Read `tombstoned: true` as terminal and stop, rather than attempting
  recovery.
- Configure and verify both chain IDs and both API families without conflating
  them.
- Prepare a Proof of Authority admission: the three identifiers, the readiness
  evidence, and the commitments the set actually asks for.

## Safety boundaries

Read-only by default. This skill broadcasts no transaction, moves no funds and
handles no key material.

Explicit operator approval is required before:

- any service stop, start or restart on a node that signs;
- any snapshot restore, data replacement or migration;
- any binary change on a signer;
- `exrpd tendermint unsafe-reset-all`, on any home;
- any firewall or exposure change;
- any transaction: `create-validator`, `edit-validator`, `unjail`, `vote`,
  `delegate`, or a transfer.

Before any of the first three, the anti-double-sign check comes first and its
result is reported, not assumed:

```bash
# on EVERY host that has ever held this key
systemctl is-active exrpd cosmovisor-exrpd
systemctl is-enabled exrpd cosmovisor-exrpd
pgrep -af exrpd
ss -ltnp | grep -E ':(26656|26657)'
```

An `inactive` unit with a live listener is a running node. A disabled unit on a
host nobody checked is the scenario that tombstones validators.

Key material — `priv_validator_key.json`, `node_key.json`, mnemonics, keyring
files — is never printed, never pasted into a message, and never included in a
snapshot archive or a log handed to a third party.

## Diagnostic order

Work down. Stop when a step explains the symptom.

1. Unit state and restart count. Is it flapping?
2. Logs since the last start, filtered for `err`, `panic`, `wrong`, `mismatch`.
3. `client.toml` chain ID — six digits or seven?
4. `app.toml` `evm-chain-id` — set, and correct for this network?
5. `/status`: height advancing, `catching_up`, `voting_power`.
6. App hash at a common height against **two** independent RPCs.
7. `/net_info` peer count. Two or fewer ⇒ stale addrbook or empty
   `persistent_peers`.
8. `abci_info` version against the fleet.
9. Presence in `last_commit`, and `missed_blocks_counter` from the slashing
   module.
10. Disk on **all** mounts, file descriptors, clock skew.
11. Only then: has anyone else started a node with this key?

## Reporting

What was checked, what was found, what was done, what remains. For an XRPL EVM
node the report is incomplete without:

- running version, and the version the fleet is running;
- height, `catching_up`, and app-hash agreement with a named independent source;
- `voting_power`, and presence in the latest commit, if this node signs;
- `missed_blocks_counter`, `jailed_until`, `tombstoned`;
- which ports are bound off loopback;
- any pending on-chain upgrade plan, its exact name and height, and whether the
  binary is staged for it.

## `scripts/xrplevm-healthcheck.sh`

Read-only. Runs no mutating command, changes nothing, prints no credential.

```bash
xrplevm-healthcheck.sh --local --chain-id xrplevm_1440000-1
xrplevm-healthcheck.sh --rpc http://127.0.0.1:26657 \
  --reference https://cosmos-rpc.xrplevm.org \
  --chain-id xrplevm_1440000-1
```

It samples the height **twice**, because one reading cannot distinguish
"advancing" from "stopped a second ago", and it compares the app hash against a
reference RPC, because a node agreeing with itself proves nothing.

A passing check is evidence, not proof.
