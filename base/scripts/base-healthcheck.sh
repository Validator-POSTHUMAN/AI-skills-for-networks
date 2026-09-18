#!/usr/bin/env bash
# Read-only Base (OP Stack L2) node health check.
#
# It runs no mutating RPC, changes nothing on the host, and prints no
# credential.
#
# The check most setups lack is safe-head progress. `unsafe_l2` comes from the
# sequencer's gossip feed and advances every two seconds whether or not the
# node can reach Ethereum. `safe_l2` only advances when the node has read the
# batch back from L1. A node whose unsafe head is at the tip and whose safe
# head is frozen has stopped verifying Ethereum — and the process is up, the
# logs are normal and every height-based monitor is green.
#
# This script therefore samples twice and reports whether the safe head moved.
set -euo pipefail

HOST=""
LOCAL_MODE=0
EL_RPC="http://127.0.0.1:8545"
CL_RPC="http://127.0.0.1:7545"
COMPOSE_DIR=""
EL_SERVICE=""
CL_SERVICE=""
EXPECTED_CHAIN_ID=""
MAX_HEAD_AGE=60
MAX_SAFE_LAG=300
MAX_TIP_DRIFT=20
MIN_EL_PEERS=5
DISK_WARN_PERCENT=90
DISK_PATH="/"
SKIP_EXTERNAL=0
SAFE_SAMPLE_WAIT=15
CURL_TIMEOUT=8
PUBLIC_REF="https://mainnet.base.org"

usage() {
  cat <<'USAGE'
Usage:
  base-healthcheck.sh [--host <ssh-target>|--local] [options]

Examples:
  base-healthcheck.sh --local --chain-id 8453
  base-healthcheck.sh --local --compose-dir /opt/base --chain-id 8453
  base-healthcheck.sh --local --el-service base-reth --cl-service base-consensus
  base-healthcheck.sh --host <user>@<host> --chain-id 84532 \
      --public-ref https://sepolia.base.org

Options:
  --local                    Run checks on the current host instead of over SSH.
  --host <ssh-target>        Run checks over SSH on this target.
  --el-rpc <url>             Execution JSON-RPC.  Default: http://127.0.0.1:8545
  --cl-rpc <url>             Rollup node RPC.     Default: http://127.0.0.1:7545
  --compose-dir <path>       Directory with docker-compose.yml. "" to skip.
  --el-service <name>        systemd unit for base-reth-node. "" to skip.
  --cl-service <name>        systemd unit for base-consensus. "" to skip.
  --chain-id <n>             Expected decimal chain id: 8453 or 84532.
  --max-head-age <s>         Unsafe head age that fails.      Default: 60
  --max-safe-lag <blocks>    unsafe-safe lag that fails.      Default: 300
  --max-tip-drift <blocks>   Drift from the public reference. Default: 20
  --min-el-peers <n>         Minimum execution peers.         Default: 5
  --disk-warn <percent>      Filesystem usage that fails.     Default: 90
  --disk-path <path>         Filesystem to check.             Default: /
  --safe-sample-wait <s>     Gap between safe-head samples.   Default: 15
  --public-ref <url>         Public endpoint for comparison.
  --skip-external            Do not compare against a public endpoint.
  -h, --help                 Show this help.

Exit codes: 0 all checks passed, 1 at least one check failed, 2 usage error.
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --local) LOCAL_MODE=1 ;;
    --host) HOST="${2:-}"; shift ;;
    --el-rpc) EL_RPC="${2:-}"; shift ;;
    --cl-rpc) CL_RPC="${2:-}"; shift ;;
    --compose-dir) COMPOSE_DIR="${2:-}"; shift ;;
    --el-service) EL_SERVICE="${2:-}"; shift ;;
    --cl-service) CL_SERVICE="${2:-}"; shift ;;
    --chain-id) EXPECTED_CHAIN_ID="${2:-}"; shift ;;
    --max-head-age) MAX_HEAD_AGE="${2:-}"; shift ;;
    --max-safe-lag) MAX_SAFE_LAG="${2:-}"; shift ;;
    --max-tip-drift) MAX_TIP_DRIFT="${2:-}"; shift ;;
    --min-el-peers) MIN_EL_PEERS="${2:-}"; shift ;;
    --disk-warn) DISK_WARN_PERCENT="${2:-}"; shift ;;
    --disk-path) DISK_PATH="${2:-}"; shift ;;
    --safe-sample-wait) SAFE_SAMPLE_WAIT="${2:-}"; shift ;;
    --public-ref) PUBLIC_REF="${2:-}"; shift ;;
    --skip-external) SKIP_EXTERNAL=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if [ "$LOCAL_MODE" -eq 0 ] && [ -z "$HOST" ]; then
  echo "one of --local or --host is required" >&2
  usage >&2
  exit 2
