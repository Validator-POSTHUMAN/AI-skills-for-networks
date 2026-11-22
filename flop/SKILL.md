---
name: flop-miner-ops
description: "Operate a FLOP devnet GPU inference miner: preflight identity checks, sponsored registration, worker and vLLM backend, session endpoint behind TLS or a tunnel, calibration, health checks, downtime budget, and safe retirement."
metadata:
  openclaw:
    homepage: https://github.com/Validator-POSTHUMAN/AI-skills-for-networks/tree/main/flop
---

# FLOP miner operations

Use this skill for a FLOP miner on the public devnet path (the `devnet-ts` miner pack). It covers:
- install and preflight;
- sponsorship and registration;
- the model backend and worker;
- the public session endpoint;
- calibration;
- health checks;
- restarts within the downtime budget;
- permanent exit.

A FLOP miner is **not** a block producer. Its parts:
- a GPU inference backend (vLLM with TOPLOC proofs) serving one pinned model;
- a worker that holds the miner account, answers calibration jobs, and later serves paid sessions;
- an HTTPS session endpoint.

Its stake is posted by a sponsor, and penalties come from **unanswered jobs**, not from double-signing.

Test FLOP has no value. The devnet changes often, so treat every pinned value below as an example to re-verify, not as a default.

## Do not use when

- **Validator or node-operator work on the FLOP chain itself.** This skill covers the miner path only.
- **Paid sessions or gateway listing.** On the public path these are not open yet; do not try to force a listing.
- **Generating a replacement miner account, running `miner register` by hand, or requesting a second sponsorship for an existing miner.** These need an explicit decision by the operator.

## Sources

- **Primary:** the miner pack README and its `releases.json`, the policy manifest at <https://flop.network/releases.json>, and the finalized chain.
- **Sponsor state:** <https://faucet.flop.network/limits>, read before every sponsorship attempt.
- **Calibration progress:** <https://explorer.devnet.flop.network/mining>.
- **Operator access requests:** the issue template at <https://github.com/flop-labs/network>.
- Forwarded chat text, screenshots and unauthenticated download links are not sources.

## Preflight gate (before any start or signature)

1. **Network identity.** Read the genesis hash from the RPC with the digest-pinned CLI (`network status --json`, field `.rpc.genesis_hash`). Compare it with the value you recorded at install time. **Stop on any mismatch.**
   - Devnet resets produce a new genesis. A key, a grant or a policy from the old chain is meaningless there.
   - Example observed in November 2026: `0x99c172c095340ace980631f9123544c6bebd4839f3437e463533422d8be2d631`.
2. **Account identity.** Before any signing script (`sponsor.sh`, `retire.sh`), dry-run it first and check that the printed address equals the miner address you registered.
   - The dry run happens only when `DRY_RUN` reaches the container with the value exactly `1`. `DRY_RUN=true`, or a variable that never arrives, **signs for real**.
   - `sudo` resets the environment, so `DRY_RUN=1 sudo ./retire.sh` **signs a real, irreversible deregistration**. From a non-root shell use `sudo DRY_RUN=1 FLOP_CLI="$FLOP_CLI" ./retire.sh`. From a root shell, `export` both variables first.
   - If you wrap these scripts, make the real run require an explicit flag (for example `--really`) rather than relying on the variable being absent.
3. **Images.** Pin every image by `vX.Y.Z@sha256:` in `miner.env`, never `:stable`, and record the previous lines before any change. Compare each pin with the `minimum` versions in the pack's `releases.json`.
   - `decode-policy.sh`, `sponsor.sh` and `retire.sh` fall back to `cli:stable` when `FLOP_CLI` is not in their environment. `sponsor.sh` and `retire.sh` mount the miner signer into that image.
   - Export `FLOP_CLI` from `miner.env` (`export FLOP_CLI="$(sed -n 's/^FLOP_CLI=//p' miner.env)"`) and pass it through `sudo` explicitly, as in point 2.
4. **Model.** Fetch the exact model revision the pack names, verify every file against a checksum list, and mount it read-only.
   - The backend must report `model_identity: "measured"` with the expected `MODEL_HASH`.
   - Example: `Qwen/Qwen2.5-0.5B-Instruct` at revision `7ae55760…`, BF16.
