---
name: ethereum-node-and-validator-ops
description: "Operate Ethereum infrastructure: execution and consensus client pairs, checkpoint sync, validator creation and lifecycle, withdrawal credentials, exits and consolidations, MEV-Boost, monitoring, security hardening, client and fork upgrades, incident triage, and concise operator reports."
---

# Ethereum Node and Validator Ops

Use this skill for Ethereum node and staking operations: choosing and running an
execution/consensus client pair, creating and operating validators, monitoring,
security hardening, client and network upgrades, incident triage, and
operator-facing reports.

This skill is operator-neutral and provider-neutral. It must work for any
operator and must not assume a specific hosting provider, relay, staking pool,
custody arrangement or cloud.

## Read this first: the one irreversible mistake

**Never run the same validator key in two places.** Two processes signing for one
public key produce a slashable double vote: the stake is cut, the validator is
force-exited, and the correlation penalty scales with how many others are
slashed at the same time.

The asymmetry that decides every incident: an offline validator loses a few
cents an hour; a double-signing validator loses ETH and is ejected. **Uptime
never justifies a second instance.** When key uniqueness cannot be proven, leave
the validator off and escalate.

The three keys are not equally dangerous:

| Key | Risk if leaked |
|---|---|
| Mnemonic | Total loss of the stake |
| Withdrawal address key | Can trigger exits and withdraw the stake (Pectra) |
| Validator signing key | Slashing liability only — cannot move funds |

An attacker with the signing key cannot steal the stake. That is why the signing
key may live on a networked server and the mnemonic may not.

## Source Priority

1. Current command output from the target host: client logs, `systemctl`,
   `eth_syncing`, the Beacon API, `ss`, disk and clock state.
2. Local operator inventory and runbooks, if available.
3. Official sources:
   - https://ethereum.org/developers/docs/nodes-and-clients/
   - https://ethereum.org/staking/solo/ and https://launchpad.ethereum.org/
   - https://blog.ethereum.org/category/protocol (fork announcements)
   - https://github.com/eth-clients (per-network configs and fork epochs)
   - https://eips.ethereum.org/
   - Client documentation and release notes for the exact pair in use.
4. Community references: https://ethdocker.com/, https://clientdiversity.org/,
   https://beaconcha.in/.

Never call a node or validator healthy without live checks. Refresh the official
release notes before quoting a version, a flag or a fork epoch.

## Architecture

An Ethereum node is **two processes**; staking adds a third.

- **Execution client (EL)** — state and transaction execution. P2P `30303`,
  JSON-RPC `8545`, Engine API `8551`.
- **Consensus client (CL)** — proof of stake. P2P `9000`/`9001`, Beacon API
  `5052`.
- **Validator client (VC)** — holds keystores, signs duties, talks to the CL
  over the Beacon API. No internet access of its own.

EL and CL authenticate over the Engine API with a shared 32-byte hex JWT. A
trailing newline in that file is the most common cause of `Unauthorized`.

## Core Facts

Verify against current sources before acting.

- Mainnet chain ID `1`; deposit contract
  `0x00000000219ab540356cBB839Cbe05303d7705Fa`.
- Staking testnet: **Hoodi**, chain ID `560048`. Holesky is deprecated and shut
  down. Sepolia (`11155111`) is for application development, permissioned
  validator set.
- Active mainnet forks: Deneb (epoch 269568), Electra/Pectra (364032),
  Fulu/Fusaka (411392, 2025-12-03). Glamsterdam is next and unscheduled.
  Fusaka's BPO forks raise blob throughput on their own schedule and are
  fork-critical.
- Minimum stake 32 ETH; maximum effective balance 2048 ETH with `0x02`
  compounding credentials (EIP-7251).
- Pectra system contracts: withdrawal requests
  `0x00000961Ef480Eb55e80D19ad83579A64c007002` (EIP-7002); consolidation
  requests `0x0000BBdDc7CE488642fb579F8B00f3a590007251` (EIP-7251).
- Slashing protection interchange is EIP-3076 and is portable across clients.

## Client Diversity Is an Operational Decision

Recommend a minority client on at least one side, and say why: a client above
33% share can stop finalisation; above 66% it can finalise a fork that its
validators cannot leave without being slashed.

Report shares from a live source rather than memory — they move. As of
2026-09-18, Lighthouse was above 50% of the consensus layer, and Geth and
Nethermind were roughly 43% each on the execution layer.

## Health Verification

Four checks. Report all four or report nothing.

1. `eth_chainId` returns the expected chain.
2. `eth_syncing` returns `false`.
3. `/eth/v1/node/syncing` returns `is_syncing: false`, **`is_optimistic:
   false`**, small `sync_distance`.
4. Head slot matches an independent source.

