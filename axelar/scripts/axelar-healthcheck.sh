#!/usr/bin/env bash
set -euo pipefail

HOST=""
LOCAL_MODE=0
NODE_SERVICE=""
VALD_SERVICE=""
TOFND_SERVICE=""
RPC=""
PUBLIC_RPC=""
EXPECTED_CHAIN_ID=""
VALCONS=""
VALOPER=""
BROADCASTER=""
DAEMON="axelard"
HOME_DIR=""
TOFND_HOST="127.0.0.1"
TOFND_PORT="50051"
BLOCKS=5
CURL_TIMEOUT=8
MIN_BROADCASTER_UAXL=5000000
VALD_LOG_MINUTES=15
MAX_BLOCK_AGE_SECONDS=15
MAINTAINER_CHAINS=()

usage() {
  cat <<'USAGE'
Usage:
  axelar-healthcheck.sh [--host <ssh-target>|--local] --node-service <service> --rpc <local-rpc> --valcons <hex-address> --valoper <axelarvaloper> --broadcaster <axelar1...>

Example:
  axelar-healthcheck.sh \
    --host <user>@<host> \
    --node-service axelard \
    --vald-service axelar-vald \
    --tofnd-service tofnd \
    --rpc http://127.0.0.1:<rpc-port> \
    --expected-chain-id axelar-dojo-1 \
    --valcons <HEX_CONSENSUS_ADDRESS> \
    --valoper <axelarvaloper...> \
    --broadcaster <axelar1...> \
    --public-rpc https://<public-rpc> \
    --maintainer-chain ethereum \
    --maintainer-chain avalanche

Options:
  --local                       Run checks on the current host instead of SSH.
  --daemon <name>               Chain daemon binary name. Default: axelard.
  --home <path>                 Axelar home directory for CLI queries.
  --tofnd-host <host>           Host used by axelard health-check. Default: 127.0.0.1.
  --tofnd-port <port>           Tofnd gRPC port. Default: 50051.
  --public-rpc <url>            Optional public RPC for local/public height compare.
  --expected-chain-id <id>      Fail if local RPC reports a different chain ID.
  --blocks <n>                  Recent blocks to inspect for signatures. Default: 5.
  --curl-timeout <sec>          Per-request curl timeout. Default: 8.
  --min-broadcaster-uaxl <n>    Minimum broadcaster balance. Default: 5000000 (5 AXL).
  --vald-log-minutes <n>        Vald journal window for error counts. Default: 15.
  --max-block-age-seconds <n>   Fail when latest block is older. Default: 15.
  --maintainer-chain <name>     External chain expected to be maintained. Repeatable.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) HOST="$2"; shift 2 ;;
    --local) LOCAL_MODE=1; shift ;;
    --node-service) NODE_SERVICE="$2"; shift 2 ;;
    --vald-service) VALD_SERVICE="$2"; shift 2 ;;
    --tofnd-service) TOFND_SERVICE="$2"; shift 2 ;;
    --rpc) RPC="$2"; shift 2 ;;
    --public-rpc) PUBLIC_RPC="$2"; shift 2 ;;
    --expected-chain-id) EXPECTED_CHAIN_ID="$2"; shift 2 ;;
    --valcons) VALCONS="$2"; shift 2 ;;
    --valoper) VALOPER="$2"; shift 2 ;;
    --broadcaster) BROADCASTER="$2"; shift 2 ;;
    --daemon) DAEMON="$2"; shift 2 ;;
    --home) HOME_DIR="$2"; shift 2 ;;
    --tofnd-host) TOFND_HOST="$2"; shift 2 ;;
    --tofnd-port) TOFND_PORT="$2"; shift 2 ;;
    --blocks) BLOCKS="$2"; shift 2 ;;
    --curl-timeout) CURL_TIMEOUT="$2"; shift 2 ;;
    --min-broadcaster-uaxl) MIN_BROADCASTER_UAXL="$2"; shift 2 ;;
    --vald-log-minutes) VALD_LOG_MINUTES="$2"; shift 2 ;;
    --max-block-age-seconds) MAX_BLOCK_AGE_SECONDS="$2"; shift 2 ;;
    --maintainer-chain) MAINTAINER_CHAINS+=("$2"); shift 2 ;;
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

