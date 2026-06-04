#!/usr/bin/env bash
set -euo pipefail

HOST=""
LOCAL_MODE=0
SERVICE=""
RPC=""
PUBLIC_RPC=""
VALCONS=""
VALCONS_BECH32=""
VALOPER=""
DAEMON="gaiad"
HOME_DIR=""
EXPECTED_CHAIN_ID="cosmoshub-4"
BLOCKS=5
CURL_TIMEOUT=8
LOG_MINUTES=15

usage() {
  cat <<'USAGE'
Usage:
  cosmoshub-healthcheck.sh [--host <ssh-target>|--local] --service <service> --rpc <local-rpc> [--valcons <hex-address>] [--valoper <cosmosvaloper...>]

Example:
  cosmoshub-healthcheck.sh \
    --host <user>@<host> \
    --service gaiad \
    --rpc http://127.0.0.1:26657 \
    --public-rpc https://<reference-rpc> \
    --valcons <HEX_CONSENSUS_ADDRESS> \
    --valcons-bech32 <cosmosvalcons...> \
    --valoper <cosmosvaloper...>

Options:
  --local                       Run checks on the current host instead of SSH.
  --daemon <name>               Chain daemon binary name. Default: gaiad.
  --home <path>                 Gaia home directory for CLI queries.
  --expected-chain-id <id>      Expected chain ID. Default: cosmoshub-4.
  --public-rpc <url>            Optional public/reference RPC for height compare.
  --blocks <n>                  Recent blocks to inspect for signatures. Default: 5.
  --curl-timeout <sec>          Per-request curl timeout. Default: 8.
  --log-minutes <n>             Journal window for error counts. Default: 15.
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
    --valcons-bech32) VALCONS_BECH32="$2"; shift 2 ;;
    --valoper) VALOPER="$2"; shift 2 ;;
    --daemon) DAEMON="$2"; shift 2 ;;
    --home) HOME_DIR="$2"; shift 2 ;;
    --expected-chain-id) EXPECTED_CHAIN_ID="$2"; shift 2 ;;
    --blocks) BLOCKS="$2"; shift 2 ;;
    --curl-timeout) CURL_TIMEOUT="$2"; shift 2 ;;
    --log-minutes) LOG_MINUTES="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown_arg=$1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "$SERVICE" || -z "$RPC" ]]; then
  usage >&2
  exit 2
fi
if [[ "$LOCAL_MODE" -eq 0 && -z "$HOST" ]]; then
  echo "error=provide --host or --local" >&2
  exit 2
fi
if [[ "$LOCAL_MODE" -eq 1 && -n "$HOST" ]]; then
  echo "error=use either --host or --local, not both" >&2
  exit 2
fi

REMOTE_SCRIPT='
set -euo pipefail

SERVICE="$1"; shift
RPC="$1"; shift
PUBLIC_RPC="$1"; shift
VALCONS="$1"; shift
VALCONS_BECH32="$1"; shift
VALOPER="$1"; shift
DAEMON="$1"; shift
HOME_DIR="$1"; shift
EXPECTED_CHAIN_ID="$1"; shift
BLOCKS="$1"; shift
CURL_TIMEOUT="$1"; shift
LOG_MINUTES="$1"; shift

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

count_pattern() {
  local pattern="$1"
  local input="$2"
  printf "%s\n" "$input" | grep -Eic "$pattern" || true
}

require_cmd curl
require_cmd jq
require_cmd date

echo "time=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "service=$(systemctl is-active "$SERVICE" 2>/dev/null || true)"
echo "service_enabled=$(systemctl is-enabled "$SERVICE" 2>/dev/null || true)"

STATUS_JSON="$(fetch_json "$RPC/status")"
CHAIN_ID="$(printf "%s" "$STATUS_JSON" | jq -r ".result.node_info.network // empty")"
HEIGHT="$(printf "%s" "$STATUS_JSON" | jq -r ".result.sync_info.latest_block_height // empty")"
if ! is_uint "$HEIGHT"; then
  echo "height_error=non_numeric_or_missing"
  exit 1
