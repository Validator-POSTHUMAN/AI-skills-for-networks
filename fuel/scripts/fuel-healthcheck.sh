#!/usr/bin/env bash
set -euo pipefail

MODE=""
HOST=""
LOCAL_MODE=0
SERVICE=""
CONTAINER=""
GRAPHQL=""
PUBLIC_GRAPHQL=""
RPC=""
PUBLIC_RPC=""
DAEMON="fuelsequencerd"
VALCONS=""
VALOPER=""
EXPECTED_CHAIN_ID=""
EXPECTED_CHAIN_NAME=""
DATA_DIR=""
BLOCKS=5
MAX_BLOCK_LAG=""
CURL_TIMEOUT=8

usage() {
  cat <<'USAGE'
Usage:
  fuel-healthcheck.sh --mode ignition [--host <ssh-target>|--local] --graphql <url>
  fuel-healthcheck.sh --mode sequencer [--host <ssh-target>|--local] --rpc <cometbft-rpc-url>

Fuel Ignition example:
  fuel-healthcheck.sh \
    --mode ignition \
    --host <user>@<host> \
    --service fuel-core.service \
    --graphql http://127.0.0.1:4000/v1/graphql \
    --public-graphql https://mainnet.fuel.network/v1/graphql \
    --expected-chain-name Ignition \
    --max-block-lag 100

Fuel Sequencer example:
  fuel-healthcheck.sh \
    --mode sequencer \
    --host <user>@<host> \
    --service fuelsequencerd.service \
    --rpc http://127.0.0.1:26657 \
    --public-rpc https://<reference-rpc> \
    --expected-chain-id seq-mainnet-1 \
    --valcons <HEX_CONSENSUS_ADDRESS> \
    --valoper <fuelsequencervaloper...>

Options:
  --local                         Run checks on the current host instead of SSH.
  --service <name>                Optional systemd service to check.
  --container <name>              Optional Docker container to check.
  --graphql <url>                 Fuel Ignition GraphQL URL.
  --public-graphql <url>          Optional reference GraphQL URL.
  --rpc <url>                     Fuel Sequencer CometBFT RPC URL.
  --public-rpc <url>              Optional reference CometBFT RPC URL.
  --daemon <name>                 Sequencer daemon. Default: fuelsequencerd.
  --valcons <hex-address>         Optional Sequencer validator consensus address.
  --valoper <address>             Optional Sequencer validator operator address.
  --expected-chain-id <id>        Optional Sequencer chain ID.
  --expected-chain-name <name>    Optional Fuel Ignition GraphQL chain name.
  --data-dir <path>               Optional data directory for disk usage.
  --blocks <n>                    Recent Sequencer blocks to inspect. Default: 5.
  --max-block-lag <n>             Optional max allowed local/reference height gap.
  --curl-timeout <sec>            Per-request curl timeout. Default: 8.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="$2"; shift 2 ;;
    --host) HOST="$2"; shift 2 ;;
    --local) LOCAL_MODE=1; shift ;;
    --service) SERVICE="$2"; shift 2 ;;
    --container) CONTAINER="$2"; shift 2 ;;
    --graphql) GRAPHQL="$2"; shift 2 ;;
    --public-graphql) PUBLIC_GRAPHQL="$2"; shift 2 ;;
    --rpc) RPC="$2"; shift 2 ;;
    --public-rpc) PUBLIC_RPC="$2"; shift 2 ;;
    --daemon) DAEMON="$2"; shift 2 ;;
    --valcons) VALCONS="$2"; shift 2 ;;
    --valoper) VALOPER="$2"; shift 2 ;;
    --expected-chain-id) EXPECTED_CHAIN_ID="$2"; shift 2 ;;
    --expected-chain-name) EXPECTED_CHAIN_NAME="$2"; shift 2 ;;
    --data-dir) DATA_DIR="$2"; shift 2 ;;
    --blocks) BLOCKS="$2"; shift 2 ;;
    --max-block-lag) MAX_BLOCK_LAG="$2"; shift 2 ;;
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

case "$MODE" in
  ignition)
    [[ -n "$GRAPHQL" ]] || { usage >&2; exit 2; }
    ;;
  sequencer)
    [[ -n "$RPC" ]] || { usage >&2; exit 2; }
    ;;
  *)
    echo "--mode must be ignition or sequencer" >&2
    usage >&2
    exit 2
    ;;
