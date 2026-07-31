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
DAEMON="osmosisd"
NODE_HOME=""
EXPECTED_CHAIN_ID="osmosis-1"
BLOCKS=6
CURL_TIMEOUT=8
MAX_BLOCK_AGE=45
MAX_HEIGHT_GAP=20
LOG_MINUTES=15

usage() {
  cat <<'USAGE'
Usage:
  osmosis-healthcheck.sh [--host <ssh-target>|--local] --service <service> --rpc <local-rpc> [options]

Options:
  --public-rpc <url>         Independent RPC for chain/height comparison.
  --valcons <hex>            40-hex consensus address for recent signing.
  --valcons-bech32 <addr>    osmovalcons address for slashing query.
  --valoper <addr>           osmovaloper address for staking query.
  --daemon <name>            Daemon name. Default: osmosisd.
  --home <path>              Node home for config and CLI queries.
  --expected-chain-id <id>   Default: osmosis-1.
  --blocks <n>               Signing window. Default: 6.
  --max-block-age <sec>      Freshness threshold. Default: 45.
  --max-height-gap <n>       Maximum reference gap. Default: 20.
  --curl-timeout <sec>       Request timeout. Default: 8.
  --log-minutes <n>          Bounded journal window. Default: 15.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) HOST="$2"; shift 2 ;;
    --local) LOCAL_MODE=1; shift ;;
    --service) SERVICE="$2"; shift 2 ;;
    --rpc) RPC="${2%/}"; shift 2 ;;
    --public-rpc) PUBLIC_RPC="${2%/}"; shift 2 ;;
    --valcons) VALCONS="${2^^}"; shift 2 ;;
    --valcons-bech32) VALCONS_BECH32="$2"; shift 2 ;;
    --valoper) VALOPER="$2"; shift 2 ;;
    --daemon) DAEMON="$2"; shift 2 ;;
    --home) NODE_HOME="$2"; shift 2 ;;
    --expected-chain-id) EXPECTED_CHAIN_ID="$2"; shift 2 ;;
    --blocks) BLOCKS="$2"; shift 2 ;;
    --max-block-age) MAX_BLOCK_AGE="$2"; shift 2 ;;
    --max-height-gap) MAX_HEIGHT_GAP="$2"; shift 2 ;;
    --curl-timeout) CURL_TIMEOUT="$2"; shift 2 ;;
    --log-minutes) LOG_MINUTES="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown_arg=$1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -n "$SERVICE" && -n "$RPC" ]] || { usage >&2; exit 2; }
[[ "$LOCAL_MODE" -eq 0 || -z "$HOST" ]] || {
  echo "error=use either --host or --local" >&2; exit 2;
}
[[ "$LOCAL_MODE" -eq 1 || -n "$HOST" ]] || {
  echo "error=provide --host or --local" >&2; exit 2;
}
for value in "$BLOCKS" "$CURL_TIMEOUT" "$MAX_BLOCK_AGE" "$MAX_HEIGHT_GAP" "$LOG_MINUTES"; do
  [[ "$value" =~ ^[0-9]+$ ]] || { echo "error=numeric_option_invalid" >&2; exit 2; }
done
[[ -z "$VALCONS" || "$VALCONS" =~ ^[0-9A-F]{40}$ ]] || {
  echo "error=valcons_hex_invalid" >&2; exit 2;
}
[[ -z "$VALOPER" || "$VALOPER" =~ ^osmovaloper[0-9a-z]+$ ]] || {
  echo "error=valoper_invalid" >&2; exit 2;
}
[[ -z "$VALCONS_BECH32" || "$VALCONS_BECH32" =~ ^osmovalcons[0-9a-z]+$ ]] || {
  echo "error=valcons_bech32_invalid" >&2; exit 2;
}

