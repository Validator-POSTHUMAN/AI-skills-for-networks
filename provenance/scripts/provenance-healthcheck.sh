#!/usr/bin/env bash
set -euo pipefail

HOST=""
LOCAL_MODE=0
SERVICE=""
RPC=""
PUBLIC_RPC=""
VALCONS=""
VALOPER=""
EXPECTED_CHAIN_ID="pio-mainnet-1"
DAEMON="provenanced"
BLOCKS=5
CURL_TIMEOUT=8

usage() {
  cat <<'USAGE'
Usage:
  provenance-healthcheck.sh [--host <ssh-target>|--local] --service <service> --rpc <local-rpc>

Example:
  provenance-healthcheck.sh \
    --host <user>@<host> \
    --service <systemd-service> \
    --rpc http://127.0.0.1:<rpc-port> \
    --public-rpc https://<public-rpc> \
    --valcons <HEX_CONSENSUS_ADDRESS> \
    --valoper <pbvaloper...> \
    --expected-chain-id pio-mainnet-1

Options:
  --local                   Run checks on the current host instead of SSH.
  --daemon <name>           Chain daemon binary name. Default: provenanced.
  --expected-chain-id <id>  Expected RPC network field. Default: pio-mainnet-1.
  --public-rpc <url>        Optional public RPC for local/public height compare.
  --valcons <hex>           Optional consensus address for recent signing checks.
  --valoper <address>       Optional valoper address for staking query.
  --blocks <n>              Recent blocks to inspect for signatures. Default: 5.
  --curl-timeout <sec>      Per-request curl timeout. Default: 8.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) HOST="$2"; shift 2 ;;
    --local) LOCAL_MODE=1; shift ;;
    --service) SERVICE="$2"; shift 2 ;;
    --rpc) RPC="$2"; shift 2 ;;
    --public-rpc) PUBLIC_RPC="$2"; shift 2 ;;
    --valcons) VALCONS="$2"; shift 2 ;;
    --valoper) VALOPER="$2"; shift 2 ;;
    --expected-chain-id) EXPECTED_CHAIN_ID="$2"; shift 2 ;;
    --daemon) DAEMON="$2"; shift 2 ;;
    --blocks) BLOCKS="$2"; shift 2 ;;
    --curl-timeout) CURL_TIMEOUT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -n "$HOST" && "$LOCAL_MODE" == "1" ]]; then
  echo "choose either --host or --local, not both" >&2
  exit 2
fi

if [[ -z "$HOST" && "$LOCAL_MODE" == "0" ]]; then
  LOCAL_MODE=1
fi

if [[ -z "$SERVICE" || -z "$RPC" ]]; then
  usage >&2
  exit 2
fi

if ! [[ "$BLOCKS" =~ ^[0-9]+$ ]] || [[ "$BLOCKS" -lt 1 ]]; then
  echo "--blocks must be a positive integer" >&2
  exit 2
fi

if ! [[ "$CURL_TIMEOUT" =~ ^[0-9]+$ ]] || [[ "$CURL_TIMEOUT" -lt 1 ]]; then
  echo "--curl-timeout must be a positive integer" >&2
  exit 2
fi

if [[ "$LOCAL_MODE" == "0" ]] && ! command -v ssh >/dev/null 2>&1; then
  echo "missing required command: ssh" >&2
  exit 127
fi

REMOTE_SCRIPT="$(cat <<'REMOTE'
set -euo pipefail

SERVICE="$1"
RPC="$2"
VALCONS="$3"
VALOPER="$4"
PUBLIC_RPC="$5"
DAEMON="$6"
BLOCKS="$7"
CURL_TIMEOUT="$8"
EXPECTED_CHAIN_ID="$9"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing_required_command=$1"
    exit 127
  fi
}

fetch_json() {
  curl -fsS --max-time "$CURL_TIMEOUT" --retry 1 --retry-delay 1 "$1"
}

is_uint() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

require_cmd curl
require_cmd jq
require_cmd date

echo "time=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "service=$(systemctl is-active "$SERVICE" 2>/dev/null || true)"
echo "enabled=$(systemctl is-enabled "$SERVICE" 2>/dev/null || true)"

STATUS_JSON="$(fetch_json "$RPC/status")"
CHAIN_ID="$(printf '%s' "$STATUS_JSON" | jq -r '.result.node_info.network')"
HEIGHT="$(printf '%s' "$STATUS_JSON" | jq -r '.result.sync_info.latest_block_height')"
if ! is_uint "$HEIGHT"; then
  echo "height_error=non_numeric_or_missing"
  exit 1
fi

echo "chain_id=$CHAIN_ID"
if [[ -n "$EXPECTED_CHAIN_ID" && "$CHAIN_ID" != "$EXPECTED_CHAIN_ID" ]]; then
  echo "chain_id_mismatch=expected_${EXPECTED_CHAIN_ID}_got_${CHAIN_ID}"
