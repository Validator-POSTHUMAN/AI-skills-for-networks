#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/osmosis-healthcheck.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -r -- "$TMP_DIR"' EXIT
BIN_DIR="$TMP_DIR/bin"
mkdir -p "$BIN_DIR"

cat >"$BIN_DIR/systemctl" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  is-active) echo active ;;
  is-enabled) echo enabled ;;
  show) echo 0 ;;
  *) exit 2 ;;
esac
EOF

cat >"$BIN_DIR/curl" <<'EOF'
#!/usr/bin/env bash
url="${!#}"
fixture="${HEALTHCHECK_FIXTURE:-healthy}"
if [[ "$url" == */net_info ]]; then
  printf '%s\n' '{"result":{"n_peers":"8"}}'
  exit 0
fi
if [[ "$url" == http://public/status ]]; then
  height=100
  [[ "$fixture" != gap ]] || height=140
  printf '{"result":{"node_info":{"network":"osmosis-1"},"sync_info":{"latest_block_height":"%s","latest_block_time":"%s","catching_up":false},"validator_info":{"voting_power":"0"}}}\n' \
    "$height" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  exit 0
fi
if [[ "$url" == http://local/status ]]; then
  chain=osmosis-1
  catching=false
  block_time="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  [[ "$fixture" != wrong_chain ]] || chain=wrong-1
  [[ "$fixture" != catching_up ]] || catching=true
  [[ "$fixture" != stale ]] || block_time=2020-01-01T00:00:00Z
  printf '{"result":{"node_info":{"network":"%s","id":"fixture-node"},"sync_info":{"latest_block_height":"100","latest_block_time":"%s","catching_up":%s},"validator_info":{"voting_power":"0"}}}\n' \
    "$chain" "$block_time" "$catching"
  exit 0
fi
exit 22
EOF

cat >"$BIN_DIR/pgrep" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF

cat >"$BIN_DIR/df" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 'Filesystem 1024-blocks Used Available Capacity Mounted on' '/dev/test 1000000 100000 900000 10% /fixture'
EOF

cat >"$BIN_DIR/journalctl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

chmod 755 "$BIN_DIR"/*

run_case() {
  local fixture="$1" expected_rc="$2" expected_pattern="$3"
  local output="$TMP_DIR/$fixture.out" rc=0
  HEALTHCHECK_FIXTURE="$fixture" PATH="$BIN_DIR:$PATH" \
    "$SCRIPT" --local --service osmosis.service --rpc http://local \
      --public-rpc http://public --max-block-age 45 --max-height-gap 20 \
      >"$output" 2>&1 || rc=$?
  [[ "$rc" -eq "$expected_rc" ]] || {
    printf 'fixture=%s expected_rc=%s actual_rc=%s\n' "$fixture" "$expected_rc" "$rc" >&2
    sed -n '1,160p' "$output" >&2
    exit 1
  }
  grep -Fq "$expected_pattern" "$output" || {
    printf 'fixture=%s missing_pattern=%s\n' "$fixture" "$expected_pattern" >&2
    sed -n '1,160p' "$output" >&2
    exit 1
  }
}

run_case healthy 0 'overall=healthy failures=0'
run_case wrong_chain 1 'FAIL chain_id_mismatch'
run_case catching_up 1 'FAIL catching_up'
run_case stale 1 'FAIL stale_or_future_block_time'
run_case gap 1 'FAIL height_gap_exceeded'

rc=0
"$SCRIPT" --local --service osmosis.service --rpc http://local --blocks nope \
  >"$TMP_DIR/invalid.out" 2>&1 || rc=$?
[[ "$rc" -eq 2 ]]
grep -Fq 'error=numeric_option_invalid' "$TMP_DIR/invalid.out"

echo 'osmosis-healthcheck fixtures: PASS'