esac

if ! [[ "$BLOCKS" =~ ^[0-9]+$ ]] || [[ "$BLOCKS" -lt 1 ]]; then
  echo "--blocks must be a positive integer" >&2
  exit 2
fi

if ! [[ "$CURL_TIMEOUT" =~ ^[0-9]+$ ]] || [[ "$CURL_TIMEOUT" -lt 1 ]]; then
  echo "--curl-timeout must be a positive integer" >&2
  exit 2
fi

if [[ -n "$MAX_BLOCK_LAG" ]] && ! [[ "$MAX_BLOCK_LAG" =~ ^[0-9]+$ ]]; then
  echo "--max-block-lag must be a non-negative integer" >&2
  exit 2
fi

if [[ "$LOCAL_MODE" == "0" ]] && ! command -v ssh >/dev/null 2>&1; then
  echo "missing required command: ssh" >&2
  exit 127
fi

REMOTE_SCRIPT="$(cat <<'REMOTE'
set -euo pipefail

MODE="$1"
SERVICE="$2"
CONTAINER="$3"
GRAPHQL="$4"
PUBLIC_GRAPHQL="$5"
RPC="$6"
PUBLIC_RPC="$7"
DAEMON="$8"
VALCONS="$9"
VALOPER="${10}"
EXPECTED_CHAIN_ID="${11}"
EXPECTED_CHAIN_NAME="${12}"
DATA_DIR="${13}"
BLOCKS="${14}"
MAX_BLOCK_LAG="${15}"
CURL_TIMEOUT="${16}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing_required_command=$1"
    exit 127
  fi
}

fetch_json() {
  curl -fsS --max-time "$CURL_TIMEOUT" --retry 1 --retry-delay 1 "$1"
}

graphql_query() {
  local url="$1"
  local query="$2"
  curl -fsS --max-time "$CURL_TIMEOUT" --retry 1 --retry-delay 1 \
    -H 'Content-Type: application/json' \
    --data "{\"query\":\"${query}\"}" \
    "$url"
}

json_get() {
  python3 -c 'import json, sys
path = sys.argv[1].split(".")
data = json.loads(sys.stdin.read())
for key in path:
    if key == "":
        continue
    if isinstance(data, dict):
        data = data.get(key)
    else:
        data = None
    if data is None:
        break
if isinstance(data, bool):
    print(str(data).lower())
elif isinstance(data, (dict, list)):
    print(json.dumps(data, separators=(",", ":")))
elif data is None:
    print("")
else:
    print(data)' "$1"
}

is_uint() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

print_runtime() {
  echo "time=$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  if [[ -n "$SERVICE" ]]; then
    echo "service=$(systemctl is-active "$SERVICE" 2>/dev/null || true)"
    echo "service_enabled=$(systemctl is-enabled "$SERVICE" 2>/dev/null || true)"
    echo "service_restarts=$(systemctl show "$SERVICE" -p NRestarts --value 2>/dev/null || true)"
  fi

  if [[ -n "$CONTAINER" ]]; then
    if command -v docker >/dev/null 2>&1; then
      echo "container=$(docker inspect -f '{{.State.Status}}' "$CONTAINER" 2>/dev/null || echo missing)"
      echo "container_image=$(docker inspect -f '{{.Config.Image}}' "$CONTAINER" 2>/dev/null || echo unknown)"
      echo "container_restarts=$(docker inspect -f '{{.RestartCount}}' "$CONTAINER" 2>/dev/null || echo unknown)"
    else
      echo "docker=missing"
    fi
  fi

  if [[ -n "$DATA_DIR" ]]; then
    df -h "$DATA_DIR" 2>/dev/null | awk 'NR==2 {print "data_dir_use=" $5, "data_dir_avail=" $4, "data_dir_mount=" $6}' || true
    df -ih "$DATA_DIR" 2>/dev/null | awk 'NR==2 {print "data_dir_inode_use=" $5}' || true
  fi
}