if [[ -z "$NODE_SERVICE" || -z "$RPC" || -z "$VALCONS" || -z "$VALOPER" || -z "$BROADCASTER" ]]; then
  usage >&2
  exit 2
fi

for n in "$BLOCKS" "$CURL_TIMEOUT" "$MIN_BROADCASTER_UAXL" "$VALD_LOG_MINUTES" "$MAX_BLOCK_AGE_SECONDS" "$TOFND_PORT"; do
  if ! [[ "$n" =~ ^[0-9]+$ ]] || [[ "$n" -lt 1 ]]; then
    echo "numeric options must be positive integers" >&2
    exit 2
  fi
done

if [[ "$LOCAL_MODE" == "0" ]] && ! command -v ssh >/dev/null 2>&1; then
  echo "missing required command: ssh" >&2
  exit 127
fi
if ! command -v base64 >/dev/null 2>&1; then
  echo "missing required command: base64" >&2
  exit 127
fi

CHAIN_LIST=""
if [[ "${#MAINTAINER_CHAINS[@]}" -gt 0 ]]; then
  CHAIN_LIST="$(printf '%s\n' "${MAINTAINER_CHAINS[@]}")"
fi

EMPTY_ARG="__AXELAR_EMPTY__"
VALD_SERVICE_ARG="${VALD_SERVICE:-$EMPTY_ARG}"
TOFND_SERVICE_ARG="${TOFND_SERVICE:-$EMPTY_ARG}"
PUBLIC_RPC_ARG="${PUBLIC_RPC:-$EMPTY_ARG}"
HOME_DIR_ARG="${HOME_DIR:-$EMPTY_ARG}"
CHAIN_LIST_ARG="${CHAIN_LIST//$'\n'/,}"
CHAIN_LIST_ARG="${CHAIN_LIST_ARG%,}"
CHAIN_LIST_ARG="${CHAIN_LIST_ARG:-$EMPTY_ARG}"

ARGS_PAYLOAD="$(
  printf '%s\0' \
    "$NODE_SERVICE" \
    "$VALD_SERVICE_ARG" \
    "$TOFND_SERVICE_ARG" \
    "$RPC" \
    "$VALCONS" \
    "$VALOPER" \
    "$BROADCASTER" \
    "$PUBLIC_RPC_ARG" \
    "$DAEMON" \
    "$HOME_DIR_ARG" \
    "$TOFND_HOST" \
    "$TOFND_PORT" \
    "$BLOCKS" \
    "$CURL_TIMEOUT" \
    "$MIN_BROADCASTER_UAXL" \
    "$VALD_LOG_MINUTES" \
    "$MAX_BLOCK_AGE_SECONDS" \
    "$CHAIN_LIST_ARG" \
    "${EXPECTED_CHAIN_ID:-$EMPTY_ARG}" |
    base64 -w0
)"

REMOTE_SCRIPT="$(cat <<'REMOTE'
set -euo pipefail

if ! command -v base64 >/dev/null 2>&1; then
  echo "missing_required_command=base64"
  exit 127
fi

mapfile -d '' -t ARGS < <(printf '%s' "$1" | base64 --decode)
if [[ "${#ARGS[@]}" -ne 19 ]]; then
  echo "argument_payload_error=expected_19_fields_got_${#ARGS[@]}"
  exit 2
fi

empty_to_blank() {
  if [[ "$1" == "__AXELAR_EMPTY__" ]]; then
    printf ''
  else
    printf '%s' "$1"
  fi
}

