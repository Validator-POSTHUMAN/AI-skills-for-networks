#!/usr/bin/env bash
# espresso-healthcheck.sh — read-only Espresso validator health check.
#
# Reports consensus liveness, missed proposals, cliquenet peer state, running
# image tag, participation score and the on-chain stake table entry.
#
# Read-only by design: it never restarts a service, never writes configuration,
# and never signs or broadcasts a transaction. Secrets are never printed.
#
# Usage:
#   espresso-healthcheck.sh --local  --network mainnet [options]
#   espresso-healthcheck.sh --host user@node --network decaf [options]
#
# Options:
#   --local                    Run the node-side checks on this machine.
#   --host <ssh-target>        Run the node-side checks over SSH.
#   --network mainnet|decaf    Target network. Required.
#   --api <url>                Node API base URL. Default http://127.0.0.1:8080
#   --query <url>              Query service. Default: the network's public one.
#   --bls-key <BLS_VER_KEY~..> Read this key's participation score.
#   --validator-address <0x..> Read this address from the stake table.
#   --expected-tag <tag>       Compare against consensus_version.
#   --p2p-host <host>          Probe this public host's P2P port from here.
#   --p2p-port <port>          P2P port for the probe. Default 9977.
#   --settle <seconds>         Gap between the two view reads. Default 30.
#
# Exit status: 0 all checks passed, 1 at least one FAIL, 2 usage error.

set -uo pipefail

MODE=""
SSH_TARGET=""
NETWORK=""
API="http://127.0.0.1:8080"
QUERY=""
BLS_KEY=""
VALIDATOR_ADDRESS=""
EXPECTED_TAG=""
P2P_HOST=""
P2P_PORT="9977"
SETTLE="30"

STAKING_CLI_IMAGE="ghcr.io/espressosystems/espresso-network/staking-cli:main"

fail_count=0
warn_count=0

die() { printf 'error: %s\n' "$1" >&2; exit 2; }
ok()   { printf '  [ OK ]   %s\n' "$1"; }
warn() { printf '  [ WARN ] %s\n' "$1"; warn_count=$((warn_count + 1)); }
bad()  { printf '  [ FAIL ] %s\n' "$1"; fail_count=$((fail_count + 1)); }
note() { printf '  [ .. ]   %s\n' "$1"; }
head_() { printf '\n== %s\n' "$1"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --local) MODE="local"; shift ;;
    --host) MODE="ssh"; SSH_TARGET="${2:-}"; shift 2 ;;
    --network) NETWORK="${2:-}"; shift 2 ;;
    --api) API="${2:-}"; shift 2 ;;
    --query) QUERY="${2:-}"; shift 2 ;;
    --bls-key) BLS_KEY="${2:-}"; shift 2 ;;
    --validator-address) VALIDATOR_ADDRESS="${2:-}"; shift 2 ;;
    --expected-tag) EXPECTED_TAG="${2:-}"; shift 2 ;;
    --p2p-host) P2P_HOST="${2:-}"; shift 2 ;;
    --p2p-port) P2P_PORT="${2:-}"; shift 2 ;;
    --settle) SETTLE="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[ -n "$MODE" ] || die "one of --local or --host is required"
[ "$MODE" = "ssh" ] && [ -z "$SSH_TARGET" ] && die "--host needs an ssh target"
case "$NETWORK" in
  mainnet|decaf) ;;
  *) die "--network must be mainnet or decaf" ;;
esac
case "$SETTLE" in ''|*[!0-9]*) die "--settle must be an integer" ;; esac

if [ -z "$QUERY" ]; then
  if [ "$NETWORK" = "mainnet" ]; then
    QUERY="https://query.main.net.espresso.network"
  else
    QUERY="https://query.decaf.testnet.espresso.network"
  fi
fi

# Run a command on the node, locally or over SSH.
on_node() {
  if [ "$MODE" = "local" ]; then
    bash -c "$1"
  else
    ssh -o BatchMode=yes -o ConnectTimeout=10 "$SSH_TARGET" "$1"
  fi
}

# Fetch the metrics document, trying the versioned path first.
fetch_metrics() {
  on_node "curl -fsS -m 15 '${API}/v1/status/metrics' 2>/dev/null || curl -fsS -m 15 '${API}/status/metrics' 2>/dev/null"
}

metric_value() { # metric_value <document> <metric name>
  awk -v name="$2" '$1 == name { print $2; exit }' <<<"$1"
}

printf 'Espresso health check — network=%s api=%s\n' "$NETWORK" "$API"
printf 'Started %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