fi

command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 2; }

FAILED=0
pass() { printf 'ok    %-26s %s\n' "$1" "${2:-}"; }
warn() { printf 'warn  %-26s %s\n' "$1" "${2:-}"; }
fail() { printf 'FAIL  %-26s %s\n' "$1" "${2:-}"; FAILED=1; }

run() {
  if [ "$LOCAL_MODE" -eq 1 ]; then
    bash -c "$1"
  else
    ssh -o BatchMode=yes -o ConnectTimeout=10 "$HOST" "$1"
  fi
}

# One JSON-RPC call with no params against an endpoint the caller named.
#
# `|| true` is load-bearing. The script runs under `set -o pipefail`, and a
# curl to an endpoint that is not listening exits 7, which kills the whole
# check at the first unreachable service — exactly when its diagnosis is most
# wanted. An unreachable endpoint must produce an empty result that the caller
# reports as a failure, not a silent exit.
rpc() {
  run "curl -s --max-time ${CURL_TIMEOUT} -X POST -H 'Content-Type: application/json' \
    --data '{\"jsonrpc\":\"2.0\",\"method\":\"$2\",\"params\":[],\"id\":1}' '$1' || true"
}

hex2dec() {
  local v="${1#0x}"
  [ -n "$v" ] || { echo ""; return; }
  printf '%d\n' "$((16#$v))" 2>/dev/null || echo ""
}

echo "== processes"
if [ -n "$COMPOSE_DIR" ]; then
  state="$(run "cd '${COMPOSE_DIR}' && docker compose ps --format '{{.Service}}:{{.State}}' 2>/dev/null || true")"
  if [ -z "$state" ]; then
    fail "compose.ps" "no output from ${COMPOSE_DIR}"
  else
    bad="$(printf '%s\n' "$state" | grep -v ':running$' || true)"
    if [ -n "$bad" ]; then
      fail "compose.ps" "not running: $(printf '%s' "$bad" | tr '\n' ' ')"
    else
      pass "compose.ps" "$(printf '%s' "$state" | tr '\n' ' ')"
    fi
  fi
  tag="$(run "cd '${COMPOSE_DIR}' && docker compose config 2>/dev/null | grep -m1 'image:' | awk '{print \$2}' || true")"
  if [ -z "$tag" ]; then
    warn "compose.image" "unavailable"
  elif printf '%s' "$tag" | grep -q ':latest$'; then
    warn "compose.image" "${tag} — pin a release tag; 'latest' changes on any restart"
  else
    pass "compose.image" "$tag"
  fi
fi

for pair in "execution:$EL_SERVICE" "consensus:$CL_SERVICE"; do
  label="${pair%%:*}"; unit="${pair#*:}"
  [ -n "$unit" ] || continue
  st="$(run "systemctl is-active ${unit} 2>/dev/null || true")"
  restarts="$(run "systemctl show ${unit} -p NRestarts --value 2>/dev/null || true")"
  if [ "$st" = "active" ]; then
    pass "${label}.service" "${unit} active, NRestarts=${restarts:-?}"
  else
    fail "${label}.service" "${unit} is ${st:-unknown}"
  fi
done

echo "== execution layer"
chain_hex="$(rpc "$EL_RPC" eth_chainId | jq -r '.result // empty')"
chain_dec="$(hex2dec "$chain_hex")"
if [ -z "$chain_dec" ]; then
  fail "el.chain_id" "no answer from ${EL_RPC}"
