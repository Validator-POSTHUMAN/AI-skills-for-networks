#!/usr/bin/env bash
set -euo pipefail

HOST=""
LOCAL_MODE=0
NODE_SERVICE=""
RPC=""
PUBLIC_RPC=""
EXPECTED_CHAIN_ID=""
AMPD_SERVICE=""
TOFND_SERVICE=""
AMPD_MONITOR=""
AMPD_GRPC_HOST="127.0.0.1"
AMPD_GRPC_PORT="9090"
TOFND_HOST="127.0.0.1"
TOFND_PORT="50051"
MAX_BLOCK_AGE_SECONDS=15
CURL_TIMEOUT=8
LOG_MINUTES=15
HANDLERS=()
CHAIN_CLIENTS=()

usage() {
  cat <<'USAGE'
Usage:
  axelar-amplifier-healthcheck.sh [--host <ssh-target>|--local] \
    --node-service <service> --rpc <local-rpc> --expected-chain-id <chain-id> \
    --ampd-service <service> --tofnd-service <amplifier-tofnd-service> \
    --ampd-monitor http://127.0.0.1:<port> \
    --handler <chain>=<service> --chain-client <chain>=<service>

The handler and chain-client chain sets must match. Run chain-native health
checks separately; this helper verifies process boundaries and ampd telemetry.

Options:
  --local                         Run on the current host (default without --host).
  --public-rpc <url>              Independent Axelar RPC for height comparison.
  --ampd-grpc-host <host>         Private ampd handler-gRPC host. Default: 127.0.0.1.
  --ampd-grpc-port <port>         Private ampd handler-gRPC port. Default: 9090.
  --tofnd-host <host>             Amplifier-only tofnd host. Default: 127.0.0.1.
  --tofnd-port <port>             Amplifier-only tofnd port. Default: 50051.
  --handler <chain>=<service>     Expected handler service. Repeat once per chain.
  --chain-client <chain>=<service> Expected full-node/light-client service. Repeat.
  --max-block-age-seconds <n>     Axelar block freshness limit. Default: 15.
  --curl-timeout <seconds>        Per-request timeout. Default: 8.
  --log-minutes <n>               Bounded ampd/handler journal window. Default: 15.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) HOST="$2"; shift 2 ;;
    --local) LOCAL_MODE=1; shift ;;
    --node-service) NODE_SERVICE="$2"; shift 2 ;;
    --rpc) RPC="$2"; shift 2 ;;
    --public-rpc) PUBLIC_RPC="$2"; shift 2 ;;
    --expected-chain-id) EXPECTED_CHAIN_ID="$2"; shift 2 ;;
    --ampd-service) AMPD_SERVICE="$2"; shift 2 ;;
    --tofnd-service) TOFND_SERVICE="$2"; shift 2 ;;
    --ampd-monitor) AMPD_MONITOR="$2"; shift 2 ;;
    --ampd-grpc-host) AMPD_GRPC_HOST="$2"; shift 2 ;;
    --ampd-grpc-port) AMPD_GRPC_PORT="$2"; shift 2 ;;
    --tofnd-host) TOFND_HOST="$2"; shift 2 ;;
    --tofnd-port) TOFND_PORT="$2"; shift 2 ;;
    --handler) HANDLERS+=("$2"); shift 2 ;;
    --chain-client) CHAIN_CLIENTS+=("$2"); shift 2 ;;
    --max-block-age-seconds) MAX_BLOCK_AGE_SECONDS="$2"; shift 2 ;;
    --curl-timeout) CURL_TIMEOUT="$2"; shift 2 ;;
    --log-minutes) LOG_MINUTES="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -n "$HOST" && "$LOCAL_MODE" == "1" ]]; then
  echo "choose either --host or --local, not both" >&2
  exit 2
fi
[[ -n "$HOST" ]] || LOCAL_MODE=1

for required in NODE_SERVICE RPC EXPECTED_CHAIN_ID AMPD_SERVICE TOFND_SERVICE AMPD_MONITOR; do
  if [[ -z "${!required}" ]]; then
    echo "missing required option for ${required,,}" >&2
    usage >&2
    exit 2
  fi
done

if [[ "${#HANDLERS[@]}" -eq 0 || "${#CHAIN_CLIENTS[@]}" -eq 0 ]]; then
  echo "at least one --handler and matching --chain-client are required" >&2
  exit 2