check_lag() {
  local local_height="$1"
  local public_height="$2"
  if is_uint "$local_height" && is_uint "$public_height"; then
    local gap=$((public_height - local_height))
    echo "height_gap=$gap"
    if [[ -n "$MAX_BLOCK_LAG" ]]; then
      if (( gap <= MAX_BLOCK_LAG )); then
        echo "height_gap_ok=true"
      else
        echo "height_gap_ok=false max=$MAX_BLOCK_LAG"
      fi
    fi
  fi
}

check_ignition() {
  require_cmd curl
  require_cmd python3
  require_cmd date
  print_runtime

  local query='query { chain { name daHeight latestBlock { header { height id } } } nodeInfo { nodeVersion } }'
  local json
  json="$(graphql_query "$GRAPHQL" "$query")"

  local height chain_name da_height node_version block_id
  height="$(printf '%s' "$json" | json_get data.chain.latestBlock.header.height)"
  chain_name="$(printf '%s' "$json" | json_get data.chain.name)"
  da_height="$(printf '%s' "$json" | json_get data.chain.daHeight)"
  node_version="$(printf '%s' "$json" | json_get data.nodeInfo.nodeVersion)"
  block_id="$(printf '%s' "$json" | json_get data.chain.latestBlock.header.id)"

  echo "mode=ignition"
  echo "height=$height"
  echo "chain_name=$chain_name"
  echo "da_height=$da_height"
  echo "node_version=$node_version"
  echo "latest_block_id=$block_id"

  if [[ -n "$EXPECTED_CHAIN_NAME" ]]; then
    if [[ "$chain_name" == "$EXPECTED_CHAIN_NAME" ]]; then
      echo "chain_name_match=true"
    else
      echo "chain_name_match=false expected=$EXPECTED_CHAIN_NAME"
    fi
  fi

  if [[ -n "$PUBLIC_GRAPHQL" ]]; then
    local public_json public_height public_version
    if public_json="$(graphql_query "$PUBLIC_GRAPHQL" "$query" 2>/dev/null)"; then
      public_height="$(printf '%s' "$public_json" | json_get data.chain.latestBlock.header.height)"
      public_version="$(printf '%s' "$public_json" | json_get data.nodeInfo.nodeVersion)"
      echo "public_height=$public_height"
      echo "public_node_version=$public_version"
      check_lag "$height" "$public_height"
    else
      echo "public_graphql_error=unreachable"
    fi
  fi

  if [[ -n "$SERVICE" ]]; then
    echo "recent_errors_begin"
    journalctl -u "$SERVICE" -n 200 --no-pager 2>/dev/null |
      grep -Eai 'error|warn|panic|fatal|rocksdb|relayer|ethereum|graphql|p2p|peer|database' |
      tail -20 || true
    echo "recent_errors_end"
  fi
}

