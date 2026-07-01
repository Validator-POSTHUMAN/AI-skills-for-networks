---
name: fastlane-sidecar-ops
description: "Install, verify, monitor, upgrade, and troubleshoot the FastLane MEV sidecar for Monad validators, including shMonad onboarding order, beneficiary/coinbase prerequisites, rootless Docker isolation, mempool IPC wiring, release signature/provenance verification, health checks, rollback, and concise operator reports."
---

# FastLane Sidecar Ops

Use this skill when working on FastLane / shMonad MEV sidecar operations for
Monad validators: onboarding preparation, installation, service wiring,
rootless container setup, release verification, health checks, monitoring,
upgrades, rollback, and incident triage.

## Source Priority

1. Current target-host state: services, config, process flags, socket paths,
   container state, sidecar health endpoint, logs, and metrics.
2. Operator inventory and local runbooks.
3. Official FastLane / shMonad docs:
   - https://docs.shmonad.xyz/validators/onboarding
   - https://docs.shmonad.xyz/validators/onboarding/validator-setup
   - https://docs.shmonad.xyz/validators/onboarding/install-sidecar-rootless-docker
   - https://docs.shmonad.xyz/stake-allocation
   - https://github.com/FastLane-Labs/fastlane-sidecar
4. Public dashboards and explorers only as secondary confirmation.

Refresh official docs before production install or upgrade. Do not treat this
skill as a replacement for current FastLane onboarding instructions.

## Required Inputs

Before changing a validator, identify:

- Network: mainnet or testnet.
- Host / SSH target and whether commands run locally or over SSH.
- Monad node user and paths.
- Service names for BFT, execution, RPC, and optional OTel.
- Current full ExecStart for monad-bft and monad-rpc.
- Current BFT version; FastLane docs state sidecar requires monad-bft v0.12.6
  or newer.
- shMonad onboarding status, including whether a validator-specific coinbase
  contract has been deployed.
- Beneficiary / coinbase target and FastLane fullnode pubkeys received from
  the team, if the task includes those steps.
- Sidecar version to install or upgrade to.
- CPU set/resource policy, metrics bind policy, and monitoring destination.

When a structured inventory is useful, read references/inventory.schema.json.
Use examples/inventory.example.json only as fake-value structure.

## Safety Rules

- Do not publish secrets, keystore passwords, private keys, OTel credentials,
  webhook URLs, private hosts, or production inventory.
- Do not change beneficiary / coinbase address without explicit operator
  confirmation and a config backup.
- Do not install the sidecar before the validator has completed the required
  shMonad onboarding steps. Official order: onboarding / coinbase contract,
  beneficiary update, FastLane fullnodes, then sidecar.
- Use systemctl edit drop-ins for Monad service flag changes. Do not edit
  installed unit files directly.
- In a Service drop-in, ExecStart= replaces the whole command. Preserve every
  original flag and change only the intended IPC path.
- Keep the FastLane sidecar isolated under a dedicated fastlane user.
- Expose sidecar metrics on loopback by default, for example
  127.0.0.1:8765; do not open it publicly unless explicitly requested.
- Pin container images by digest and verify the release before running:
  GPG manifest, cosign image signature, and SLSA provenance/attestation.
- Stop if local BFT/RPC service wiring, socket ACLs, or sidecar health checks
  disagree. Report the exact failing evidence.

## Install Workflow

1. Read current official FastLane docs and operator inventory.
2. Capture pre-state:

~~~bash
systemctl is-active monad-bft monad-execution monad-rpc || true
systemctl cat monad-bft
systemctl cat monad-rpc
ps -eo pid,user,args | grep -E 'monad-node|monad-rpc|fastlane-sidecar' | grep -v grep || true
curl -fsS http://127.0.0.1:8080/ -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}'
curl -fsS http://127.0.0.1:8080/ -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"eth_syncing","params":[]}'
~~~

3. Back up current service definitions and relevant config into a timestamped
   backup directory. Do not back up secrets into public docs.
4. Confirm BFT version is new enough and Monad node is synced.
5. If requested by onboarding, update node.toml beneficiary to the
   validator-specific coinbase contract, then restart only what the official
   docs require and verify the node is healthy.