NODE_SERVICE="${ARGS[0]}"
VALD_SERVICE="$(empty_to_blank "${ARGS[1]}")"
TOFND_SERVICE="$(empty_to_blank "${ARGS[2]}")"
RPC="${ARGS[3]}"
VALCONS="${ARGS[4]}"
VALOPER="${ARGS[5]}"
BROADCASTER="${ARGS[6]}"
PUBLIC_RPC="$(empty_to_blank "${ARGS[7]}")"
DAEMON="${ARGS[8]}"
HOME_DIR="$(empty_to_blank "${ARGS[9]}")"
TOFND_HOST="${ARGS[10]}"
TOFND_PORT="${ARGS[11]}"
BLOCKS="${ARGS[12]}"
CURL_TIMEOUT="${ARGS[13]}"
MIN_BROADCASTER_UAXL="${ARGS[14]}"
VALD_LOG_MINUTES="${ARGS[15]}"
MAX_BLOCK_AGE_SECONDS="${ARGS[16]}"
CHAIN_LIST_CSV="$(empty_to_blank "${ARGS[17]}")"
CHAIN_LIST="${CHAIN_LIST_CSV//,/$'\n'}"
EXPECTED_CHAIN_ID="$(empty_to_blank "${ARGS[18]}")"
FAILURES=0

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

cli_args() {
  if [[ -n "$HOME_DIR" ]]; then
    printf '%s\n' --home "$HOME_DIR"
  fi
}

count_pattern() {
  local pattern="$1"
  local input="$2"
  printf '%s\n' "$input" | grep -Eic "$pattern" || true
}

require_cmd curl
require_cmd jq
require_cmd date
require_cmd timeout

echo "time=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
NODE_STATE="$(systemctl is-active "$NODE_SERVICE" 2>/dev/null || true)"
echo "node_service=$NODE_STATE"
echo "node_enabled=$(systemctl is-enabled "$NODE_SERVICE" 2>/dev/null || true)"
[[ "$NODE_STATE" == "active" ]] || FAILURES=$((FAILURES+1))
if [[ -n "$VALD_SERVICE" ]]; then
  VALD_STATE="$(systemctl is-active "$VALD_SERVICE" 2>/dev/null || true)"
  echo "vald_service=$VALD_STATE"
  echo "vald_enabled=$(systemctl is-enabled "$VALD_SERVICE" 2>/dev/null || true)"
  [[ "$VALD_STATE" == "active" ]] || FAILURES=$((FAILURES+1))
fi
if [[ -n "$TOFND_SERVICE" ]]; then
  TOFND_STATE="$(systemctl is-active "$TOFND_SERVICE" 2>/dev/null || true)"
  echo "tofnd_service=$TOFND_STATE"
  echo "tofnd_enabled=$(systemctl is-enabled "$TOFND_SERVICE" 2>/dev/null || true)"
  [[ "$TOFND_STATE" == "active" ]] || FAILURES=$((FAILURES+1))
  if timeout "$CURL_TIMEOUT" bash -c \
    'exec 3<>"/dev/tcp/$1/$2"' bash "$TOFND_HOST" "$TOFND_PORT" 2>/dev/null; then
    echo "tofnd_tcp=reachable"
  else
    echo "tofnd_tcp=unreachable"
    FAILURES=$((FAILURES+1))
  fi
fi

STATUS_JSON="$(fetch_json "$RPC/status")"
CHAIN_ID="$(printf '%s' "$STATUS_JSON" | jq -r '.result.node_info.network // empty')"
HEIGHT="$(printf '%s' "$STATUS_JSON" | jq -r '.result.sync_info.latest_block_height')"
if ! is_uint "$HEIGHT"; then
  echo "height_error=non_numeric_or_missing"
  exit 1
fi

