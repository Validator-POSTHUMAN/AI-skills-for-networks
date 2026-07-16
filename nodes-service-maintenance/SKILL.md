---
name: "nodes-service-maintenance"
description: "Use when changing or deploying a public blockchain node-guides service, its source data, UI, contribution content, or cache."
---

# Public node-guides service maintenance

Use for maintaining a public website that renders blockchain network metadata, guides, endpoints, contribution content, or skill tabs from repositories.

This public skill is deployment-neutral. Resolve `service_ref`, repository refs, branch policy, schema, build command, deploy target, process manager, cache behavior, and verification URLs from private knowledge and live state. Never embed operator hosts, paths, accounts, domains, or credentials.

## 1. Classify the change

Identify the owning layer before editing:

- source-data registry or network guide;
- UI/application code;
- contribution or auxiliary content;
- image/asset configuration;
- build/runtime configuration;
- deployment-only cache or process state.

Trace how the affected public page obtains its data. Search all rendered sources for stale text before assuming one repository owns it.

## 2. Preflight

1. Read the canonical service guide and repository instructions.
2. Confirm exact repositories, remotes, branches, working-tree state, deployment target, and active process.
3. Inspect existing entries and schemas; follow established naming and content patterns.
4. Pull/fetch safely and avoid stale clones, personal forks, or scratch data.
5. Check current public behavior and capture a reproducible before-state.
6. Identify whether the change alters public content, endpoints, downloads, scripts, images, or security-sensitive instructions.
7. Define build, rollback, and user-facing verification criteria.

Public content changes and deployment require explicit operator authorization. Never publish private RPCs, signer infrastructure, credentials, internal paths, or unverified commands.

## 3. Edit the canonical source

Make the smallest change in the true source of record:

- validate registry JSON/YAML and required fields;
- keep filenames and service keys consistent;
- use raw-content URLs or repository APIs according to the application's actual contract;
- verify external images are allowed and stable;
- keep public guides generic and free of private inventory;
- preserve generated sections and repository conventions;
- update all linked source repositories when content is duplicated by design.

Do not edit generated build output as the source of truth.

## 4. Review before publication

Run repository-specific formatting, schema, link, security, and build checks. Inspect the complete diff for:

- accidental secrets or private infrastructure;
- wrong network/chain identifiers;
- stale endpoints or snapshot URLs;
- executable commands copied from untrusted sources;
- unrelated changes;
- caching or branch-reference assumptions.

Use a branch and reviewed pull request for public repository changes unless the operator explicitly chooses another workflow.

## 5. Deploy

After approval and merged/available source:

1. Confirm the deploy host and application still match private knowledge.
2. Capture current commit, build/runtime state, and rollback point.
3. Pull the intended commit with a fast-forward or immutable checkout.
4. Clear only the documented framework cache when source changes require it.
5. Build using the canonical package manager and configuration.
6. Restart or reload only the intended process.
7. Do not expose environment files, tokens, or full process configuration.

If build or startup fails, preserve logs and restore the captured known-good revision when safe.

## 6. Verify the public result

Require:

- build and process health;
- stable restart count and no new fatal loop;
- homepage and changed pages return expected status;
- exact new content is present;
- exact removed/stale content is absent from the full rendered payload;
- images, downloads, tabs, endpoints, and links work;
- no template placeholders or source API objects leak into pages;
- unrelated representative pages remain healthy.

Account for CDN or raw-repository edge lag. Pin an immutable content revision only when documented and record how it will return to the normal branch.

## 7. Close

Report repositories/commits/PR, deployment revision, cache/restart action, verification URLs or redacted refs, rollback point, and unresolved propagation delay. Update private service knowledge and daily memory; keep deployment inventory out of this public package.