6. Add FastLane dedicated fullnode identities received from FastLane. If docs
   allow live reload, prefer reload over restart and verify it succeeded.
7. Create the fastlane user and rootless Docker environment.
8. Create segregated IPC directory, for example /var/run/monad-ipc, and ACLs
   that let fastlane access only the mempool socket.
9. Add systemd drop-ins:
   - monad-bft: preserve original command; set --mempool-ipc-path
     /var/run/monad-ipc/mempool.sock; recreate IPC dir and ACLs at service
     start; use a UMask that preserves ACL write access.
   - monad-rpc: preserve original command; set --ipc-path
     /var/run/monad-ipc/mempool.sock.
10. Run systemctl daemon-reload, then restart Monad services according to the
    current official docs/local runbook.
11. As fastlane, create compose config for
    ghcr.io/fastlane-labs/fastlane-sidecar:VERSION@DIGEST, read-only
    container, cap_drop ALL, no-new-privileges, resource limits,
    /var/run/monad-ipc mount, and loopback metrics.
12. Verify release and image:
    - import FastLane release public key;
    - verify release manifest GPG signature;
    - extract digest from the signed manifest;
    - verify image with cosign;
    - verify provenance with gh attestation verify or cosign attestation.
13. Pull and run the container.
14. Verify health, logs, and metrics.

## Health Check

Use the bundled helper when possible:

~~~bash
scripts/fastlane-sidecar-healthcheck.sh --local
scripts/fastlane-sidecar-healthcheck.sh --host user@example
scripts/fastlane-sidecar-healthcheck.sh --local --health-url http://127.0.0.1:8765/health
~~~

Manual checks:

~~~bash
systemctl is-active monad-bft monad-execution monad-rpc || true
sudo -iu fastlane env DOCKER_HOST=unix:///run/user/$(id -u fastlane)/docker.sock \
  docker ps --filter name=fastlane-sidecar
curl -fsS http://127.0.0.1:8765/health
curl -fsS http://127.0.0.1:8765/metrics | head
journalctl -u monad-bft -n 100 --no-pager
~~~

Healthy baseline:

- Monad BFT, execution, and RPC services active.
- BFT and RPC process flags point to the same segregated mempool socket.
- /var/run/monad-ipc/mempool.sock exists and is accessible to fastlane.
- fastlane-sidecar container is running from a digest-pinned image.
- /health returns recent last_received_at.
- tx_received is nonzero after the validator has had time to receive
  transactions. It can remain 0 briefly before the validator approaches leader
  duty.
- Metrics endpoint is reachable locally.
- Logs do not show repeated socket connection failures or tx decode loops.

## Upgrade Workflow

1. Read current FastLane release notes and official upgrade instructions.
2. Capture current image digest, health output, compose file, and .env.
3. As fastlane, download the new signed release manifest and signature.
4. Verify GPG signature, cosign image signature, and provenance.
5. Update only SIDECAR_VERSION and SIDECAR_DIGEST in /home/fastlane/.env.
6. Pull and restart the compose service.
7. Verify container image digest, /health, /metrics, and logs.
8. If health fails, roll back to the previous digest and report evidence.

## Rollback

Rollback should be deliberate:

- Container-only rollback: restore previous SIDECAR_VERSION and
  SIDECAR_DIGEST, pull, and docker compose up -d.
- Sidecar disable: docker compose down as fastlane; keep Monad services
  healthy and leave IPC wiring untouched unless reverting it is requested.
- Full wiring rollback: restore backed-up monad-bft and monad-rpc
  drop-ins/config, systemctl daemon-reload, restart affected Monad services,
  and verify local RPC health.
- Beneficiary rollback affects revenue routing. Do it only with explicit
  operator confirmation and after checking shMonad/FastLane implications.

## Reporting

Operator report should include:

- Network, host label, and sidecar version/digest.
- What changed: beneficiary, fullnode identities, IPC path, service drop-ins,
  container image, monitoring.
- Verification: service states, RPC health, sidecar /health, metrics, and
  relevant log lines.
- Any warnings: tx_received=0, stale timestamp, socket permissions, image
  verification skipped/failed, or missing monitoring.
- Rollback path used or available.