echo "chain_id=$CHAIN_ID"
if [[ -n "$EXPECTED_CHAIN_ID" ]]; then
  if [[ "$CHAIN_ID" == "$EXPECTED_CHAIN_ID" ]]; then
    echo "chain_id_status=ok"
  else
    echo "chain_id_status=mismatch"
    FAILURES=$((FAILURES+1))
  fi
fi
echo "$STATUS_JSON" | jq -r '
  "height=" + .result.sync_info.latest_block_height,
  "block_time=" + .result.sync_info.latest_block_time,
  "catching_up=" + (.result.sync_info.catching_up|tostring),
  "voting_power=" + .result.validator_info.voting_power'
CATCHING_UP="$(printf '%s' "$STATUS_JSON" | jq -r '.result.sync_info.catching_up')"
[[ "$CATCHING_UP" == "false" ]] || FAILURES=$((FAILURES+1))

BLOCK_TIME="$(printf '%s' "$STATUS_JSON" | jq -r '.result.sync_info.latest_block_time')"
NOW_EPOCH="$(date -u +%s)"
if BLOCK_EPOCH="$(date -u -d "$BLOCK_TIME" +%s 2>/dev/null)"; then
  BLOCK_AGE_SECONDS=$((NOW_EPOCH - BLOCK_EPOCH))
  echo "block_age_seconds=$BLOCK_AGE_SECONDS"
  if [[ "$BLOCK_AGE_SECONDS" -gt "$MAX_BLOCK_AGE_SECONDS" ]]; then
    echo "consensus_freshness=stale"
    FAILURES=$((FAILURES+1))
  elif [[ "$BLOCK_AGE_SECONDS" -lt "-$MAX_BLOCK_AGE_SECONDS" ]]; then
    echo "consensus_freshness=clock_skew"
    FAILURES=$((FAILURES+1))
  else
    echo "consensus_freshness=fresh"
  fi
else
  echo "consensus_freshness=invalid_block_time"
  FAILURES=$((FAILURES+1))
fi

if [[ -n "$PUBLIC_RPC" ]]; then
  if PUBLIC_STATUS_JSON="$(fetch_json "$PUBLIC_RPC/status" 2>/dev/null)"; then
    PUBLIC_HEIGHT="$(printf '%s' "$PUBLIC_STATUS_JSON" | jq -r '.result.sync_info.latest_block_height')"
    PUBLIC_BLOCK_TIME="$(printf '%s' "$PUBLIC_STATUS_JSON" | jq -r '.result.sync_info.latest_block_time')"
    echo "public_height=$PUBLIC_HEIGHT"
    if is_uint "$PUBLIC_HEIGHT"; then
      echo "height_gap=$((PUBLIC_HEIGHT - HEIGHT))"
    fi
    if PUBLIC_BLOCK_EPOCH="$(date -u -d "$PUBLIC_BLOCK_TIME" +%s 2>/dev/null)"; then
      PUBLIC_BLOCK_AGE_SECONDS=$((NOW_EPOCH - PUBLIC_BLOCK_EPOCH))
      echo "public_block_age_seconds=$PUBLIC_BLOCK_AGE_SECONDS"
      if [[ "$PUBLIC_BLOCK_AGE_SECONDS" -gt "$MAX_BLOCK_AGE_SECONDS" ]]; then
        echo "public_consensus_freshness=stale"
      elif [[ "$PUBLIC_BLOCK_AGE_SECONDS" -lt "-$MAX_BLOCK_AGE_SECONDS" ]]; then
        echo "public_consensus_freshness=clock_skew"
      else
        echo "public_consensus_freshness=fresh"
      fi
    else
      echo "public_consensus_freshness=invalid_block_time"
    fi
  else
    echo "public_rpc_error=unreachable"
  fi
fi

PID="$(pgrep -f "${DAEMON}.*start" | grep -v "vald-start" | head -1 || true)"
BIN="$DAEMON"
if [[ -n "$PID" && -e "/proc/$PID/exe" ]]; then
  BIN="$(readlink -f "/proc/$PID/exe")"
  echo "node_pid=$PID"
  echo "node_exe=$BIN"
  echo "node_version=$("$BIN" version 2>/dev/null || true)"