# ---------------------------------------------------------------- metrics ---
head_ "Status API"

metrics_before="$(fetch_metrics)"
if [ -z "$metrics_before" ]; then
  bad "metrics endpoint returned nothing on ${API} (tried /v1/status/metrics and /status/metrics)"
  printf '\nSummary: %d fail, %d warn\n' "$fail_count" "$warn_count"
  exit 1
fi
ok "metrics endpoint responded"

view_before="$(metric_value "$metrics_before" consensus_current_view)"
decided_before="$(metric_value "$metrics_before" consensus_last_decided_view)"
timeouts_before="$(metric_value "$metrics_before" consensus_number_of_timeouts_as_leader)"

if [ -z "$view_before" ]; then
  bad "consensus_current_view is absent — is the status module enabled?"
else
  note "consensus_current_view=${view_before} consensus_last_decided_view=${decided_before:-absent}"
fi

# --------------------------------------------------------------- liveness ---
head_ "Consensus liveness (${SETTLE}s observation)"

decide_age="$(on_node "curl -fsS -m 15 '${API}/v1/status/time-since-last-decide' 2>/dev/null || curl -fsS -m 15 '${API}/status/time-since-last-decide' 2>/dev/null" | tr -dc '0-9.')"
if [ -n "$decide_age" ]; then
  note "time-since-last-decide=${decide_age}s"
else
  warn "time-since-last-decide did not answer; relying on view movement only"
fi

sleep "$SETTLE"
metrics_after="$(fetch_metrics)"
view_after="$(metric_value "$metrics_after" consensus_current_view)"
decided_after="$(metric_value "$metrics_after" consensus_last_decided_view)"

if [ -n "$view_before" ] && [ -n "$view_after" ]; then
  if awk -v a="$view_before" -v b="$view_after" 'BEGIN{exit !(b>a)}'; then
    ok "current view advanced ${view_before} -> ${view_after}"
  else
    bad "current view did not advance in ${SETTLE}s (stuck at ${view_after})"
  fi
fi

if [ -n "$decided_before" ] && [ -n "$decided_after" ]; then
  if awk -v a="$decided_before" -v b="$decided_after" 'BEGIN{exit !(b>a)}'; then
    ok "last decided view advanced ${decided_before} -> ${decided_after}"
  elif [ -n "$view_before" ] && [ -n "$view_after" ] && awk -v a="$view_before" -v b="$view_after" 'BEGIN{exit !(b>a)}'; then
    bad "views advance but nothing decides — check other operators before touching this node"
  else
    bad "last decided view did not advance in ${SETTLE}s"
  fi
fi

# ------------------------------------------------------- missed proposals ---
head_ "Proposal health"

if [ -n "$timeouts_before" ]; then
  if awk -v v="$timeouts_before" 'BEGIN{exit !(v>0)}'; then
    warn "consensus_number_of_timeouts_as_leader=${timeouts_before} — every increment is a missed proposal"
  else
    ok "no leader timeouts recorded"
  fi
else
  note "consensus_number_of_timeouts_as_leader absent (created lazily on first update)"
fi

# ------------------------------------------------------------------ peers ---
head_ "Cliquenet peers"

peer_tasks="$(grep -E '^consensus_cliquenet_peer_tasks' <<<"$metrics_after" | awk '{print $2; exit}')"
hellos_count="$(grep -cE '^consensus_cliquenet_hellos' <<<"$metrics_after")"
connect_tasks="$(grep -E '^consensus_cliquenet_connect_tasks' <<<"$metrics_after" | awk '{print $2; exit}')"

if [ -z "$peer_tasks" ]; then
  bad "consensus_cliquenet_peer_tasks is absent — the node has never established a peer connection"
elif [ "${peer_tasks%.*}" -eq 0 ] 2>/dev/null; then
  bad "consensus_cliquenet_peer_tasks=0 — no P2P mesh connections"
else
  ok "established peer connections: ${peer_tasks}"
fi

if [ "$hellos_count" -eq 0 ]; then
  warn "no consensus_cliquenet_hellos series — nothing has ever reached this node INBOUND; check the port, any proxy, and the registered P2P address"
else
  ok "inbound hellos observed from ${hellos_count} peer key(s)"
fi

[ -n "$connect_tasks" ] && note "outbound dials in flight: ${connect_tasks}"

# --------------------------------------------------------------- resources ---
head_ "Resources and version"

open_fds="$(metric_value "$metrics_after" process_open_fds)"
max_fds="$(metric_value "$metrics_after" process_max_fds)"
rss="$(metric_value "$metrics_after" process_resident_memory_bytes)"

