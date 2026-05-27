#!/usr/bin/env bash
set -euo pipefail

HOST=""
LOCAL_MODE=0
RPC=""
PUBLIC_RPC=""
CLIENT=""
SERVICE=""
ATTESTATION_SERVICE=""
CONTAINER=""
ATTESTATION_CONTAINER=""
EXPECTED_CHAIN_ID=""
EXPECTED_SPEC_VERSION=""
MAX_BLOCK_LAG=""
CURL_TIMEOUT=8

usage() {
  cat <<'USAGE'
Usage:
  starknet-healthcheck.sh [--host <ssh-target>|--local] --rpc <local-json-rpc-url>

Example:
  starknet-healthcheck.sh \
    --host <user>@<host> \
    --rpc http://127.0.0.1:9545/rpc/v0_9 \
    --client pathfinder \
    --container pathfinder \
    --attestation-container starknet-attestation \
    --public-rpc https://<public-rpc>/rpc/v0_9 \
    --expected-chain-id SN_MAIN \
    --max-block-lag 20

Options:
  --local                         Run checks on the current host instead of SSH.
  --client <name>                 Node client label, e.g. pathfinder or juno.
  --service <name>                Optional node systemd service to check.
  --attestation-service <name>    Optional attestation systemd service to check.
  --container <name>              Optional node Docker container to check.
  --attestation-container <name>  Optional attestation Docker container to check.
  --public-rpc <url>              Optional public/reference RPC for block compare.
  --expected-chain-id <id>        Optional expected chain ID label or felt hex.
                                  Examples: SN_MAIN, SN_SEPOLIA.
  --expected-spec-version <ver>   Optional expected starknet_specVersion result.
  --max-block-lag <n>             Optional max allowed local/public block gap.
  --curl-timeout <sec>            Per-request curl timeout. Default: 8.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) HOST="$2"; shift 2 ;;
    --local) LOCAL_MODE=1; shift ;;
    --rpc) RPC="$2"; shift 2 ;;
    --public-rpc) PUBLIC_RPC="$2"; shift 2 ;;
    --client) CLIENT="$2"; shift 2 ;;
    --service) SERVICE="$2"; shift 2 ;;
    --attestation-service) ATTESTATION_SERVICE="$2"; shift 2 ;;
    --container) CONTAINER="$2"; shift 2 ;;
    --attestation-container) ATTESTATION_CONTAINER="$2"; shift 2 ;;
    --expected-chain-id) EXPECTED_CHAIN_ID="$2"; shift 2 ;;
    --expected-spec-version) EXPECTED_SPEC_VERSION="$2"; shift 2 ;;
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

if [[ -z "$RPC" ]]; then
  usage >&2
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

RPC="$1"
PUBLIC_RPC="$2"
CLIENT="$3"
SERVICE="$4"
ATTESTATION_SERVICE="$5"
CONTAINER="$6"
ATTESTATION_CONTAINER="$7"
EXPECTED_CHAIN_ID="$8"
EXPECTED_SPEC_VERSION="$9"
MAX_BLOCK_LAG="${10}"
CURL_TIMEOUT="${11}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing_required_command=$1"
    exit 127
  fi
}

json_rpc() {
  local url="$1"
  local method="$2"
  curl -fsS --max-time "$CURL_TIMEOUT" --retry 1 --retry-delay 1 \
    -H 'Content-Type: application/json' \
    --data "{\"jsonrpc\":\"2.0\",\"method\":\"${method}\",\"params\":[],\"id\":1}" \
    "$url"
}

json_field() {
  python3 - "$1" <<'PY'
import json, sys
data = json.loads(sys.stdin.read())
field = sys.argv[1]
if data.get("error") is not None:
    err = data["error"]
    print("ERROR:" + str(err.get("message", err)))
    raise SystemExit(0)
value = data.get(field)
if value is None:
    value = data.get("result")
if isinstance(value, bool):
    print(str(value).lower())
elif isinstance(value, (dict, list)):
    print(json.dumps(value, separators=(",", ":")))
else:
    print(value)
PY
}

decode_chain_id() {
  python3 - "$1" <<'PY'
import sys
value = sys.argv[1]
try:
    if value.startswith("0x"):
        raw = bytes.fromhex(value[2:])
        print(raw.decode("ascii"))
    else:
        print(value)
except Exception:
    print(value)
PY
}

is_uint() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

require_cmd curl
require_cmd python3
require_cmd date

echo "time=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
[[ -n "$CLIENT" ]] && echo "client=$CLIENT"

if [[ -n "$SERVICE" ]]; then
  echo "service=$(systemctl is-active "$SERVICE" 2>/dev/null || true)"
  echo "service_enabled=$(systemctl is-enabled "$SERVICE" 2>/dev/null || true)"
fi

if [[ -n "$ATTESTATION_SERVICE" ]]; then
  echo "attestation_service=$(systemctl is-active "$ATTESTATION_SERVICE" 2>/dev/null || true)"
  echo "attestation_service_enabled=$(systemctl is-enabled "$ATTESTATION_SERVICE" 2>/dev/null || true)"
fi

if [[ -n "$CONTAINER" ]]; then
  if command -v docker >/dev/null 2>&1; then
    echo "container=$(docker inspect -f '{{.State.Status}}' "$CONTAINER" 2>/dev/null || echo missing)"
    echo "container_image=$(docker inspect -f '{{.Config.Image}}' "$CONTAINER" 2>/dev/null || echo unknown)"
  else
    echo "docker=missing"
  fi
fi

