# AI Skills for Networks

This repository contains AI-agent skills for blockchain network operations.
They are maintained by POSTHUMAN, but the skills are intended to be usable by
any validator operator with their own inventory and runbooks.

Each network directory is a self-contained skill that helps an AI agent perform
safe validator operations: monitoring, upgrade preparation, incident triage,
recovery checks, and operator-facing reports.

## Skills

- [Shentu](shentu/SKILL.md) — Shentu Chain validator operations for
  `shentu-2.2`.

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