if [ -n "$open_fds" ] && [ -n "$max_fds" ]; then
  if awk -v a="$open_fds" -v b="$max_fds" 'BEGIN{exit !(b>0 && a/b>0.8)}'; then
    warn "open file descriptors ${open_fds}/${max_fds} — above 80% of the limit"
  else
    ok "file descriptors ${open_fds}/${max_fds}"
  fi
fi
[ -n "$rss" ] && note "resident memory: $(awk -v v="$rss" 'BEGIN{printf "%.1f GiB", v/1073741824}')"

version_line="$(grep -E '^consensus_version' <<<"$metrics_after" | head -1)"
if [ -n "$version_line" ]; then
  note "${version_line}"
  if [ -n "$EXPECTED_TAG" ]; then
    if grep -qF "$EXPECTED_TAG" <<<"$version_line"; then
      ok "running the expected tag ${EXPECTED_TAG}"
    else
      bad "consensus_version does not contain the expected tag ${EXPECTED_TAG}"
    fi
  fi
else
  note "consensus_version absent"
fi

# ----------------------------------------------------------- participation ---
head_ "Participation (${QUERY})"

if [ -z "$BLS_KEY" ]; then
  note "skipped — pass --bls-key to score this validator"
else
  for kind in proposal vote; do
    body="$(curl -fsS -m 20 "${QUERY}/node/participation/${kind}/current" 2>/dev/null)"
    if [ -z "$body" ]; then
      warn "${kind} participation endpoint did not answer"
      continue
    fi
    score="$(printf '%s' "$body" | python3 -c '
import json, sys
key = sys.argv[1]
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)
if isinstance(data, dict):
    for container in (data, data.get("participation") or {}):
        if isinstance(container, dict) and key in container:
            print(container[key])
            break
' "$BLS_KEY" 2>/dev/null)"
    if [ -z "$score" ]; then
      warn "${kind}: this BLS key is not present in the current epoch response"
    elif awk -v v="$score" 'BEGIN{exit !(v+0<0.95)}'; then
      warn "${kind} participation ${score} — below 0.95 (expected for up to one epoch after a restart)"
    else
      ok "${kind} participation ${score}"
    fi
  done
fi

# ------------------------------------------------------------- stake table ---
head_ "Stake table entry"

if [ -z "$VALIDATOR_ADDRESS" ]; then
  note "skipped — pass --validator-address to read the on-chain entry"
elif ! command -v docker >/dev/null 2>&1; then
  note "skipped — docker is not available on this machine"
else
  entry="$(docker run --rm "$STAKING_CLI_IMAGE" \
      staking-cli --network "$NETWORK" stake-table-entry --address "$VALIDATOR_ADDRESS" 2>&1)"
  if [ -z "$entry" ]; then
    warn "stake-table-entry returned nothing"
  else
    printf '%s\n' "$entry" | sed 's/^/    /'
    grep -qi 'Status: *Active' <<<"$entry" && ok "validator status is Active" || bad "validator status is not Active"
    grep -qi 'x25519 public key: *not set' <<<"$entry" && bad "x25519 public key is not set on-chain — peers cannot dial this validator"
    grep -qi 'p2p address: *not set' <<<"$entry" && bad "p2p address is not set on-chain — peers cannot dial this validator"
  fi
fi

# ---------------------------------------------------------------- P2P probe ---
head_ "Public P2P probe"

if [ -z "$P2P_HOST" ]; then
  note "skipped — pass --p2p-host to probe the registered public address from this machine"
elif ! command -v nc >/dev/null 2>&1; then
  note "skipped — nc is not available on this machine"
else
  probe="$(nc -w3 "$P2P_HOST" "$P2P_PORT" </dev/null 2>/dev/null | od -An -tx1 | tr -s ' ' | tr -d '\n ')"
  if [ "$probe" = "00010001" ]; then
    ok "${P2P_HOST}:${P2P_PORT} returned the expected version range"
  elif [ -z "$probe" ]; then
    bad "${P2P_HOST}:${P2P_PORT} returned no bytes — closed port, a buffering middlebox, or nothing listening"
  else
    bad "${P2P_HOST}:${P2P_PORT} returned unexpected bytes (${probe}) — the stream is being rewritten"
  fi
  note "run the three-probe sequence in SKILL.md to distinguish a sniffer from a closed port"
fi

# ------------------------------------------------------------------ summary ---
printf '\nSummary: %d fail, %d warn\n' "$fail_count" "$warn_count"
[ "$fail_count" -eq 0 ] || exit 1
exit 0