REMOTE_SCRIPT='set -euo pipefail
SERVICE="$1"; RPC="$2"; PUBLIC_RPC="$3"; VALCONS="$4"; VALCONS_BECH32="$5"
VALOPER="$6"; DAEMON="$7"; NODE_HOME="$8"; EXPECTED_CHAIN_ID="$9"
BLOCKS="${10}"; CURL_TIMEOUT="${11}"; MAX_BLOCK_AGE="${12}"
MAX_HEIGHT_GAP="${13}"; LOG_MINUTES="${14}"
for optional_name in PUBLIC_RPC VALCONS VALCONS_BECH32 VALOPER NODE_HOME; do
  [[ "${!optional_name}" != __NONE__ ]] || printf -v "$optional_name" %s ""
done

failures=0
warn() { printf "WARN %s\n" "$1"; }
fail() { printf "FAIL %s\n" "$1"; failures=$((failures + 1)); }
fetch() { curl -fsS --max-time "$CURL_TIMEOUT" --retry 1 --retry-delay 1 "$1"; }
uint() { [[ "$1" =~ ^[0-9]+$ ]]; }
count() { printf "%s\n" "$2" | grep -Eic "$1" || true; }

for command in curl jq date systemctl; do
  command -v "$command" >/dev/null || { echo "missing_command=$command"; exit 127; }
done

printf "checked_at=%s\n" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
service_state="$(systemctl is-active "$SERVICE" 2>/dev/null || true)"
service_enabled="$(systemctl is-enabled "$SERVICE" 2>/dev/null || true)"
restarts="$(systemctl show "$SERVICE" -p NRestarts --value 2>/dev/null || true)"
printf "service=%s\nservice_enabled=%s\nrestarts=%s\n" "$service_state" "$service_enabled" "${restarts:-unknown}"
[[ "$service_state" == active ]] || fail "service_not_active"

status="$(fetch "$RPC/status")" || { fail "local_rpc_unreachable"; echo "overall=unhealthy failures=$failures"; exit 1; }
chain_id="$(jq -r ".result.node_info.network // empty" <<<"$status")"
height="$(jq -r ".result.sync_info.latest_block_height // empty" <<<"$status")"
block_time="$(jq -r ".result.sync_info.latest_block_time // empty" <<<"$status")"
catching_up="$(jq -r ".result.sync_info.catching_up | if . == null then empty else tostring end" <<<"$status")"
voting_power="$(jq -r ".result.validator_info.voting_power // empty" <<<"$status")"
node_id="$(jq -r ".result.node_info.id // empty" <<<"$status")"
printf "chain_id=%s\nheight=%s\nblock_time=%s\ncatching_up=%s\nvoting_power=%s\nnode_id=%s\n" \
  "$chain_id" "$height" "$block_time" "$catching_up" "$voting_power" "$node_id"
[[ "$chain_id" == "$EXPECTED_CHAIN_ID" ]] || fail "chain_id_mismatch"
[[ "$catching_up" == false ]] || fail "catching_up"
uint "$height" || fail "height_invalid"

block_epoch="$(date -u -d "$block_time" +%s 2>/dev/null || true)"
now_epoch="$(date -u +%s)"
if uint "$block_epoch"; then
  block_age=$((now_epoch - block_epoch))
  printf "block_age_seconds=%s\n" "$block_age"
  (( block_age >= 0 && block_age <= MAX_BLOCK_AGE )) || fail "stale_or_future_block_time"
else
  fail "block_time_invalid"
fi

peers="$(fetch "$RPC/net_info" | jq -r ".result.n_peers // empty" 2>/dev/null || true)"
printf "peers=%s\n" "${peers:-unknown}"
uint "$peers" || fail "peer_count_invalid"

