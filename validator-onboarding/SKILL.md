---
name: "validator-onboarding"
description: "Use when onboarding or registering a validator with readiness, key-custody, parameter, transaction, and monitoring gates."
---

# Validator onboarding

Use for creating, registering, or activating a new validator after its node infrastructure is prepared.

This public skill is operator-neutral. Resolve `network_ref`, `target_ref`, validator identity, approved branding, commission, funding, service, monitoring, and custody policy from private knowledge and live state. Never embed organization-specific values.

## 1. Establish requirements and authority

Confirm:

- exact chain and environment;
- official current validator onboarding or registration procedure;
- eligibility, active-set, allowlist, stake, hardware, version, and network requirements;
- mainnet versus testnet intent;
- validator type: local signer, remote signer, committee member, sequencer, or non-Cosmos role;
- required identities, consensus/BLS keys, operational addresses, contracts, forms, or governance approvals;
- approved moniker, metadata, commission, self-delegation, funding, and custody owner.

Do not reuse parameters from another chain or infer branding/commission defaults from this package.

## 2. Prove node and signer readiness

Before registration:

1. Verify expected binary/image and chain ID.
2. Confirm the node is synced and height/block time agree with independent external truth.
3. Verify peer health, time synchronization, disk/memory headroom, stable service restarts, and clean recent logs.
4. Prove only the intended signer can use the consensus key.
5. Back up all required key-bearing configuration without opening or printing secret contents.
6. Verify safe public-key/address metadata using supported CLI or API output; do not read raw private key files to derive it.
7. Confirm P2P/RPC/admin exposure and firewall policy match the intended validator role.
8. Check monitoring, upgrade handling, backups, and recovery prerequisites.

If key custody, signer uniqueness, or network identity is uncertain, stop before registration.

## 3. Build the registration plan

Record every immutable or hard-to-change parameter:

- validator/operator/consensus/operational addresses;
- self-delegation or stake amount and denom;
- commission rate, maximum, and change rate;
- moniker, description, website, identity, and security contact;
- chain ID, contract, registry, RPC, gas, fees, and memo;
- special keys or proofs;
- expected post-registration state.

Compare values to official rules and private operator decisions. Flag irreversible commission or identity constraints.

## 4. Transaction and external-form gate

Registration, validator creation, staking, delegation, contract calls, governance submissions, and external forms are separate external actions.

For a transaction:

1. Use a healthy verified RPC and official command/schema.
2. Simulate, dry-run, or build unsigned output when supported.
3. Present the exact signer, addresses, amount, denom, commission, chain ID, fees, and expected state transition.
4. Obtain explicit operator approval before signing or broadcast.
5. Never expose wallet passwords, mnemonics, private keys, or credential files.
6. Verify transaction inclusion and resulting validator state independently.

For a form, explorer, repository, or allowlist submission, present the complete public payload and destination for approval before sending. Do not claim acceptance until externally verified.

## 5. Activate safely

After registration:

- confirm validator identity and all published fields;
- verify bonded/active/committee status or document the pending activation condition;
- verify recent signatures/attestations from independent truth;
- ensure no duplicate signer or stale standby can activate;
- fund only the approved operational balances;
- add validator and dependencies to monitoring;
- validate alert routing and a read-only recovery check;
- record upgrade, backup, snapshot, sentry, relayer, or remote-signer dependencies.

A successful transaction alone is not successful onboarding.

## 6. Document and watch

Update private network and infrastructure knowledge with actual targets, identifiers, service placement, monitoring, backup custody, and unresolved activation conditions. Keep these facts out of the public skill.

Run a bounded watch through the first signing/attestation cycles. Report:

- official source and version;
- readiness evidence;
- approved parameters;
- transaction/submission result;
- validator state and recent signatures;
- monitoring state;
- remaining activation or funding tasks.