elif [ -n "$EXPECTED_CHAIN_ID" ] && [ "$chain_dec" != "$EXPECTED_CHAIN_ID" ]; then
  fail "el.chain_id" "got ${chain_dec}, expected ${EXPECTED_CHAIN_ID}"
else
  case "$chain_dec" in
    8453) pass "el.chain_id" "8453 (Base Mainnet)" ;;
    84532) pass "el.chain_id" "84532 (Base Sepolia)" ;;
    *) warn "el.chain_id" "${chain_dec} — not a known Base network" ;;
  esac
fi

syncing="$(rpc "$EL_RPC" eth_syncing | jq -c '.result')"
if [ "$syncing" = "false" ]; then
  pass "el.syncing" "synced"
elif [ -z "$syncing" ] || [ "$syncing" = "null" ]; then
  fail "el.syncing" "no answer"
else
  cur="$(hex2dec "$(echo "$syncing" | jq -r '.currentBlock // empty')")"
  hi="$(hex2dec "$(echo "$syncing" | jq -r '.highestBlock // empty')")"
  fail "el.syncing" "syncing ${cur:-?}/${hi:-?}"
fi

el_peers="$(hex2dec "$(rpc "$EL_RPC" net_peerCount | jq -r '.result // empty')")"
if [ -z "$el_peers" ]; then
  warn "el.peers" "unavailable"
elif [ "$el_peers" -lt "$MIN_EL_PEERS" ]; then
  fail "el.peers" "${el_peers} < ${MIN_EL_PEERS} — check EGRESS to 30301/tcp+udp and 9200/udp (Base bootnodes)"
else
  pass "el.peers" "$el_peers"
fi

local_head="$(hex2dec "$(rpc "$EL_RPC" eth_blockNumber | jq -r '.result // empty')")"
[ -n "$local_head" ] && pass "el.head" "$local_head" || fail "el.head" "unavailable"

echo "== derivation (rollup node)"
status1="$(rpc "$CL_RPC" optimism_syncStatus | jq -c '.result // empty')"
if [ -z "$status1" ]; then
  fail "cl.sync_status" "no answer from ${CL_RPC} — without it, safe-head health is unknown"
  safe1=""
else
  unsafe1="$(echo "$status1" | jq -r '.unsafe_l2.number // empty')"
  safe1="$(echo "$status1" | jq -r '.safe_l2.number // empty')"
  final1="$(echo "$status1" | jq -r '.finalized_l2.number // empty')"
  l1head="$(echo "$status1" | jq -r '.head_l1.number // empty')"
  head_ts="$(echo "$status1" | jq -r '.unsafe_l2.timestamp // empty')"

  pass "cl.heads" "unsafe=${unsafe1:-?} safe=${safe1:-?} finalized=${final1:-?} l1=${l1head:-?}"

  if [ -n "$head_ts" ]; then
    age=$(( $(date +%s) - head_ts ))
    if [ "$age" -le "$MAX_HEAD_AGE" ]; then
      pass "cl.head_age" "${age}s"
    else
      fail "cl.head_age" "${age}s > ${MAX_HEAD_AGE}s — not following the sequencer feed"
    fi
  else
    warn "cl.head_age" "unavailable"
  fi

  if [ -n "$unsafe1" ] && [ -n "$safe1" ]; then
    lag=$(( unsafe1 - safe1 ))
    if [ "$lag" -le "$MAX_SAFE_LAG" ]; then
      pass "cl.safe_lag" "${lag} blocks"
    else
      fail "cl.safe_lag" "${lag} > ${MAX_SAFE_LAG} — L1 derivation is degraded (L1 RPC, beacon, or blob availability)"
    fi
  fi
fi