if [[ -n "$PUBLIC_RPC" ]]; then
  if public_status="$(fetch "$PUBLIC_RPC/status" 2>/dev/null)"; then
    public_chain="$(jq -r ".result.node_info.network // empty" <<<"$public_status")"
    public_height="$(jq -r ".result.sync_info.latest_block_height // empty" <<<"$public_status")"
    printf "reference_chain_id=%s\nreference_height=%s\n" "$public_chain" "$public_height"
    [[ "$public_chain" == "$EXPECTED_CHAIN_ID" ]] || fail "reference_chain_id_mismatch"
    if uint "$public_height" && uint "$height"; then
      gap=$((public_height - height))
      (( gap < 0 )) && gap=$((-gap))
      printf "height_gap=%s\n" "$gap"
      (( gap <= MAX_HEIGHT_GAP )) || fail "height_gap_exceeded"
    else
      fail "reference_height_invalid"
    fi
  else
    warn "reference_rpc_unreachable"
  fi
fi

pid="$(pgrep -f "$DAEMON.*start" | head -1 || true)"
binary=""
if [[ -n "$pid" && -x "/proc/$pid/exe" ]]; then
  binary="$(readlink -f "/proc/$pid/exe")"
fi
if [[ -n "$binary" ]]; then
  printf "binary=%s\nversion=%s\n" "$binary" "$("$binary" version 2>/dev/null || true)"
elif command -v "$DAEMON" >/dev/null 2>&1; then
  binary="$(command -v "$DAEMON")"
  printf "binary=%s\nversion=%s\n" "$binary" "$("$binary" version 2>/dev/null || true)"
else
  warn "daemon_binary_not_resolved"
fi

if [[ -n "$NODE_HOME" ]]; then
  if [[ -f "$NODE_HOME/config/app.toml" ]]; then
    awk -F= "/^(pruning|pruning-keep-recent|pruning-keep-every|pruning-interval|minimum-gas-prices)[[:space:]]*=/ {gsub(/^[[:space:]]+|[[:space:]]+$/, \"\", \$1); print \"config_\" \$1 \"=\" \$2}" "$NODE_HOME/config/app.toml"
  else
    warn "app_toml_missing"
  fi
  if [[ -f "$NODE_HOME/config/config.toml" ]]; then
    awk -F= "/^indexer[[:space:]]*=/ {gsub(/^[[:space:]]+|[[:space:]]+$/, \"\", \$1); print \"config_\" \$1 \"=\" \$2; exit}" "$NODE_HOME/config/config.toml"
  else
    warn "config_toml_missing"
  fi
  [[ -d "$NODE_HOME/wasm" ]] || warn "wasm_directory_missing"
  df -Pk "$NODE_HOME" | awk "NR==2 {print \"disk_used_percent=\" int(100*\$3/(\$3+\$4)), \"disk_available_kb=\" \$4}"
fi

if [[ -n "$VALCONS" ]] && uint "$height"; then
  signed=0; checked=0
  for ((offset=1; offset<=BLOCKS; offset++)); do
    block=$((height - offset)); (( block > 0 )) || continue
    flag="query_error"
    if block_json="$(fetch "$RPC/block?height=$block" 2>/dev/null)"; then
      flag="$(jq -r --arg value "$VALCONS" "[.result.block.last_commit.signatures[]? | select(.validator_address==\$value) | .block_id_flag][0] // \"missing\"" <<<"$block_json")"
    fi
    printf "signing_height_%s=%s\n" "$block" "$flag"
    checked=$((checked + 1))
    [[ "$flag" == 2 || "$flag" == BLOCK_ID_FLAG_COMMIT ]] && signed=$((signed + 1))
  done
  printf "recent_signing=%s/%s\n" "$signed" "$checked"
  (( checked > 0 && signed == checked )) || fail "recent_signing_incomplete"
else
  printf "recent_signing=not_checked\n"
fi

