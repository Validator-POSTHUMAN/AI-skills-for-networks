#!/usr/bin/env bash
# Read-only XRPL EVM (exrpd) node health check.
#
# It runs no mutating command, changes nothing on the host, and prints no
# credential or key material.
#
# Two checks decide almost everything here, and most setups have neither:
#
#   1. Does this node AGREE with the network? `catching_up=false` is fully
#      compatible with following a different chain. The only thing that
#      settles it is the app hash at a common height, compared against an
#      independent RPC.
#   2. Is it SIGNING? A validator can be up, synced, and quietly absent from
#      every commit. `voting_power` alone does not show that.
#
# It also samples the height twice, because one reading cannot distinguish
# "advancing" from "stopped a second ago".
set -euo pipefail

HOST=""
LOCAL_MODE=0
RPC="http://127.0.0.1:26657"
REFERENCE="https://cosmos-rpc.xrplevm.org"
REFERENCE2=""
EXPECTED_CHAIN_ID=""
SERVICE=""
NODE_HOME=""
EXPECT_SIGNING=0
MIN_PEERS=5
MAX_HEAD_AGE=60
DISK_WARN_PERCENT=90
DISK_PATH="/"
SKIP_EXTERNAL=0
SAMPLE_WAIT=12
CURL_TIMEOUT=8

usage() {
  cat <<'USAGE'
Usage:
  xrplevm-healthcheck.sh [--local|--host <ssh-target>] [options]

Examples:
  xrplevm-healthcheck.sh --local --chain-id xrplevm_1440000-1
  xrplevm-healthcheck.sh --local --service exrpd --expect-signing \
      --chain-id xrplevm_1440000-1
  xrplevm-healthcheck.sh --host <user>@<host> \
      --rpc http://127.0.0.1:62657 \
      --reference https://cosmos-rpc.xrplevm.org \
      --reference2 https://xrplevm-mainnet-rpc.itrocket.net

Options:
  --local                  Run on the current host instead of over SSH.
  --host <ssh-target>      Run over SSH on this target.
  --rpc <url>              CometBFT RPC.   Default: http://127.0.0.1:26657
  --reference <url>        Independent RPC for agreement checks.
  --reference2 <url>       A second independent RPC. Strongly recommended.
  --chain-id <id>          Expected chain id, e.g. xrplevm_1440000-1
  --service <unit>         systemd unit to inspect. "" to skip.
  --node-home <path>       Node home, for the disk check.
  --expect-signing         Require non-zero voting power and commit presence.
  --min-peers <n>          Minimum peer count.       Default: 5
  --max-head-age <s>       Head age that fails.      Default: 60
  --disk-path <path>       Filesystem to check.      Default: /
  --disk-warn <percent>    Disk use that warns.      Default: 90
  --sample-wait <s>        Seconds between samples.  Default: 12
  --skip-external          Do not contact any reference RPC.
  -h, --help               This message.

Exit code is the number of failed checks.
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --local) LOCAL_MODE=1 ;;
    --host) HOST="${2:-}"; shift ;;
    --rpc) RPC="${2:-}"; shift ;;
    --reference) REFERENCE="${2:-}"; shift ;;
    --reference2) REFERENCE2="${2:-}"; shift ;;
    --chain-id) EXPECTED_CHAIN_ID="${2:-}"; shift ;;
    --service) SERVICE="${2:-}"; shift ;;
    --node-home) NODE_HOME="${2:-}"; shift ;;
    --expect-signing) EXPECT_SIGNING=1 ;;
    --min-peers) MIN_PEERS="${2:-}"; shift ;;
    --max-head-age) MAX_HEAD_AGE="${2:-}"; shift ;;
    --disk-path) DISK_PATH="${2:-}"; shift ;;
    --disk-warn) DISK_WARN_PERCENT="${2:-}"; shift ;;
    --sample-wait) SAMPLE_WAIT="${2:-}"; shift ;;
    --skip-external) SKIP_EXTERNAL=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if [ "$LOCAL_MODE" -eq 0 ] && [ -z "$HOST" ]; then
  echo "one of --local or --host is required" >&2
  exit 2
fi

FAILED=0
pass() { printf '  PASS  %-22s %s\n' "$1" "${2:-}"; }
warn() { printf '  WARN  %-22s %s\n' "$1" "${2:-}"; }
fail() { printf '  FAIL  %-22s %s\n' "$1" "${2:-}"; FAILED=$((FAILED + 1)); }

# Run a command on the target. Nothing here mutates state.
run() {
  if [ "$LOCAL_MODE" -eq 1 ]; then
    bash -lc "$1"
  else
    ssh -o BatchMode=yes -o ConnectTimeout=10 "$HOST" "$1"
  fi
}

# Fetch from the node's RPC, from wherever the node is.
node_get() {
  run "curl -fsS --max-time ${CURL_TIMEOUT} '${RPC}$1' 2>/dev/null || true"
}