fi

echo "$STATUS_JSON" | jq -r '
  "height=" + .result.sync_info.latest_block_height,
  "block_time=" + .result.sync_info.latest_block_time,
  "catching_up=" + (.result.sync_info.catching_up|tostring),
  "voting_power=" + .result.validator_info.voting_power'

if [[ -n "$PUBLIC_RPC" ]]; then
  if PUBLIC_STATUS_JSON="$(fetch_json "$PUBLIC_RPC/status" 2>/dev/null)"; then
    PUBLIC_CHAIN_ID="$(printf '%s' "$PUBLIC_STATUS_JSON" | jq -r '.result.node_info.network')"
    PUBLIC_HEIGHT="$(printf '%s' "$PUBLIC_STATUS_JSON" | jq -r '.result.sync_info.latest_block_height')"
    echo "public_chain_id=$PUBLIC_CHAIN_ID"
    echo "public_height=$PUBLIC_HEIGHT"
    if is_uint "$PUBLIC_HEIGHT"; then
      echo "height_gap=$((PUBLIC_HEIGHT - HEIGHT))"
    fi
  else
    echo "public_rpc_error=unreachable"
  fi
fi

PID="$(pgrep -f "${DAEMON}.*start" | head -1 || true)"
BIN="$DAEMON"
if [[ -n "$PID" && -e "/proc/$PID/exe" ]]; then
  BIN="$(readlink -f "/proc/$PID/exe")"
  echo "pid=$PID"
  echo "exe=$BIN"
  echo "version=$("$BIN" version --long 2>/dev/null || "$BIN" version 2>/dev/null || true)"
else
  echo "pid=missing"
fi

echo "peers=$(fetch_json "$RPC/net_info" | jq -r '.result.n_peers')"

if [[ -n "$VALCONS" ]]; then
  SIGNED=0
  CHECKED=0
  for ((i=1; i<=BLOCKS; i++)); do
    B=$((HEIGHT-i))
    if [[ "$B" -lt 1 ]]; then
      continue
    fi
    if BLOCK_JSON="$(fetch_json "$RPC/block?height=$B" 2>/dev/null)"; then
      FLAG="$(printf "%s" "$BLOCK_JSON" |
        jq -r --arg v "$VALCONS" '[.result.block.last_commit.signatures[]? |
          select(.validator_address==$v) | .block_id_flag][0] // "missing"')"
    else
      FLAG="query_error"
    fi
    echo "signed_$B=$FLAG"
    CHECKED=$((CHECKED+1))
    if [[ "$FLAG" == "2" || "$FLAG" == "BLOCK_ID_FLAG_COMMIT" ]]; then
      SIGNED=$((SIGNED+1))
    fi
  done
  echo "recent_signing=$SIGNED/$CHECKED"
else
  echo "recent_signing=skipped_no_valcons"
fi

QUERY_BIN=""
if [[ -x "$BIN" && "$(basename "$BIN")" == "$DAEMON" ]]; then
  QUERY_BIN="$BIN"
elif command -v "$DAEMON" >/dev/null 2>&1; then
  QUERY_BIN="$DAEMON"
fi

if [[ -n "$VALOPER" && -n "$QUERY_BIN" ]]; then
  "$QUERY_BIN" query staking validator "$VALOPER" --node "$RPC" -o json 2>/dev/null |
    jq -r '(.validator // .) as $v | "validator_status=" + ($v.status // "unknown"), "jailed=" + (($v.jailed // "unknown")|tostring), "tokens=" + ($v.tokens // "unknown")' || true
elif [[ -z "$VALOPER" ]]; then
  echo "validator_query=skipped_no_valoper"
else
  echo "validator_query=skipped_no_${DAEMON}_binary"
fi

echo "disk_root=$(df -h / | awk 'NR==2 {print $5}')"
echo "inode_root=$(df -ih / | awk 'NR==2 {print $5}')"
REMOTE
)"

if [[ "$LOCAL_MODE" == "1" ]]; then
  bash -s -- "$SERVICE" "$RPC" "$VALCONS" "$VALOPER" "$PUBLIC_RPC" "$DAEMON" "$BLOCKS" "$CURL_TIMEOUT" "$EXPECTED_CHAIN_ID" <<<"$REMOTE_SCRIPT"
else
  ssh -o BatchMode=yes -o ConnectTimeout=8 "$HOST" bash -s -- "$SERVICE" "$RPC" "$VALCONS" "$VALOPER" "$PUBLIC_RPC" "$DAEMON" "$BLOCKS" "$CURL_TIMEOUT" "$EXPECTED_CHAIN_ID" <<<"$REMOTE_SCRIPT"
fi
