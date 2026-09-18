#!/usr/bin/env bash
# Read-only Arc Network node health check.
#
# It runs no mutating RPC, changes nothing on the host, and prints no
# credential.
#
# An Arc node is a follower: it reaches the network entirely through relay
# endpoints over HTTPS and WebSocket. When those stop answering the node does
# not crash — it stops advancing. Both processes stay active, eth_blockNumber
# answers instantly, and the answer is old. Every process-based monitor reports
# success.
#
# So this script samples the height TWICE, because one reading cannot
# distinguish "advancing" from "stopped a second ago", and compares the block
# HASH against an independent reference, because two chains can sit at the same
# block number.
set -euo pipefail

HOST=""
LOCAL_MODE=0
RPC="http://127.0.0.1:8545"
CL_RPC="http://127.0.0.1:31000"
REFERENCE="https://rpc.mainnet.arc.io"
EXPECTED_CHAIN_ID=""
EL_SERVICE="arc-execution"
CL_SERVICE="arc-consensus"
ARC_RUN="/run/arc"
DISK_PATH="$HOME/.arc"
DISK_WARN_PERCENT=90
SAMPLE_WAIT=30
CURL_TIMEOUT=8
SKIP_EXTERNAL=0

usage() {
  cat <<'USAGE'
Usage:
  arc-healthcheck.sh [--local|--host <ssh-target>] [options]

Examples:
  arc-healthcheck.sh --local --chain-id 5042
  arc-healthcheck.sh --local --chain-id 5042002 \
      --reference https://rpc.testnet.arc.io
  arc-healthcheck.sh --host <user>@<host> --chain-id 5042 \
      --el-service arc-execution --cl-service arc-consensus

Options:
  --local                 Run on the current host instead of over SSH.
  --host <ssh-target>     Run over SSH on this target.
  --rpc <url>             EL JSON-RPC.   Default: http://127.0.0.1:8545
  --cl-rpc <url>          CL RPC.        Default: http://127.0.0.1:31000
  --reference <url>       Independent public RPC for the hash comparison.
  --chain-id <n>          Expected decimal chain id: 5042, 5042002, 5042001.
  --el-service <name>     systemd unit for the execution layer. "" to skip.
  --cl-service <name>     systemd unit for the consensus layer. "" to skip.
  --arc-run <path>        Runtime dir holding the IPC sockets. Default: /run/arc
  --disk-path <path>      Filesystem to check.   Default: $HOME/.arc
  --disk-warn <percent>   Disk use that fails.   Default: 90
  --sample-wait <s>       Seconds between height samples. Default: 30
  --skip-external         Do not contact the reference RPC.
  -h, --help              This message.

Exit code is the number of failed checks.
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --local) LOCAL_MODE=1 ;;
    --host) HOST="${2:-}"; shift ;;
    --rpc) RPC="${2:-}"; shift ;;
    --cl-rpc) CL_RPC="${2:-}"; shift ;;
    --reference) REFERENCE="${2:-}"; shift ;;
    --chain-id) EXPECTED_CHAIN_ID="${2:-}"; shift ;;
    --el-service) EL_SERVICE="${2:-}"; shift ;;
    --cl-service) CL_SERVICE="${2:-}"; shift ;;
    --arc-run) ARC_RUN="${2:-}"; shift ;;
    --disk-path) DISK_PATH="${2:-}"; shift ;;
    --disk-warn) DISK_WARN_PERCENT="${2:-}"; shift ;;
    --sample-wait) SAMPLE_WAIT="${2:-}"; shift ;;
    --skip-external) SKIP_EXTERNAL=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if [ "$LOCAL_MODE" -eq 0 ] && [ -z "$HOST" ]; then
  echo "one of --local or --host is required" >&2
  exit 2
fi

command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 2; }

FAILED=0
pass() { printf '  PASS  %-22s %s\n' "$1" "${2:-}"; }
warn() { printf '  WARN  %-22s %s\n' "$1" "${2:-}"; }
fail() { printf '  FAIL  %-22s %s\n' "$1" "${2:-}"; FAILED=$((FAILED + 1)); }

run() {
  if [ "$LOCAL_MODE" -eq 1 ]; then
    bash -lc "$1"
  else
    ssh -o BatchMode=yes -o ConnectTimeout=10 "$HOST" "$1"
  fi
}

# JSON-RPC against the node, from wherever the node is.
node_rpc() {
  run "curl -fsS --max-time ${CURL_TIMEOUT} -X POST '${RPC}' -H 'Content-Type: application/json' -d '$1' 2>/dev/null || true"
}

# JSON-RPC against the reference, from this machine.
ref_rpc() {
  curl -fsS --max-time "${CURL_TIMEOUT}" -X POST "$REFERENCE" \
    -H 'Content-Type: application/json' -d "$1" 2>/dev/null || true
}

