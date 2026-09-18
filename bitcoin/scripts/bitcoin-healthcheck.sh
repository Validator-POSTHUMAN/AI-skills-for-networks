#!/usr/bin/env bash
# Read-only Bitcoin Core health check.
#
# It runs no mutating RPC, sends no transaction, touches no wallet and changes
# nothing on the host. The one check worth having and the one most setups lack
# is the last: two independent sources agreeing on the tip *hash*, not just the
# height. A node at the same height on a different chain looks healthy to every
# height-based monitor and silently corrupts everything downstream.
set -euo pipefail

HOST=""
LOCAL_MODE=0
DATADIR=""
CLI="bitcoin-cli"
SERVICE="bitcoind"
CONTAINER=""
RPC_USER_ARGS=""
MAX_BLOCK_LAG=3
MIN_OUTBOUND=4
DISK_WARN_PERCENT=90
SKIP_EXTERNAL=0
CURL_TIMEOUT=8
EXTERNAL_SOURCES=(
  "https://mempool.space/api/blocks/tip/hash"
  "https://blockstream.info/api/blocks/tip/hash"
)

usage() {
  cat <<'USAGE'
Usage:
  bitcoin-healthcheck.sh [--host <ssh-target>|--local] [options]

Examples:
  bitcoin-healthcheck.sh --local --datadir /var/lib/bitcoind
  bitcoin-healthcheck.sh --host <user>@<host> --datadir /var/lib/bitcoind --service bitcoind
  bitcoin-healthcheck.sh --local --container bitcoind --datadir /data

Options:
  --local                  Run checks on the current host instead of over SSH.
  --host <ssh-target>      Run checks over SSH on this target.
  --datadir <path>         Bitcoin data directory passed to bitcoin-cli.
  --cli <path>             bitcoin-cli binary. Default: bitcoin-cli
  --service <name>         systemd unit to inspect. Default: bitcoind. "" to skip.
  --container <name>       Docker container to exec bitcoin-cli in instead of systemd.
  --max-block-lag <n>      headers-blocks gap that fails the check. Default: 3
  --min-outbound <n>       Minimum outbound peers. Default: 4
  --disk-warn <percent>    Filesystem usage that warns. Default: 90
  --skip-external          Do not compare the tip against public sources.
  -h, --help               Show this help.

Exit codes:
  0 healthy
  1 usage error
  2 node unreachable or unreadable
  3 a health check failed
  4 chain divergence: an external source disagrees at the same height
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --local) LOCAL_MODE=1; shift;;
    --host) HOST="${2:-}"; shift 2;;
    --datadir) DATADIR="${2:-}"; shift 2;;
    --cli) CLI="${2:-}"; shift 2;;
    --service) SERVICE="${2:-}"; shift 2;;
    --container) CONTAINER="${2:-}"; shift 2;;
    --max-block-lag) MAX_BLOCK_LAG="${2:-}"; shift 2;;
    --min-outbound) MIN_OUTBOUND="${2:-}"; shift 2;;
    --disk-warn) DISK_WARN_PERCENT="${2:-}"; shift 2;;
    --skip-external) SKIP_EXTERNAL=1; shift;;
    -h|--help) usage; exit 0;;
    *) echo "unknown option: $1" >&2; usage; exit 1;;
  esac
done

if [[ $LOCAL_MODE -eq 0 && -z "$HOST" ]]; then
  echo "one of --local or --host is required" >&2
  usage
  exit 1
fi

command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }

[[ -n "$DATADIR" ]] && RPC_USER_ARGS="-datadir=${DATADIR}"

run() {
  if [[ $LOCAL_MODE -eq 1 ]]; then
    bash -lc "$1"
  else
    ssh -o BatchMode=yes "$HOST" "$1"
  fi
}

cli() {
  if [[ -n "$CONTAINER" ]]; then
    run "docker exec ${CONTAINER} ${CLI} ${RPC_USER_ARGS} $*"
  else
    run "${CLI} ${RPC_USER_ARGS} $*"
  fi
}

FAILURES=0
DIVERGED=0
fail() { echo "FAIL  $*"; FAILURES=$((FAILURES + 1)); }
warn() { echo "WARN  $*"; }
ok()   { echo "ok    $*"; }

