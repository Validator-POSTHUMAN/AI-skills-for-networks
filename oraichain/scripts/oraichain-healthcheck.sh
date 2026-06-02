#!/usr/bin/env bash
set -euo pipefail

HOST=""
LOCAL_MODE=0
SERVICE=""
RPC=""
PUBLIC_RPC=""
VALCONS=""
VALOPER=""
DAEMON="oraid"
EXPECTED_CHAIN_ID=""
DATA_DIR=""
BLOCKS=5
CURL_TIMEOUT=8
MIN_PEERS=1
MAX_BLOCK_LAG=20

usage() {
  cat <<'USAGE'
Usage:
  oraichain-healthcheck.sh [--host <ssh-target>|--local] --rpc <rpc-url> [options]

Options:
  --local                    Run checks on the current host instead of SSH.
  --service <name>           Optional systemd service name.
  --daemon <name>            Chain daemon binary name. Default: oraid.
  --public-rpc <url>         Optional public/reference RPC for height compare.
  --valcons <hex>            Optional consensus address for signing checks.
  --valoper <address>        Optional oraivaloper address for staking status.
  --expected-chain-id <id>   Expected CometBFT network value.
  --data-dir <path>          Optional data directory for disk/inode usage.
  --blocks <n>               Recent blocks to inspect. Default: 5.
  --min-peers <n>            Peer warning threshold. Default: 1.
  --max-block-lag <n>        Public-local height gap warning threshold. Default: 20.
  --curl-timeout <sec>       Per-request curl timeout. Default: 8.

Example:
  oraichain-healthcheck.sh --local --rpc https://rpc.example.net --expected-chain-id Oraichain
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
    --daemon) DAEMON="$2"; shift 2 ;;
    --expected-chain-id) EXPECTED_CHAIN_ID="$2"; shift 2 ;;
    --data-dir) DATA_DIR="$2"; shift 2 ;;
    --blocks) BLOCKS="$2"; shift 2 ;;
    --min-peers) MIN_PEERS="$2"; shift 2 ;;
    --max-block-lag) MAX_BLOCK_LAG="$2"; shift 2 ;;
    --curl-timeout) CURL_TIMEOUT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown_argument=$1" >&2; usage; exit 2 ;;
  esac
done

if [[ -n "$HOST" && "$LOCAL_MODE" == "1" ]]; then
  echo "choose either --host or --local, not both" >&2
  exit 2
fi

if [[ -z "$HOST" && "$LOCAL_MODE" == "0" ]]; then
  LOCAL_MODE=1
fi

if [[ -z "$RPC" ]]; then
  usage >&2
  exit 2
fi

validate_uint() {
  local field="$1"
  local value="$2"
  if ! [[ "$value" =~ ^[0-9]+$ ]]; then
    echo "$field"_must_be_uint="$value" >&2
    exit 2
  fi
}

validate_uint blocks "$BLOCKS"
validate_uint curl_timeout "$CURL_TIMEOUT"
validate_uint min_peers "$MIN_PEERS"
validate_uint max_block_lag "$MAX_BLOCK_LAG"

if [[ "$BLOCKS" -lt 1 || "$CURL_TIMEOUT" -lt 1 ]]; then
  echo "blocks_and_curl_timeout_must_be_positive" >&2
  exit 2
fi

if [[ "$LOCAL_MODE" == "0" ]] && ! command -v ssh >/dev/null 2>&1; then
  echo "missing_required_command=ssh" >&2
  exit 127
fi

REMOTE_SCRIPT="$(cat <<'REMOTE'
set -euo pipefail

SERVICE="$1"; shift
RPC="$1"; shift
PUBLIC_RPC="$1"; shift
VALCONS="$1"; shift
VALOPER="$1"; shift
DAEMON="$1"; shift
EXPECTED_CHAIN_ID="$1"; shift
DATA_DIR="$1"; shift
BLOCKS="$1"; shift
CURL_TIMEOUT="$1"; shift
MIN_PEERS="$1"; shift
MAX_BLOCK_LAG="$1"; shift

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

warn() {
  echo "warning=$1"
}

require_cmd curl
require_cmd jq
require_cmd date

echo "time=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "rpc=$RPC"

if [[ -n "$SERVICE" ]]; then
  echo "service=$(systemctl is-active "$SERVICE" 2>/dev/null || true)"
  echo "enabled=$(systemctl is-enabled "$SERVICE" 2>/dev/null || true)"
  echo "restart_count=$(systemctl show "$SERVICE" -p NRestarts --value 2>/dev/null || true)"
fi

STATUS_JSON="$(fetch_json "$RPC/status")"
HEIGHT="$(printf '%s' "$STATUS_JSON" | jq -r '.result.sync_info.latest_block_height')"
if ! is_uint "$HEIGHT"; then
  echo "height_error=non_numeric_or_missing"
  exit 1
fi

NETWORK="$(printf '%s' "$STATUS_JSON" | jq -r '.result.node_info.network')"
echo "network=$NETWORK"
echo "$STATUS_JSON" | jq -r '
  "height=" + .result.sync_info.latest_block_height,
  "block_time=" + .result.sync_info.latest_block_time,
  "catching_up=" + (.result.sync_info.catching_up|tostring),
  "voting_power=" + .result.validator_info.voting_power'