fi

for n in "$AMPD_GRPC_PORT" "$TOFND_PORT" "$MAX_BLOCK_AGE_SECONDS" "$CURL_TIMEOUT" "$LOG_MINUTES"; do
  if ! [[ "$n" =~ ^[0-9]+$ ]] || [[ "$n" -lt 1 ]]; then
    echo "numeric options must be positive integers" >&2
    exit 2
  fi
done

validate_mapping() {
  local mapping="$1" kind="$2" chain service
  if [[ "$mapping" != *=* ]]; then
    echo "$kind mapping must be <chain>=<service>" >&2
    exit 2
  fi
  chain="${mapping%%=*}"
  service="${mapping#*=}"
  if ! [[ "$chain" =~ ^[A-Za-z0-9._-]+$ ]] ||
     ! [[ "$service" =~ ^[A-Za-z0-9_.@:-]+$ ]] ||
     [[ "$service" == -* ]]; then
    echo "invalid $kind mapping: $mapping" >&2
    exit 2
  fi
}

for mapping in "${HANDLERS[@]}"; do validate_mapping "$mapping" handler; done
for mapping in "${CHAIN_CLIENTS[@]}"; do validate_mapping "$mapping" chain-client; done

handler_chains="$(printf '%s\n' "${HANDLERS[@]%%=*}" | sort -u)"
client_chains="$(printf '%s\n' "${CHAIN_CLIENTS[@]%%=*}" | sort -u)"
if [[ "$handler_chains" != "$client_chains" ]]; then
  echo "handler and chain-client chain sets do not match" >&2
  exit 2
fi
if [[ "$(printf '%s\n' "${HANDLERS[@]%%=*}" | wc -l)" -ne "$(printf '%s\n' "$handler_chains" | wc -l)" ]] ||
   [[ "$(printf '%s\n' "${CHAIN_CLIENTS[@]%%=*}" | wc -l)" -ne "$(printf '%s\n' "$client_chains" | wc -l)" ]]; then
  echo "duplicate chain mapping" >&2
  exit 2
fi

if [[ "$LOCAL_MODE" == "0" ]] && ! command -v ssh >/dev/null 2>&1; then
  echo "missing required command: ssh" >&2
  exit 127
fi
command -v base64 >/dev/null 2>&1 || { echo "missing required command: base64" >&2; exit 127; }

EMPTY_ARG="__AXELAR_EMPTY__"
PUBLIC_RPC_ARG="${PUBLIC_RPC:-$EMPTY_ARG}"
HANDLER_ARG="$(IFS=,; echo "${HANDLERS[*]}")"
CLIENT_ARG="$(IFS=,; echo "${CHAIN_CLIENTS[*]}")"
ARGS_PAYLOAD="$(
  printf '%s\0' \
    "$NODE_SERVICE" "$RPC" "$PUBLIC_RPC_ARG" "$EXPECTED_CHAIN_ID" \
    "$AMPD_SERVICE" "$TOFND_SERVICE" "$AMPD_MONITOR" \
    "$AMPD_GRPC_HOST" "$AMPD_GRPC_PORT" "$TOFND_HOST" "$TOFND_PORT" \
    "$MAX_BLOCK_AGE_SECONDS" "$CURL_TIMEOUT" "$LOG_MINUTES" \
    "$HANDLER_ARG" "$CLIENT_ARG" | base64 -w0
)"

REMOTE_SCRIPT="$(cat <<'REMOTE'
set -euo pipefail

command -v base64 >/dev/null 2>&1 || { echo "missing_required_command=base64"; exit 127; }
mapfile -d '' -t ARGS < <(printf '%s' "$1" | base64 --decode)
if [[ "${#ARGS[@]}" -ne 16 ]]; then
  echo "argument_payload_error=expected_16_fields_got_${#ARGS[@]}"
  exit 2
fi

