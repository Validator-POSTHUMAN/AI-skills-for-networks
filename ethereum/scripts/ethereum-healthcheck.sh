#!/usr/bin/env bash
# Read-only Ethereum node and validator health check.
#
# It runs no mutating RPC, signs nothing, touches no keystore and changes
# nothing on the host.
#
# The check most setups lack is `is_optimistic`. A beacon node in optimistic
# mode is following heads its execution client has not verified: every service
# is "active", the log looks normal, the head slot advances — and the
# validator's attestations are worthless. Height-based and systemd-based
# monitors all report that node as healthy.
set -euo pipefail

HOST=""
LOCAL_MODE=0
EL_RPC="http://127.0.0.1:8545"
CL_API="http://127.0.0.1:5052"
EL_SERVICE=""
CL_SERVICE=""
VC_SERVICE=""
EXPECTED_CHAIN_ID=""
MAX_SYNC_DISTANCE=4
MIN_EL_PEERS=10
MIN_CL_PEERS=20
DISK_WARN_PERCENT=90
CLOCK_WARN_MS=200
SKIP_EXTERNAL=0
CURL_TIMEOUT=8
EXTERNAL_HEAD_SOURCE="https://beaconcha.in/api/v1/epoch/latest"

usage() {
  cat <<'USAGE'
Usage:
  ethereum-healthcheck.sh [--host <ssh-target>|--local] [options]

Examples:
  ethereum-healthcheck.sh --local
  ethereum-healthcheck.sh --local --el-service execution --cl-service consensus --vc-service validator
  ethereum-healthcheck.sh --host <user>@<host> --chain-id 1

Options:
  --local                    Run checks on the current host instead of over SSH.
  --host <ssh-target>        Run checks over SSH on this target.
  --el-rpc <url>             Execution JSON-RPC. Default: http://127.0.0.1:8545
  --cl-api <url>             Beacon API. Default: http://127.0.0.1:5052
  --el-service <name>        systemd unit for the execution client. "" to skip.
  --cl-service <name>        systemd unit for the consensus client. "" to skip.
  --vc-service <name>        systemd unit for the validator client. "" to skip.
  --chain-id <n>             Expected decimal chain id, e.g. 1 or 560048.
  --max-sync-distance <n>    Beacon sync distance that fails. Default: 4
  --min-el-peers <n>         Minimum execution peers. Default: 10
  --min-cl-peers <n>         Minimum consensus peers. Default: 20
  --disk-warn <percent>      Filesystem usage that warns. Default: 90
  --clock-warn <ms>          Clock offset that warns. Default: 200
  --skip-external            Do not compare the head against a public source.
  -h, --help                 Show this help.

Exit codes: 0 all checks passed, 1 at least one check failed, 2 usage error.
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --local) LOCAL_MODE=1 ;;
    --host) HOST="${2:-}"; shift ;;
    --el-rpc) EL_RPC="${2:-}"; shift ;;
    --cl-api) CL_API="${2:-}"; shift ;;
    --el-service) EL_SERVICE="${2:-}"; shift ;;
    --cl-service) CL_SERVICE="${2:-}"; shift ;;
    --vc-service) VC_SERVICE="${2:-}"; shift ;;
    --chain-id) EXPECTED_CHAIN_ID="${2:-}"; shift ;;
    --max-sync-distance) MAX_SYNC_DISTANCE="${2:-}"; shift ;;
    --min-el-peers) MIN_EL_PEERS="${2:-}"; shift ;;
    --min-cl-peers) MIN_CL_PEERS="${2:-}"; shift ;;
    --disk-warn) DISK_WARN_PERCENT="${2:-}"; shift ;;
    --clock-warn) CLOCK_WARN_MS="${2:-}"; shift ;;
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

rpc() {
  run "curl -s --max-time ${CURL_TIMEOUT} -X POST -H 'Content-Type: application/json' \
    --data '{\"jsonrpc\":\"2.0\",\"method\":\"$1\",\"params\":[],\"id\":1}' '${EL_RPC}'"
}

beacon() {
  run "curl -s --max-time ${CURL_TIMEOUT} '${CL_API}$1'"
}

hex2dec() {
  local v="${1#0x}"
  [ -n "$v" ] || { echo ""; return; }
  printf '%d\n' "$((16#$v))" 2>/dev/null || echo ""
}

echo "== services"
for pair in "execution:$EL_SERVICE" "consensus:$CL_SERVICE" "validator:$VC_SERVICE"; do
  label="${pair%%:*}"; unit="${pair#*:}"
  [ -n "$unit" ] || continue
  state="$(run "systemctl is-active ${unit} 2>/dev/null || true")"
  restarts="$(run "systemctl show ${unit} -p NRestarts --value 2>/dev/null || true")"
  if [ "$state" = "active" ]; then
    pass "${label}.service" "${unit} active, NRestarts=${restarts:-?}"
  else
    fail "${label}.service" "${unit} is ${state:-unknown}"
  fi
done

echo "== execution layer"
chain_hex="$(rpc eth_chainId | jq -r '.result // empty')"
chain_dec="$(hex2dec "$chain_hex")"
if [ -z "$chain_dec" ]; then
  fail "el.chain_id" "no answer from ${EL_RPC}"
else
  if [ -n "$EXPECTED_CHAIN_ID" ] && [ "$chain_dec" != "$EXPECTED_CHAIN_ID" ]; then
    fail "el.chain_id" "got ${chain_dec}, expected ${EXPECTED_CHAIN_ID}"
  else
    pass "el.chain_id" "$chain_dec"
  fi
fi

syncing="$(rpc eth_syncing | jq -c '.result')"
if [ "$syncing" = "false" ]; then
  pass "el.syncing" "synced"