fi

printf "%s" "$STATUS_JSON" | jq -r "
  \"chain_id=\" + (.result.node_info.network // \"unknown\"),
  \"height=\" + .result.sync_info.latest_block_height,
  \"block_time=\" + .result.sync_info.latest_block_time,
  \"catching_up=\" + (.result.sync_info.catching_up|tostring),
  \"voting_power=\" + .result.validator_info.voting_power"

if [[ -n "$EXPECTED_CHAIN_ID" && "$CHAIN_ID" != "$EXPECTED_CHAIN_ID" ]]; then
  echo "chain_id_mismatch=expected:$EXPECTED_CHAIN_ID actual:$CHAIN_ID"
fi

if [[ -n "$PUBLIC_RPC" ]]; then
  if PUBLIC_STATUS_JSON="$(fetch_json "$PUBLIC_RPC/status" 2>/dev/null)"; then
    PUBLIC_HEIGHT="$(printf "%s" "$PUBLIC_STATUS_JSON" | jq -r ".result.sync_info.latest_block_height // empty")"
    PUBLIC_CHAIN_ID="$(printf "%s" "$PUBLIC_STATUS_JSON" | jq -r ".result.node_info.network // empty")"
    echo "public_chain_id=$PUBLIC_CHAIN_ID"
    echo "public_height=$PUBLIC_HEIGHT"
    if is_uint "$PUBLIC_HEIGHT"; then
      echo "height_gap=$((PUBLIC_HEIGHT - HEIGHT))"
    fi
  else
    echo "public_rpc_error=unreachable"
  fi
fi

echo "peers=$(fetch_json "$RPC/net_info" | jq -r ".result.n_peers // \"unknown\"")"

PID="$(pgrep -f "$DAEMON.*start" | head -1 || true)"
COSMOVISOR_PID="$(pgrep -f "cosmovisor.*run start" | head -1 || true)"
BIN=""
if [[ -n "$PID" && -e "/proc/$PID/exe" ]]; then
  BIN="$(readlink -f "/proc/$PID/exe")"
  echo "node_pid=$PID"
  echo "node_exe=$BIN"
elif [[ -n "$COSMOVISOR_PID" && -e "/proc/$COSMOVISOR_PID/exe" ]]; then
  echo "cosmovisor_pid=$COSMOVISOR_PID"
  echo "cosmovisor_exe=$(readlink -f "/proc/$COSMOVISOR_PID/exe")"
fi

if [[ -n "$BIN" && -x "$BIN" ]]; then
  echo "node_version=$("$BIN" version 2>/dev/null || true)"
  "$BIN" version --long 2>/dev/null | sed "s/^/node_version_long=/" || true
elif command -v "$DAEMON" >/dev/null 2>&1; then
  echo "node_version=$("$DAEMON" version 2>/dev/null || true)"
  "$DAEMON" version --long 2>/dev/null | sed "s/^/node_version_long=/" || true
else
  echo "node_binary=not_found_in_path"
fi

if [[ -n "$HOME_DIR" ]]; then
  df -h "$HOME_DIR" 2>/dev/null | awk "NR==2 {print \"home_disk_used=\" \$5, \"home_disk_avail=\" \$4}" || true
fi
df -h / 2>/dev/null | awk "NR==2 {print \"root_disk_used=\" \$5, \"root_disk_avail=\" \$4}" || true

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
        jq -r --arg v "$VALCONS" "[.result.block.last_commit.signatures[]? |
          select(.validator_address==\$v) | .block_id_flag][0] // \"missing\"")"
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
  echo "recent_signing=skipped_missing_valcons_hex"
fi

QUERY_BIN=""
if [[ -n "$BIN" && -x "$BIN" && "$(basename "$BIN")" == "$DAEMON" ]]; then
  QUERY_BIN="$BIN"
elif command -v "$DAEMON" >/dev/null 2>&1; then
  QUERY_BIN="$DAEMON"
fi