NODE_SERVICE="${ARGS[0]}"
RPC="${ARGS[1]%/}"
PUBLIC_RPC="${ARGS[2]%/}"
EXPECTED_CHAIN_ID="${ARGS[3]}"
AMPD_SERVICE="${ARGS[4]}"
TOFND_SERVICE="${ARGS[5]}"
AMPD_MONITOR="${ARGS[6]%/}"
AMPD_GRPC_HOST="${ARGS[7]}"
AMPD_GRPC_PORT="${ARGS[8]}"
TOFND_HOST="${ARGS[9]}"
TOFND_PORT="${ARGS[10]}"
MAX_BLOCK_AGE_SECONDS="${ARGS[11]}"
CURL_TIMEOUT="${ARGS[12]}"
LOG_MINUTES="${ARGS[13]}"
IFS=',' read -r -a HANDLERS <<< "${ARGS[14]}"
IFS=',' read -r -a CHAIN_CLIENTS <<< "${ARGS[15]}"
[[ "$PUBLIC_RPC" == "__AXELAR_EMPTY__" ]] && PUBLIC_RPC=""
FAILURES=0

for cmd in curl jq date timeout systemctl journalctl grep sed; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "missing_required_command=$cmd"; exit 127; }
done

fetch_json() {
  curl -fsS --max-time "$CURL_TIMEOUT" --retry 1 --retry-delay 1 "$1"
}

check_service() {
  local label="$1" service="$2" state restarts pid exe
  state="$(systemctl is-active "$service" 2>/dev/null || true)"
  restarts="$(systemctl show -p NRestarts --value "$service" 2>/dev/null || true)"
  pid="$(systemctl show -p MainPID --value "$service" 2>/dev/null || true)"
  echo "${label}_service=$state"
  echo "${label}_restarts=${restarts:-unknown}"
  if [[ "$state" != "active" ]]; then FAILURES=$((FAILURES+1)); fi
  if [[ "$pid" =~ ^[1-9][0-9]*$ && -e "/proc/$pid/exe" ]]; then
    exe="$(readlink -f "/proc/$pid/exe")"
    echo "${label}_pid=$pid"
    echo "${label}_exe=$exe"
  else
    echo "${label}_pid=missing"
  fi
}

check_tcp() {
  local label="$1" host="$2" port="$3"
  if timeout "$CURL_TIMEOUT" bash -c 'exec 3<>"/dev/tcp/$1/$2"' bash "$host" "$port" 2>/dev/null; then
    echo "${label}_tcp=reachable"
  else
    echo "${label}_tcp=unreachable"
    FAILURES=$((FAILURES+1))
  fi
}

echo "time=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
check_service axelar_node "$NODE_SERVICE"
check_service ampd "$AMPD_SERVICE"
check_service amplifier_tofnd "$TOFND_SERVICE"
check_tcp amplifier_tofnd "$TOFND_HOST" "$TOFND_PORT"
check_tcp ampd_grpc "$AMPD_GRPC_HOST" "$AMPD_GRPC_PORT"

STATUS_JSON="$(fetch_json "$RPC/status")"
CHAIN_ID="$(printf '%s' "$STATUS_JSON" | jq -r '.result.node_info.network // empty')"
HEIGHT="$(printf '%s' "$STATUS_JSON" | jq -r '.result.sync_info.latest_block_height // empty')"
BLOCK_TIME="$(printf '%s' "$STATUS_JSON" | jq -r '.result.sync_info.latest_block_time // empty')"
CATCHING_UP="$(printf '%s' "$STATUS_JSON" | jq -r '.result.sync_info.catching_up | tostring')"
echo "chain_id=$CHAIN_ID"
echo "height=$HEIGHT"
echo "block_time=$BLOCK_TIME"
echo "catching_up=$CATCHING_UP"
if [[ "$CHAIN_ID" != "$EXPECTED_CHAIN_ID" ]]; then
  echo "chain_id_status=mismatch"
  FAILURES=$((FAILURES+1))
else
  echo "chain_id_status=ok"
fi
if ! [[ "$HEIGHT" =~ ^[0-9]+$ ]] || [[ "$CATCHING_UP" != "false" ]]; then
  FAILURES=$((FAILURES+1))
fi
NOW_EPOCH="$(date -u +%s)"
if BLOCK_EPOCH="$(date -u -d "$BLOCK_TIME" +%s 2>/dev/null)"; then
  BLOCK_AGE_SECONDS=$((NOW_EPOCH - BLOCK_EPOCH))
  echo "block_age_seconds=$BLOCK_AGE_SECONDS"
  if [[ "$BLOCK_AGE_SECONDS" -gt "$MAX_BLOCK_AGE_SECONDS" || "$BLOCK_AGE_SECONDS" -lt "-$MAX_BLOCK_AGE_SECONDS" ]]; then
    echo "consensus_freshness=failed"
    FAILURES=$((FAILURES+1))
  else
    echo "consensus_freshness=ok"
  fi