hex2dec() {
  local v="${1#0x}"
  [ -z "$v" ] && return 0
  printf '%d' "$((16#$v))" 2>/dev/null || true
}

echo "Arc node health check"
echo "  target      ${HOST:-local}"
echo "  rpc         ${RPC}"
echo

# --- services ----------------------------------------------------------------
for pair in "el:${EL_SERVICE}" "cl:${CL_SERVICE}"; do
  layer="${pair%%:*}"; unit="${pair#*:}"
  [ -z "$unit" ] && continue
  state="$(run "systemctl is-active ${unit} 2>/dev/null || true" | tr -d '[:space:]')"
  case "$state" in
    active) pass "service.${layer}" "${unit}" ;;
    "")     warn "service.${layer}" "${unit}: no answer from systemctl" ;;
    *)      fail "service.${layer}" "${unit} is ${state}" ;;
  esac
done

# --- IPC sockets -------------------------------------------------------------
# The EL writes both within ~30s of starting. Missing sockets mean the EL did
# not start, which is the first thing to know when the height reads 0x0.
if [ -n "$ARC_RUN" ]; then
  sockets="$(run "ls -1 '${ARC_RUN}' 2>/dev/null || true")"
  missing=""
  case "$sockets" in *reth.ipc*) : ;; *) missing="reth.ipc" ;; esac
  case "$sockets" in *auth.ipc*) : ;; *) missing="${missing:+$missing }auth.ipc" ;; esac
  if [ -z "$missing" ]; then
    pass "ipc.sockets" "${ARC_RUN}/{reth,auth}.ipc"
  else
    fail "ipc.sockets" "missing in ${ARC_RUN}: ${missing} — the execution layer did not start"
  fi
fi

# --- chain identity ----------------------------------------------------------
chain_hex="$(node_rpc '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' | jq -r '.result // empty')"
if [ -z "$chain_hex" ]; then
  fail "rpc.reachable" "${RPC} did not answer eth_chainId"
  echo
  echo "healthcheck=failed"
  exit "$FAILED"
fi
pass "rpc.reachable" "${RPC}"

chain_dec="$(hex2dec "$chain_hex")"
if [ -n "$EXPECTED_CHAIN_ID" ]; then
  if [ "$chain_dec" = "$EXPECTED_CHAIN_ID" ]; then
    pass "chain.id" "${chain_dec} (${chain_hex})"
  else
    fail "chain.id" "node reports ${chain_dec}, expected ${EXPECTED_CHAIN_ID} — check --chain; every Circle quickstart targets arc-testnet"
  fi
else
  warn "chain.id" "${chain_dec} (no --chain-id given, not verified)"
fi

# --- version -----------------------------------------------------------------
ver="$(node_rpc '{"jsonrpc":"2.0","method":"arc_getVersion","params":[],"id":1}' | jq -r '.result.git_version // empty')"
if [ -n "$ver" ]; then
  pass "node.version" "$ver"
else
  warn "node.version" "arc_getVersion did not answer — is --enable-arc-rpc set?"
fi