else
  echo "node_pid=missing"
fi

VALD_PID="$(pgrep -f "${DAEMON} vald-start" | head -1 || true)"
echo "vald_pid=${VALD_PID:-missing}"
TOFND_PID="$(pgrep -f "tofnd" | head -1 || true)"
echo "tofnd_pid=${TOFND_PID:-missing}"

PEERS="$(fetch_json "$RPC/net_info" | jq -r '.result.n_peers')"
echo "peers=$PEERS"
if is_uint "$PEERS" && [[ "$PEERS" -eq 0 ]]; then
  FAILURES=$((FAILURES+1))
fi

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
if [[ "$CHECKED" -gt 0 && "$SIGNED" -eq 0 ]]; then
  FAILURES=$((FAILURES+1))
fi

QUERY_BIN=""
if [[ -x "$BIN" && "$(basename "$BIN")" == "$DAEMON" ]]; then
  QUERY_BIN="$BIN"
elif command -v "$DAEMON" >/dev/null 2>&1; then
  QUERY_BIN="$DAEMON"
fi

if [[ -n "$QUERY_BIN" ]]; then
  mapfile -t HOME_FLAGS < <(cli_args)

  if VALIDATOR_JSON="$("$QUERY_BIN" query staking validator "$VALOPER" --node "$RPC" -o json "${HOME_FLAGS[@]}" 2>/dev/null)"; then
    VALIDATOR_STATUS="$(printf '%s' "$VALIDATOR_JSON" | jq -r '(.validator // .).status // "unknown"')"
    VALIDATOR_TOKENS="$(printf '%s' "$VALIDATOR_JSON" | jq -r '(.validator // .).tokens // "unknown"')"
    echo "validator_status=$VALIDATOR_STATUS"
    echo "tokens=$VALIDATOR_TOKENS"
    if [[ "$VALIDATOR_STATUS" != "BOND_STATUS_BONDED" && "$VALIDATOR_STATUS" != "3" ]]; then
      echo "validator_bond_status=failed"
      FAILURES=$((FAILURES+1))
    fi
  else
    echo "validator_query=failed"
    FAILURES=$((FAILURES+1))
  fi

  if HEALTH_OUTPUT="$("$QUERY_BIN" health-check --tofnd-host "$TOFND_HOST" --tofnd-port "$TOFND_PORT" --operator-addr "$VALOPER" --node "$RPC" "${HOME_FLAGS[@]}" 2>&1)"; then
    echo "health_check=ok"
    printf '%s\n' "$HEALTH_OUTPUT" | sed 's/^/health_check_output=/'
  elif [[ "$HEALTH_OUTPUT" == *"cannot parse 'axelar_bridge_evm["*".finality_override' as int"* ]]; then
    echo "health_check_tofnd=compatibility_fallback_for_config_decode_bug"
    if FALLBACK_OUTPUT="$("$QUERY_BIN" health-check --skip-tofnd --operator-addr "$VALOPER" --node "$RPC" "${HOME_FLAGS[@]}" 2>&1)"; then
      echo "health_check=ok_with_tofnd_tcp_fallback"
      printf '%s\n' "$FALLBACK_OUTPUT" | sed 's/^/health_check_output=/'
    else
      echo "health_check=failed"
      printf '%s\n' "$FALLBACK_OUTPUT" | sed 's/^/health_check_output=/'
      FAILURES=$((FAILURES+1))
    fi
  else
    echo "health_check=failed"
    printf '%s\n' "$HEALTH_OUTPUT" | sed 's/^/health_check_output=/'
    FAILURES=$((FAILURES+1))
  fi

  if BALANCE_JSON="$("$QUERY_BIN" q bank balances "$BROADCASTER" --node "$RPC" -o json "${HOME_FLAGS[@]}" 2>/dev/null)"; then
    BALANCE_UAXL="$(printf '%s' "$BALANCE_JSON" | jq -r '[.balances[]? | select(.denom=="uaxl") | .amount][0] // "0"')"
    echo "broadcaster_uaxl=$BALANCE_UAXL"
    if is_uint "$BALANCE_UAXL"; then
      if [[ "$BALANCE_UAXL" -lt "$MIN_BROADCASTER_UAXL" ]]; then
        echo "broadcaster_balance_status=low"
        FAILURES=$((FAILURES+1))
      else
        echo "broadcaster_balance_status=ok"
      fi
    fi
  else
    echo "broadcaster_balance_status=query_error"
    FAILURES=$((FAILURES+1))
  fi

  if PROXY_JSON="$("$QUERY_BIN" q snapshot proxy "$VALOPER" --node "$RPC" -o json "${HOME_FLAGS[@]}" 2>/dev/null)"; then
    printf '%s' "$PROXY_JSON" | jq -r '"proxy_query=" + (.|tostring)'
  else
    echo "proxy_query=query_error"
    FAILURES=$((FAILURES+1))
  fi

  if [[ -n "$CHAIN_LIST" ]]; then
    while IFS= read -r CHAIN; do
      [[ -z "$CHAIN" ]] && continue
      if MAINTAINERS="$("$QUERY_BIN" q nexus chain-maintainers "$CHAIN" --node "$RPC" -o json "${HOME_FLAGS[@]}" 2>/dev/null)"; then
        if printf '%s' "$MAINTAINERS" | grep -q "$VALOPER"; then
          echo "maintainer_${CHAIN}=present"
        else
          echo "maintainer_${CHAIN}=missing"
          FAILURES=$((FAILURES+1))
        fi
      else
        echo "maintainer_${CHAIN}=query_error"
        FAILURES=$((FAILURES+1))
      fi
    done <<< "$CHAIN_LIST"
  fi