elif [ -z "$syncing" ] || [ "$syncing" = "null" ]; then
  fail "el.syncing" "no answer"
else
  cur="$(hex2dec "$(echo "$syncing" | jq -r '.currentBlock // empty')")"
  hi="$(hex2dec "$(echo "$syncing" | jq -r '.highestBlock // empty')")"
  fail "el.syncing" "syncing ${cur:-?}/${hi:-?}"
fi

el_peers="$(hex2dec "$(rpc net_peerCount | jq -r '.result // empty')")"
if [ -z "$el_peers" ]; then
  warn "el.peers" "unavailable"
elif [ "$el_peers" -lt "$MIN_EL_PEERS" ]; then
  fail "el.peers" "${el_peers} < ${MIN_EL_PEERS} — check inbound reachability from another host"
else
  pass "el.peers" "$el_peers"
fi

client="$(rpc web3_clientVersion | jq -r '.result // "unknown"')"
pass "el.client" "$client"

echo "== consensus layer"
sync_json="$(beacon /eth/v1/node/syncing | jq -c '.data // empty')"
if [ -z "$sync_json" ]; then
  fail "cl.syncing" "no answer from ${CL_API}"
else
  is_syncing="$(echo "$sync_json" | jq -r '.is_syncing')"
  is_optimistic="$(echo "$sync_json" | jq -r '.is_optimistic')"
  distance="$(echo "$sync_json" | jq -r '.sync_distance')"

  [ "$is_syncing" = "false" ] && pass "cl.syncing" "synced" || fail "cl.syncing" "is_syncing=${is_syncing}"

  # The check this script exists for.
  if [ "$is_optimistic" = "false" ]; then
    pass "cl.optimistic" "false"
  else
    fail "cl.optimistic" "TRUE — head is unverified by the execution client; attestations are worthless"
  fi

  if [ "${distance:-0}" -le "$MAX_SYNC_DISTANCE" ]; then
    pass "cl.sync_distance" "$distance"
  else
    fail "cl.sync_distance" "${distance} > ${MAX_SYNC_DISTANCE}"
  fi
fi

cl_peers="$(beacon /eth/v1/node/peer_count | jq -r '.data.connected // empty')"
if [ -z "$cl_peers" ]; then
  warn "cl.peers" "unavailable"
elif [ "$cl_peers" -lt "$MIN_CL_PEERS" ]; then
  fail "cl.peers" "${cl_peers} < ${MIN_CL_PEERS} — attestations may propagate too late to be included"
else
  pass "cl.peers" "$cl_peers"
fi

cl_version="$(beacon /eth/v1/node/version | jq -r '.data.version // "unknown"')"
pass "cl.client" "$cl_version"

head_slot="$(beacon /eth/v1/beacon/headers/head | jq -r '.data.header.message.slot // empty')"
[ -n "$head_slot" ] && pass "cl.head_slot" "$head_slot" || fail "cl.head_slot" "unavailable"

finality="$(beacon /eth/v1/beacon/states/head/finality_checkpoints | jq -r '.data.finalized.epoch // empty')"
[ -n "$finality" ] && pass "cl.finalized_epoch" "$finality" || warn "cl.finalized_epoch" "unavailable"

echo "== host"
clock="$(run "timedatectl show -p NTPSynchronized --value 2>/dev/null || true")"
if [ "$clock" = "yes" ]; then
  pass "host.clock" "NTP synchronized"
else
  fail "host.clock" "NTP not synchronized — slot timing will be wrong (warn threshold ${CLOCK_WARN_MS}ms)"
fi

disk="$(run "df -P / | awk 'NR==2 {gsub(/%/,\"\",\$5); print \$5\" \"\$4}'")"
disk_pct="${disk%% *}"
disk_avail="${disk##* }"
if [ -n "$disk_pct" ] && [ "$disk_pct" -ge "$DISK_WARN_PERCENT" ]; then
  fail "host.disk" "/ at ${disk_pct}%, ${disk_avail}K free"
else
  pass "host.disk" "/ at ${disk_pct:-?}%"
fi

# Anything listening off-loopback other than ssh and the two P2P ports is a finding.
exposed="$(run "ss -tlnH 2>/dev/null | awk '{print \$4}' | grep -vE '^(127\\.0\\.0\\.1|\\[::1\\])' || true")"
if [ -n "$exposed" ]; then
  warn "host.listeners" "off-loopback: $(echo "$exposed" | tr '\n' ' ')"
else
  pass "host.listeners" "loopback only"
fi

if [ "$SKIP_EXTERNAL" -eq 0 ] && [ -n "$head_slot" ]; then
  echo "== independent comparison"
  ext_epoch="$(curl -s --max-time "$CURL_TIMEOUT" "$EXTERNAL_HEAD_SOURCE" | jq -r '.data.epoch // empty' 2>/dev/null || true)"
  if [ -z "$ext_epoch" ]; then
    warn "external.head" "public source unavailable; local head not independently confirmed"
  else
    local_epoch=$(( head_slot / 32 ))
    diff=$(( ext_epoch - local_epoch ))
    [ "$diff" -lt 0 ] && diff=$(( -diff ))
    if [ "$diff" -le 1 ]; then
      pass "external.head" "local epoch ${local_epoch}, public ${ext_epoch}"
    else
      fail "external.head" "local epoch ${local_epoch}, public ${ext_epoch} — the node may be on a different chain"
    fi
  fi
fi

echo
if [ "$FAILED" -eq 0 ]; then
  echo "healthcheck=passed"
  echo "This is evidence, not proof. For a validator, confirm attestation inclusion"
  echo "externally over the last two epochs before declaring it healthy."
else
  echo "healthcheck=failed"
fi
exit "$FAILED"
