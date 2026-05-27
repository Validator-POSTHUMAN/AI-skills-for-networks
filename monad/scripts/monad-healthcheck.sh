#!/usr/bin/env bash
set -euo pipefail

HOST=""
LOCAL_MODE=0
NETWORK=""
RPC="http://127.0.0.1:8080"
PUBLIC_RPC=""
VALIDATOR_ID=""
EXPECTED_VERSION=""
STAKING_CLI=""
METRICS_URL="http://127.0.0.1:8889/metrics"
CURL_TIMEOUT=8
SERVICES=("monad-bft" "monad-execution" "monad-rpc" "otelcol.service")

usage() {
  cat <<'USAGE'
Usage:
  monad-healthcheck.sh [--host <ssh-target>|--local] [options]

Options:
  --network <name>             mainnet, testnet, tempnet, or solonet.
  --rpc <url>                  Local JSON-RPC endpoint. Default: http://127.0.0.1:8080.
  --public-rpc <url>           Optional public JSON-RPC endpoint for height comparison.
  --validator-id <id>          Optional validator ID for staking-cli query.
  --expected-version <version> Optional expected Monad package/runtime version substring.
  --staking-cli <path>         Optional staking-sdk-cli directory or executable.
  --metrics-url <url>          Optional OTel metrics URL. Default: http://127.0.0.1:8889/metrics.
  --service <name>             Override services to check. Repeatable; first use clears defaults.
  --curl-timeout <sec>         Per-request curl timeout. Default: 8.
  -h, --help                   Show this help.
USAGE
}

SERVICES_OVERRIDDEN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) HOST="$2"; shift 2 ;;
    --local) LOCAL_MODE=1; shift ;;
    --network) NETWORK="$2"; shift 2 ;;
    --rpc) RPC="$2"; shift 2 ;;
    --public-rpc) PUBLIC_RPC="$2"; shift 2 ;;
    --validator-id) VALIDATOR_ID="$2"; shift 2 ;;
    --expected-version) EXPECTED_VERSION="$2"; shift 2 ;;
    --staking-cli) STAKING_CLI="$2"; shift 2 ;;
    --metrics-url) METRICS_URL="$2"; shift 2 ;;
    --curl-timeout) CURL_TIMEOUT="$2"; shift 2 ;;
    --service)
      if [[ "$SERVICES_OVERRIDDEN" -eq 0 ]]; then
        SERVICES=()
        SERVICES_OVERRIDDEN=1
      fi
      SERVICES+=("$2")
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ "$LOCAL_MODE" -eq 0 && -z "$HOST" ]]; then
  echo "error: pass --local or --host <ssh-target>" >&2
  exit 2
fi

remote_quote() {
  printf "%q" "$1"
}

run_remote() {
  local script="$1"
  if [[ "$LOCAL_MODE" -eq 1 ]]; then
    bash -s <<<"$script"
  else
    ssh -o BatchMode=yes -o ConnectTimeout=8 "$HOST" "bash -s" <<<"$script"
  fi
}

rpc_payload() {
  local method="$1"
  printf '{"jsonrpc":"2.0","id":1,"method":"%s","params":[]}' "$method"
}

rpc_call_script() {
  local url="$1"
  local method="$2"
  local payload
  payload="$(rpc_payload "$method")"
  printf 'curl -fsS --max-time %q -H %q --data %q %q\n' \
    "$CURL_TIMEOUT" "Content-Type: application/json" "$payload" "$url"
}

hex_to_dec() {
  local value="$1"
  value="${value#0x}"
  if [[ -z "$value" || "$value" == "null" ]]; then
    echo ""
  else
    printf '%d\n' "0x$value"
  fi
}

echo "== Monad healthcheck =="
[[ -n "$NETWORK" ]] && echo "network: $NETWORK"
[[ -n "$HOST" ]] && echo "host: $HOST"
echo "rpc: $RPC"
[[ -n "$PUBLIC_RPC" ]] && echo "public_rpc: $PUBLIC_RPC"

services_joined=""
for service in "${SERVICES[@]}"; do
  services_joined+=" $(remote_quote "$service")"
done

local_script="
set -euo pipefail
echo '== services =='
for s in$services_joined; do
  printf '%s ' \"\$s\"
  systemctl is-active \"\$s\" 2>/dev/null || true
