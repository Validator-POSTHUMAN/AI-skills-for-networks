#!/usr/bin/env bash
# Read-only FLOP miner health check, a companion to the pack's own self-check.sh.
#
# It never starts, stops, restarts, signs or rotates anything, and prints no
# credential. miner.env is never sourced: single non-secret values are read
# with sed, and the session token is never touched.
#
# What it adds to self-check.sh:
#   - network identity: the RPC genesis against the value you recorded;
#   - container state and restart counts (a restart loop answers no jobs);
#   - whether the GPU answers, and its memory in use;
#   - the miner's registration, calibration record and one free-balance
#     reading, through the digest-pinned CLI (compare balances between runs).
# It also repeats self-check's unauthenticated edge probe (expect 401), so one
# run gives the whole picture.
#
# Usage (as root, because miner.env and the Docker socket are root-only):
#   sudo flop-miner-healthcheck.sh --address <miner ss58> --genesis <0x…> [--dir /opt/flop-miner] [--json]
set -euo pipefail

DIR=/opt/flop-miner
ADDRESS=""
GENESIS=""
JSON=0

usage() { sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
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
check() { # id status detail
  [ "$2" != fail ] || failed=1
  jq -nc --arg id "$1" --arg status "$2" --arg detail "$3" '{id:$id,status:$status,detail:$detail}' >> "$results"
}
cli() { timeout 90 docker run --rm --network host "$CLI" --network "$NET" --rpc "$RPC" "$@" </dev/null 2>/dev/null; }

# 1. The CLI must be digest-pinned, or every chain read below is unauthenticated code.
case "$CLI" in
  *@sha256:*) check cli-pinned pass "$CLI" ;;
  *) check cli-pinned fail "FLOP_CLI is not digest-pinned: ${CLI:-empty}"; CLI="" ;;
esac

# 2. Network identity.
if [ -n "$CLI" ]; then
  got="$(cli network status --json | jq -r '.rpc.genesis_hash // empty' || true)"
  if [ "$got" = "$GENESIS" ]; then check genesis pass "$got via $RPC"
  else check genesis fail "got '${got:-no answer}', expected $GENESIS: STOP before any start or signature"; fi
fi

# 3. Containers: every long-running service running, restart counts reported.
ids="$(docker ps -aq --filter "label=com.docker.compose.project.working_dir=$DIR" 2>/dev/null || true)"
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

# 6. Chain: registration, calibration record, free balance.
if [ -n "$CLI" ]; then
  st="$(cli miner status "$ADDRESS" --json || true)"
  if [ -n "$st" ] && jq -e 'type == "object"' <<<"$st" >/dev/null 2>&1; then
    reg="$(jq -r '.registered' <<<"$st" 2>/dev/null || echo unknown)"
    [ "$reg" = true ] && check registered pass "registered=true" || check registered fail "registered=$reg"
    cal="$(jq -c '.calibration | if . == null then null elif type == "object" then {acceptedAt, verifiedJobs, capGflopsPerSec} else . end' <<<"$st" 2>/dev/null || echo null)"
    [ "$cal" != null ] && check calibration pass "$cal" || check calibration warn "no accepted calibration yet (normal for up to a day after first start)"
  else
    check registered fail "miner status gave no JSON answer"
  fi
  bal="$(cli balance "$ADDRESS" --json | jq -r '.free // empty' || true)"
  if [ -n "$bal" ]; then
    check balance pass "free=$(awk -v b="$bal" 'BEGIN{printf "%.6f", b/1e18}') (assumes 18 decimals; compare with the previous run)"
  else
    check balance warn "balance read failed"
  fi
fi

if [ "$JSON" = 1 ]; then
  jq -s --argjson failed "$failed" '{ok: ($failed == 0), checks: .}' "$results"
else
  jq -r '"\(.status | ascii_upcase)\t\(.id)\t\(.detail)"' "$results"
  [ "$failed" = 0 ] && echo "OK" || echo "FAIL: fix the first failing check"
fi
exit "$failed"