if [[ -n "$ATTESTATION_CONTAINER" ]]; then
  if command -v docker >/dev/null 2>&1; then
    echo "attestation_container=$(docker inspect -f '{{.State.Status}}' "$ATTESTATION_CONTAINER" 2>/dev/null || echo missing)"
    echo "attestation_image=$(docker inspect -f '{{.Config.Image}}' "$ATTESTATION_CONTAINER" 2>/dev/null || echo unknown)"
  else
    echo "docker=missing"
  fi
fi

BLOCK_JSON="$(json_rpc "$RPC" starknet_blockNumber)"
BLOCK_NUMBER="$(printf '%s' "$BLOCK_JSON" | json_field result)"
if ! is_uint "$BLOCK_NUMBER"; then
  echo "block_number_error=$BLOCK_NUMBER"
  exit 1
fi
echo "block_number=$BLOCK_NUMBER"

SYNC_JSON="$(json_rpc "$RPC" starknet_syncing 2>/dev/null || true)"
if [[ -n "$SYNC_JSON" ]]; then
  echo "syncing=$(printf '%s' "$SYNC_JSON" | json_field result)"
else
  echo "syncing=query_error"
fi

CHAIN_JSON="$(json_rpc "$RPC" starknet_chainId 2>/dev/null || true)"
if [[ -n "$CHAIN_JSON" ]]; then
  CHAIN_ID="$(printf '%s' "$CHAIN_JSON" | json_field result)"
  echo "chain_id=$CHAIN_ID"
  echo "chain_id_ascii=$(decode_chain_id "$CHAIN_ID")"
  if [[ -n "$EXPECTED_CHAIN_ID" ]]; then
    DECODED="$(decode_chain_id "$CHAIN_ID")"
    if [[ "$CHAIN_ID" == "$EXPECTED_CHAIN_ID" || "$DECODED" == "$EXPECTED_CHAIN_ID" ]]; then
      echo "chain_id_match=true"
    else
      echo "chain_id_match=false expected=$EXPECTED_CHAIN_ID"
    fi
  fi
else
  echo "chain_id=query_error"
fi

SPEC_JSON="$(json_rpc "$RPC" starknet_specVersion 2>/dev/null || true)"
if [[ -n "$SPEC_JSON" ]]; then
  SPEC_VERSION="$(printf '%s' "$SPEC_JSON" | json_field result)"
  echo "spec_version=$SPEC_VERSION"
  if [[ -n "$EXPECTED_SPEC_VERSION" ]]; then
    if [[ "$SPEC_VERSION" == "$EXPECTED_SPEC_VERSION" ]]; then
      echo "spec_version_match=true"
    else
      echo "spec_version_match=false expected=$EXPECTED_SPEC_VERSION"
    fi
  fi
else
  echo "spec_version=query_error"
fi

if [[ -n "$PUBLIC_RPC" ]]; then
  if PUBLIC_BLOCK_JSON="$(json_rpc "$PUBLIC_RPC" starknet_blockNumber 2>/dev/null)"; then
    PUBLIC_BLOCK="$(printf '%s' "$PUBLIC_BLOCK_JSON" | json_field result)"
    echo "public_block_number=$PUBLIC_BLOCK"
    if is_uint "$PUBLIC_BLOCK"; then
      GAP=$((PUBLIC_BLOCK - BLOCK_NUMBER))
      echo "block_gap=$GAP"
      if [[ -n "$MAX_BLOCK_LAG" ]]; then
        if [[ "$GAP" -le "$MAX_BLOCK_LAG" ]]; then
          echo "block_gap_ok=true"
        else
          echo "block_gap_ok=false max=$MAX_BLOCK_LAG"
        fi
      fi
    fi
  else
    echo "public_rpc_error=unreachable"
  fi
fi

if [[ -n "$CONTAINER" && -x "$(command -v docker 2>/dev/null || true)" ]]; then
  echo "node_recent_errors_begin"
  docker logs --tail 80 "$CONTAINER" 2>&1 |
    grep -iE 'error|warn|ethereum|websocket|provider|l1|database|panic|fatal|rate|timeout' |
    tail -20 || true
  echo "node_recent_errors_end"
fi

if [[ -n "$ATTESTATION_CONTAINER" && -x "$(command -v docker 2>/dev/null || true)" ]]; then
  echo "attestation_recent_signals_begin"
  docker logs --tail 120 "$ATTESTATION_CONTAINER" 2>&1 |
    grep -iE 'current attestation info|epoch|attestation transaction sent|attestation confirmed|error|warn|fatal|panic' |
    tail -30 || true
  echo "attestation_recent_signals_end"
fi
REMOTE
)"

if [[ "$LOCAL_MODE" == "1" ]]; then
  bash -s -- "$RPC" "$PUBLIC_RPC" "$CLIENT" "$SERVICE" "$ATTESTATION_SERVICE" "$CONTAINER" "$ATTESTATION_CONTAINER" "$EXPECTED_CHAIN_ID" "$EXPECTED_SPEC_VERSION" "$MAX_BLOCK_LAG" "$CURL_TIMEOUT" <<<"$REMOTE_SCRIPT"
else
  ssh -o BatchMode=yes -o ConnectTimeout=8 "$HOST" bash -s -- "$RPC" "$PUBLIC_RPC" "$CLIENT" "$SERVICE" "$ATTESTATION_SERVICE" "$CONTAINER" "$ATTESTATION_CONTAINER" "$EXPECTED_CHAIN_ID" "$EXPECTED_SPEC_VERSION" "$MAX_BLOCK_LAG" "$CURL_TIMEOUT" <<<"$REMOTE_SCRIPT"
fi