done

echo '== versions =='
for b in monad-node monad-rpc monad-bft monad; do
  if command -v \"\$b\" >/dev/null 2>&1; then
    \"\$b\" --version 2>/dev/null | head -1 || true
  fi
done

echo '== disk =='
df -h / /home /dev/triedb 2>/dev/null || df -h /

echo '== triedb =='
if command -v monad-mpt >/dev/null 2>&1 && [[ -e /dev/triedb ]]; then
  timeout 15s monad-mpt --storage /dev/triedb 2>/dev/null | sed -n '1,20p' || true
else
  echo 'monad-mpt or /dev/triedb unavailable'
fi

echo '== local rpc =='
$(rpc_call_script "$RPC" "eth_chainId") || true
echo
$(rpc_call_script "$RPC" "eth_blockNumber") || true
echo
$(rpc_call_script "$RPC" "eth_syncing") || true
echo
$(rpc_call_script "$RPC" "web3_clientVersion") || true
echo

echo '== metrics =='
curl -fsS --max-time $(remote_quote "$CURL_TIMEOUT") $(remote_quote "$METRICS_URL") 2>/dev/null | sed -n '1,8p' || true

echo '== recent errors =='
journalctl -u monad-bft -u monad-execution -u monad-rpc --since '15 minutes ago' --no-pager 2>/dev/null \
  | grep -Ei 'panic|fatal|error|failed|triedb|statesync|blocksync' \
  | tail -40 || true
"

run_remote "$local_script"

local_block_json="$(run_remote "$(rpc_call_script "$RPC" "eth_blockNumber")" 2>/dev/null || true)"
local_block_hex="$(printf '%s' "$local_block_json" | jq -r '.result // empty' 2>/dev/null || true)"
local_block_dec="$(hex_to_dec "$local_block_hex")"

if [[ -n "$PUBLIC_RPC" ]]; then
  echo "== public rpc compare =="
  public_block_json="$(curl -fsS --max-time "$CURL_TIMEOUT" \
    -H 'Content-Type: application/json' \
    --data '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}' \
    "$PUBLIC_RPC" 2>/dev/null || true)"
  public_block_hex="$(printf '%s' "$public_block_json" | jq -r '.result // empty' 2>/dev/null || true)"
  public_block_dec="$(hex_to_dec "$public_block_hex")"
  echo "local_height: ${local_block_dec:-unknown}"
  echo "public_height: ${public_block_dec:-unknown}"
  if [[ -n "$local_block_dec" && -n "$public_block_dec" ]]; then
    echo "height_lag: $((public_block_dec - local_block_dec))"
  fi
fi

if [[ -n "$EXPECTED_VERSION" ]]; then
  echo "== expected version check =="
  version_output="$(run_remote 'for b in monad-node monad-rpc monad-bft monad; do command -v "$b" >/dev/null 2>&1 && "$b" --version 2>/dev/null || true; done' 2>/dev/null || true)"
  if printf '%s\n' "$version_output" | grep -F "$EXPECTED_VERSION" >/dev/null; then
    echo "expected_version_match: yes ($EXPECTED_VERSION)"
  else
    echo "expected_version_match: no ($EXPECTED_VERSION)"
  fi
fi

if [[ -n "$STAKING_CLI" && -n "$VALIDATOR_ID" ]]; then
  echo "== staking-cli validator query =="
  staking_script="
set -euo pipefail
target=$(remote_quote "$STAKING_CLI")
validator_id=$(remote_quote "$VALIDATOR_ID")
if [[ -d \"\$target\" ]]; then
  cd \"\$target\"
  if [[ -f cli-venv/bin/activate ]]; then source cli-venv/bin/activate; fi
  if [[ -f staking-cli/main.py ]]; then
    python staking-cli/main.py query validator --validator-id \"\$validator_id\"
  elif [[ -f main.py ]]; then
    python main.py query validator --validator-id \"\$validator_id\"
  else
    echo 'staking-cli directory found but main.py path is unknown'
  fi
elif [[ -x \"\$target\" ]]; then
  \"\$target\" query validator --validator-id \"\$validator_id\"
else
  echo 'staking-cli not found or not executable'
fi
"
  run_remote "$staking_script" || true
fi