else
  echo "consensus_freshness=invalid_block_time"
  FAILURES=$((FAILURES+1))
fi

if [[ -n "$PUBLIC_RPC" ]]; then
  if PUBLIC_JSON="$(fetch_json "${PUBLIC_RPC%/}/status" 2>/dev/null)"; then
    PUBLIC_HEIGHT="$(printf '%s' "$PUBLIC_JSON" | jq -r '.result.sync_info.latest_block_height // empty')"
    echo "public_height=$PUBLIC_HEIGHT"
    if [[ "$HEIGHT" =~ ^[0-9]+$ && "$PUBLIC_HEIGHT" =~ ^[0-9]+$ ]]; then
      echo "height_gap=$((PUBLIC_HEIGHT - HEIGHT))"
    fi
  else
    echo "public_rpc=unreachable"
  fi
fi

if MONITOR_STATUS="$(fetch_json "$AMPD_MONITOR/status" 2>/dev/null)" &&
   printf '%s' "$MONITOR_STATUS" | jq -e '.ok == true' >/dev/null 2>&1; then
  echo "ampd_monitor_status=ok"
else
  echo "ampd_monitor_status=failed"
  FAILURES=$((FAILURES+1))
fi

if METRICS="$(curl -fsS --max-time "$CURL_TIMEOUT" "$AMPD_MONITOR/metrics" 2>/dev/null)"; then
  echo "ampd_metrics=reachable"
  for metric in blocks_received_total verification_votes_total rpc_calls_total rpc_calls_failed_total stage_processed_total stage_failed_total; do
    if printf '%s\n' "$METRICS" | grep -Eq "^${metric}(\{|[[:space:]])"; then
      echo "metric_${metric}=present"
    else
      echo "metric_${metric}=missing"
      FAILURES=$((FAILURES+1))
    fi
  done
  BLOCKS_RECEIVED="$(printf '%s\n' "$METRICS" | sed -nE 's/^blocks_received_total[[:space:]]+([^[:space:]]+).*/\1/p' | head -1)"
  echo "blocks_received_total=${BLOCKS_RECEIVED:-unknown}"
else
  echo "ampd_metrics=unreachable"
  FAILURES=$((FAILURES+1))
fi

for mapping in "${HANDLERS[@]}"; do
  chain="${mapping%%=*}"
  service="${mapping#*=}"
  check_service "handler_${chain}" "$service"
done
for mapping in "${CHAIN_CLIENTS[@]}"; do
  chain="${mapping%%=*}"
  service="${mapping#*=}"
  check_service "chain_client_${chain}" "$service"
done

if AMPD_LOGS="$(journalctl -u "$AMPD_SERVICE" --since "$LOG_MINUTES minutes ago" --no-pager 2>/dev/null)"; then
  echo "ampd_log_window_minutes=$LOG_MINUTES"
  echo "ampd_error_count=$(printf '%s\n' "$AMPD_LOGS" | grep -Eic 'error|fatal|panic|timeout|failed' || true)"
else
  echo "ampd_logs=query_error"
fi
for mapping in "${HANDLERS[@]}"; do
  chain="${mapping%%=*}"
  service="${mapping#*=}"
  if LOGS="$(journalctl -u "$service" --since "$LOG_MINUTES minutes ago" --no-pager 2>/dev/null)"; then
    echo "handler_${chain}_error_count=$(printf '%s\n' "$LOGS" | grep -Eic 'error|fatal|panic|timeout|failed' || true)"
  else
    echo "handler_${chain}_logs=query_error"
  fi
done

echo "chain_native_freshness=not_checked_use_chain_runbooks"
echo "onchain_amplifier_state=not_checked_verify_authorization_bond_keys_support"
echo "failure_count=$FAILURES"
if [[ "$FAILURES" -ne 0 ]]; then
  echo "overall_status=failed"
  exit 1
fi
echo "overall_status=ok_process_and_telemetry_only"
REMOTE
)"

if [[ "$LOCAL_MODE" == "1" ]]; then
  bash -s -- "$ARGS_PAYLOAD" <<<"$REMOTE_SCRIPT"
else
  ssh -o BatchMode=yes -o ConnectTimeout=8 -- "$HOST" bash -s -- "$ARGS_PAYLOAD" <<<"$REMOTE_SCRIPT"
fi