echo "== bitcoin health check =="
[[ $LOCAL_MODE -eq 1 ]] && echo "target: local" || echo "target: ${HOST}"
[[ -n "$DATADIR" ]] && echo "datadir: ${DATADIR}"
[[ -n "$CONTAINER" ]] && echo "container: ${CONTAINER}"
echo

CHAIN_JSON="$(cli getblockchaininfo 2>/dev/null || true)"
if [[ -z "$CHAIN_JSON" ]] || ! jq -e . >/dev/null 2>&1 <<<"$CHAIN_JSON"; then
  echo "FAIL  getblockchaininfo returned nothing readable; the node is down, the datadir is wrong, or RPC auth failed" >&2
  exit 2
fi

NET_JSON="$(cli getnetworkinfo 2>/dev/null || echo '{}')"
MEMPOOL_JSON="$(cli getmempoolinfo 2>/dev/null || echo '{}')"

CHAIN="$(jq -r '.chain // "unknown"' <<<"$CHAIN_JSON")"
BLOCKS="$(jq -r '.blocks // 0' <<<"$CHAIN_JSON")"
HEADERS="$(jq -r '.headers // 0' <<<"$CHAIN_JSON")"
PROGRESS="$(jq -r '.verificationprogress // 0' <<<"$CHAIN_JSON")"
# jq's // treats false as absent, so a boolean default must be an explicit
# null check. Reading `false` as `true` here would report a synced node as
# still in initial block download, and a disabled network as enabled.
IBD="$(jq -r 'if .initialblockdownload == null then true else .initialblockdownload end' <<<"$CHAIN_JSON")"
PRUNED="$(jq -r 'if .pruned == null then false else .pruned end' <<<"$CHAIN_JSON")"
SIZE_ON_DISK="$(jq -r '.size_on_disk // 0' <<<"$CHAIN_JSON")"
VERSION="$(jq -r '.subversion // "unknown"' <<<"$NET_JSON")"
IN="$(jq -r '.connections_in // 0' <<<"$NET_JSON")"
OUT="$(jq -r '.connections_out // 0' <<<"$NET_JSON")"
ACTIVE="$(jq -r 'if .networkactive == null then true else .networkactive end' <<<"$NET_JSON")"
WARNINGS="$(jq -r 'if (.warnings|type) == "array" then (.warnings|join("; ")) else (.warnings // "") end' <<<"$NET_JSON")"
MEMPOOL_TXS="$(jq -r '.size // 0' <<<"$MEMPOOL_JSON")"
MEMPOOL_MIN_FEE="$(jq -r '.mempoolminfee // 0' <<<"$MEMPOOL_JSON")"

echo "chain=${CHAIN} version=${VERSION} height=${BLOCKS} headers=${HEADERS} pruned=${PRUNED} size_on_disk=${SIZE_ON_DISK}"
echo "peers in=${IN} out=${OUT} mempool=${MEMPOOL_TXS} tx minfee=${MEMPOOL_MIN_FEE}"
echo

LAG=$((HEADERS - BLOCKS))
if [[ "$IBD" == "true" ]]; then
  fail "still in initial block download (verificationprogress=${PROGRESS}); the node is not trustworthy for services yet"
elif [[ $LAG -gt $MAX_BLOCK_LAG ]]; then
  fail "behind by ${LAG} blocks (headers=${HEADERS} blocks=${BLOCKS})"
else
  ok "synced, ${LAG} block(s) behind headers"
fi

if [[ "$ACTIVE" != "true" ]]; then
  fail "networkactive is false; P2P is disabled on this node"
fi

if [[ $OUT -lt $MIN_OUTBOUND ]]; then
  fail "only ${OUT} outbound peers (minimum ${MIN_OUTBOUND})"
else
  ok "${OUT} outbound peers"
fi

# Inbound zero is a legitimate choice for a private backend, so it warns and
# never fails.
[[ $IN -eq 0 ]] && warn "no inbound peers; fine for a private backend, wrong if this node should serve the network"

if [[ -n "$WARNINGS" ]]; then
  fail "node reports warnings: ${WARNINGS}"
else
  ok "no node warnings"
fi

