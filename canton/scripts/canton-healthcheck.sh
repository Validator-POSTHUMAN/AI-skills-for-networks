#!/usr/bin/env bash
# Read-only health check for a Canton Network (Splice) validator.
#
# Never writes, never restarts a container, never submits a transaction, never
# reads secret material. Exit code 0 = all requested checks passed,
# 1 = at least one failed.

set -uo pipefail

HOST=""
LOCAL_MODE=0
NETWORK=""
PROJECT="splice-validator"
SCAN_URL=""
MAX_SYNC_LAG_MS=60000
CURL_TIMEOUT=10
FAILURES=0

usage() {
  cat <<'USAGE'
Usage:
  canton-healthcheck.sh [--host <ssh-target>|--local] --network <mainnet|testnet|devnet> [options]

Options:
  --host <user@host>        run node checks over SSH
  --local                   run node checks on this machine
  --network <name>          mainnet | testnet | devnet (selects the /info endpoint)
  --project <name>          Compose project name prefix (default: splice-validator)
  --scan-url <url>          Scan base URL to probe, e.g.
                            https://scan.sv-1.dev.global.canton.network.digitalasset.com
  --max-sync-lag-ms <ms>    fail if sync lag exceeds this (default: 60000)
  --timeout <seconds>       HTTP timeout (default: 10)

Notes:
  MainNet and TestNet Scan endpoints answer 403 from any address that is not an
  onboarded validator. Run --scan-url from the validator host, or omit it.

Example:
  canton-healthcheck.sh --host valoper@1.2.3.4 --network mainnet \
    --scan-url https://scan.sv-1.global.canton.network.digitalasset.com
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --host) HOST="${2:-}"; shift 2 ;;
    --local) LOCAL_MODE=1; shift ;;
    --network) NETWORK="${2:-}"; shift 2 ;;
    --project) PROJECT="${2:-}"; shift 2 ;;
    --scan-url) SCAN_URL="${2:-}"; shift 2 ;;
    --max-sync-lag-ms) MAX_SYNC_LAG_MS="${2:-}"; shift 2 ;;
    --timeout) CURL_TIMEOUT="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

if [ -z "$HOST" ] && [ "$LOCAL_MODE" -eq 0 ]; then
  echo "one of --host or --local is required" >&2; usage; exit 2
fi
case "$NETWORK" in
  mainnet|testnet|devnet) ;;
  *) echo "--network must be mainnet, testnet or devnet" >&2; exit 2 ;;
esac

case "$NETWORK" in
  mainnet) INFO_URL="https://docs.global.canton.network.sync.global/info" ;;
  testnet) INFO_URL="https://docs.test.global.canton.network.sync.global/info" ;;
  devnet)  INFO_URL="https://docs.dev.global.canton.network.sync.global/info" ;;
esac

run() {
  if [ "$LOCAL_MODE" -eq 1 ]; then
    bash -c "$1"
  else
    ssh -o BatchMode=yes -o ConnectTimeout=15 "$HOST" "$1"
  fi
}

report() {
  # report <name> <ok|fail|warn|info> <detail>
  printf 'check=%s result=%s %s\n' "$1" "$2" "$3"
  [ "$2" = "fail" ] && FAILURES=$((FAILURES + 1))
  return 0
}

# ---------------------------------------------------------------- containers
containers="$(run "docker ps --format '{{.Names}}\t{{.Status}}' | grep -- '${PROJECT}-' || true")"
if [ -z "$containers" ]; then
  report containers fail "no containers matching ${PROJECT}-"
else
  total=$(printf '%s\n' "$containers" | wc -l | tr -d ' ')
  unhealthy=$(printf '%s\n' "$containers" | grep -c 'unhealthy' || true)
  starting=$(printf '%s\n' "$containers" | grep -c 'health: starting' || true)
  if [ "$unhealthy" -gt 0 ]; then
    report containers fail "total=${total} unhealthy=${unhealthy}"
    printf '%s\n' "$containers" | grep 'unhealthy' | sed 's/^/  unhealthy: /'
  elif [ "$starting" -gt 0 ]; then
    report containers warn "total=${total} starting=${starting}"
  else
    report containers ok "total=${total} all_healthy"
  fi
fi

# ------------------------------------------------------------------- version
validator_container="$(run "docker ps --format '{{.Names}}' | grep -- '${PROJECT}-validator' | head -1")"
if [ -z "$validator_container" ]; then
  report version fail "validator container not found"
  running_version=""
else
  image="$(run "docker inspect ${validator_container} --format '{{.Config.Image}}'")"
  running_version="${image##*:}"
  report version info "container=${validator_container} image=${image}"
fi

info_json="$(curl -s --max-time "$CURL_TIMEOUT" "$INFO_URL" || true)"
if [ -z "$info_json" ]; then
  report network_info fail "no response from ${INFO_URL}"