# Fetch from a reference RPC, from this machine.
ref_get() {
  curl -fsS --max-time "${CURL_TIMEOUT}" "$1$2" 2>/dev/null || true
}

jqr() { printf '%s' "$1" | jq -r "$2" 2>/dev/null || true; }

command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 2; }

echo "XRPL EVM node health check"
echo "  target      ${HOST:-local}"
echo "  rpc         ${RPC}"
echo

# --- service -----------------------------------------------------------------
if [ -n "$SERVICE" ]; then
  state="$(run "systemctl is-active ${SERVICE} 2>/dev/null || true" | tr -d '[:space:]')"
  case "$state" in
    active) pass "service.active" "${SERVICE}" ;;
    "")     warn "service.active" "${SERVICE}: no answer from systemctl" ;;
    *)      fail "service.active" "${SERVICE} is ${state}" ;;
  esac

  restarts="$(run "systemctl show -p NRestarts --value ${SERVICE} 2>/dev/null || true" | tr -d '[:space:]')"
  if [ -n "$restarts" ]; then
    if [ "$restarts" = "0" ]; then
      pass "service.restarts" "NRestarts=0"
    else
      warn "service.restarts" "NRestarts=${restarts} — check why it restarted"
    fi
  fi
fi

# --- status ------------------------------------------------------------------
status="$(node_get /status)"
if [ -z "$status" ]; then
  fail "rpc.reachable" "${RPC}/status returned nothing"
  echo
  echo "healthcheck=failed"
  exit "$FAILED"
fi
pass "rpc.reachable" "${RPC}"

network="$(jqr "$status" '.result.node_info.network')"
height1="$(jqr "$status" '.result.sync_info.latest_block_height')"
blocktime="$(jqr "$status" '.result.sync_info.latest_block_time')"
catching="$(jqr "$status" '.result.sync_info.catching_up')"
power="$(jqr "$status" '.result.validator_info.voting_power')"
valaddr="$(jqr "$status" '.result.validator_info.address')"

# --- chain identity ----------------------------------------------------------
if [ -n "$EXPECTED_CHAIN_ID" ]; then
  if [ "$network" = "$EXPECTED_CHAIN_ID" ]; then
    pass "chain.id" "$network"
  else
    fail "chain.id" "node reports '${network}', expected '${EXPECTED_CHAIN_ID}'"
  fi
else
  warn "chain.id" "${network} (no --chain-id given, not verified)"
fi

case "$network" in
  *_144000-1)
    fail "chain.id.digits" \
      "'${network}' has six digits. Mainnet is xrplevm_1440000-1. This exact typo causes deterministic app-hash divergence."
    ;;
esac

# --- version -----------------------------------------------------------------
abci="$(node_get /abci_info)"
version="$(jqr "$abci" '.result.response.version')"
[ -n "$version" ] && pass "node.version" "$version" || warn "node.version" "not reported"

# --- sync --------------------------------------------------------------------
if [ "$catching" = "false" ]; then
  pass "sync.catching_up" "false"
elif [ "$catching" = "true" ]; then
  fail "sync.catching_up" "true — node is still syncing"
else
  warn "sync.catching_up" "unknown"
fi

if [ -n "$blocktime" ]; then
  bt_epoch="$(date -u -d "$blocktime" +%s 2>/dev/null || echo "")"
  if [ -n "$bt_epoch" ]; then
    age=$(( $(date -u +%s) - bt_epoch ))
    if [ "$age" -le "$MAX_HEAD_AGE" ]; then
      pass "sync.head_age" "${age}s"
    else
      fail "sync.head_age" "${age}s > ${MAX_HEAD_AGE}s — head is stale"
    fi
  fi
fi

# --- height advances ---------------------------------------------------------
# One reading cannot tell "advancing" from "stopped a second ago".
sleep "$SAMPLE_WAIT"
status2="$(node_get /status)"
height2="$(jqr "$status2" '.result.sync_info.latest_block_height')"
if [ -n "$height1" ] && [ -n "$height2" ]; then
  if [ "$height2" -gt "$height1" ]; then
    pass "sync.advancing" "${height1} -> ${height2} in ${SAMPLE_WAIT}s"
  else
    fail "sync.advancing" "height did not move: ${height1} -> ${height2}"
  fi
fi

# --- peers -------------------------------------------------------------------
peers="$(jqr "$(node_get /net_info)" '.result.n_peers')"
if [ -n "$peers" ]; then
  if [ "$peers" -ge "$MIN_PEERS" ]; then
    pass "p2p.peers" "$peers"
  else
    fail "p2p.peers" "${peers} < ${MIN_PEERS} — stale addrbook or empty persistent_peers"
  fi
fi

