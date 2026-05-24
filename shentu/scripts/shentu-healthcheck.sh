#!/usr/bin/env bash
set -euo pipefail

HOST=""
SERVICE=""
RPC=""
VALCONS=""
VALOPER=""

usage() {
  cat <<'USAGE'
Usage:
  shentu-healthcheck.sh --host <ssh-target> --service <service> --rpc <local-rpc> --valcons <hex-address> --valoper <shentuvaloper>

Example:
  shentu-healthcheck.sh \
    --host ubuntu@142.132.158.158 \
    --service shentu \
    --rpc http://127.0.0.1:35657 \
    --valcons EA4A6B5765D8DC4F663A71693E6459B15194544E \
    --valoper shentuvaloper1036rphfnyw49fzm5ajfud743j2qutlk9v8lgp2
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) HOST="$2"; shift 2 ;;
    --service) SERVICE="$2"; shift 2 ;;
    --rpc) RPC="$2"; shift 2 ;;
    --valcons) VALCONS="$2"; shift 2 ;;
    --valoper) VALOPER="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "$HOST" || -z "$SERVICE" || -z "$RPC" || -z "$VALCONS" || -z "$VALOPER" ]]; then
  usage >&2
  exit 2
fi

ssh -o BatchMode=yes -o ConnectTimeout=8 "$HOST" bash -s -- "$SERVICE" "$RPC" "$VALCONS" "$VALOPER" <<'REMOTE'
set -euo pipefail

SERVICE="$1"
RPC="$2"
VALCONS="$3"
VALOPER="$4"

echo "time=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "service=$(systemctl is-active "$SERVICE" 2>/dev/null || true)"
echo "enabled=$(systemctl is-enabled "$SERVICE" 2>/dev/null || true)"

STATUS_JSON="$(curl -fsS "$RPC/status")"
HEIGHT="$(printf '%s' "$STATUS_JSON" | jq -r '.result.sync_info.latest_block_height')"
echo "$STATUS_JSON" | jq -r '
  "height=" + .result.sync_info.latest_block_height,
  "block_time=" + .result.sync_info.latest_block_time,
  "catching_up=" + (.result.sync_info.catching_up|tostring),
  "voting_power=" + .result.validator_info.voting_power'

PID="$(pgrep -f 'shentud.*start' | head -1 || true)"
BIN="shentud"
if [[ -n "$PID" && -e "/proc/$PID/exe" ]]; then
  BIN="$(readlink -f "/proc/$PID/exe")"
  echo "pid=$PID"
  echo "exe=$BIN"
  echo "version=$("$BIN" version 2>/dev/null || true)"
else
  echo "pid=missing"
fi

echo "peers=$(curl -fsS "$RPC/net_info" | jq -r '.result.n_peers')"

SIGNED=0
CHECKED=0
for B in $((HEIGHT-1)) $((HEIGHT-2)) $((HEIGHT-3)) $((HEIGHT-4)) $((HEIGHT-5)); do
  FLAG="$(curl -fsS "$RPC/block?height=$B" |
    jq -r --arg v "$VALCONS" '[.result.block.last_commit.signatures[]? |
      select(.validator_address==$v) | .block_id_flag][0] // "missing"')"
  echo "signed_$B=$FLAG"
  CHECKED=$((CHECKED+1))
  if [[ "$FLAG" == "2" || "$FLAG" == "BLOCK_ID_FLAG_COMMIT" ]]; then
    SIGNED=$((SIGNED+1))
  fi
done
echo "recent_signing=$SIGNED/$CHECKED"

if command -v "$BIN" >/dev/null 2>&1; then
  "$BIN" query staking validator "$VALOPER" --node "$RPC" -o json 2>/dev/null |
    jq -r '(.validator // .) as $v | "validator_status=" + ($v.status // "unknown"), "jailed=" + (($v.jailed // "unknown")|tostring), "tokens=" + ($v.tokens // "unknown")' || true
fi
REMOTE
