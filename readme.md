# AI Skills for Networks

This repository contains AI-agent skills for blockchain networks validated by
POSTHUMAN.

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
