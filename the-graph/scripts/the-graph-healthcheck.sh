#!/usr/bin/env bash
# Read-only health check for a Graph Protocol indexer.
#
# Never writes, never submits a transaction, never reads secret material.
# Exit code 0 = all requested checks passed, 1 = at least one failed.

set -uo pipefail

HOST=""
LOCAL_MODE=0
CLI_CONTAINER="cli"
STATUS_URL=""
PUBLIC_ENDPOINT=""
AGENT_METRICS=""
SERVICE_METRICS=""
TAP_METRICS=""
MIN_OPERATOR_ETH=""
MAX_BLOCK_LAG=""
CURL_TIMEOUT=8
CLI_TIMEOUT=180
FAILURES=0

usage() {
  cat <<'USAGE'
Usage:
  the-graph-healthcheck.sh [--host <ssh-target>|--local] [options]

Options:
  --host <user@host>          run checks over SSH
  --local                     run checks on this machine
  --cli-container <name>      graph CLI container name (default: cli)
  --status-url <url>          graph-node status API, e.g. http://127.0.0.1:8030/graphql
  --public-endpoint <url>     public indexer endpoint, e.g. https://index.example.com
  --agent-metrics <url>       indexer-agent metrics, e.g. http://127.0.0.1:7300/metrics
  --service-metrics <url>     indexer-service metrics
  --tap-metrics <url>         indexer-tap metrics
  --min-operator-eth <value>  fail if operator ETH balance is below this
  --max-block-lag <blocks>    fail if a deployment lags chain head by more than this
  --timeout <seconds>         HTTP timeout (default: 8)
  --cli-timeout <seconds>     timeout for graph CLI calls (default: 180; they are slow)

Example:
  the-graph-healthcheck.sh --local \
    --status-url http://127.0.0.1:8030/graphql \
    --public-endpoint https://index.example.com \
    --agent-metrics http://127.0.0.1:7300/metrics \
    --min-operator-eth 0.05 --max-block-lag 100
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --host) HOST="$2"; shift 2 ;;
    --local) LOCAL_MODE=1; shift ;;
    --cli-container) CLI_CONTAINER="$2"; shift 2 ;;
    --status-url) STATUS_URL="$2"; shift 2 ;;
    --public-endpoint) PUBLIC_ENDPOINT="$2"; shift 2 ;;
    --agent-metrics) AGENT_METRICS="$2"; shift 2 ;;
    --service-metrics) SERVICE_METRICS="$2"; shift 2 ;;
    --tap-metrics) TAP_METRICS="$2"; shift 2 ;;
    --min-operator-eth) MIN_OPERATOR_ETH="$2"; shift 2 ;;
    --max-block-lag) MAX_BLOCK_LAG="$2"; shift 2 ;;
    --timeout) CURL_TIMEOUT="$2"; shift 2 ;;
    --cli-timeout) CLI_TIMEOUT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

if [ -z "$HOST" ] && [ "$LOCAL_MODE" -eq 0 ]; then
  echo "choose --host <ssh-target> or --local" >&2
  exit 2
fi

run() {
  if [ "$LOCAL_MODE" -eq 1 ]; then
    bash -c "$1"
  else
    ssh -o BatchMode=yes "$HOST" "$1"
  fi
}

