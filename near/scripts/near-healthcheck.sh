#!/usr/bin/env bash
# NEAR node and validator health check.
#
# Read-only. Performs no transaction, touches no key, changes no service.
# Exit code 0 when every executed check passed, 1 when any check failed.
set -euo pipefail

HOST=""
LOCAL_MODE=0
NETWORK="mainnet"
RPC="http://127.0.0.1:3030"
PUBLIC_RPC=""
POOL=""
EXPECTED_VERSION=""
SERVICE="neard"
HEIGHT_LAG_THRESHOLD=100
SAMPLE_SECONDS=30
CURL_TIMEOUT=10
CHECK_ARCHIVAL=0
SKIP_SAMPLE=0

usage() {
  cat <<'USAGE'
Usage:
  near-healthcheck.sh [--host <ssh-target>|--local] [options]

Options:
  --network <mainnet|testnet>  Network name. Sets the default public RPC. Default: mainnet.
  --rpc <url>                  Local JSON-RPC endpoint. Default: http://127.0.0.1:3030.
  --public-rpc <url>           Independent endpoint for height comparison.
                               Defaults from --network.
  --pool <account>             Staking pool account, e.g. example.poolv1.near.
                               Enables validator production checks.
  --expected-version <string>  Expected neard version substring.
  --service <name>             systemd unit name. Default: neard.
  --lag <blocks>               Height lag that fails the check. Default: 100.
  --sample-seconds <sec>       Gap between production samples. Default: 30.
  --skip-sample                Skip the second production sample (faster, less evidence).
  --check-archival             Also check split-storage cold head progress.
  --curl-timeout <sec>         Per-request timeout. Default: 10.
  -h, --help                   Show this help.

Notes:
  Use 127.0.0.1 rather than localhost for the local RPC: on a dual-stack host
  the resolver tries ::1 first and a service bound to 0.0.0.0 only answers
  after that attempt times out.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) HOST="$2"; shift 2 ;;
    --local) LOCAL_MODE=1; shift ;;
    --network) NETWORK="$2"; shift 2 ;;
    --rpc) RPC="$2"; shift 2 ;;
    --public-rpc) PUBLIC_RPC="$2"; shift 2 ;;
    --pool) POOL="$2"; shift 2 ;;
    --expected-version) EXPECTED_VERSION="$2"; shift 2 ;;
    --service) SERVICE="$2"; shift 2 ;;
    --lag) HEIGHT_LAG_THRESHOLD="$2"; shift 2 ;;
    --sample-seconds) SAMPLE_SECONDS="$2"; shift 2 ;;
    --skip-sample) SKIP_SAMPLE=1; shift ;;
    --check-archival) CHECK_ARCHIVAL=1; shift ;;
    --curl-timeout) CURL_TIMEOUT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "$HOST" && "$LOCAL_MODE" -eq 0 ]]; then
  echo "Specify --local or --host <ssh-target>." >&2
  exit 2
fi

if [[ -z "$PUBLIC_RPC" ]]; then
  case "$NETWORK" in
    mainnet) PUBLIC_RPC="https://free.rpc.fastnear.com" ;;
    testnet) PUBLIC_RPC="https://test.rpc.fastnear.com" ;;
    *) PUBLIC_RPC="" ;;
  esac
fi

FAILED=0
pass() { printf '  [ ok ] %s\n' "$1"; }
fail() { printf '  [FAIL] %s\n' "$1"; FAILED=1; }
info() { printf '  [info] %s\n' "$1"; }
section() { printf '\n== %s\n' "$1"; }

run() {
  if [[ "$LOCAL_MODE" -eq 1 ]]; then
    bash -lc "$1"
  else
    ssh -o BatchMode=yes -o ConnectTimeout=10 "$HOST" "$1"
  fi
}

rpc_call() {
  # $1 endpoint, $2 method, $3 params json
  run "curl -sS --max-time ${CURL_TIMEOUT} -X POST '$1' -H 'Content-Type: application/json' \
    -d '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$2\",\"params\":$3}'"
}

printf 'NEAR health check — %s — %s\n' "${HOST:-local}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

section "Service"
if STATE=$(run "systemctl is-active ${SERVICE}" 2>/dev/null); then
  [[ "$STATE" == "active" ]] && pass "${SERVICE} is ${STATE}" || fail "${SERVICE} is ${STATE}"
else
  fail "${SERVICE} is not active"
fi
RESTARTS=$(run "systemctl show ${SERVICE} -p NRestarts --value" 2>/dev/null || echo "unknown")
info "NRestarts=${RESTARTS}"

