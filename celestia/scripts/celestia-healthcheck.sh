#!/usr/bin/env bash
set -euo pipefail

HOST=""
LOCAL_MODE=0
CONSENSUS_SERVICE=""
CONSENSUS_RPC=""
PUBLIC_RPC=""
VALCONS=""
VALOPER=""
EXPECTED_CHAIN_ID="celestia"
DAEMON="celestia-appd"
BLOCKS=5
CURL_TIMEOUT=8
BRIDGE_SERVICE=""
BRIDGE_RPC="http://127.0.0.1:26658"
BRIDGE_NODE_TYPE="bridge"
NODE_STORE=""
CORE_RPC=""
BRIDGE_AUTH_TOKEN=""

usage() {
  cat <<'USAGE'
Usage:
  celestia-healthcheck.sh [--host <ssh-target>|--local] [consensus options] [bridge options]

Consensus example:
  celestia-healthcheck.sh \
    --host <user>@<host> \
    --consensus-service celestia-appd \
    --consensus-rpc http://127.0.0.1:<rpc-port> \
    --public-rpc https://<public-rpc> \
    --valcons <HEX_CONSENSUS_ADDRESS> \
    --valoper <celestiavaloper...>

Bridge example:
  celestia-healthcheck.sh \
    --host <user>@<host> \
    --bridge-service celestia-bridge \
    --bridge-node-type bridge \
    --node-store ~/.celestia-bridge \
    --bridge-rpc http://127.0.0.1:26658 \
    --core-rpc https://<trusted-core-rpc>

Options:
  --local                       Run checks on the current host instead of SSH.
  --consensus-service <name>    Optional consensus systemd service/container name.
  --consensus-rpc <url>         Optional CometBFT RPC endpoint.
  --public-rpc <url>            Optional public RPC for height comparison.
  --valcons <hex>               Optional consensus address for recent signing checks.
  --valoper <address>           Optional valoper address for staking query.
  --expected-chain-id <id>      Expected consensus network field. Default: celestia.
  --daemon <name>               Consensus binary. Default: celestia-appd.
  --blocks <n>                  Recent blocks to inspect for signatures. Default: 5.
  --curl-timeout <sec>          Per-request curl timeout. Default: 8.
  --bridge-service <name>       Optional DA node service name.
  --bridge-node-type <type>     bridge, full, or light. Default: bridge.
  --node-store <path>           DA node store, e.g. ~/.celestia-bridge.
  --bridge-rpc <url>            DA node JSON-RPC endpoint. Default: http://127.0.0.1:26658.
  --bridge-auth-token <token>   Optional DA node auth token. Omit to let script try celestia auth.
  --core-rpc <url>              Optional trusted core RPC used by the DA node.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) HOST="$2"; shift 2 ;;
    --local) LOCAL_MODE=1; shift ;;
    --consensus-service) CONSENSUS_SERVICE="$2"; shift 2 ;;
    --consensus-rpc) CONSENSUS_RPC="$2"; shift 2 ;;
    --public-rpc) PUBLIC_RPC="$2"; shift 2 ;;
    --valcons) VALCONS="$2"; shift 2 ;;
    --valoper) VALOPER="$2"; shift 2 ;;
    --expected-chain-id) EXPECTED_CHAIN_ID="$2"; shift 2 ;;
    --daemon) DAEMON="$2"; shift 2 ;;
    --blocks) BLOCKS="$2"; shift 2 ;;
    --curl-timeout) CURL_TIMEOUT="$2"; shift 2 ;;
    --bridge-service) BRIDGE_SERVICE="$2"; shift 2 ;;
    --bridge-node-type) BRIDGE_NODE_TYPE="$2"; shift 2 ;;
    --node-store) NODE_STORE="$2"; shift 2 ;;
    --bridge-rpc) BRIDGE_RPC="$2"; shift 2 ;;
    --bridge-auth-token) BRIDGE_AUTH_TOKEN="$2"; shift 2 ;;
    --core-rpc) CORE_RPC="$2"; shift 2 ;;
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

if [[ -z "$CONSENSUS_RPC" && -z "$BRIDGE_SERVICE" ]]; then
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

CONSENSUS_SERVICE="$1"
CONSENSUS_RPC="$2"
PUBLIC_RPC="$3"
VALCONS="$4"
VALOPER="$5"
EXPECTED_CHAIN_ID="$6"
DAEMON="$7"
BLOCKS="$8"
CURL_TIMEOUT="$9"
BRIDGE_SERVICE="${10}"
BRIDGE_RPC="${11}"
BRIDGE_NODE_TYPE="${12}"
NODE_STORE="${13}"
CORE_RPC="${14}"
BRIDGE_AUTH_TOKEN="${15}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing_required_command=$1"
    exit 127
  fi
}