query_binary="$binary"
[[ -x "$query_binary" ]] || query_binary="$(command -v "$DAEMON" 2>/dev/null || true)"
if [[ -n "$query_binary" ]]; then
  query_home=()
  [[ -z "$NODE_HOME" ]] || query_home=(--home "$NODE_HOME")
  if [[ -n "$VALOPER" ]]; then
    set +e
    validator_json="$("$query_binary" query staking validator "$VALOPER" --node "$RPC" "${query_home[@]}" -o json 2>&1)"
    validator_query_rc=$?
    set -e
    printf "validator_query_rc=%s\n" "$validator_query_rc"
    if [[ "$validator_query_rc" -eq 0 ]] && jq -e ".validator.operator_address // .operator_address" >/dev/null 2>&1 <<<"$validator_json"; then
      jq -r "(.validator // .) as \$v | \"validator_status=\" + (\$v.status // \"unknown\"), \"validator_jailed=\" + ((\$v.jailed // false)|tostring), \"validator_tokens=\" + (\$v.tokens // \"unknown\")" <<<"$validator_json"
      jailed="$(jq -r "(.validator // .).jailed // false" <<<"$validator_json")"
      status_value="$(jq -r "(.validator // .).status // empty" <<<"$validator_json")"
      [[ "$jailed" == false ]] || fail "validator_jailed"
      [[ "$status_value" == BOND_STATUS_BONDED || "$status_value" == 3 ]] || fail "validator_not_bonded"
    else
      fail "validator_query_failed"
    fi
  fi
  if [[ -n "$VALCONS_BECH32" ]]; then
    signing_json="$("$query_binary" query slashing signing-info "$VALCONS_BECH32" --node "$RPC" "${query_home[@]}" -o json 2>&1 || true)"
    if [[ -n "$signing_json" ]]; then
      tombstoned="$(jq -r ".val_signing_info.tombstoned // .tombstoned // false" <<<"$signing_json")"
      missed="$(jq -r ".val_signing_info.missed_blocks_counter // .missed_blocks_counter // \"unknown\"" <<<"$signing_json")"
      printf "tombstoned=%s\nmissed_blocks_counter=%s\n" "$tombstoned" "$missed"
      [[ "$tombstoned" == false ]] || fail "validator_tombstoned"
    else
      warn "slashing_query_failed"
    fi
  fi
  plan_json="$("$query_binary" query upgrade plan --node "$RPC" "${query_home[@]}" -o json 2>&1 || true)"
  [[ -z "$plan_json" ]] || printf "upgrade_plan_present=%s\n" "$(jq -r "if (.plan // .) == {} or (.plan // null) == null then false else true end" <<<"$plan_json" 2>/dev/null || echo unknown)"
fi

if logs="$(journalctl -u "$SERVICE" --since "$LOG_MINUTES minutes ago" --no-pager 2>/dev/null | tail -400)"; then
  printf "log_lines=%s\n" "$(printf "%s\n" "$logs" | wc -l | tr -d " ")"
  printf "log_critical=%s\n" "$(count "panic|fatal|wrong app.?hash|app.?hash (mismatch|error)|corrupt|out of memory|no space left|too many open files" "$logs")"
  printf "log_osmosis_module=%s\n" "$(count "wasmvm|iavl|epoch|incentive|concentrated.?liquidity|superfluid" "$logs")"
else
  warn "journal_unavailable"
fi

if (( failures == 0 )); then
  echo "overall=healthy failures=0"
  exit 0
fi
echo "overall=unhealthy failures=$failures"
exit 1'

args=("$SERVICE" "$RPC" "${PUBLIC_RPC:-__NONE__}" "${VALCONS:-__NONE__}" "${VALCONS_BECH32:-__NONE__}" "${VALOPER:-__NONE__}" "$DAEMON" "${NODE_HOME:-__NONE__}" "$EXPECTED_CHAIN_ID" "$BLOCKS" "$CURL_TIMEOUT" "$MAX_BLOCK_AGE" "$MAX_HEIGHT_GAP" "$LOG_MINUTES")
if [[ "$LOCAL_MODE" -eq 1 ]]; then
  bash -s -- "${args[@]}" <<<"$REMOTE_SCRIPT"
else
  ssh -o BatchMode=yes -o ConnectTimeout=10 "$HOST" bash -s -- "${args[@]}" <<<"$REMOTE_SCRIPT"
fi