section "Local status"
STATUS=$(rpc_call "$RPC" status '[]' 2>/dev/null || true)
if [[ -z "$STATUS" ]] || ! jq -e '.result' >/dev/null 2>&1 <<<"$STATUS"; then
  fail "local RPC ${RPC} did not return a status result"
  echo
  echo "Local RPC is unreachable. Check the process, memory and disk before anything else."
  exit 1
fi

VERSION=$(jq -r '.result.version.version' <<<"$STATUS")
CHAIN=$(jq -r '.result.chain_id' <<<"$STATUS")
PROTO=$(jq -r '.result.protocol_version' <<<"$STATUS")
LATEST_PROTO=$(jq -r '.result.latest_protocol_version' <<<"$STATUS")
LOCAL_HEIGHT=$(jq -r '.result.sync_info.latest_block_height' <<<"$STATUS")
SYNCING=$(jq -r '.result.sync_info.syncing' <<<"$STATUS")

info "version=${VERSION} chain=${CHAIN} protocol=${PROTO} latest_protocol=${LATEST_PROTO}"
info "height=${LOCAL_HEIGHT} syncing=${SYNCING}"

[[ "$CHAIN" == "$NETWORK" ]] && pass "chain_id matches ${NETWORK}" \
  || fail "chain_id is ${CHAIN}, expected ${NETWORK}"
[[ "$SYNCING" == "false" ]] && pass "node reports syncing=false" \
  || fail "node reports syncing=${SYNCING}"
[[ "$PROTO" == "$LATEST_PROTO" ]] && pass "protocol_version matches latest_protocol_version" \
  || fail "protocol drift: node ${PROTO}, network ${LATEST_PROTO} — upgrade before the switch"

if [[ -n "$EXPECTED_VERSION" ]]; then
  [[ "$VERSION" == *"$EXPECTED_VERSION"* ]] && pass "version contains ${EXPECTED_VERSION}" \
    || fail "version ${VERSION} does not contain ${EXPECTED_VERSION}"
fi

section "External height"
if [[ -n "$PUBLIC_RPC" ]]; then
  PUB=$(rpc_call "$PUBLIC_RPC" status '[]' 2>/dev/null || true)
  PUB_HEIGHT=$(jq -r '.result.sync_info.latest_block_height // empty' <<<"${PUB:-}" 2>/dev/null || true)
  if [[ -n "$PUB_HEIGHT" ]]; then
    LAG=$(( PUB_HEIGHT - LOCAL_HEIGHT ))
    info "public=${PUB_HEIGHT} local=${LOCAL_HEIGHT} lag=${LAG}"
    (( LAG <= HEIGHT_LAG_THRESHOLD )) && pass "height lag within ${HEIGHT_LAG_THRESHOLD}" \
      || fail "height lag ${LAG} exceeds ${HEIGHT_LAG_THRESHOLD}"
  else
    info "public RPC ${PUBLIC_RPC} did not answer; height not cross-checked"
  fi
else
  info "no public RPC configured; height not cross-checked"
fi

section "Peers"
NET=$(rpc_call "$RPC" network_info '[]' 2>/dev/null || true)
PEERS=$(jq -r '.result.num_active_peers // empty' <<<"${NET:-}" 2>/dev/null || true)
if [[ -n "$PEERS" ]]; then
  info "active_peers=${PEERS}"
  (( PEERS > 0 )) && pass "node has peers" || fail "node has no active peers — check network.boot_nodes"
fi