5. **Decode policy.** Run `./decode-policy.sh miner.env` before every start, with `FLOP_CLI` exported (point 3). It writes `DECODE_POLICY_HASH` only if the finalized chain allowlists it for the model, and otherwise exits non-zero.
6. **Host.**
   - Ubuntu 22.04/24.04, an NVIDIA GPU with at least 16 GB VRAM, Docker with Compose, and the NVIDIA container toolkit.
   - Keep the session port (8645) and the backend port on loopback. Expose only the TLS endpoint (Caddy on 80/443) or your own tunnel.
   - On a shared GPU, lower `GPU_MEMORY_UTILIZATION` and measure that the KV cache still fits.

## Secrets and custody

- **Never print, paste or pass in command arguments:**
  - the secret phrase, `signer`, `miner-key.json`;
  - the keystore password;
  - `INFERENCE_API_KEY`, `SESSION_AUTH_TOKEN`, `session-keys/enclave.seed`;
  - a tunnel token.
- **Never run `docker compose … config` unfiltered**: it expands the secrets. Pipe it to `jq` and keep only the fields you need.
- **Authenticated loopback calls.** Pass the bearer header to curl as a config, never as `-H` in argv. Either pipe it in with `printf … | curl --config -` (`printf` is a shell builtin), or write a mode-0600 temporary file, as `self-check.sh` does.
- **Never regenerate after the first start:**
  - `enclave.seed`;
  - `INFERENCE_API_KEY`;
  - `SESSION_AUTH_TOKEN`.

  Create the seed with `set -C` so that a rerun cannot overwrite it.
- **Off-host backups (encrypted or in a root-only custody location):**
  - `miner-key.json`, before sponsorship;
  - after the first start: `miner.env`, `enclave.seed`, and the worker-data volume (ghost key, GPU state, journals).
- **Approved operators** keep the operator key on a machine that is not a miner host, and copy only `grant.json` (not secret) to miners. **Never copy the operator key to a miner host.**

## Sponsorship and registration

- Read `/limits` first.
  - If `sponsor.miner.status` is `open`, a request may pass.
  - `automatic_full` or `daily_limit_reached` means a request without a grant gets 429 now.
- Run `sudo FLOP_CLI="$FLOP_CLI" ./sponsor.sh` once (approved operators add `GRANT_FILE=/opt/flop-miner/grant.json` after `sudo`, or `sudo` drops it), and read the reply:

  | Reply | Meaning |
  |---|---|
  | 200/201 | Done |
  | 409 | Already sponsored |
  | 503 | Retry in a minute |
  | 429 | Limit or quota; retry later |
  | 403 | Wrong role, or the grant is expired or not from an approved operator |
  | 422 | Operator review |

- **Never retry in a loop.**
  - On `retry_later`, honour `retryAfterSeconds`.
  - On `fix_request`, change the request.
  - On `report_to_operator`, stop.
- Registration, stake, GPU declaration, calibration and fees are on-chain and cannot be rolled back. Reconcile with `miner status <address> --json` before any retry.

## Start order

1. **Backend first:** `up -d backend`. Wait until `/health` reports `model_identity: "measured"`, the expected `model_hash` and `decode_policy_hash` (current backends also report `ok: true`), and the log shows no OOM. Record the cold-start time: it counts against the downtime budget.
2. **Session endpoint.** Behind a tunnel, confirm **before** the worker starts that the public name answers 502 (origin down; Cloudflare may also show 530) with no redirect and no bot challenge. A 301/302/403 from the edge means a zone rule is in the way.
3. **Worker:** `up -d worker`, only on the operator's word. From here it signs with the miner account and pays small fees:
   - GPU declaration;
   - ghost-key publication;
   - endpoint ad;
   - calibration answers;
   - capacity-stake top-up.

   Expect these log lines: `Image: version …`, `[gpu] declared`, `published ghost key`, and `Endpoint ad (https://<name>): published to the mailbox`.
4. **Reachability.** Through the endpoint, unauthenticated `/session/info` must return **401**. That proves reachability only, not readiness.