# --- height advances ---------------------------------------------------------
h1="$(hex2dec "$(node_rpc '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | jq -r '.result // empty')")"
if [ -z "$h1" ]; then
  fail "sync.height" "eth_blockNumber did not answer"
elif [ "$h1" = "0" ]; then
  fail "sync.height" "0 — check the IPC sockets, the start order (EL first), and whether the snapshot restore finished"
else
  sleep "$SAMPLE_WAIT"
  h2="$(hex2dec "$(node_rpc '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | jq -r '.result // empty')")"
  if [ -n "$h2" ] && [ "$h2" -gt "$h1" ]; then
    pass "sync.advancing" "${h1} -> ${h2} in ${SAMPLE_WAIT}s"
  else
    fail "sync.advancing" "height did not move: ${h1} -> ${h2:-?} — the relay endpoints are the first thing to check, from THIS host"
  fi
fi

# --- agreement with the network, by hash -------------------------------------
if [ "$SKIP_EXTERNAL" -eq 0 ] && [ -n "${h2:-}" ]; then
  ref_head="$(hex2dec "$(ref_rpc '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | jq -r '.result // empty')")"
  if [ -z "$ref_head" ]; then
    warn "external.head" "${REFERENCE} unavailable; local head not independently confirmed"
  else
    drift=$(( ref_head - h2 )); [ "$drift" -lt 0 ] && drift=$(( -drift ))
    if [ "$drift" -le 50 ]; then
      pass "external.head" "local ${h2}, reference ${ref_head}, drift ${drift}"
    else
      fail "external.head" "local ${h2}, reference ${ref_head}, drift ${drift}"
    fi

    # Same number is not the same chain. Compare the hash.
    cmp_height="$h2"
    [ "$ref_head" -lt "$cmp_height" ] && cmp_height="$ref_head"
    cmp_hex="$(printf '0x%x' "$cmp_height")"
    payload="{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"${cmp_hex}\",false],\"id\":1}"
    local_hash="$(node_rpc "$payload" | jq -r '.result.hash // empty')"
    ref_hash="$(ref_rpc "$payload" | jq -r '.result.hash // empty')"
    if [ -z "$local_hash" ] || [ -z "$ref_hash" ]; then
      warn "external.hash" "could not read both block hashes at ${cmp_height}"
    elif [ "$local_hash" = "$ref_hash" ]; then
      pass "external.hash" "block ${cmp_height} matches ${REFERENCE}"
    else
      fail "external.hash" "DIVERGENCE at ${cmp_height}: local ${local_hash}, reference ${ref_hash}"
    fi
  fi

  ref_ver="$(ref_rpc '{"jsonrpc":"2.0","method":"arc_getVersion","params":[],"id":1}' | jq -r '.result.git_version // empty')"
  if [ -n "$ref_ver" ] && [ -n "$ver" ]; then
    if [ "$ref_ver" = "$ver" ]; then
      pass "version.fleet" "local and reference both ${ver}"
    else
      warn "version.fleet" "local ${ver}, reference ${ref_ver} — Arc forks activate on a wall-clock timestamp, with no on-chain plan to warn you"
    fi
  fi
elif [ "$SKIP_EXTERNAL" -eq 1 ]; then
  warn "external" "skipped — this is the check that detects a stalled or wrong chain"
fi

# --- CL reachable ------------------------------------------------------------
# Required by --enable-arc-rpc: the EL proxies arc_getCertificate here.
cl_ready="$(run "curl -fsS --max-time ${CURL_TIMEOUT} '${CL_RPC}/ready' 2>/dev/null || true")"
if [ -n "$cl_ready" ]; then
  pass "cl.rpc" "${CL_RPC} answering"
else
  warn "cl.rpc" "${CL_RPC} did not answer — arc_getCertificate will not work; check for 'Address already in use' on the CL"
fi

# --- exposure ----------------------------------------------------------------
# Listeners are evidence. `ufw status` is not: Docker writes its iptables rules
# ahead of ufw, so a published container port is reachable on a host whose
# firewall reads as correct.
offloop="$(run "ss -ltn 2>/dev/null | awk 'NR>1 {print \$4}' | grep -vE '127\\.0\\.0\\.1|\\[::1\\]' | grep -E ':(8545|8546|8551|9001|29000|31000)\$' || true")"
if [ -n "$offloop" ]; then
  fail "exposure.offloopback" "$(printf '%s' "$offloop" | tr '\n' ' ')— 8551 and 31000 must never be exposed; RPC and metrics belong on loopback or behind a reviewed proxy"
else
  pass "exposure.offloopback" "no node port bound off loopback"
fi

# --- namespaces --------------------------------------------------------------
modules="$(node_rpc '{"jsonrpc":"2.0","method":"rpc_modules","params":[],"id":1}' | jq -r '.result | keys | join(",") // empty' 2>/dev/null || true)"
if [ -n "$modules" ]; then
  unsafe="$(printf '%s' "$modules" | tr ',' '\n' | grep -E '^(txpool|debug|trace|admin|flashbots|mev|ots)$' | tr '\n' ' ' || true)"
  if [ -z "$unsafe" ]; then
    pass "rpc.namespaces" "$modules"
  else
    warn "rpc.namespaces" "${modules} — ${unsafe}must not be exposed publicly; Circle's quickstart enables them"
  fi
else
  warn "rpc.namespaces" "rpc_modules not available"
fi

# --- disk --------------------------------------------------------------------
used="$(run "df -P '${DISK_PATH}' 2>/dev/null | awk 'NR==2 {gsub(\"%\",\"\",\$5); print \$5}' || true" | tr -d '[:space:]')"
if [ -n "$used" ]; then
  if [ "$used" -lt "$DISK_WARN_PERCENT" ]; then
    pass "host.disk" "${DISK_PATH} at ${used}%"
  else
    fail "host.disk" "${DISK_PATH} at ${used}% >= ${DISK_WARN_PERCENT}%"
  fi
fi

echo
if [ "$FAILED" -eq 0 ]; then
  echo "healthcheck=passed"
  echo "This is evidence, not proof. Confirm the height advances over several"
  echo "consecutive samples after an upgrade or an incident, and check the running"
  echo "version against the next fork timestamp — Arc activates forks on wall-clock"
  echo "time, with no on-chain plan and no approaching height to watch."
else
  echo "healthcheck=failed"
fi
exit "$FAILED"