if [[ -n "$EXPECTED_CHAIN_ID" ]]; then
  if [[ "$NETWORK" == "$EXPECTED_CHAIN_ID" ]]; then
    echo "chain_id_match=true"
  else
    echo "chain_id_match=false"
    warn "unexpected_chain_id"
  fi
fi

if [[ -n "$PUBLIC_RPC" ]]; then
  if PUBLIC_STATUS_JSON="$(fetch_json "$PUBLIC_RPC/status" 2>/dev/null)"; then
    PUBLIC_HEIGHT="$(printf '%s' "$PUBLIC_STATUS_JSON" | jq -r '.result.sync_info.latest_block_height')"
    echo "public_height=$PUBLIC_HEIGHT"
    if is_uint "$PUBLIC_HEIGHT"; then
      GAP=$((PUBLIC_HEIGHT - HEIGHT))
      echo "height_gap=$GAP"
      if [[ "$GAP" -gt "$MAX_BLOCK_LAG" ]]; then
        warn "height_gap_above_threshold"
      fi
    fi
  else
    echo "public_rpc_error=unreachable"
  fi
fi

PEERS="$(fetch_json "$RPC/net_info" | jq -r '.result.n_peers')"
echo "peers=$PEERS"
if is_uint "$PEERS" && [[ "$PEERS" -lt "$MIN_PEERS" ]]; then
  warn "peer_count_below_threshold"
fi

PID="$(pgrep -f "$DAEMON.*start" | head -1 || true)"
BIN="$DAEMON"
if [[ -n "$PID" && -e "/proc/$PID/exe" ]]; then
  BIN="$(readlink -f "/proc/$PID/exe")"
  echo "pid=$PID"
  echo "exe=$BIN"
  echo "version=$("$BIN" version 2>/dev/null || true)"
elif command -v "$DAEMON" >/dev/null 2>&1; then
  echo "pid=missing"
  echo "version=$("$DAEMON" version 2>/dev/null || true)"
else
  echo "pid=missing"
  echo "version=unavailable"
fi

if [[ -n "$DATA_DIR" ]]; then
  if [[ -d "$DATA_DIR" ]]; then
    df -h "$DATA_DIR" | awk 'NR==2 {print "disk_used=" $5, "disk_avail=" $4, "disk_mount=" $6}'
    df -ih "$DATA_DIR" | awk 'NR==2 {print "inode_used=" $5, "inode_avail=" $4}'
  else
    echo "data_dir_missing=$DATA_DIR"
  fi
fi

if [[ -n "$VALCONS" ]]; then
  SIGNED=0
  CHECKED=0
  for ((i=1; i<=BLOCKS; i++)); do
    B=$((HEIGHT-i))
    if [[ "$B" -lt 1 ]]; then
      continue
    fi
    if BLOCK_JSON="$(fetch_json "$RPC/block?height=$B" 2>/dev/null)"; then
      FLAG="$(printf "%s" "$BLOCK_JSON" | jq -r --arg v "$VALCONS" '[.result.block.last_commit.signatures[]? | select(.validator_address==$v) | .block_id_flag][0] // "missing"')"
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

if [[ -n "$VALOPER" ]]; then
  if command -v "$DAEMON" >/dev/null 2>&1; then
    "$DAEMON" query staking validator "$VALOPER" --node "$RPC" -o json 2>/dev/null |
      jq -r '(.validator // .) as $v | "validator_status=" + ($v.status // "unknown"), "jailed=" + (($v.jailed // "unknown")|tostring), "tokens=" + ($v.tokens // "unknown")' || true
  else
    echo "validator_query=skipped_no_binary"
  fi
else
  echo "validator_query=skipped_no_valoper"
fi

if [[ -n "$SERVICE" ]]; then
  echo "recent_errors_begin"
  journalctl -u "$SERVICE" -n 80 --no-pager 2>/dev/null |
    grep -Ei 'panic|fatal|error|failed|timeout|refused|corrupt|no space|oom|evidence|double.sign|bridge|oracle|vrf' |
    tail -20 || true
  echo "recent_errors_end"
fi
REMOTE
)"

if [[ "$LOCAL_MODE" == "1" ]]; then
  bash -s -- "$SERVICE" "$RPC" "$PUBLIC_RPC" "$VALCONS" "$VALOPER" "$DAEMON" "$EXPECTED_CHAIN_ID" "$DATA_DIR" "$BLOCKS" "$CURL_TIMEOUT" "$MIN_PEERS" "$MAX_BLOCK_LAG" <<<"$REMOTE_SCRIPT"
else
  ssh -o BatchMode=yes -o ConnectTimeout=8 "$HOST" bash -s -- "$SERVICE" "$RPC" "$PUBLIC_RPC" "$VALCONS" "$VALOPER" "$DAEMON" "$EXPECTED_CHAIN_ID" "$DATA_DIR" "$BLOCKS" "$CURL_TIMEOUT" "$MIN_PEERS" "$MAX_BLOCK_LAG" <<<"$REMOTE_SCRIPT"
fi