fetch_json() {
  curl -fsS --max-time "$CURL_TIMEOUT" --retry 1 --retry-delay 1 "$1"
}

post_json() {
  local url="$1"
  local token="$2"
  local body="$3"
  curl -fsS --max-time "$CURL_TIMEOUT" \
    -H "Authorization: Bearer $token" \
    -H 'Content-Type: application/json' \
    -d "$body" "$url"
}

is_uint() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

require_cmd curl
require_cmd jq
require_cmd date

echo "time=$(date -u +%Y-%m-%dT%H:%M:%SZ)"

if [[ -n "$CONSENSUS_SERVICE" ]]; then
  echo "consensus_service=$(systemctl is-active "$CONSENSUS_SERVICE" 2>/dev/null || true)"
  echo "consensus_enabled=$(systemctl is-enabled "$CONSENSUS_SERVICE" 2>/dev/null || true)"
fi

if [[ -n "$CONSENSUS_RPC" ]]; then
  STATUS_JSON="$(fetch_json "$CONSENSUS_RPC/status")"
  CHAIN_ID="$(printf '%s' "$STATUS_JSON" | jq -r '.result.node_info.network')"
  HEIGHT="$(printf '%s' "$STATUS_JSON" | jq -r '.result.sync_info.latest_block_height')"
  if ! is_uint "$HEIGHT"; then
    echo "consensus_height_error=non_numeric_or_missing"
    exit 1
  fi

  echo "chain_id=$CHAIN_ID"
  if [[ -n "$EXPECTED_CHAIN_ID" && "$CHAIN_ID" != "$EXPECTED_CHAIN_ID" ]]; then
    echo "chain_id_mismatch=expected_${EXPECTED_CHAIN_ID}_got_${CHAIN_ID}"
  fi

  printf '%s' "$STATUS_JSON" | jq -r '
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

  PID=""
  if [[ -n "$CONSENSUS_SERVICE" ]]; then
    PID="$(systemctl show -p MainPID --value "$CONSENSUS_SERVICE" 2>/dev/null || true)"
    if [[ "$PID" == "0" ]]; then
      PID=""
    fi
  fi
  if [[ -z "$PID" ]]; then
    PID="$(pgrep -f "${DAEMON}.*start" | head -1 || true)"
  fi
  BIN="$DAEMON"
  if [[ -n "$PID" && -e "/proc/$PID/exe" ]]; then
    BIN="$(readlink -f "/proc/$PID/exe")"
    echo "consensus_pid=$PID"
    echo "consensus_exe=$BIN"
    echo "consensus_version=$("$BIN" version 2>/dev/null || "$BIN" version --long 2>/dev/null || true)"
  else
    echo "consensus_pid=missing"
    echo "consensus_version=$("$DAEMON" version 2>/dev/null || "$DAEMON" version --long 2>/dev/null || true)"
  fi

  echo "peers=$(fetch_json "$CONSENSUS_RPC/net_info" | jq -r '.result.n_peers')"

  if [[ -n "$VALCONS" ]]; then
    SIGNED=0
    CHECKED=0
    for ((i=1; i<=BLOCKS; i++)); do
      B=$((HEIGHT-i))
      if [[ "$B" -lt 1 ]]; then
        continue
      fi
      if BLOCK_JSON="$(fetch_json "$CONSENSUS_RPC/block?height=$B" 2>/dev/null)"; then
        FLAG="$(printf '%s' "$BLOCK_JSON" | jq -r --arg v "$VALCONS" '[.result.block.last_commit.signatures[]? | select(.validator_address==$v) | .block_id_flag][0] // "missing"')"
        echo "signature_height_${B}=$FLAG"
        CHECKED=$((CHECKED + 1))
        if [[ "$FLAG" == "2" || "$FLAG" == "BLOCK_ID_FLAG_COMMIT" ]]; then
          SIGNED=$((SIGNED + 1))
        fi
      else
        echo "signature_height_${B}=fetch_error"
      fi
    done
    echo "signatures_signed=$SIGNED"
    echo "signatures_checked=$CHECKED"
  fi

  if [[ -n "$VALOPER" ]]; then
    if command -v "$DAEMON" >/dev/null 2>&1; then
      "$DAEMON" query staking validator "$VALOPER" --node "$CONSENSUS_RPC" -o json 2>/dev/null |
        jq -r '(.validator // .) as $v |
          "validator_status=" + ($v.status // "unknown"),
          "validator_jailed=" + (($v.jailed // "unknown")|tostring),
          "validator_tokens=" + ($v.tokens // "unknown")' || true
    else
      echo "staking_query=daemon_missing"
    fi
  fi

  echo "recent_consensus_errors_begin"
  if [[ -n "$CONSENSUS_SERVICE" ]]; then
    journalctl -u "$CONSENSUS_SERVICE" --since '30 minutes ago' --no-pager -n 80 2>/dev/null |
      grep -Ei 'panic|error|failed|fatal|corrupt|timeout|out of memory|oom' || true
  fi
  echo "recent_consensus_errors_end"
fi

if [[ -n "$BRIDGE_SERVICE" ]]; then
  echo "bridge_service=$(systemctl is-active "$BRIDGE_SERVICE" 2>/dev/null || true)"
  echo "bridge_enabled=$(systemctl is-enabled "$BRIDGE_SERVICE" 2>/dev/null || true)"
fi

if [[ -n "$BRIDGE_SERVICE" || -n "$NODE_STORE" ]]; then
  if command -v celestia >/dev/null 2>&1; then
    echo "celestia_node_version=$(celestia version 2>/dev/null || true)"
    STORE_ARG=()
    if [[ -n "$NODE_STORE" ]]; then
      STORE_ARG=(--node.store "$NODE_STORE")
    fi

    echo "header_sync_begin"
    celestia "$BRIDGE_NODE_TYPE" header sync-state "${STORE_ARG[@]}" 2>/dev/null || echo "header_sync_error=true"
    echo "header_sync_end"

    echo "balance_begin"
    celestia state balance "${STORE_ARG[@]}" 2>/dev/null || echo "balance_error=true"
    echo "balance_end"

    if [[ -z "$BRIDGE_AUTH_TOKEN" ]]; then
      BRIDGE_AUTH_TOKEN="$(celestia "$BRIDGE_NODE_TYPE" auth admin "${STORE_ARG[@]}" 2>/dev/null || true)"
    fi

    if [[ -n "$BRIDGE_AUTH_TOKEN" ]]; then
      if INFO_JSON="$(post_json "$BRIDGE_RPC" "$BRIDGE_AUTH_TOKEN" '{"jsonrpc":"2.0","id":0,"method":"p2p.Info","params":[]}' 2>/dev/null)"; then
        printf '%s' "$INFO_JSON" | jq -r '
          "bridge_peer_id=" + ((.result.ID // .result.id // "unknown")|tostring),
          "bridge_listen_addrs=" + ((.result.Addrs // .result.addrs // [])|tostring)'
      else
        echo "bridge_jsonrpc_error=p2p_info_failed"
      fi
    else
      echo "bridge_auth_token=unavailable"
    fi
  else
    echo "celestia_binary=missing"
  fi

  if [[ -n "$CORE_RPC" ]]; then
    if CORE_STATUS_JSON="$(fetch_json "$CORE_RPC/status" 2>/dev/null)"; then
      printf '%s' "$CORE_STATUS_JSON" | jq -r '
        "core_chain_id=" + .result.node_info.network,
        "core_height=" + .result.sync_info.latest_block_height,
        "core_catching_up=" + (.result.sync_info.catching_up|tostring)'
    else
      echo "core_rpc_error=unreachable"
    fi
  fi

  echo "recent_bridge_errors_begin"
  if [[ -n "$BRIDGE_SERVICE" ]]; then
    journalctl -u "$BRIDGE_SERVICE" --since '30 minutes ago' --no-pager -n 80 2>/dev/null |
      grep -Ei 'panic|error|failed|fatal|timeout|header|sync|peer|balance|auth|core|oom|out of memory' || true
  fi
  echo "recent_bridge_errors_end"
fi
REMOTE
)"

if [[ "$LOCAL_MODE" == "1" ]]; then
  bash -s -- \
    "$CONSENSUS_SERVICE" "$CONSENSUS_RPC" "$PUBLIC_RPC" "$VALCONS" "$VALOPER" \
    "$EXPECTED_CHAIN_ID" "$DAEMON" "$BLOCKS" "$CURL_TIMEOUT" \
    "$BRIDGE_SERVICE" "$BRIDGE_RPC" "$BRIDGE_NODE_TYPE" "$NODE_STORE" \
    "$CORE_RPC" "$BRIDGE_AUTH_TOKEN" <<<"$REMOTE_SCRIPT"
else
  ssh -o BatchMode=yes -o ConnectTimeout=10 "$HOST" bash -s -- \
    "$CONSENSUS_SERVICE" "$CONSENSUS_RPC" "$PUBLIC_RPC" "$VALCONS" "$VALOPER" \
    "$EXPECTED_CHAIN_ID" "$DAEMON" "$BLOCKS" "$CURL_TIMEOUT" \
    "$BRIDGE_SERVICE" "$BRIDGE_RPC" "$BRIDGE_NODE_TYPE" "$NODE_STORE" \
    "$CORE_RPC" "$BRIDGE_AUTH_TOKEN" <<<"$REMOTE_SCRIPT"
fi