if [[ -n "$POOL" ]]; then
  section "Validator production (${POOL})"
  sample() {
    rpc_call "$RPC" validators '[null]' 2>/dev/null \
      | jq -c --arg p "$POOL" '.result.current_validators[]? | select(.account_id==$p) |
          {stake, is_slashed,
           bp: .num_produced_blocks, be: .num_expected_blocks,
           cp: .num_produced_chunks, ce: .num_expected_chunks,
           ep: .num_produced_endorsements, ee: .num_expected_endorsements}'
  }
  S1=$(sample || true)
  if [[ -z "$S1" ]]; then
    fail "${POOL} is not in current_validators"
    NEXT=$(rpc_call "$RPC" validators '[null]' 2>/dev/null \
      | jq -r --arg p "$POOL" '[.result.next_validators[]?.account_id] | index($p) // "no"')
    info "present in next_validators: ${NEXT}"
    KICK=$(rpc_call "$RPC" validators '[null]' 2>/dev/null \
      | jq -c --arg p "$POOL" '[.result.prev_epoch_kickout[]? | select(.account_id==$p)]')
    info "prev_epoch_kickout: ${KICK}"
  else
    info "sample 1: ${S1}"
    SLASHED=$(jq -r '.is_slashed' <<<"$S1")
    [[ "$SLASHED" == "false" ]] && pass "is_slashed=false" || fail "is_slashed=${SLASHED}"

    for pair in "bp be blocks" "cp ce chunks" "ep ee endorsements"; do
      set -- $pair
      P=$(jq -r ".$1" <<<"$S1"); E=$(jq -r ".$2" <<<"$S1")
      if [[ "$E" == "0" || "$E" == "null" ]]; then
        info "$3: none expected this epoch so far"
      else
        RATIO=$(awk -v p="$P" -v e="$E" 'BEGIN{printf "%.4f", p/e}')
        info "$3: ${P}/${E} (${RATIO})"
      fi
    done

    if [[ "$SKIP_SAMPLE" -eq 0 ]]; then
      info "sampling again in ${SAMPLE_SECONDS}s to distinguish a live fault from a retrospective ratio"
      sleep "$SAMPLE_SECONDS"
      S2=$(sample || true)
      info "sample 2: ${S2}"
      if [[ -n "$S2" ]]; then
        E1=$(jq -r '.ee' <<<"$S1"); E2=$(jq -r '.ee' <<<"$S2")
        P1=$(jq -r '.ep' <<<"$S1"); P2=$(jq -r '.ep' <<<"$S2")
        DE=$(( E2 - E1 )); DP=$(( P2 - P1 ))
        info "delta endorsements: produced +${DP}, expected +${DE}"
        if (( DE == 0 )); then
          info "no new endorsements were expected in the window; inconclusive, widen --sample-seconds"
        elif (( DP >= DE )); then
          pass "fresh production is healthy — a low cumulative ratio is retrospective, do not restart for it"
        else
          fail "missing $(( DE - DP )) of ${DE} freshly expected endorsements — live fault"
        fi
      fi
    fi
  fi
fi

section "Capacity"
MEM=$(run "free -m | awk '/^Mem:/ {print \$7}'" 2>/dev/null || echo "")
if [[ -n "$MEM" ]]; then
  info "available memory: ${MEM} MiB"
  (( MEM >= 8192 )) && pass "memory headroom >= 8 GiB" \
    || fail "memory headroom ${MEM} MiB is below the 8 GiB guidance — OOM risk during state transitions"
fi
echo "  --- mounts ---"
run "df -h | grep -v 'tmpfs\|udev\|loop'" 2>/dev/null | sed 's/^/  /' || true
FULL=$(run "df -P | awk 'NR>1 && \$1 !~ /tmpfs|udev|loop/ && \$5+0 >= 85 {print \$6\" \"\$5}'" 2>/dev/null || true)
if [[ -n "$FULL" ]]; then
  fail "mounts at or above 85% used: ${FULL}"
else
  pass "no mount above 85% used"
fi

if [[ "$CHECK_ARCHIVAL" -eq 1 ]]; then
  section "Archival split storage"
  C1=$(run "curl -sS --max-time ${CURL_TIMEOUT} ${RPC}/metrics | grep -m1 cold_head_height | awk '{print \$2}'" 2>/dev/null || true)
  info "cold_head_height sample 1: ${C1:-unavailable}"
  if [[ -n "$C1" ]]; then
    sleep 60
    C2=$(run "curl -sS --max-time ${CURL_TIMEOUT} ${RPC}/metrics | grep -m1 cold_head_height | awk '{print \$2}'" 2>/dev/null || true)
    info "cold_head_height sample 2: ${C2:-unavailable}"
    if [[ -n "$C2" ]] && awk -v a="$C1" -v b="$C2" 'BEGIN{exit !(b>a)}'; then
      pass "cold head is advancing"
    else
      fail "cold head is not advancing — hot/cold mismatch or an incomplete migration"
    fi
  else
    fail "cold_head_height metric not exported — split storage may not be enabled"
  fi
fi

section "Log signatures"
LOGS=$(run "journalctl -u ${SERVICE} -n 500 --no-pager 2>/dev/null | grep -icE 'panic|fatal|corrupt|out of memory' || true" 2>/dev/null | tail -n1)
if [[ "${LOGS:-0}" -gt 0 ]]; then
  fail "${LOGS} panic/fatal/corruption/OOM lines in the last 500 log lines"
else
  pass "no panic, fatal, corruption or OOM lines in the last 500 log lines"
fi

echo
if [[ "$FAILED" -eq 0 ]]; then
  echo "RESULT: all executed checks passed."
else
  echo "RESULT: at least one check failed. Do not report this node as healthy."
fi
exit "$FAILED"
