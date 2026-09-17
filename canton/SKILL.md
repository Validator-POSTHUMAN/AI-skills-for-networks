---
name: canton-validator-ops
description: "Operate a Canton Network validator on MainNet, TestNet or DevNet: Splice stack health, sync lag and reward triggers, scan API access, identities and database backups, disaster recovery and re-onboarding, upgrades and migration IDs, security hardening, and incident triage."
---

# Canton Validator Operations

Use this skill for any work on a Canton Network validator: health verification,
sync and reward diagnosis, backups, disaster recovery, upgrades, security
review, and incident triage — on MainNet, TestNet or DevNet.

A Canton validator runs the **Splice** stack: a validator app and a Canton
participant, backed by PostgreSQL, fronted by nginx, with wallet and ANS web
UIs. It is not a Cosmos SDK chain and not an EVM node.

This skill is operator-neutral and provider-neutral. It must not assume a
specific validator, party, host, sponsor, domain or hosting stack. Keep real
hosts, party IDs, endpoints, credentials and key locations in the operator's
own inventory, never in this repository.

## Source priority

1. Live state: container health, `/metrics` on port 10013, the validator
   admin API, and the network `/info` endpoint.
2. The operator's inventory: hosts, Compose paths, party hints, sponsor and
   scan URLs, backup destinations, rollback copies.
3. Official docs:
   - <https://docs.sync.global/>
   - <https://docs.sync.global/validator_operator/validator_backups.html>
   - <https://docs.sync.global/validator_operator/validator_disaster_recovery.html>
   - <https://docs.sync.global/validator_operator/validator_security.html>
   - <https://github.com/digital-asset/decentralized-canton-sync>

Never call a validator healthy from `docker ps` alone. Running is not earning.

## Canton rules that change operational decisions

- **No slashing, no jail, no unbonding, no delegation, no commission.** Do not
  carry any Cosmos risk reflex into this network.
- **The risk is key loss, not double-signing.** The participant namespace key
  proves ownership of the party, the Canton Coin balance and the CNS entries.
  It cannot be rotated and cannot be reconstructed from the network.
- **Liveness is a trigger, not a block.** There is no missed-block counter. A
  validator earns because `ReceiveFaucetCouponTrigger` completes; a stalled
  trigger earns nothing while every other signal stays green.
- **A database backup expires in 30 days.** Sequencer pruning means a
  participant restored from anything older can never catch up.
- **Backup order is strict.** The validator app database must be dumped at a
  point strictly earlier than the participant database.
- **No inbound ports are required.** Splice states validators have no external
  ingress requirements; only egress on 443 to the Super Validators.
- **MainNet and TestNet scan are IP-restricted.** Every Super Validator mirror
  answers `403 RBAC: access denied` from a non-onboarded address. DevNet scan
  is public.
- **KMS is a one-time decision.** External key storage is Kubernetes-only and
  cannot be migrated onto an existing participant; switching means a fresh
  validator and an asset transfer.
- **Never downgrade.** A participant that migrated its schema forward cannot be
  rolled back; the rollback path is a backup.

## Step 1 — Load the target

Establish from the operator's inventory, not from memory: network, host,
Compose project working directory, Compose project name, party hint, party ID,
sponsor SV URL, scan URL, backup destination, and whether auth is disabled.
Stop and ask if the target is ambiguous.

Read the running Compose directory from the container rather than trusting a
path or a `current` symlink:

```bash
docker inspect <validator-container> \
  --format '{{index .Config.Labels "com.docker.compose.project.working_dir"}}'
```

A stale `~/.canton/current` symlink pointing at an older version than the one
actually running is a known trap. The running image is the only version truth:

```bash
docker inspect <validator-container> --format '{{.Config.Image}}'
```

## Step 2 — Verify the four layers

Check all four. Each hides a failure the others cannot see.

**Containers.** Every Splice container up and `healthy`, restart counts stable.

```bash
docker ps --format '{{.Names}}\t{{.Status}}' | grep splice
```

`Up 7 weeks (unhealthy)` is a real finding and reads as normal at a glance.
Note that `postgres-splice`, `wallet-web-ui` and `ans-web-ui` ship with restart
policy `no` in some bundles: after a host reboot they stay exited and the
participant loops until they are started explicitly.

**Sync.** Derive lag from the store metric; it is not exported directly.

```promql
time() * 1000 - splice_store_last_seen_record_time_ms
```

Under 30 s normal, over 60 s warning, over 120 s the participant is falling
behind the synchronizer. `daml_health_status{job="canton-participant"}` must be
`1`.

**Automation.** The Canton substitute for missed blocks. Splice exports the
health of every background service as a gauge where **0 means healthy**; on a
healthy validator all 29 series read `0`, and a non-zero series names the
broken automation in its `service` label.

```promql
splice_automation_background_service_health != 0
```

Then check the reward trigger, treating iterations and completions as two
different facts:

```promql
increase(splice_trigger_iterations_total{trigger_name="ReceiveFaucetCouponTrigger"}[1h]) == 0
```