if [[ -n "$QUERY_BIN" ]]; then
  if [[ -n "$VALOPER" ]]; then
    if [[ -n "$HOME_DIR" ]]; then
      "$QUERY_BIN" query staking validator "$VALOPER" --node "$RPC" --home "$HOME_DIR" -o json 2>/dev/null |
        jq -r "(.validator // .) as \$v | \"validator_status=\" + (\$v.status // \"unknown\"), \"jailed=\" + ((\$v.jailed // \"unknown\")|tostring), \"tokens=\" + (\$v.tokens // \"unknown\")" || true
    else
      "$QUERY_BIN" query staking validator "$VALOPER" --node "$RPC" -o json 2>/dev/null |
        jq -r "(.validator // .) as \$v | \"validator_status=\" + (\$v.status // \"unknown\"), \"jailed=\" + ((\$v.jailed // \"unknown\")|tostring), \"tokens=\" + (\$v.tokens // \"unknown\")" || true
    fi
  else
    echo "validator_query=skipped_missing_valoper"
  fi

  if [[ -n "$VALCONS_BECH32" ]]; then
    if [[ -n "$HOME_DIR" ]]; then
      "$QUERY_BIN" query slashing signing-info "$VALCONS_BECH32" --node "$RPC" --home "$HOME_DIR" -o json 2>/dev/null |
        jq -r "\"signing_info=\" + (.|tostring)" || true
    else
      "$QUERY_BIN" query slashing signing-info "$VALCONS_BECH32" --node "$RPC" -o json 2>/dev/null |
        jq -r "\"signing_info=\" + (.|tostring)" || true
    fi
  else
    echo "signing_info=skipped_missing_valcons_bech32"
  fi

  if [[ -n "$HOME_DIR" ]]; then
    "$QUERY_BIN" query upgrade plan --node "$RPC" --home "$HOME_DIR" -o json 2>/dev/null |
      jq -r "\"upgrade_plan=\" + ((.plan // .) | tostring)" || true

    "$QUERY_BIN" query provider list-consumer-chains --node "$RPC" --home "$HOME_DIR" -o json 2>/dev/null |
      jq -r "\"consumer_chains=\" + (.|tostring)" || true
  else
    "$QUERY_BIN" query upgrade plan --node "$RPC" -o json 2>/dev/null |
      jq -r "\"upgrade_plan=\" + ((.plan // .) | tostring)" || true

    "$QUERY_BIN" query provider list-consumer-chains --node "$RPC" -o json 2>/dev/null |
      jq -r "\"consumer_chains=\" + (.|tostring)" || true
  fi
else
  echo "cli_queries=skipped_missing_daemon"
fi

if LOGS="$(journalctl -u "$SERVICE" --since "$LOG_MINUTES minutes ago" --no-pager 2>/dev/null | tail -300)"; then
  echo "recent_log_lines=$(printf "%s\n" "$LOGS" | wc -l | tr -d " ")"
  echo "recent_log_errors=$(count_pattern "panic|fatal|error|failed|app hash|consensus failure|out of memory|no space left|too many open files|dial tcp|connection refused" "$LOGS")"
else
  echo "recent_logs=unavailable"
fi
'

if [[ "$LOCAL_MODE" -eq 1 ]]; then
  bash -s -- "$SERVICE" "$RPC" "$PUBLIC_RPC" "$VALCONS" "$VALCONS_BECH32" "$VALOPER" "$DAEMON" "$HOME_DIR" "$EXPECTED_CHAIN_ID" "$BLOCKS" "$CURL_TIMEOUT" "$LOG_MINUTES" <<<"$REMOTE_SCRIPT"
else
  ssh -o BatchMode=yes -o ConnectTimeout=10 "$HOST" bash -s -- "$SERVICE" "$RPC" "$PUBLIC_RPC" "$VALCONS" "$VALCONS_BECH32" "$VALOPER" "$DAEMON" "$HOME_DIR" "$EXPECTED_CHAIN_ID" "$BLOCKS" "$CURL_TIMEOUT" "$LOG_MINUTES" <<<"$REMOTE_SCRIPT"
fi