check_sequencer() {
  require_cmd curl
  require_cmd jq
  require_cmd date
  print_runtime

  local status_json height network catching_up voting_power block_time
  status_json="$(fetch_json "$RPC/status")"
  height="$(printf '%s' "$status_json" | jq -r '.result.sync_info.latest_block_height')"
  network="$(printf '%s' "$status_json" | jq -r '.result.node_info.network')"
  catching_up="$(printf '%s' "$status_json" | jq -r '.result.sync_info.catching_up')"
  voting_power="$(printf '%s' "$status_json" | jq -r '.result.validator_info.voting_power')"
  block_time="$(printf '%s' "$status_json" | jq -r '.result.sync_info.latest_block_time')"

  echo "mode=sequencer"
  echo "network=$network"
  echo "height=$height"
  echo "block_time=$block_time"
  echo "catching_up=$catching_up"
  echo "voting_power=$voting_power"

  if [[ -n "$EXPECTED_CHAIN_ID" ]]; then
    if [[ "$network" == "$EXPECTED_CHAIN_ID" ]]; then
      echo "chain_id_match=true"
    else
      echo "chain_id_match=false expected=$EXPECTED_CHAIN_ID"
    fi
  fi

  if [[ -n "$PUBLIC_RPC" ]]; then
    local public_status public_height
    if public_status="$(fetch_json "$PUBLIC_RPC/status" 2>/dev/null)"; then
      public_height="$(printf '%s' "$public_status" | jq -r '.result.sync_info.latest_block_height')"
      echo "public_height=$public_height"
      check_lag "$height" "$public_height"
    else
      echo "public_rpc_error=unreachable"
    fi
  fi

  echo "peers=$(fetch_json "$RPC/net_info" | jq -r '.result.n_peers')"

  local pid bin
  pid="$(pgrep -f "${DAEMON}.*start" | head -1 || true)"
  bin="$DAEMON"
  if [[ -n "$pid" && -e "/proc/$pid/exe" ]]; then
    bin="$(readlink -f "/proc/$pid/exe")"
    echo "pid=$pid"
    echo "exe=$bin"
    echo "version=$("$bin" version 2>/dev/null || true)"
  elif command -v "$DAEMON" >/dev/null 2>&1; then
    echo "pid=missing"
    echo "version=$("$DAEMON" version 2>/dev/null || true)"
  else
    echo "pid=missing"
    echo "version=unknown"
  fi

  if [[ -n "$VALCONS" ]]; then
    local signed checked b flag block_json
    signed=0
    checked=0
    for ((i=1; i<=BLOCKS; i++)); do
      b=$((height-i))
      if [[ "$b" -lt 1 ]]; then
        continue
      fi
      if block_json="$(fetch_json "$RPC/block?height=$b" 2>/dev/null)"; then
        flag="$(printf "%s" "$block_json" |
          jq -r --arg v "$VALCONS" '[.result.block.last_commit.signatures[]? |
            select(.validator_address==$v) | .block_id_flag][0] // "missing"')"
      else
        flag="query_error"
      fi
      echo "signed_$b=$flag"
      checked=$((checked+1))
      if [[ "$flag" == "2" || "$flag" == "BLOCK_ID_FLAG_COMMIT" ]]; then
        signed=$((signed+1))
      fi
    done
    echo "recent_signing=$signed/$checked"
  fi

  if [[ -n "$VALOPER" ]]; then
    local query_bin
    query_bin=""
    if [[ -x "$bin" && "$(basename "$bin")" == "$DAEMON" ]]; then
      query_bin="$bin"
    elif command -v "$DAEMON" >/dev/null 2>&1; then
      query_bin="$DAEMON"
    fi
    if [[ -n "$query_bin" ]]; then
      "$query_bin" query staking validator "$VALOPER" --node "$RPC" -o json 2>/dev/null |
        jq -r '(.validator // .) as $v | "validator_status=" + ($v.status // "unknown"), "jailed=" + (($v.jailed // "unknown")|tostring), "tokens=" + ($v.tokens // "unknown")' || true
    else
      echo "validator_query=skipped_no_${DAEMON}_binary"
    fi
  fi

  if [[ -n "$SERVICE" ]]; then
    echo "recent_errors_begin"
    journalctl -u "$SERVICE" -n 200 --no-pager 2>/dev/null |
      grep -Eai 'error|warn|panic|fatal|consensus|mempool|peer|p2p|sidecar|ethereum|bridge|keyring|database' |
      tail -20 || true
    echo "recent_errors_end"
  fi
}

case "$MODE" in
  ignition) check_ignition ;;
  sequencer) check_sequencer ;;
esac
REMOTE
)"

if [[ "$LOCAL_MODE" == "1" ]]; then
  bash -s -- "$MODE" "$SERVICE" "$CONTAINER" "$GRAPHQL" "$PUBLIC_GRAPHQL" "$RPC" "$PUBLIC_RPC" "$DAEMON" "$VALCONS" "$VALOPER" "$EXPECTED_CHAIN_ID" "$EXPECTED_CHAIN_NAME" "$DATA_DIR" "$BLOCKS" "$MAX_BLOCK_LAG" "$CURL_TIMEOUT" <<<"$REMOTE_SCRIPT"
else
  ssh -o BatchMode=yes -o ConnectTimeout=8 "$HOST" bash -s -- "$MODE" "$SERVICE" "$CONTAINER" "$GRAPHQL" "$PUBLIC_GRAPHQL" "$RPC" "$PUBLIC_RPC" "$DAEMON" "$VALCONS" "$VALOPER" "$EXPECTED_CHAIN_ID" "$EXPECTED_CHAIN_NAME" "$DATA_DIR" "$BLOCKS" "$MAX_BLOCK_LAG" "$CURL_TIMEOUT" <<<"$REMOTE_SCRIPT"
fi