`splice_trigger_completed_total` for that trigger **does not exist until the
first completion** — it is absent on healthy POSTHUMAN MainNet and TestNet
validators while iterations climb normally. An alert written as
`rate(splice_trigger_completed_total{...}[1h]) == 0` never fires, because
PromQL returns no data for a missing series rather than zero. Alert on
iterations and automation health, and use `absent()` if you need to assert the
completion series exists. Cross-check
`splice_wallet_unlocked_amulet_balance` — a flat balance confirms a stall.

**Network position.** Compare the running version against the network:

```bash
curl -s https://docs.global.canton.network.sync.global/info       # mainnet
curl -s https://docs.test.global.canton.network.sync.global/info  # testnet
curl -s https://docs.dev.global.canton.network.sync.global/info   # devnet
```

The response carries `sv.version` and `sv.migration_id`. A node more than one
release behind, or on an old migration ID, is drifting off the network. This
endpoint is public and keyless from anywhere — unlike scan.

Completion criterion: all four layers pass, or the failing layer is named with
its evidence.

## Step 3 — Read the metrics that matter

Every Splice node exposes Prometheus metrics on port **10013** at `/metrics`,
enabled by default under Docker Compose. Both the validator app and the
participant publish. Confirm names against the live endpoint before writing an
alert rule. The validator image ships **wget, not curl**; a `curl` exec fails
with `executable file not found in $PATH` and an empty body, which reads
exactly like a dead metrics port:

```bash
docker exec <validator-container> \
  wget -q -O - --timeout=10 http://localhost:10013/metrics | head -20
```

Values are exported in scientific notation (`1.789684504197E12`); shell
integer arithmetic cannot parse them, so derive lag with `awk` or PromQL.

Scrape `validator:10013` and `participant:10013` **directly**. The bundled
nginx routes by `Host` header and Prometheus cannot set one per target, so a
scrape through nginx returns 404.

| Metric | Use |
| --- | --- |
| `up{job="canton-validator"}` | validator app reachable |
| `daml_health_status{job="canton-participant"}` | participant self-reported health |
| `splice_automation_background_service_health` | per-service automation health, `0` = healthy |
| `splice_store_last_seen_record_time_ms` | sync lag input |
| `splice_trigger_iterations_total{trigger_name="ReceiveFaucetCouponTrigger"}` | reward polling loop alive |
| `splice_trigger_completed_total{trigger_name=...}` | work actually done; series absent until first completion |
| `splice_wallet_unlocked_amulet_balance` | CC balance |
| `splice_retries_failures` | retry failures by `operation` and `error_kind`; low tens on a healthy node, six figures on a broken one |
| `splice_validator_scan_bft_calls_total` | BFT scan reads; failures mean the node cannot read the network |
| `daml_sequencer_client_submissions_dropped_total` | submissions lost to overload or timeout |

The 47 Grafana dashboards in the Splice bundle do not work under Docker
Compose: every query filters on a Kubernetes-only `namespace` label and every
panel renders empty. Use a dashboard built on `job` and `instance`.

## Step 4 — Scan API and the validator set

Scan is the Super Validators' read API and the source of truth for the
validator set and DSO configuration.

```bash
curl -s "$SCAN/api/scan/version"
curl -s "$SCAN/api/scan/v0/dso"
curl -s "$SCAN/api/scan/v0/scans"
curl -s "$SCAN/api/scan/v0/admin/validator/licenses?page_size=1000"
```

`validator/licenses` is the validator list: each entry carries the validator
party, the sponsoring SV, `lastActiveAt`, and metadata with the node `version`
and a `contactPoint`. `dso` carries the Super Validators with their reward
weights and the current mining round.

Access differs by network and this is the most common false alarm:

| Network | Scan reachable from |
| --- | --- |
| DevNet | anywhere |
| TestNet | onboarded validator IPs only |
| MainNet | onboarded validator IPs only |

A `403 RBAC: access denied` from a workstation is expected, not an outage.
Re-run the same call from the validator host before reporting anything. On
MainNet and TestNet, `/api/scan/v0/scans` plus a `version` call to each listed
SV is also the IP-whitelist test: all responding means the address is
whitelisted.

## Step 5 — Backups before anything destructive

Two backups, both required. Verify they exist and are current **before** any
upgrade, restore, migration or host change.

**Identities.** Contains the participant private keys. Off-host, in a secret
manager, never beside the database dumps.

```bash
TOKEN=$(python3 get-token.py administrator)   # auth-disabled Compose deployments
curl --fail -sS "http://localhost:5003/api/validator/v0/admin/participant/identities" \
  -H "authorization: Bearer ${TOKEN}" -o identities-$(date -u +%Y%m%dT%H%M%SZ).json
jq -e '.id and (.keys | length > 0)' identities-*.json
```

An unverified dump is the classic silent failure: an error body is still a
file. Never print the contents, never pass the token as a visible argument,
keep the file mode `0600`.

**Databases.** Every 4 hours, validator app strictly before participant:

```bash
docker exec <postgres-container> pg_dump -U cnadmin validator > validator-<utc>.dump
active_participant_db=$(docker exec <participant-container> bash -c 'echo $CANTON_PARTICIPANT_POSTGRES_DB')
docker exec <postgres-container> pg_dump -U cnadmin "$active_participant_db" > "$active_participant_db"-<utc>.dump
```

Read the participant database name from the container; it carries the migration
ID and changes on a hard migration.

Alert on the **upload** step, not only the dump step. A broken SSH key at the
backup destination produces successful local dumps and no off-host copy, and
will abort a guarded auto-upgrade behind it.

## Step 6 — Recovery paths

Asset recovery is possible only with a database backup under 30 days old, an
up-to-date identities backup, or a KMS that still holds the keys. Confirm which
one exists before choosing a path, and say so in the report.

**Restore from database backup** — single node broken, network healthy, backup
under 30 days, no logical synchronizer upgrade since it was taken. Stop, drop
the postgres volume, start postgres alone, restore validator then
`participant-<migration_id>`, stop postgres, start normally. Users onboarded
after the backup must be re-onboarded by hand.

**Re-onboard from identities backup** — database gone, too old or
untrustworthy:

```bash
./start.sh -s "<SPONSOR_SV_URL>" -o "" -p "<ORIGINAL_PARTY_HINT>" \
  -m "<MIGRATION_ID>" -i "<identities-dump.json>" -P "<new-participant-id>" -w
```

Keep the original party hint, pass `-o ""`, and use a `-P` identifier never
used before — then pass the same `-P` on every later restart. An error asking
for a new onboarding secret means the configuration is wrong; fix the
configuration rather than requesting a secret from the sponsor.

**Logical synchronizer upgrade** — the SVs roll forward to a new physical
synchronizer and publish the parameters. Follow their announcement; the
operator-side preparation is retaining backups across the upgrade.

## Step 7 — Gated changes

Ask the operator before: exporting, moving or restoring identities; any
transaction or Canton Coin transfer; dropping a database volume or deleting
node data; re-onboarding; changing the party hint or participant ID; changing
the sponsor or scan endpoint; opening a port or changing the firewall; enabling
unsafe auth mode; and any upgrade that crosses a migration ID.

For every permitted change:

1. Write a timestamped rollback copy of the file in place before editing.
2. Confirm a current identities backup and database backup exist off-host.
3. Pre-pull images while the old node still runs, then stop and start — this
   is seconds of downtime instead of minutes.
4. Change one component at a time and recreate only the affected container.
5. Re-verify with Step 2, then record what changed.

Never print `.env` in full, never paste an onboarding secret, alert token or
database password into chat, logs or a command line. Keep `.env`,
`toolkit.conf` and `.htpasswd` at mode `0600`.

## Step 8 — Port exposure

Public: nothing. A Canton validator needs no inbound port beyond the
operator's own SSH.

Never public: the wallet and ANS UIs on `127.0.0.1:8888`, the validator admin
API on `5003`, the ledger API on `7575`, PostgreSQL, and the metrics ports on
`10013`.

Verify from outside the host, not with a local port scan. `docker run -p`
writes to the `DOCKER-USER` chain and bypasses ufw, so a published port is
reachable from the internet even with ufw set to deny.

```bash
ss -tlnp | grep -v '127.0.0.1'
docker ps --format '{{.Names}}\t{{.Ports}}'
```

Every non-loopback listener needs a justification.

## Step 9 — Triage table

| Symptom | Check first |
| --- | --- |
| Container up, node earning nothing | `ReceiveFaucetCouponTrigger` rate — sync can be perfect while rewards are dead |
| Sync lag climbing | participant health, database load, disk I/O, then sequencer client delay |
| Participant restart loop after host reboot | `postgres-splice` and the web UIs have restart policy `no`; start them, wait for healthy, then restart the validator once |
| Participant exits on permission errors | Postgres volume ownership and the image's non-root UID; compare the volume owner against the container user |
| `403 RBAC: access denied` from scan | running from a non-whitelisted IP; retry from the validator host |
| `401 API key required` from lighthouse | that API now needs a key; use the `/info` endpoint instead |
| Wallet UI `401` | nginx virtual host; reach it as `wallet.localhost`, not by IP |
| Wallet UI ZodError on config | missing `AUTH_URL` / `SPLICE_APP_UI_NETWORK_FAVICON_URL` under disabled auth |
| Backup alert with healthy node | backup destination SSH key or object-store credentials, not the dump |
| Version far behind the network | DevNet and TestNet reset; a node left on an old migration ID must be rebuilt, not upgraded |
| Published port reachable despite ufw | Docker `DOCKER-USER` chain bypasses ufw; fix the bind address |

## Step 10 — Report

State what was checked, what was found, what was changed, what remains, and
which facts are unverified. Include exact numbers with their timestamp, and
name the source for each — container inspect, metrics, scan API, `/info`, or
docs. Do not claim a fix succeeded without post-change output that shows it.
Do not call an upgrade complete without post-upgrade health, sync and reward
verification.

## Helper

`scripts/canton-healthcheck.sh` runs the read-only parts of Steps 2 and 4
against a local or remote host. It never writes, never submits a transaction,
never restarts a container, and never reads secret material.