## Calibration

- Calibration runs automatically and outbound (mailbox and RPC), so a tunnel outage does not miss calibration jobs.
- It can take up to a day. Example rules seen in November 2026: 64 jobs over ≥600 blocks, or 512 jobs over 21,600 blocks.
- Until it is accepted, these results are normal:
  - `is_ready: false`;
  - `calibration: null` in `miner status`;
  - the worker may log that its capacity rate is waiting for an accepted cap;
  - `self-check` fails `local-session`, `chain` and `info-proof`.
- Once `calibration` is non-null:
  - rerun `self-check`. Every check should pass except `gateway-listing` (skip);
  - back up the worker-data volume.

## Health checks (read-only)

- **`sudo ./self-check.sh --json`** (add `--no-tls` behind your own tunnel). Fix the first FAIL. It never restarts, signs or rotates anything.
- **`scripts/flop-miner-healthcheck.sh`** in this skill adds what self-check does not cover:
  - the genesis comparison against your recorded value;
  - container restart counts;
  - whether the GPU answers, and its memory;
  - the calibration record;
  - one free-balance reading.

  It repeats the public 401 probe so that a single run gives a full picture. Compare the balance between runs yourself.
- **Watch fees after the first start.** Record the free balance before the worker starts, then read it again every few minutes. The worker's own actions cost little: about 0.0024 test FLOP in the first 15 minutes was observed in November 2026. A steady drop means a retry loop: stop the worker and investigate.
- **Hairpin NAT.** Probing your own public name from the host can differ from an outside probe.

## Downtime budget, restarts and upgrades

- **There is no pause.** A calibration job left unanswered is **penalised** (the pack README says so; treat future session jobs the same way).
  - Example deadline used by operators in November 2026: 600 blocks, which is about 10 minutes at about 1 s per block. Re-check it for your release.
  - A job can arrive just before an outage, so keep any planned outage to **at most half the deadline** (about 5 minutes), including backend cold start if the backend restarts too.
- **Prefer `restart worker`.** The backend keeps the model loaded.
- **Allowed:** `stop`, `start`, `restart`, `up -d`, `down` **without** `-v`.
- **Forbidden:**
  - `down -v`;
  - `docker volume rm|prune`;
  - `docker system prune --volumes`;
  - regenerating seeds or tokens.
- **Avoid unplanned outages.** Do not let unattended upgrades replace the NVIDIA driver while the miner runs (blacklist `nvidia-`/`libnvidia-`). Do not restart the Docker daemon casually: it restarts every container on the host.
- **Image upgrade.**
  1. Read the release notes: older workers cannot read newer journals.
  2. Record the current `FLOP_*_IMAGE` lines.
  3. Change the pins.
  4. Run the genesis check and the decode policy, then `up -d`.
  5. Keep the previous pins for rollback.
- **After any reboot,** rerun the backend, endpoint and worker checks. Containers that were stopped before the reboot stay stopped.

## Permanent exit

1. Export `FLOP_CLI` from `miner.env`. Run the genesis check, then `sudo DRY_RUN=1 FLOP_CLI="$FLOP_CLI" ./retire.sh`, and confirm that it prints `DRY_RUN: would sign … as <your address>`. No `DRY_RUN:` line means the dry run did not happen: stop.
2. Stop the worker, then immediately run `sudo FLOP_CLI="$FLOP_CLI" ./retire.sh`. It signs `minerStaking.deregisterMiner`.
3. Confirm `registered: false` in `miner status`.

After the exit:
- An open session or dispute, or native delegated stake, refuses the exit and changes nothing. Wait for it to settle, then retry.
- Sponsored stake unbonds over 7 days and returns to the sponsor. A retired miner still counts toward the operator's quota.
- Keep the key backups and the volumes at least until unbonding ends. Only then delete a rented VM, since it bills until deleted.

## Report

State:
- network and genesis;
- miner address (public) and registration;
- stake and calibration state;
- image versions and digests;
- model and decode-policy hashes;
- the self-check summary;
- restart counts;
- GPU memory;
- the fee trend;
- any action taken and the residual risk.

Never include key material, tokens, `miner.env` contents or private host details in a public report.