else
  net_version="$(printf '%s' "$info_json" | sed -n 's/.*"sv":{"migration_id":[0-9]*,"serial_id":[0-9]*,"version":"\([^"]*\)".*/\1/p')"
  migration_id="$(printf '%s' "$info_json" | sed -n 's/.*"sv":{"migration_id":\([0-9]*\).*/\1/p')"
  report network_info ok "network=${NETWORK} version=${net_version:-unknown} migration_id=${migration_id:-unknown}"
  if [ -n "$running_version" ] && [ -n "$net_version" ]; then
    if [ "$running_version" = "$net_version" ]; then
      report version_drift ok "running=${running_version} network=${net_version}"
    else
      report version_drift warn "running=${running_version} network=${net_version}"
    fi
  fi
fi

# -------------------------------------------------------------------- metrics
# The validator image ships wget, not curl. Try both rather than assuming
# either: an exec that fails on a missing binary returns an empty body and
# reads as "metrics port down".
metrics="$(run "docker exec ${validator_container:-none} wget -q -O - --timeout=${CURL_TIMEOUT} http://localhost:10013/metrics 2>/dev/null \
  || docker exec ${validator_container:-none} curl -s --max-time ${CURL_TIMEOUT} http://localhost:10013/metrics 2>/dev/null \
  || true")"
if [ -z "$metrics" ]; then
  report metrics fail "port 10013 returned nothing on ${validator_container:-unknown}"
else
  report metrics ok "bytes=$(printf '%s' "$metrics" | wc -c | tr -d ' ')"

  # Values are exported in scientific notation (1.789684504197E12). Let awk do
  # the arithmetic; shell integer maths cannot parse them.
  last_seen="$(printf '%s\n' "$metrics" | awk '/^splice_store_last_seen_record_time_ms/ {v=$NF} END {print v}')"
  if [ -n "${last_seen:-}" ]; then
    lag=$(awk -v n="$(date -u +%s)" -v l="$last_seen" 'BEGIN {printf "%d", n * 1000 - l + 0}')
    if [ "$lag" -le "$MAX_SYNC_LAG_MS" ]; then
      report sync_lag ok "lag_ms=${lag} threshold_ms=${MAX_SYNC_LAG_MS}"
    else
      report sync_lag fail "lag_ms=${lag} threshold_ms=${MAX_SYNC_LAG_MS}"
    fi
  else
    report sync_lag warn "splice_store_last_seen_record_time_ms not exported"
  fi

  # Automation health is a gauge where 0 means healthy; 29 services report it
  # on a validator. Anything non-zero names the broken automation directly.
  unhealthy_services="$(printf '%s\n' "$metrics" \
    | awk '/^splice_automation_background_service_health/ && $NF+0 != 0 {print}' | wc -l | tr -d ' ')"
  if [ "${unhealthy_services:-0}" -eq 0 ]; then
    report automation ok "all background services healthy"
  else
    report automation fail "unhealthy_background_services=${unhealthy_services}"
    printf '%s\n' "$metrics" | awk '/^splice_automation_background_service_health/ && $NF+0 != 0 {print}' \
      | grep -oE 'service="[A-Za-z]+"' | sort -u | sed 's/^/  /'
  fi

  # Reward liveness. The polling loop and the completion counter are different
  # facts: iterations prove the trigger runs, completions prove it did work.
  # The completion series is ABSENT until the first completion, so an alert
  # written as rate(...) == 0 never fires on a node that never collected.
  faucet_iter="$(printf '%s\n' "$metrics" \
    | awk '/^splice_trigger_iterations_total/ && /ReceiveFaucetCouponTrigger/ {v=$NF} END {print v}')"
  faucet_done="$(printf '%s\n' "$metrics" \
    | awk '/^splice_trigger_completed_total/ && /ReceiveFaucetCouponTrigger/ {v=$NF} END {print v}')"
  report reward_trigger info \
    "iterations=${faucet_iter:-absent} completed=${faucet_done:-absent} (compare both against a previous run)"

  balance="$(printf '%s\n' "$metrics" | awk '/^splice_wallet_unlocked_amulet_balance/ {v=$NF} END {print v}')"
  [ -n "${balance:-}" ] && report cc_balance info "unlocked_amulet_balance=${balance}"

  retry_total="$(printf '%s\n' "$metrics" \
    | awk '/^splice_retries_failures/ {s += $NF} END {printf "%d", s}')"
  report retry_failures info "splice_retries_failures_sum=${retry_total}"
fi

# ----------------------------------------------------------------------- disk
disk_free_gb="$(run "df -BG --output=avail / | tail -1 | tr -dc '0-9'")"
if [ -n "${disk_free_gb:-}" ]; then
  if [ "$disk_free_gb" -ge 20 ]; then
    report disk ok "root_free_gb=${disk_free_gb}"
  else
    report disk fail "root_free_gb=${disk_free_gb} threshold_gb=20"
  fi
else
  report disk warn "could not read free space"
fi

# ----------------------------------------------------------------------- scan
if [ -n "$SCAN_URL" ]; then
  scan_code="$(run "curl -s -o /dev/null -w '%{http_code}' --max-time ${CURL_TIMEOUT} ${SCAN_URL}/api/scan/version")"
  case "$scan_code" in
    200) report scan ok "code=200 url=${SCAN_URL}" ;;
    403) report scan fail "code=403 RBAC — this source IP is not an onboarded validator for ${NETWORK}" ;;
    *)   report scan fail "code=${scan_code} url=${SCAN_URL}" ;;
  esac
fi

echo "failures=${FAILURES}"
[ "$FAILURES" -eq 0 ]