# The check this script exists for: is the safe head actually moving?
if [ -n "${safe1:-}" ] && [ "$SAFE_SAMPLE_WAIT" -gt 0 ]; then
  sleep "$SAFE_SAMPLE_WAIT"
  status2="$(rpc "$CL_RPC" optimism_syncStatus | jq -c '.result // empty')"
  safe2="$(echo "$status2" | jq -r '.safe_l2.number // empty')"
  unsafe2="$(echo "$status2" | jq -r '.unsafe_l2.number // empty')"
  if [ -z "$safe2" ]; then
    warn "cl.safe_progress" "second sample unavailable"
  elif [ "$safe2" -gt "$safe1" ]; then
    pass "cl.safe_progress" "+$(( safe2 - safe1 )) blocks in ${SAFE_SAMPLE_WAIT}s"
  elif [ -n "${unsafe1:-}" ] && [ -n "$unsafe2" ] && [ "$unsafe2" -gt "$unsafe1" ]; then
    fail "cl.safe_progress" "unsafe advanced +$(( unsafe2 - unsafe1 )), safe did NOT — node is following the sequencer without verifying L1"
  else
    warn "cl.safe_progress" "no movement in ${SAFE_SAMPLE_WAIT}s; batches are posted in bursts — re-sample over a longer window"
  fi
fi

echo "== host"
clock="$(run "timedatectl show -p NTPSynchronized --value 2>/dev/null || true")"
if [ "$clock" = "yes" ]; then
  pass "host.clock" "NTP synchronized"
else
  fail "host.clock" "NTP not synchronized — clock drift breaks P2P before it breaks anything obvious"
fi

disk="$(run "df -P '${DISK_PATH}' 2>/dev/null | awk 'NR==2 {gsub(/%/,\"\",\$5); print \$5\" \"\$4}' || true")"
disk_pct="${disk%% *}"
disk_avail="${disk##* }"
if [ -n "$disk_pct" ] && [ "$disk_pct" -ge "$DISK_WARN_PERCENT" ]; then
  fail "host.disk" "${DISK_PATH} at ${disk_pct}%, ${disk_avail}K free"
else
  pass "host.disk" "${DISK_PATH} at ${disk_pct:-?}%"
fi

# Only P2P belongs off-loopback. Docker publishes past ufw, so listeners are
# the evidence and the firewall is not.
exposed="$(run "ss -tlnH 2>/dev/null | awk '{print \$4}' | grep -vE '^(127\\.0\\.0\\.1|\\[::1\\])' || true")"
if [ -z "$exposed" ]; then
  pass "host.listeners" "loopback only"
else
  risky="$(printf '%s\n' "$exposed" | grep -E ':(8545|8546|8551|7545|7300|7301|6060)$' || true)"
  if [ -n "$risky" ]; then
    fail "host.listeners" "RPC/metrics/pprof off-loopback: $(printf '%s' "$risky" | tr '\n' ' ') — ufw does not cover Docker-published ports"
  else
    pass "host.listeners" "off-loopback: $(printf '%s' "$exposed" | tr '\n' ' ')"
  fi
fi

if [ "$SKIP_EXTERNAL" -eq 0 ] && [ -n "${local_head:-}" ]; then
  echo "== independent comparison"
  ref_hex="$(curl -s --max-time "$CURL_TIMEOUT" -X POST -H 'Content-Type: application/json' \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' "$PUBLIC_REF" \
    | jq -r '.result // empty' 2>/dev/null || true)"
  ref_head="$(hex2dec "$ref_hex")"
  if [ -z "$ref_head" ]; then
    warn "external.head" "${PUBLIC_REF} unavailable; local head not independently confirmed"
  else
    drift=$(( ref_head - local_head ))
    [ "$drift" -lt 0 ] && drift=$(( -drift ))
    if [ "$drift" -le "$MAX_TIP_DRIFT" ]; then
      pass "external.head" "local ${local_head}, public ${ref_head}, drift ${drift}"
    else
      fail "external.head" "local ${local_head}, public ${ref_head}, drift ${drift} > ${MAX_TIP_DRIFT}"
    fi
  fi
fi

echo
if [ "$FAILED" -eq 0 ]; then
  echo "healthcheck=passed"
  echo "This is evidence, not proof. After an upgrade or an incident, confirm the"
  echo "safe head advances over several consecutive samples, and compare the safe"
  echo "block HASH against a public endpoint — matching heights are not the same"
  echo "chain."
else
  echo "healthcheck=failed"
fi
exit "$FAILED"