ok()   { printf 'OK    %s\n' "$1"; }
warn() { printf 'WARN  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; FAILURES=$((FAILURES + 1)); }

section() { printf '\n== %s\n' "$1"; }

# ---------------------------------------------------------------- containers
section "containers"
CONTAINERS=$(run "docker ps --format '{{.Names}}\t{{.Status}}' 2>/dev/null")
if [ -z "$CONTAINERS" ]; then
  warn "no docker output; skipping container checks"
else
  printf '%s\n' "$CONTAINERS" | grep -Ei 'graph|index|tap|postgres' || true
  if printf '%s\n' "$CONTAINERS" | grep -qi 'restarting'; then
    fail "at least one container is restarting"
  else
    ok "no container in Restarting state"
  fi
fi

# ------------------------------------------------------------- deployments
if [ -n "$STATUS_URL" ]; then
  section "deployments"
  STATUS_JSON=$(run "curl -s --max-time $CURL_TIMEOUT -H 'content-type: application/json' -d '{\"query\":\"{ indexingStatuses { subgraph health synced chains { chainHeadBlock { number } latestBlock { number } } } }\"}' '$STATUS_URL'")
  if [ -z "$STATUS_JSON" ]; then
    fail "status API returned nothing: $STATUS_URL"
  else
    STATUS_JSON="$STATUS_JSON" MAX_BLOCK_LAG="$MAX_BLOCK_LAG" python3 <<'PY'
import json, os, sys
raw = os.environ.get("STATUS_JSON", "")
max_lag = os.environ.get("MAX_BLOCK_LAG", "")
try:
    statuses = json.loads(raw)["data"]["indexingStatuses"]
except Exception as exc:
    print(f"FAIL  cannot parse status API response: {exc}")
    sys.exit(1)
bad = 0
for s in statuses:
    dep = s["subgraph"]
    chains = s.get("chains") or [{}]
    head = chains[0].get("chainHeadBlock") or {}
    latest = chains[0].get("latestBlock") or {}
    lag = None
    if head.get("number") and latest.get("number"):
        lag = int(head["number"]) - int(latest["number"])
    line = f"{dep[:12]}… health={s['health']} synced={s['synced']}"
    if lag is not None:
        line += f" lag={lag}"
    if s["health"] != "healthy" or not s["synced"]:
        print(f"FAIL  {line}")
        bad += 1
    elif max_lag and lag is not None and lag > int(max_lag):
        print(f"FAIL  {line} exceeds max lag {max_lag}")
        bad += 1
    else:
        print(f"OK    {line}")
print(f"      {len(statuses)} deployment(s), {bad} failing")
sys.exit(1 if bad else 0)
PY
    [ $? -ne 0 ] && FAILURES=$((FAILURES + 1))
  fi
fi

# ------------------------------------------------------------ protocol state
section "protocol state"
ALLOC=$(run "timeout $CLI_TIMEOUT docker exec $CLI_CONTAINER graph indexer allocations get all --network arbitrum-one 2>/dev/null")
if [ -z "$ALLOC" ]; then
  warn "no allocation output within ${CLI_TIMEOUT}s; check that CLI container '$CLI_CONTAINER' is running"
else
  printf '%s\n' "$ALLOC" | head -20
  ok "allocations queried"
fi

ACTIONS=$(run "timeout $CLI_TIMEOUT docker exec $CLI_CONTAINER graph indexer actions get all --network arbitrum-one 2>/dev/null")
if [ -n "$ACTIONS" ]; then
  if printf '%s\n' "$ACTIONS" | grep -Eq '\b(queued|approved|pending)\b'; then
    fail "non-terminal indexer action present"
    printf '%s\n' "$ACTIONS" | grep -E '\b(queued|approved|pending)\b' | head -10
  else
    ok "no non-terminal indexer action"
  fi
fi

# ---------------------------------------------------------- public endpoint
if [ -n "$PUBLIC_ENDPOINT" ]; then
  section "public endpoint (checked from this machine)"
  for path in "/" "/healthz" "/status"; do
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time "$CURL_TIMEOUT" "${PUBLIC_ENDPOINT%/}$path")
    if [ "$code" = "200" ]; then
      ok "$path -> $code"
    else
      fail "$path -> $code"
    fi
  done
fi

# ----------------------------------------------------------------- metrics
scrape() { run "curl -s --max-time $CURL_TIMEOUT '$1'"; }

if [ -n "$AGENT_METRICS" ]; then
  section "indexer-agent metrics"
  M=$(scrape "$AGENT_METRICS")
  BAL=$(printf '%s\n' "$M" | awk '/^indexer_agent_operator_eth_balance/ {print $2; exit}')
  if [ -z "$BAL" ]; then
    warn "operator ETH balance metric not found"
  elif [ -n "$MIN_OPERATOR_ETH" ] && awk -v b="$BAL" -v m="$MIN_OPERATOR_ETH" 'BEGIN{exit !(b < m)}'; then
    fail "operator ETH balance $BAL below floor $MIN_OPERATOR_ETH"
  else
    ok "operator ETH balance $BAL"
  fi
  FAILED_REDEEMS=$(printf '%s\n' "$M" | awk '/^indexer_agent_rav_v2_redeems_failed/ {print $2; exit}')
  [ -n "$FAILED_REDEEMS" ] && printf '      rav_v2_redeems_failed=%s\n' "$FAILED_REDEEMS"
fi

if [ -n "$SERVICE_METRICS" ]; then
  section "indexer-service metrics"
  M=$(scrape "$SERVICE_METRICS")
  INVALID=$(printf '%s\n' "$M" | awk '/^indexer_tap_invalid_total/ {s+=$2} END {print s+0}')
  if [ "${INVALID:-0}" != "0" ]; then
    warn "indexer_tap_invalid_total=$INVALID — paid queries are being rejected"
  else
    ok "no invalid TAP receipts counted"
  fi
fi

if [ -n "$TAP_METRICS" ]; then
  section "indexer-tap metrics"
  M=$(scrape "$TAP_METRICS")
  DENIED=$(printf '%s\n' "$M" | awk '/^tap_sender_denied/ {s+=$2} END {print s+0}')
  RECEIPTS=$(printf '%s\n' "$M" | awk '/^tap_receipts_received_total/ {s+=$2} END {print s+0}')
  if [ "${DENIED:-0}" != "0" ]; then
    fail "tap_sender_denied=$DENIED — check the GraphTally sender allow-list"
  else
    ok "no denied GraphTally sender"
  fi
  printf '      tap_receipts_received_total=%s (compare against the previous run; flat means no gateway traffic)\n' "$RECEIPTS"
fi

section "result"
if [ "$FAILURES" -eq 0 ]; then
  echo "all requested checks passed"
  echo "NOTE: POI staleness and REO rewards eligibility are not covered here — verify them separately."
  exit 0
fi
echo "$FAILURES check(s) failed"
exit 1