else
  echo "validator_query=skipped_no_${DAEMON}_binary"
fi

if [[ -n "$VALD_SERVICE" ]]; then
  if VALD_LOGS="$(journalctl -u "$VALD_SERVICE" --since "$VALD_LOG_MINUTES minutes ago" --no-pager 2>/dev/null)"; then
    FILTERED_LOGS="$(printf '%s\n' "$VALD_LOGS" | grep -Evi -- '--log_level' || true)"
    echo "vald_log_window_minutes=$VALD_LOG_MINUTES"
    echo "vald_incorrect_account_sequence=$(count_pattern 'incorrect account sequence' "$FILTERED_LOGS")"
    echo "vald_out_of_gas=$(count_pattern 'out of gas' "$FILTERED_LOGS")"
    echo "vald_poll_not_found=$(count_pattern 'poll not found' "$FILTERED_LOGS")"
    echo "vald_signing_session_not_found=$(count_pattern 'signing session not found' "$FILTERED_LOGS")"
    echo "vald_rpc_client_not_found=$(count_pattern 'rpc client not found' "$FILTERED_LOGS")"
    echo "vald_panic_fatal=$(count_pattern 'panic|fatal' "$FILTERED_LOGS")"
  else
    echo "vald_logs=query_error"
  fi
fi

echo "failure_count=$FAILURES"
if [[ "$FAILURES" -ne 0 ]]; then
  echo "overall_status=failed"
  exit 1
fi
echo "overall_status=ok"
REMOTE
)"

if [[ "$LOCAL_MODE" == "1" ]]; then
  bash -s -- "$ARGS_PAYLOAD" <<<"$REMOTE_SCRIPT"
else
  ssh -o BatchMode=yes -o ConnectTimeout=8 -- "$HOST" bash -s -- "$ARGS_PAYLOAD" <<<"$REMOTE_SCRIPT"
fi