# --- agreement with the network ----------------------------------------------
# A node agreeing with itself proves nothing.
check_reference() {
  ref="$1"; label="$2"
  [ -z "$ref" ] && return 0
  local_hash="$(jqr "$(node_get "/block?height=${height2}")" '.result.block.header.app_hash')"
  ref_hash="$(jqr "$(ref_get "$ref" "/block?height=${height2}")" '.result.block.header.app_hash')"
  if [ -z "$ref_hash" ]; then
    warn "agree.${label}" "${ref} did not answer for height ${height2}"
    return 0
  fi
  if [ -z "$local_hash" ]; then
    warn "agree.${label}" "local node did not return an app hash for ${height2}"
    return 0
  fi
  if [ "$local_hash" = "$ref_hash" ]; then
    pass "agree.${label}" "app hash matches at ${height2}"
  else
    fail "agree.${label}" "APP HASH DIVERGENCE at ${height2}: local ${local_hash}, ${ref} ${ref_hash}"
  fi
}

if [ "$SKIP_EXTERNAL" -eq 0 ]; then
  check_reference "$REFERENCE" "ref1"
  if [ -n "$REFERENCE2" ]; then
    check_reference "$REFERENCE2" "ref2"
  else
    warn "agree.ref2" "only one reference RPC — a second independent source is strongly recommended"
  fi

  ref_ver="$(jqr "$(ref_get "$REFERENCE" /abci_info)" '.result.response.version')"
  if [ -n "$ref_ver" ] && [ -n "$version" ]; then
    if [ "$ref_ver" = "$version" ]; then
      pass "version.fleet" "local and ${REFERENCE} both ${version}"
    else
      warn "version.fleet" "local ${version}, ${REFERENCE} ${ref_ver} — patch releases do not appear in the docs table or as an on-chain plan"
    fi
  fi
else
  warn "agree" "skipped — this check is the one that detects a wrong chain"
fi

# --- signing -----------------------------------------------------------------
if [ "$EXPECT_SIGNING" -eq 1 ]; then
  if [ -n "$power" ] && [ "$power" != "0" ]; then
    pass "validator.power" "$power"
  else
    fail "validator.power" "voting_power=0 — syncing, jailed, wrong key, or 'systemctl start' on an already-active unit (which is a no-op)"
  fi

  if [ -n "$valaddr" ]; then
    in_commit="$(jqr "$(node_get "/commit?height=${height2}")" \
      "[.result.signed_header.commit.signatures[].validator_address] | index(\"${valaddr}\") // \"absent\"")"
    if [ "$in_commit" = "absent" ] || [ -z "$in_commit" ]; then
      fail "validator.commit" "consensus address ${valaddr} is absent from the commit at ${height2}"
    else
      pass "validator.commit" "present in commit at ${height2}"
    fi
  fi
fi

# --- exposure ----------------------------------------------------------------
# Anything listening off loopback is public, whatever the firewall says.
listeners="$(run "ss -ltn 2>/dev/null | awk 'NR>1 {print \$4}' | grep -vE '127\\.0\\.0\\.1|\\[::1\\]' || true")"
if [ -n "$listeners" ]; then
  offloop="$(printf '%s\n' "$listeners" | grep -E ':(26657|1317|9090|8545|8546|26660|6[12]6(57|60)|6[12]317|6[12]090)$' || true)"
  if [ -n "$offloop" ]; then
    warn "exposure.offloopback" "$(printf '%s' "$offloop" | tr '\n' ' ')— RPC/REST/gRPC/metrics reachable off loopback; only P2P belongs on the internet"
  else
    pass "exposure.offloopback" "no query or metrics port bound off loopback"
  fi
fi

# --- disk --------------------------------------------------------------------
disk_target="${NODE_HOME:-$DISK_PATH}"
used="$(run "df -P '${disk_target}' 2>/dev/null | awk 'NR==2 {gsub(\"%\",\"\",\$5); print \$5}' || true" | tr -d '[:space:]')"
if [ -n "$used" ]; then
  if [ "$used" -lt "$DISK_WARN_PERCENT" ]; then
    pass "host.disk" "${disk_target} at ${used}%"
  else
    fail "host.disk" "${disk_target} at ${used}% >= ${DISK_WARN_PERCENT}%"
  fi
fi

# --- clock -------------------------------------------------------------------
sync_state="$(run "timedatectl show -p NTPSynchronized --value 2>/dev/null || true" | tr -d '[:space:]')"
case "$sync_state" in
  yes) pass "host.clock" "NTP synchronised" ;;
  no)  fail "host.clock" "NTP not synchronised — clock skew causes missed precommits" ;;
  *)   warn "host.clock" "could not determine NTP state" ;;
esac

echo
if [ "$FAILED" -eq 0 ]; then
  echo "healthcheck=passed"
  echo "This is evidence, not proof. On a signer, confirm presence in several"
  echo "consecutive commits and check missed_blocks_counter, jailed_until and"
  echo "tombstoned in the slashing module before declaring the validator healthy."
else
  echo "healthcheck=failed"
fi
exit "$FAILED"