INDEX_JSON="$(cli getindexinfo 2>/dev/null || echo '{}')"
if jq -e 'type == "object" and length > 0' >/dev/null 2>&1 <<<"$INDEX_JSON"; then
  while IFS=$'\t' read -r name synced best; do
    [[ -z "$name" ]] && continue
    if [[ "$synced" == "true" ]]; then
      ok "index ${name} synced at ${best}"
    else
      fail "index ${name} is not synced (best_block_height=${best})"
    fi
  done < <(jq -r 'to_entries[] | [.key, (.value.synced|tostring), (.value.best_block_height|tostring)] | @tsv' <<<"$INDEX_JSON")
fi

if [[ -n "$SERVICE" && -z "$CONTAINER" ]]; then
  STATE="$(run "systemctl show ${SERVICE} -p ActiveState -p NRestarts --value 2>/dev/null | tr '\n' ' '" || true)"
  if [[ -z "$STATE" ]]; then
    warn "could not read systemd state for ${SERVICE}"
  else
    read -r ACTIVE_STATE RESTARTS <<<"$STATE"
    [[ "$ACTIVE_STATE" == "active" ]] && ok "${SERVICE} active, NRestarts=${RESTARTS:-0}" || fail "${SERVICE} is ${ACTIVE_STATE}"
    [[ "${RESTARTS:-0}" != "0" ]] && warn "${SERVICE} has restarted ${RESTARTS} time(s); an unclean stop corrupts the chainstate"
  fi
fi

# Every mount, not just /: a datadir on its own volume fills independently, and
# a full datadir volume is how nodes corrupt themselves.
while read -r usage_percent mount; do
  [[ -z "$usage_percent" ]] && continue
  value="${usage_percent%\%}"
  [[ "$value" =~ ^[0-9]+$ ]] || continue
  [[ $value -ge $DISK_WARN_PERCENT ]] && warn "filesystem ${mount} is ${usage_percent} full"
done < <(run "df -P -h | grep -v 'tmpfs\|udev\|loop' | awk 'NR>1 {print \$5, \$6}'")

if [[ $SKIP_EXTERNAL -eq 0 && "$CHAIN" == "main" ]]; then
  echo
  LOCAL_TIP="$(cli getbestblockhash 2>/dev/null | tr -d '[:space:]' || true)"
  if [[ ! "$LOCAL_TIP" =~ ^[0-9a-f]{64}$ ]]; then
    fail "could not read the local tip hash"
  else
    echo "local tip ${LOCAL_TIP}"
    AGREED=0
    CHECKED=0
    for source in "${EXTERNAL_SOURCES[@]}"; do
      REMOTE="$(curl -sS --max-time "$CURL_TIMEOUT" "$source" 2>/dev/null | tr -d '[:space:]' || true)"
      if [[ ! "$REMOTE" =~ ^[0-9a-f]{64}$ ]]; then
        warn "external source unreachable: ${source}"
        continue
      fi
      CHECKED=$((CHECKED + 1))
      if [[ "$REMOTE" == "$LOCAL_TIP" ]]; then
        AGREED=$((AGREED + 1))
        ok "tip agrees with ${source}"
      else
        # Not yet divergence: the sources may simply be one block apart. Ask
        # this source for the hash at the local height before escalating.
        HEIGHT_HASH="$(curl -sS --max-time "$CURL_TIMEOUT" "${source%/blocks/tip/hash}/block-height/${BLOCKS}" 2>/dev/null | tr -d '[:space:]' || true)"
        if [[ "$HEIGHT_HASH" =~ ^[0-9a-f]{64}$ ]]; then
          if [[ "$HEIGHT_HASH" == "$LOCAL_TIP" ]]; then
            AGREED=$((AGREED + 1))
            ok "tip agrees with ${source} at height ${BLOCKS} (that source is ahead)"
          else
            echo "FAIL  CHAIN DIVERGENCE: at height ${BLOCKS} this node has ${LOCAL_TIP}, ${source} has ${HEIGHT_HASH}"
            DIVERGED=1
          fi
        else
          warn "could not compare at height ${BLOCKS} against ${source}"
        fi
      fi
    done
    [[ $CHECKED -eq 0 ]] && warn "no external source answered; chain agreement was not verified"
  fi
fi

echo
if [[ $DIVERGED -eq 1 ]]; then
  echo "RESULT: CHAIN DIVERGENCE. Stop consumers of this node, do not credit payments from it, and investigate before restarting."
  exit 4
fi
if [[ $FAILURES -gt 0 ]]; then
  echo "RESULT: ${FAILURES} check(s) failed."
  exit 3
fi
echo "RESULT: healthy."