`is_optimistic: true` is the failure that looks healthy: the beacon node is
following unverified heads, and the validator's attestations are worthless.
Always check it explicitly; never infer it from "the service is running".

Peer floors: EL below 10 or CL below 20 usually means the P2P ports are not
reachable from outside. Test from another host.

For a validator, service state is not evidence. **Inclusion is.** Confirm
attestations landing within two epochs from an independent explorer.

## Triage Order for Missed Attestations

Work in this order; it is ordered by frequency, not by interest.

1. Clock drift (`timedatectl`; drift over ~1 s breaks slot timing).
2. `is_optimistic: true`.
3. Engine API — JWT length/path, EL reachable on `8551`.
4. Peer count and external P2P reachability.
5. Disk saturation (`iostat -x`); a slow SSD delays import, then attestation.
6. VC loaded key count against the expected count.
7. Beacon node head against an external source.
8. If only *proposals* are missed, suspect the MEV relay and verify local
   block-building fallback.

Attestations that land late point at timing, network or disk. Attestations that
never land point at the VC or the beacon node.

## Validator Lifecycle

- **Key generation** belongs on an offline machine, with
  `ethstaker/ethstaker-deposit-cli` (the `ethereum/staking-deposit-cli`
  repository is deprecated). Verify checksums.
- **Withdrawal credentials**: `0x01` caps effective balance at 32 ETH and sweeps
  rewards; `0x02` compounds to 2048 ETH and allows consolidation. `0x00` cannot
  withdraw and must be migrated. `0x01` → `0x02` is irreversible without a full
  exit.
- **Deposit** through the Launchpad; verify the deposit contract address in the
  transaction against the value above before signing.
- **Activation** takes about 13 minutes to be noticed plus a variable queue.
- **Fee recipient** must be set; several clients refuse to start without it.
- **Doppelganger protection** on every client, always. It is a backstop, not
  permission to be careless.
- **Exits** can be initiated with the signing key or, since Pectra, from the
  withdrawal address through the EIP-7002 predeploy. Exit queues plus withdrawal
  delay mean days; the validator must keep attesting throughout.

## Migration and Key Movement

Order is fixed and non-overlapping:

1. Stop the validator client on the old host and confirm it is stopped.
2. Export the EIP-3076 slashing protection interchange.
3. Import it on the new host.
4. Start the validator client on the new host.
5. Verify inclusion externally before declaring the migration done.

Restoring keystores without their slashing protection database is a slashing
event waiting to happen. If the database's age is unknown, wait at least two
epochs — preferably a weak subjectivity period — before starting.

Chain data is disposable; keys and the slashing protection database are not.

## Upgrades

Distinguish the two cases and never treat them the same:

- **Routine update** — no deadline. Stop the VC, update the EL or CL, verify
  sync and non-optimistic, start the VC last.
- **Network upgrade** — a hard slot deadline, both clients, every node. Read the
  EF announcement for the exact slot and the per-client minimum versions, test
  on Hoodi first, be present at the fork slot, and confirm the head has not
  diverged afterwards.

Never roll back across a fork. Never roll back a CL to a version that cannot
read a migrated database — resync with checkpoint sync instead, which costs
minutes.

Do not auto-update client binaries on a validator host. Pin versions.

## Security Boundaries

- Public: `30303` TCP/UDP, `9000` TCP/UDP, `9001` UDP. SSH restricted.
- Loopback only: `8545`, `8546`, `8551`, `5052`, all metrics ports, `18550`.
- Verify listeners with `ss -tlnp`, not firewall rules. **Docker publishes ports
  past ufw** — require the `127.0.0.1:` bind prefix in Compose files.
- Never expose RPC from a staking host. Run a separate keyless node for that,
  behind a proxy with a method allowlist.
- `MemoryDenyWriteExecute=true` breaks JIT runtimes (Besu, Teku, Lodestar).

## Safety Boundaries

This skill is **read-only by default**. It does not generate or move keys,
broadcast transactions, submit deposits, exits or consolidations, move funds, or
mutate services. Those stay behind the operator's explicit approval.

Before any action that could affect signing, require:

- proof that the validator keys run in exactly one place;
- a known-good slashing protection database;
- a verified rollback point;
- a stated verification criterion that includes external inclusion evidence.

Refuse to proceed, and say why, when key uniqueness cannot be proven.

`ethereum-healthcheck.sh` is read-only and prints no credential. A passing check
is evidence, not proof: confirm sync, non-optimistic status, reachability and
inclusion independently before calling a node healthy.

## Reporting

Report: what was checked, what the live values were, what was done, what
remains, and what changed. Quote the four health facts with their values, not as
"healthy". Name versions and fork epochs from live output, not memory. State
unknowns as unknowns.
