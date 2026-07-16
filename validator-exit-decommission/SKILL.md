---
name: "validator-exit-decommission"
description: "Use when exiting, retiring, or decommissioning a validator with transaction, unbonding, key-retention, and shutdown gates."
---

# Validator exit and decommission

Use for a planned validator exit, retirement, or permanent workload removal. Treat exit transactions, signing shutdown, data deletion, and key disposition as separate gates.

This public skill is environment-neutral. Resolve the authorized `network_ref`, `validator_ref`, wallet role, service, monitoring, and retention policy from private knowledge and live state. Never embed or guess inventory.

## 1. Define the exit

Confirm:

- exact chain and environment;
- validator identity and current bonded/active/jailed state;
- reason and target outcome;
- chain-specific exit, unbonding, slashing, reward, and commission rules;
- delegator communication or rename requirement;
- balances, self-delegation, rewards, commission, and non-native assets;
- whether the signer must remain online during any transition;
- key, database, log, and evidence retention periods.

Create a phased plan with explicit success criteria and dates. Do not infer that one Cosmos-style sequence applies to every chain.

## 2. Establish safety and evidence

Before transactions or shutdown:

1. Verify chain ID, validator/operator/wallet identifiers, recent signing, and external network truth.
2. Confirm the signer is unique and there is no concurrent migration or incident.
3. Back up key-bearing configuration outside any later deletion target without opening or printing key contents.
4. Verify backup existence, size, ownership, permissions, and retention.
5. Record current validator state, delegations, balances, commission, pending rewards, governance obligations, and unbonding entries.
6. Check active freezes, upgrade windows, automation, relayers, sentries, and monitors affected by the exit.

Database backup is optional and potentially large; obtain operator approval when needed.

## 3. Build the transaction plan

Each rename, reward/commission withdrawal, unbond, redelegation, transfer, or deregistration is a transaction boundary.

For every transaction:

- use official current chain instructions and a verified healthy RPC;
- confirm signer account, validator, destination, amount, denom, fees, memo, sequence, chain ID, and expected state transition;
- simulate, dry-run, or build unsigned output where supported;
- present the exact human-readable plan;
- obtain explicit operator approval before signing or broadcast;
- verify the transaction hash and resulting on-chain state independently.

Never pipe or echo passwords, mnemonics, or key material. Never transfer the maximum balance without a fee and follow-up buffer. Withdraw commission/rewards in the chain-specific safe order before removing required stake.

## 4. Manage unbonding and transition

Record amount, transaction, start time, completion estimate, unbonding identifier, and residual risk. Keep the signer online or stop it according to verified chain rules and the approved plan—not a generic assumption.

Maintain a reduced exit monitor for:

- validator state and recent signing while signing is expected;
- unbonding progress and completion;
- slashing/jailing or unexpected state changes;
- remaining balances and claimable rewards;
- dependent services and delegator-facing status.

Do not remove monitoring merely because an unbond transaction succeeded.

## 5. Decommission separately

Only after the approved exit state is proven:

1. Stop the intended workload and verify it cannot restart.
2. Preserve required keys, signer state, transaction evidence, config metadata, and logs.
3. Disable service/container automation and remove public routes or firewall exposure only within the approved scope.
4. Remove data only after mandatory key backup verification and explicit deletion approval.
5. Keep secrets and retired keys under the private retention policy; never publish or casually discard them.
6. Remove or update monitors, sentries, relayers, inventories, public pages, backup jobs, upgrade schedules, and cost records.
7. Verify no orphan listeners, containers, timers, DNS/proxy routes, or stale alerts remain.

Do not reuse or destroy the host as an implied part of validator exit.

## 6. Close

Completion requires:

- final validator/unbonding state verified externally;
- all approved transactions confirmed;
- signer stopped only when intended;
- retained artifacts verified and private;
- dependencies and public representations updated;
- residual funds, unbonding dates, and follow-ups recorded;
- decommission scan shows no unintended workload or exposure.

Report completed phases, pending unbonding or financial actions, retained assets, deletion performed, and next review date. Update private network knowledge, unbonding schedule, infrastructure inventory, TODO, and daily memory.
