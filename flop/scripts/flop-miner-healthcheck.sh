#!/usr/bin/env bash
# Read-only FLOP miner health check, a companion to the pack's own self-check.sh.
#
# It never starts, stops, restarts, signs or rotates anything, and prints no
# credential. miner.env is never sourced: single non-secret values are read
# with sed, and the session token is never read on the host (the readiness
# probe reads it inside the worker container and never prints it).
#
# What it adds to self-check.sh:
#   - network identity: the RPC genesis against the value you recorded;
#   - container state and restart counts (a restart loop answers no jobs);
#   - whether the GPU answers, and its memory in use;
#   - the miner's registration, calibration record and one free-balance
#     reading, through the digest-pinned CLI (compare balances between runs);
#   - the worker's own readiness and signer-fence state, read inside the
#     worker container (the bearer token never leaves it);
#   - IPv6-first DNS on an IPv4-only host, which drops the RPC WebSocket.
# It also repeats self-check's unauthenticated edge probe (expect 401), so one
# run gives the whole picture.
#
# Usage (as root, because miner.env and the Docker socket are root-only):
#   sudo flop-miner-healthcheck.sh --address <miner ss58> --genesis <0x…> [--dir /opt/flop-miner] [--json]
# Exit: 0 ok (warnings possible), 1 a check failed, 2 usage or precondition error, 3 genesis not confirmed.
set -euo pipefail

DIR=/opt/flop-miner
ADDRESS=""
GENESIS=""
JSON=0

usage() { sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --dir) DIR="${2:-}"; shift 2 || usage ;;
    --address) ADDRESS="${2:-}"; shift 2 || usage ;;
    --genesis) GENESIS="${2:-}"; shift 2 || usage ;;
    --json) JSON=1; shift ;;
    -h|--help) usage ;;
    *) echo "unknown option: $1" >&2; usage ;;
  esac
done
[ -n "$ADDRESS" ] && [ -n "$GENESIS" ] && [ -n "$DIR" ] || usage
DIR="${DIR%/}"
[ "$(id -u)" = 0 ] || { echo "run as root" >&2; exit 2; }
for t in docker jq curl; do command -v "$t" >/dev/null || { echo "missing $t" >&2; exit 2; }; done
[ -f "$DIR/miner.env" ] || { echo "no miner.env in $DIR" >&2; exit 2; }

envget() { sed -n "s/^$1=//p" "$DIR/miner.env" | tail -1 | sed -e "s/^'//" -e "s/'\$//"; }
CLI="$(envget FLOP_CLI)"
RPC="$(envget FLOP_RPC)"; RPC="${RPC:-wss://rpc.devnet.flop.network}"
HOST="$(envget SESSION_PUBLIC_HOST)"
NET="$(envget FLOP_NETWORK)"; NET="${NET:-devnet}"

results="$(mktemp)"; trap 'rm -f "$results"' EXIT
failed=0
genesis_unconfirmed=0
check() { # id status detail
  [ "$2" != fail ] || failed=1
  jq -nc --arg id "$1" --arg status "$2" --arg detail "$3" '{id:$id,status:$status,detail:$detail}' >> "$results"
}
# IPv4 first: on hosts without global IPv6, Node tries the RPC's AAAA record first and the
# WebSocket times out (flop-labs/network#533).
# The devnet RPC sometimes answers slower than the CLI's 10 s connect timeout, so try twice.
cli1() { timeout 90 docker run --rm --network host -e NODE_OPTIONS=--dns-result-order=ipv4first "$CLI" --network "$NET" --rpc "$RPC" "$@" </dev/null 2>/dev/null; }
cli() { local out; out="$(cli1 "$@" || true)"; [ -n "$out" ] || out="$(cli1 "$@" || true)"; printf '%s' "$out"; }

