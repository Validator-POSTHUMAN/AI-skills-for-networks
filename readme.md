# AI Skills for Networks

This repository contains AI-agent skills for blockchain network operations.
They are maintained by POSTHUMAN, but the skills are intended to be usable by
any validator operator with their own inventory and runbooks.

Each network directory is a self-contained skill that helps an AI agent perform
safe validator operations: monitoring, upgrade preparation, incident triage,
recovery checks, and operator-facing reports.

Network skills should avoid real operator infrastructure data. Use fake example
inventories and machine-readable schemas when a skill needs host, service, RPC,
valoper, or consensus-address input.

## Skills

- [Shentu](shentu/SKILL.md) — Shentu Chain validator operations for
  `shentu-2.2`.
- [Axelar](axelar/SKILL.md) — Axelar validator operations for `axelar-dojo-1`,
  including `axelard`, `vald`, `tofnd`, broadcaster, and external-chain
  maintainer checks.
- [Monad](monad/SKILL.md) — Monad validator and full-node operations for
  mainnet and testnet, including `monad-bft`, `monad-execution`,
  `monad-rpc`, TrieDB, OTel, staking, upgrades, and recovery checks.
- [Starknet](starknet/SKILL.md) — Starknet full-node, JSON-RPC,
  validator/staking/attestation, Cairo tooling, and Starkzap/app integration
  workflows.
- [Fuel](fuel/SKILL.md) — Fuel Ignition fuel-core full-node and GraphQL
  operations plus Fuel Sequencer node, validator, sidecar, bridge, upgrade,
  snapshot, and Sway/forc workflows.
- [Cosmos Hub](cosmoshub/SKILL.md) — Cosmos Hub Gaia validator and full-node
  operations for cosmoshub-4, including gaiad, CometBFT signing, provider
  security, IBC-facing checks, governance, upgrades, snapshots, and recovery.
- [Oraichain](oraichain/SKILL.md) — Oraichain oraid validator and node
  operations for mainnet, including RPC/API/gRPC checks, signing, upgrades,
  snapshot recovery, CosmWasm, oracle, VRF, OraiDEX/OBridge/OraiBTC, and
  OraichainEVM guardrails.

## Skill Package Layout

A mature network skill may include:

- `SKILL.md` — concise agent instructions and safety rules.
- `scripts/` — deterministic checks or helpers.
- `references/` — schemas or deeper reference material loaded only when needed.
- `examples/` — fake-value templates, never production inventory.
- `evals/` — scenario prompts for safety and behavior checks.

## Operating Principles

- Verify live state before acting.
- Prefer official project repositories and local operator inventory over stale
  assumptions.
- Do not perform destructive validator actions without explicit operator
  approval and key backups.
- Do not publish secrets, wallet mnemonics, keyring passwords, or private
  infrastructure credentials.

## License

This repository is licensed under the Creative Commons Attribution 4.0
International Public License (CC BY 4.0).

You may use, copy, modify, redistribute, and adapt these skills, including for
commercial and internal validator operations, provided that attribution is given
to the creator:

POSTHUMAN validator - https://github.com/Validator-POSTHUMAN

See [LICENSE](LICENSE) and [ATTRIBUTION.md](ATTRIBUTION.md).
