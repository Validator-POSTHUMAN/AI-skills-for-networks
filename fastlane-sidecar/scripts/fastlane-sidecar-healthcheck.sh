#!/usr/bin/env bash
set -euo pipefail

HOST=""
LOCAL=0
HEALTH_URL="http://127.0.0.1:8765/health"
METRICS_URL="http://127.0.0.1:8765/metrics"
CONTAINER="fastlane-sidecar"
BFT_SERVICE="monad-bft"
RPC_SERVICE="monad-rpc"
EXECUTION_SERVICE="monad-execution"
FASTLANE_USER="fastlane"

usage() {
  cat <<'USAGE'
Usage:
  fastlane-sidecar-healthcheck.sh --local [options]
  fastlane-sidecar-healthcheck.sh --host user@host [options]

Options:
  --health-url URL          Default: http://127.0.0.1:8765/health
  --metrics-url URL         Default: http://127.0.0.1:8765/metrics
  --container NAME          Default: fastlane-sidecar
  --bft-service NAME        Default: monad-bft
  --rpc-service NAME        Default: monad-rpc
  --execution-service NAME  Default: monad-execution
  --fastlane-user USER      Default: fastlane
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --local) LOCAL=1; shift ;;
    --host) HOST="$2"; shift 2 ;;
    --health-url) HEALTH_URL="$2"; shift 2 ;;
    --metrics-url) METRICS_URL="$2"; shift 2 ;;
    --container) CONTAINER="$2"; shift 2 ;;
    --bft-service) BFT_SERVICE="$2"; shift 2 ;;
    --rpc-service) RPC_SERVICE="$2"; shift 2 ;;
    --execution-service) EXECUTION_SERVICE="$2"; shift 2 ;;
    --fastlane-user) FASTLANE_USER="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [ "$LOCAL" -eq 0 ] && [ -z "$HOST" ]; then
  echo "ERROR: pass --local or --host user@host" >&2
  exit 2
fi

remote_script=$(cat <<'REMOTE'
set -euo pipefail
echo "== systemd =="
systemctl is-active "$BFT_SERVICE" "$EXECUTION_SERVICE" "$RPC_SERVICE" || true

echo "== process flags =="
ps -eo pid,user,args | grep -E 'monad-node|monad-rpc|fastlane-sidecar' | grep -v grep || true

echo "== ipc socket =="
ls -l /var/run/monad-ipc /var/run/monad-ipc/mempool.sock 2>/dev/null || true
getfacl -p /var/run/monad-ipc /var/run/monad-ipc/mempool.sock 2>/dev/null || true

echo "== docker container =="
if id "$FASTLANE_USER" >/dev/null 2>&1; then
  uid=$(id -u "$FASTLANE_USER")
  sudo -iu "$FASTLANE_USER" env DOCKER_HOST="unix:///run/user/$uid/docker.sock" \
    docker ps --filter "name=$CONTAINER" --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' || true
  sudo -iu "$FASTLANE_USER" env DOCKER_HOST="unix:///run/user/$uid/docker.sock" \
    docker inspect "$CONTAINER" --format '{{.Image}}' 2>/dev/null || true
else
  echo "fastlane user not found: $FASTLANE_USER"
fi

echo "== health =="
curl -fsS "$HEALTH_URL" || true
echo

echo "== metrics sample =="
curl -fsS "$METRICS_URL" | head -40 || true

echo "== recent sidecar logs =="
if id "$FASTLANE_USER" >/dev/null 2>&1; then
  uid=$(id -u "$FASTLANE_USER")
  sudo -iu "$FASTLANE_USER" env DOCKER_HOST="unix:///run/user/$uid/docker.sock" \
    docker logs --tail 80 "$CONTAINER" 2>&1 || true
fi
REMOTE
)

if [ "$LOCAL" -eq 1 ]; then
  BFT_SERVICE="$BFT_SERVICE" RPC_SERVICE="$RPC_SERVICE" EXECUTION_SERVICE="$EXECUTION_SERVICE" \
    FASTLANE_USER="$FASTLANE_USER" CONTAINER="$CONTAINER" HEALTH_URL="$HEALTH_URL" \
    METRICS_URL="$METRICS_URL" bash -c "$remote_script"
else
  ssh -o BatchMode=yes "$HOST" \
    "BFT_SERVICE='$BFT_SERVICE' RPC_SERVICE='$RPC_SERVICE' EXECUTION_SERVICE='$EXECUTION_SERVICE' FASTLANE_USER='$FASTLANE_USER' CONTAINER='$CONTAINER' HEALTH_URL='$HEALTH_URL' METRICS_URL='$METRICS_URL' bash -s" < <(printf '%s\n' "$remote_script")
fi