# 1. The CLI must be digest-pinned, or every chain read below is unauthenticated code.
case "$CLI" in
  *@sha256:*) check cli-pinned pass "$CLI" ;;
  *) check cli-pinned fail "FLOP_CLI is not digest-pinned: ${CLI:-empty}"; CLI="" ;;
esac

# 2. Network identity.
if [ -n "$CLI" ]; then
  # network status prints JSON even when the RPC is unreachable, so retry on an empty genesis.
  got="$(cli1 network status --json | jq -r '.rpc.genesis_hash // empty' 2>/dev/null || true)"
  [ -n "$got" ] || got="$(cli1 network status --json | jq -r '.rpc.genesis_hash // empty' 2>/dev/null || true)"
  via="$RPC"
  # Fallback: the same node over HTTPS JSON-RPC, when the WebSocket keeps timing out.
  if [ -z "$got" ]; then
    case "$RPC" in wss://*) https="https://${RPC#wss://}" ;; ws://*) https="http://${RPC#ws://}" ;; https://*|http://*) https="$RPC" ;; *) https="" ;; esac
    if [ -n "$https" ]; then
      got="$(curl -s -m 20 -H 'content-type: application/json' \
        -d '{"id":1,"jsonrpc":"2.0","method":"chain_getBlockHash","params":[0]}' "$https" | jq -r '.result // empty' 2>/dev/null || true)"
      via="$https (JSON-RPC; the WebSocket did not answer)"
    fi
  fi
  if [ "$got" = "$GENESIS" ]; then check genesis pass "$got via $via"
  elif [ -z "$got" ]; then genesis_unconfirmed=1; check genesis warn "no answer from $via: identity not confirmed, so do not start or sign until a rerun passes"
  else check genesis fail "got '$got', expected $GENESIS: STOP before any start or signature"; fi
fi

# 3. Containers: every long-running service running, restart counts reported.
ids="$(docker ps -aq --filter "label=com.docker.compose.project.working_dir=$DIR" 2>/dev/null || true)"
workers="$(docker ps -q --filter "label=com.docker.compose.project.working_dir=$DIR" --filter label=com.docker.compose.service=worker 2>/dev/null || true)"
worker="$(head -1 <<<"$workers")"
[ "$(grep -c . <<<"$workers" || true)" -le 1 ] || check workers fail "more than one running worker container for $DIR: never run two workers on one miner account"
if [ -z "$ids" ]; then
  check containers fail "no Compose containers found for $DIR"
else
  inspected="$(docker inspect -f '{{.Name}} {{.State.Status}} {{.RestartCount}} {{.HostConfig.RestartPolicy.Name}} {{.State.ExitCode}}' $ids 2>/dev/null | sed 's#^/##' || true)"
  [ -n "$inspected" ] || check containers fail "docker inspect returned nothing for $DIR"
  while read -r name status restarts policy code; do
    [ -n "$name" ] || continue
    if [ "$policy" = no ]; then
      [ "$status" = exited ] && [ "$code" = 0 ] && s=pass || s=fail
    else
      [ "$status" = running ] && s=pass || s=fail
      [ "$s" = pass ] && [ "$restarts" -gt 0 ] && s=warn
    fi
    check "container:$name" "$s" "status=$status restarts=$restarts exit=$code"
  done <<<"$inspected"
fi

# 4. GPU memory.
if command -v nvidia-smi >/dev/null; then
  if gpu="$(nvidia-smi --query-gpu=name,memory.used,memory.total,temperature.gpu --format=csv,noheader 2>&1)" && [ -n "$gpu" ]; then
    check gpu pass "$(head -1 <<<"$gpu")"
  else
    check gpu fail "nvidia-smi failed: $(head -1 <<<"$gpu")"
  fi
else
  check gpu warn "nvidia-smi not found"
fi

# 5. Public edge: an unauthenticated /session/info must be 401. 502 (or Cloudflare 530) means the origin is down;
#    301/302/403 usually means an edge rule (redirect, bot challenge) is in the way.
if [ -n "$HOST" ]; then
  code="$(curl -s -o /dev/null -w '%{http_code}' -m 15 "https://$HOST/session/info" || true)"
  case "$code" in
    401) check public-endpoint pass "https://$HOST/session/info -> 401" ;;
    *) check public-endpoint fail "https://$HOST/session/info -> ${code:-no answer} (expected 401)" ;;
  esac
else
  check public-endpoint warn "SESSION_PUBLIC_HOST is empty"
fi

# 6. Worker readiness and signer fence, asked inside the running worker container (/session/info reads the
#    chain and can take several seconds). The token is read
#    from the container's environment and never printed or passed in argv.
if [ -n "$worker" ]; then
  probe="$(timeout 120 docker exec -i "$worker" node --input-type=module 2>/dev/null <<'JS' || true
import { readFileSync } from 'node:fs';
const base = `http://127.0.0.1:${process.env.SESSION_PORT || '8645'}`;
const headers = { Authorization: `Bearer ${process.env.SESSION_AUTH_TOKEN || ''}` };
const get = async (p) => { try { const r = await fetch(base + p, { headers, signal: AbortSignal.timeout(45000) }); return r.ok ? await r.json() : { httpStatus: r.status }; } catch (e) { return { error: String(e) }; } };
const info = await get('/session/info');
const fence = await get('/internal/signer-fence');
console.log(JSON.stringify({
  isReady: info.is_ready ?? null,
  calibration: info.calibration ? { ready: info.calibration.ready, state: info.calibration.state, reason: info.calibration.reason ?? null } : null,
  infoError: info.error ?? info.httpStatus ?? null,
  fenced: fence.fenced ?? null, fencePresent: fence.fencePresent ?? null, recoverableInProcess: fence.recoverableInProcess ?? null,
  fenceSha256: fence.fenceSha256 ?? null, fenceError: fence.error ?? fence.httpStatus ?? null,
  auditEvidence: Boolean(process.env.SESSION_AUDIT_EVIDENCE_DIR && process.env.SESSION_AUDIT_EVIDENCE_KEY_FILE),
  ipv4first: /--dns-result-order=ipv4first/.test(process.env.NODE_OPTIONS || ''),
  ipv6Route: (() => { try { return readFileSync('/proc/net/ipv6_route', 'utf8').split('\n').some((l) => l.startsWith('00000000000000000000000000000000 00 ') && l.trim().split(/\s+/).pop() !== 'lo'); } catch { return null; } })(),
}));
JS
)"
  if [ -z "$probe" ] || ! jq -e 'type == "object"' <<<"$probe" >/dev/null 2>&1; then
    check worker-ready warn "could not query the worker from inside its container"
  else
    fenced="$(jq -r '.fenced' <<<"$probe")"; ready="$(jq -r '.isReady' <<<"$probe")"; calready="$(jq -r '.calibration.ready // false' <<<"$probe")"
    sha="$(jq -r '.fenceSha256 // "unknown"' <<<"$probe" | cut -c1-12)"
    if [ "$fenced" = true ]; then
      check signer-fence fail "signer fenced (fence $sha…, recoverableInProcess=$(jq -r '.recoverableInProcess' <<<"$probe")): the worker signs nothing. Follow the skill's signer-fence recovery with operator approval; do not restart or recreate the worker, or delete the fence"
    elif [ "$fenced" = false ] && [ "$(jq -r '.fencePresent' <<<"$probe")" = true ]; then
      check signer-fence warn "fenced=false but a fence file is present ($sha…): read GET /internal/signer-fence before any change"
    elif [ "$fenced" = false ]; then
      check signer-fence pass "not fenced"
    else
      check signer-fence warn "fence status unavailable: $(jq -r '.fenceError // "unknown"' <<<"$probe")"
    fi
    if [ "$(jq -r '.infoError // empty' <<<"$probe")" != "" ]; then
      check worker-ready warn "could not read /session/info: $(jq -r '.infoError' <<<"$probe")"
    elif [ "$ready" = true ]; then
      check worker-ready pass "is_ready=true, calibration $(jq -r '.calibration.state // "unknown"' <<<"$probe")"
    elif [ "$calready" != true ]; then
      check worker-ready warn "is_ready=false, calibration not ready: $(jq -r '.calibration.reason // .calibration.state // "no calibration status"' <<<"$probe")"
    elif [ "$(jq -r '.auditEvidence' <<<"$probe")" = false ]; then
      check worker-ready warn "is_ready=false with calibration active; possible cause: SESSION_AUDIT_EVIDENCE_DIR/KEY_FILE are not set, and paid sessions need them (flop-labs/network#275)"
    else
      check worker-ready warn "is_ready=false with calibration active: read the worker log"
    fi
    if [ "$(jq -r '.ipv4first' <<<"$probe")" = false ] && [ "$(jq -r '.ipv6Route' <<<"$probe")" = false ]; then
      check rpc-dns warn "the worker has no IPv6 default route and lacks NODE_OPTIONS=--dns-result-order=ipv4first: expect RPC WebSocket drops and signer fences (flop-labs/network#533)"
    fi
  fi
else
  check worker-ready warn "no running worker container found"
fi

# 7. Chain: registration, calibration record, free balance.
if [ -n "$CLI" ]; then
  st="$(cli miner status "$ADDRESS" --json || true)"
  if [ -z "$st" ]; then
    check registered warn "CLI chain read failed twice (RPC timeout, or a runtime newer than this CLI: run it by hand to see the error; for RUNTIME_INCOMPATIBLE pin the latest CLI from https://flop.network/releases.json)"
  elif [ -n "$st" ] && jq -e 'type == "object"' <<<"$st" >/dev/null 2>&1; then
    reg="$(jq -r '.registered' <<<"$st" 2>/dev/null || echo unknown)"
    [ "$reg" = true ] && check registered pass "registered=true" || check registered fail "registered=$reg"
    cal="$(jq -c '.calibration | if . == null then null elif type == "object" then {acceptedAt, verifiedJobs, capGflopsPerSec} else . end' <<<"$st" 2>/dev/null || echo null)"
    [ "$cal" != null ] && check calibration pass "$cal" || check calibration warn "no accepted calibration yet (normal for up to a day after first start)"
  else
    check registered fail "miner status gave no JSON answer"
  fi
  bal="$(cli balance "$ADDRESS" --json | jq -r '.free // empty' 2>/dev/null || true)"
  if [ -n "$bal" ]; then
    check balance pass "free=$(awk -v b="$bal" 'BEGIN{printf "%.6f", b/1e18}') (assumes 18 decimals; compare with the previous run)"
  else
    check balance warn "balance read failed"
  fi
fi

if [ "$JSON" = 1 ]; then
  jq -s --argjson failed "$failed" --argjson gu "$genesis_unconfirmed" '{ok: ($failed == 0), genesisConfirmed: ($gu == 0), warnings: ([.[] | select(.status == "warn")] | length), checks: .}' "$results"
else
  jq -r '"\(.status | ascii_upcase)\t\(.id)\t\(.detail)"' "$results"
  warns="$(jq -s '[.[] | select(.status == "warn")] | length' "$results")"
  if [ "$failed" != 0 ]; then echo "FAIL: fix the first failing check"
  elif [ "$genesis_unconfirmed" = 1 ]; then echo "INCOMPLETE: genesis not confirmed; do not start or sign"
  elif [ "$warns" != 0 ]; then echo "OK with $warns warning(s)"
  else echo "OK"; fi
fi
# Exit codes: 0 ok (warnings possible), 1 a check failed, 3 genesis not confirmed.
[ "$failed" = 0 ] && [ "$genesis_unconfirmed" = 1 ] && exit 3
exit "$failed"
